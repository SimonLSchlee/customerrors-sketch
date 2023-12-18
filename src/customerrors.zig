// idea maybe we can use tuples with optional custom errors + destructuring
// when we need custom errors, and then convert the optional error
// back to zig error codes, when we no longer are interested in the details of the error?

const std = @import("std");
const utils = @import("utils.zig");

const PayloadOptions = struct {
    print: @TypeOf(std.log.err) = std.log.err,
    enabled: bool = @import("customerrors").enabled,
};

pub fn Payload(comptime options: PayloadOptions) type {
    return struct {
        pub const enabled = options.enabled;
        /// This function is used to define a function that returns custom errors.
        ///
        /// ```zig
        /// // TODO create a test with this as real example to ensure it works and copy from there?
        /// const Number = payload.Error(u16, NumberNotAllowed);
        /// fn numberSelect(number:u32) Number.res {
        ///     if (number == 0) {
        ///         return Number.fail(NumberNotAllowed{.reason="zero not allowed"});
        ///     }
        ///     if (number == 2345) {
        ///         return Number.fail(NumberNotAllowed{.reason="this number has other things to do"});
        ///     }
        ///     const max:u32 = std.math.maxInt(u16);
        ///     if (number > max) {
        ///         return Number.fail(NumberNotAllowed{.reason="too big"});
        ///     }
        ///     return Number.success(number);
        /// }
        /// ```
        pub fn Error(comptime Value: type, comptime E: type) type {
            comptime utils.checkCustomError(E);
            const ERR = if (comptime enabled) E else OpaqueError;
            return struct {
                pub const res = std.meta.Tuple(&[_]type{ Value, ?ERR });
                pub inline fn success(value: Value) res {
                    return .{ value, null };
                }
                pub inline fn fail(err: anytype) res {
                    return .{ undefined, opaque_if_disabled(ERR, utils.error_from_payload(E, err)) };
                }
            };
        }
        inline fn opaque_if_disabled(comptime ERR: type, err: anytype) ?ERR {
            if (comptime enabled) {
                return err;
            } else {
                err.err() catch |e| return OpaqueError{ .code = e };
                unreachable;
            }
        }
        /// Unwraps the custom error by printing it and failing with the zig error.
        /// If successful returns the value.
        ///
        /// ```zig
        /// const value = try payload.unwrap(my_function());
        /// ```
        pub fn unwrap(err: anytype) !utils.GetFirst(@TypeOf(err)) {
            const T = @TypeOf(err);
            switch (@typeInfo(T)) {
                .Struct => |s| {
                    if (s.is_tuple) {
                        const val, const e = err;
                        try unwrap_error(e);
                        return val;
                    }
                },
                else => {},
            }
            @compileError("Expected a 2 element tuple, where the 2nd element has an err method, got: " ++ @typeName(T));
        }
        /// Unwraps the custom error by printing it and failing with the zig error.
        /// If successful does nothing.
        ///
        /// ```zig
        /// const value, const err = my_function();
        /// try payload.check(err);
        /// ```
        pub fn check(err: anytype) !void {
            const T = @TypeOf(err);
            switch (@typeInfo(T)) {
                .Optional => try unwrap_error(err),
                else => @compileError("Expected an optional type with an err method, got: " ++ @typeName(T)),
            }
        }
        /// Unwraps the custom error by failing with the zig error.
        /// If successful does nothing.
        ///
        /// This allows the caller to do whatever they want with the custom error,
        /// the zig error is used to communicate to the caller that there is a custom error,
        /// that needs to be handled.
        ///
        /// ```zig
        /// const value, const err = my_function();
        /// payload.custom(err) catch |zig_error| {
        ///     std.debug.print("the custom error was:\n{}\n", .{err.?});
        ///     std.debug.print("the zig error code is: {}\n", .{zig_error});
        ///     std.debug.dumpCurrentStackTrace(null);
        ///     return e;
        /// };
        /// ```
        pub fn custom(err: anytype) !void {
            const T = @TypeOf(err);
            switch (@typeInfo(T)) {
                .Optional => try unwrap_custom(err),
                else => @compileError("Expected an optional type with an err method, got: " ++ @typeName(T)),
            }
        }

        inline fn unwrap_error(err: anytype) !void {
            if (err) |e| {
                options.print("{}\n", .{e});
                std.debug.dumpCurrentStackTrace(@returnAddress());
                try @TypeOf(e).err(e);
            }
        }
        inline fn unwrap_custom(err: anytype) !void {
            if (err) |e| {
                try @TypeOf(e).err(e);
            }
        }
    };
}

pub const AllocationError = struct {
    src: std.builtin.SourceLocation,

    pub inline fn err(_: @This()) !void {
        return error.OutOfMemory;
    }
    pub fn format(
        self: AllocationError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("AllocationError\n");
        try writer.print("    file: {s}\n", .{self.src.file});
        try writer.print("    function: {s}\n", .{self.src.fn_name});
        try writer.print("    line: {d}\n", .{self.src.line});
        try writer.print("    column: {d}\n", .{self.src.column});
    }
};

pub const OpaqueError = struct {
    code: anyerror,

    pub inline fn err(self: @This()) !void {
        return self.code;
    }
    pub inline fn code(_: @This()) void {}
    pub fn format(
        self: OpaqueError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("OpaqueError\n");
        try writer.print("    use -D" ++ @import("customerrors").option_name ++ "=true to enable custom errors and see more information\n", .{});
        try writer.print("    err: {}\n", .{self.code});
    }
};

pub fn Union(comptime Errors: anytype) type {
    // @compileLog(Errors);
    return struct {
        pub const unwrap_to_single_union_field = true;
        u: utils.MakeUnion(Errors),

        pub inline fn err(e: @This()) !void {
            switch (e.u) {
                inline else => |suberr| {
                    return suberr.err();
                },
            }
        }
        pub fn format(
            self: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            switch (self.u) {
                inline else => |suberr| {
                    try suberr.format(fmt, options, writer);
                },
            }
        }
    };
}
