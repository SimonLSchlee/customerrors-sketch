const std = @import("std");

fn fieldsLength(comptime T: type) comptime_int {
    return switch (@typeInfo(T)) {
        inline else => |s| s.fields.len,
    };
}

fn countUnionMembers(comptime errors: anytype) comptime_int {
    comptime var len = 0;
    for (errors) |e| {
        const info = @typeInfo(e);
        switch (info) {
            .Union => |u| len += u.fields.len,
            .Struct => |s| len += if (needsUnwrapping(info)) fieldsLength(s.fields[0].type) else 1,
            else => |other| {
                @compileLog(other);
                @compileError("Expected tuple of Struct or Union types, but got: " ++ @typeName(@TypeOf(other)));
            },
        }
    }
    return len;
}

fn flattenedUnionTypes(comptime errors: anytype) [countUnionMembers(errors)]type {
    const len = countUnionMembers(errors);
    comptime var types: [len]type = undefined;
    comptime var i = 0;
    for (errors) |e| {
        const info = @typeInfo(e);
        switch (info) {
            .Union => |u| {
                for (u.fields) |f| {
                    // @compileLog("union fields", f.type);
                    types[i] = f.type;
                    i += 1;
                }
            },
            .Struct => |s| {
                if (needsUnwrapping(info)) {
                    for (@typeInfo(s.fields[0].type).Union.fields) |f| {
                        // @compileLog("needsUnwrapping", f.type);
                        types[i] = f.type;
                        i += 1;
                    }
                } else {
                    // @compileLog("e", e);
                    types[i] = e;
                    i += 1;
                }
            },
            else => unreachable,
        }
    }
    return types;
}

pub fn MakeUnion(comptime errors: anytype) type {
    const len = countUnionMembers(errors);
    // @compileLog(len);
    comptime var fields: [len]std.builtin.Type.UnionField = undefined;
    comptime var enum_fields: [len]std.builtin.Type.EnumField = undefined;

    // @compileLog(flattenedUnionTypes(errors));
    for (flattenedUnionTypes(errors), 0..) |S, i| {
        // @compileLog(S, i);
        switch (@typeInfo(S)) {
            .Struct => |_| {
                checkCustomError(S);
                const name = std.fmt.comptimePrint("{d}", .{i});
                fields[i] = .{ .name = name, .type = S, .alignment = @alignOf(S) };
                enum_fields[i] = .{ .name = name, .value = i };
            },
            else => unreachable,
        }
    }
    const tag = @Type(.{
        .Enum = .{
            .tag_type = u16, // TODO figure out what the compiler does for union(enum)
            .fields = &enum_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
    return @Type(.{
        .Union = .{
            .layout = .Auto,
            .tag_type = tag,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
        },
    });
}

pub fn GetFirst(comptime S: type) type {
    return switch (@typeInfo(S)) {
        .Struct => |s| s.fields[0].type,
        else => @compileError("not supported"),
    };
}
fn firstField(val: anytype) GetFirst(@TypeOf(val)) {
    return switch (@typeInfo(@TypeOf(val))) {
        .Struct => |s| @field(val, s.fields[0].name),
        else => @compileError("not supported"),
    };
}

fn needsUnwrapping(comptime info: std.builtin.Type) bool {
    return switch (info) {
        .Struct => |s| blk: {
            if (s.fields.len != 1) break :blk false;
            for (s.decls) |d| {
                if (std.mem.eql(u8, d.name, "unwrap_to_single_union_field")) {
                    // break :blk @field(V, "unwrap_to_single_union_field");
                    break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

fn doUnwrapping(comptime V: type) bool {
    return needsUnwrapping(@typeInfo(V));
}
fn UnwrappingResultType(comptime V: type) type {
    return switch (@typeInfo(V)) {
        .Struct => if (doUnwrapping(V)) GetFirst(V) else V,
        else => V,
    };
}
inline fn unwrap_single_union_field(v: anytype) UnwrappingResultType(@TypeOf(v)) {
    return if (comptime doUnwrapping(@TypeOf(v))) firstField(v) else v;
}
pub inline fn error_from_payload(comptime E: type, err: anytype) E {
    const T = @TypeOf(err);
    const R = UnwrappingResultType(E);
    const do_wrap = comptime doUnwrapping(E);
    switch (@typeInfo(R)) {
        .Union => |u| {
            inline for (u.fields) |f| {
                if (f.type == T) {
                    const val = @unionInit(R, f.name, err);
                    return if (do_wrap) E{ .u = val } else val;
                }
            }
            @compileLog(u.fields);
            @compileError("couldn't find a matching field for type " ++ @typeName(T) ++ " within union " ++ @typeName(E));
        },
        else => {
            return if (do_wrap) E{ .u = err } else err;
        },
    }
    unreachable;
}

pub fn checkCustomError(comptime E: type) void {
    if (comptime !std.meta.hasFn(E, "err")) {
        @compileLog(E);
        @compileError("Tried using type " ++ @typeName(E) ++ " as a custom error, but it is missing an pub err function.");
        // TODO check returntype of err function
    }
}
