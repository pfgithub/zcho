const std = @import("std");

const ReportedError = error{ReportedError};
pub fn reportError(ai: *ArgsIter, idx: usize, subidx: usize, msg: []const u8) ReportedError {
    printReportErrMsg(ai, idx, subidx, msg) catch return ReportedError.ReportedError;
    return ReportedError.ReportedError;
}
pub fn unicodeLen(text: []const u8) usize {
    return @import("lib/wcwidth.zig").wcswidth(text);
}
const missing_here = "[missing]";
fn printReportErrMsg(ai: *ArgsIter, idx: usize, subidx: usize, msg: []const u8) !void {
    // idx - 1 is the ai.args[i] that it is referring to
    // if idx is 0, it is not referring to any specific arg
    const out = std.io.getStdErr().writer();
    try out.writeAll("\x1b[1m\x1b[31mError:\x1b(B\x1b[m ");
    try out.writeAll(msg);
    try out.writeAll("\n");

    var len: usize = 0; // TODO unicode
    var arrow_pos: ?usize = null;

    for (ai.args) |arg, i| {
        if (i + 1 == idx) arrow_pos = len;

        if (i == 0) {
            try out.writeAll("\x1b[1m\x1b[97m");

            try out.writeAll(arg);
            len += unicodeLen(arg);
        } else {
            try out.writeAll(" \x1b[36m");
            if (subidx > 0) try out.writeAll(arg[0..std.math.min(subidx, arg.len)]);
            if (i + 1 == idx) try out.writeAll("\x1b[31m");
            if (subidx < arg.len) try out.writeAll(arg[subidx..]);
            len += unicodeLen(arg);
            if (arg.len == subidx) {
                try out.writeAll("\x1b[90m" ++ missing_here);
                len += missing_here.len;
            }
        }
        len += 1;
        if (i + 1 == ai.args.len and arrow_pos == null) {
            try out.writeAll("\x1b(B\x1b[m");
            try out.writeAll(" \x1b[90m" ++ missing_here);
        }
        try out.writeAll("\x1b(B\x1b[m");
    }
    try out.writeAll("\n");

    if (idx != 0) for (range(arrow_pos orelse len)) |_| try out.writeAll(" ");
    for (range(subidx)) |_| try out.writeAll(" ");
    try out.writeAll("\x1b[1m\x1b[92m^\x1b(B\x1b[m");
    try out.writeAll("\n");
}

pub const ArgsIter = struct {
    args: []const []const u8,
    index: usize = 0,
    subindex: usize = 0,
    pub fn next(ai: *ArgsIter) ?[]const u8 {
        ai.subindex = 0;
        if (ai.index >= ai.args.len) {
            if (ai.index == ai.args.len) ai.index += 1;
            return null;
        }
        defer ai.index += 1;
        return ai.args[ai.index];
    }
    /// if(ai.readArgOneValue(arg, "--speed") orelse return ai.err("Expected number"))) |speed|
    pub fn readValue(ai: *ArgsIter, arg: []const u8, comptime expcdt: []const u8) !?[]const u8 {
        if (std.mem.eql(u8, arg, expcdt)) {
            return ai.next() orelse return error.NoValue;
        }
        if (std.mem.startsWith(u8, arg, expcdt ++ "=")) {
            ai.subindex = expcdt.len + 1;
            const v = arg[expcdt.len + 1 ..];
            if (v.len == 0) return error.NoValue;
            return v;
        }
        return null;
    }
    pub fn err(ai: *ArgsIter, msg: []const u8) ReportedError {
        return reportError(ai, ai.index, ai.subindex, msg);
    }
};

pub fn range(max: usize) []const void {
    return @as([]const void, &[_]void{}).ptr[0..max];
}

pub fn allocDupe(alloc: *Alloc, a: anytype) !*@TypeOf(a) {
    const c = try alloc.create(@TypeOf(a));
    c.* = a;
    return c;
}

