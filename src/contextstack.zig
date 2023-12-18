const std = @import("std");
const customerrors = @import("customerrors.zig");

// TODO impl/example
fn ErrorContextStack(comptime Errors: type, comptime max_size: comptime_int) type {
    return struct {
        stack: [max_size]customerrors.Union(Errors),
        current: u16 = 0,

        pub inline fn err(self: @This()) !void {
            switch (self.stack[self.current]) {
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
            for (0..self.current) |i| {
                switch (self.stack[i]) {
                    inline else => |suberr| {
                        try suberr.format(fmt, options, writer);
                    },
                }
            }
        }
        // pub fn push(comptime err:anytype) !void {
        // }
    };
}
