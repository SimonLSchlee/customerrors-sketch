const std = @import("std");
const customerrors = @import("customerrors.zig");
const payload = customerrors.Payload(.{});
// const payload = customerrors.Payload(.{ .enabled = false });

const RndGen = std.rand.DefaultPrng;
const RngImpl = GetResultType(&RndGen.init);

fn GetResultType(comptime f: anytype) type {
    const info = @typeInfo(@TypeOf(f));
    return @typeInfo(info.Pointer.child).Fn.return_type.?;
}

const Token = enum {
    OPEN_PAREN,
    CLOSE_PAREN,
    NUMBER,
    SOMETHING_NOT_ALLOWED_IN_PARENS,
};

const File = struct {};
const fakefile: *File = undefined;

const Location = struct {
    file: *File,
    line: u32,
    column: u32,
};

const Node = struct {
    data: u32,
};

const UnexpectedToken = struct {
    expected: Token,
    got: Token,
    location: Location,

    pub fn init(expected: Token, got: Token, location: Location) @This() {
        return .{ .expected = expected, .got = got, .location = location };
    }
    pub inline fn err(_: @This()) !void {
        return error.UnexpectedToken;
    }
    pub fn format(
        self: UnexpectedToken,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("UnexpectedToken\n");
        try writer.print("    expected: {}\n", .{self.expected});
        try writer.print("    got: {}\n", .{self.got});
        try writer.print("    location: {}\n", .{self.location});
    }
};

const FileFetchError = struct {
    file: *File,
    pos: u64,

    pub inline fn err(_: @This()) !void {
        return error.FileFetchError;
    }
    pub fn format(
        self: FileFetchError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("FileFetchError\n");
        try writer.print("    file: {}\n", .{self.file});
        try writer.print("    pos: {}\n", .{self.pos});
    }
};

const TokenOrFile = customerrors.Union(.{ UnexpectedToken, FileFetchError });
const NumbersErrors = customerrors.Union(.{ customerrors.AllocationError, TokenOrFile });

const Parser = struct {
    allocator: std.mem.Allocator,
    file: *File,
    seed: u64,
    rng: RngImpl,

    fn init(allocator: std.mem.Allocator, file: *File, seed: u64) Parser {
        // @compileLog(NumbersErrors);
        // @compileLog(@typeInfo(@typeInfo(NumbersErrors).Struct.fields[0].type).Union.fields);
        return .{
            .allocator = allocator,
            .file = file,
            .seed = seed,
            .rng = RndGen.init(seed),
        };
    }

    const Numbers = payload.Error(*Node, NumbersErrors);
    fn parseNumbers(self: *Parser) Numbers.res {
        const choice = self.rng.random().uintLessThan(u16, 10);
        if (choice == 0) {
            return Numbers.fail(UnexpectedToken.init(.NUMBER, .SOMETHING_NOT_ALLOWED_IN_PARENS, .{
                .file = fakefile,
                .line = 10,
                .column = 33,
            }));
        } else if (choice == 1) {
            return Numbers.fail(FileFetchError{ .file = fakefile, .pos = 42 });
        } else {
            var node = self.randomNodeAllocFail() catch {
                return Numbers.fail(customerrors.AllocationError{ .src = @src() });
            };
            node.data = self.rng.random().uintLessThan(u16, 1000);
            return Numbers.success(node);
        }
    }

    fn randomNodeAllocFail(self: *Parser) !*Node {
        const choice = self.rng.random().uintLessThan(u16, 30);
        return if (choice == 0) error.OutOfMemory else self.allocator.create(Node);
    }

    fn parse(self: *Parser) !void {
        const node1 = try payload.unwrap(self.parseNumbers());

        const node2, const err = self.parseNumbers();
        try payload.check(err);

        const node3, const err2 = self.parseNumbers();
        payload.custom(err2) catch |e| {
            std.debug.print("the custom error was:\n{}\n", .{err2.?});
            std.debug.print("the error code is: {}\n", .{e});
            std.debug.dumpCurrentStackTrace(null); // TODO better stack trace
            return e;
        };

        const node4, const err3 = self.parseNumbers();
        if (err3) |custom_error| {
            std.debug.print("using if on the optional:\n{}\n", .{custom_error});
            std.debug.dumpCurrentStackTrace(null); // TODO better stack trace
            return custom_error.err();
        }

        // use nodes
        std.debug.print("{} {} {} {}\n", .{ node1, node2, node3, node4 });
    }
};

fn guessSeedFromTime() u64 {
    const seed: u64 = @intCast(std.time.nanoTimestamp());
    std.debug.print("\nguessed seed: {d}\n", .{seed});
    return seed;
}

fn parseSeed(seed: []const u8) !u64 {
    std.debug.print("\ngot seed: {s}\n", .{seed});
    return std.fmt.parseInt(u64, seed, 10);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        switch (gpa.deinit()) {
            .leak => @panic("leaked memory"),
            else => {},
        }
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const seed_arg = 1;
    const seed: u64 = if (args.len > seed_arg) try parseSeed(args[seed_arg]) else guessSeedFromTime();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var p = Parser.init(arena.allocator(), fakefile, seed);
    for (0..3) |_| {
        p.parse() catch |e| {
            std.debug.print("failed with seed: {}\npass it to the program to rerun with this seed\n", .{p.seed});
            return e;
        };
    }
}