const MainFn = fn (exec_args: MainFnArgs) anyerror!void;

// in the future this will have more stuff
pub const MainFnArgs = struct {
    arena_allocator: *std.mem.Allocator,
    allocator: *std.mem.Allocator,
    // stdout_writer: // make your own
    args_iter: *ArgsIter,
};

pub fn anyMain(comptime mainFn: MainFn) fn () anyerror!u8 {
    return struct {
        fn main() !u8 {
            var gpalloc = std.heap.GeneralPurposeAllocator(.{}){};
            defer std.testing.expect(!gpalloc.deinit());

            var arena = std.heap.ArenaAllocator.init(&gpalloc.allocator);
            defer arena.deinit();

            const alloc = &arena.allocator;

            const args = try std.process.argsAlloc(alloc);
            defer std.process.argsFree(alloc, args);

            var ai = ArgsIter{ .args = args };
            _ = ai.next() orelse @panic("no arg 0");

            mainFn(MainFnArgs{ .arena_allocator = alloc, .allocator = &gpalloc.allocator, .args_iter = &ai }) catch |e| switch (@as(anyerror, e)) {
                error.ReportedError => {},
                else => return e,
            };

            return 0;
        }
    }.main;
}

const Programs = struct {
    echo: @import("zcho.zig"),
    progress: @import("zrogress.zig"),
    spinner: @import("zpinner.zig"),
    jsonexplorer: @import("jsonexplorer.zig"),
    zigsh: @import("zigsh.zig"),
    @"escape-sequence-debug": @import("escape_sequence_debug.zig"),
    clreol: ClrEol,
    @"--help": HelpPage,
};

const ClrEol = struct {
    fn exec(exec_args: MainFnArgs) anyerror!void {
        const ai = exec_args.args_iter;
        const out = std.io.getStdOut().writer();

        if (ai.next()) |arg| return ai.err("Args not allowed");
        try out.writeAll("\x1b[K");
    }
    const shortdesc = "same as `tput el`";
};
const HelpPage = struct {
    fn exec(exec_args: MainFnArgs) anyerror!void {
        const ai = exec_args.args_iter;
        const out = std.io.getStdOut().writer();

        // if (ai.next()) |v| return ea.ai.err("Unexpected extra arg");
        try out.writeAll("Usage:\n");
        try out.writeAll("    z [progname] [args...]\n");
        try out.writeAll("Programs:\n");
        inline for (@typeInfo(Programs).Struct.fields) |field| {
            try out.writeAll("    " ++ field.name ++ (if (@hasDecl(field.field_type, "shortdesc")) (" - " ++ field.field_type.shortdesc) else "") ++ "\n");
        }
    }
    const shortdesc = "show this page";
};

pub const main = anyMain(struct {
    fn mainfn(exec_args: MainFnArgs) anyerror!void {
        const ai = exec_args.args_iter;

        const progname = ai.next() orelse {
            try HelpPage.exec(exec_args);
            return ai.err("Missing program name.");
        };
        inline for (@typeInfo(Programs).Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, progname)) {
                try field.field_type.exec(exec_args);
                break;
            }
        } else return ai.err("bad program name. check --help.");
    }
}.mainfn);

fn testReadNumber(args: []const []const u8, expected: ?[]const u8) void {
    var ai = ArgsIter{ .args = args };
    const valu = (ai.readValue(ai.next() orelse @panic("fail"), "--number") catch @panic("fail"));
    if (valu) |v| if (expected) |e| std.testing.expectEqualStrings(v, e) else @panic("fail") //
    else if (expected) |e| @panic("fail") else {}
}

test "args iter" {
    testReadNumber(&[_][]const u8{ "--number", "2" }, "2");
    testReadNumber(&[_][]const u8{"--number=2"}, "2");
    testReadNumber(&[_][]const u8{"--something-else"}, null);
}
// testpanic "" { testReadNumber(…) } // would be useful to have
