const std = @import("std");

const ReportedError = error{ReportedError};
pub fn reportError(ai: *PositionalIter, idx: usize, subidx: usize, msg: []const u8) ReportedError {
    printReportErrMsg(ai, idx, subidx, msg) catch return ReportedError.ReportedError;
    return ReportedError.ReportedError;
}
pub fn unicodeLen(text: []const u8) usize {
    return @import("lib/wcwidth.zig").wcswidth(text);
}
const missing_here = "[missing]";
fn printReportErrMsg(ai: *PositionalIter, idx: usize, subidx: usize, msg: []const u8) !void {
    // idx - 1 is the ai.report_info[i] that it is referring to
    // if idx is 0, it is not referring to any specific arg
    const out = std.io.getStdErr().writer();
    try out.writeAll("\x1b[1m\x1b[31mError:\x1b(B\x1b[m ");
    try out.writeAll(msg);
    try out.writeAll("\n");

    var len: usize = 0; // TODO unicode
    var arrow_pos: ?usize = null;

    for (ai.report_info) |arg, i| {
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
        if (i + 1 == ai.report_info.len and arrow_pos == null) {
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

pub const Positional = struct {
    text: []const u8,
    index: usize,
    offset: usize = 0,

    pub fn err(positional: Positional, pi: *PositionalIter, msg: []const u8) ReportedError {
        std.log.err("hmm {} {} {}", .{ positional, positional.index, msg });
        return reportError(pi, positional.index, positional.offset, msg);
    }
};

pub const PositionalIter = struct {
    args: []Positional,
    report_info: []const []const u8,
    index: usize = 0,
    offset: usize = 0,

    /// args are not duped and must be alive for the lfietime of PositionalIter
    pub fn positionalsFromArgs(args: []const []const u8, alloc: *std.mem.Allocator) ![]Positional {
        const positionals = try alloc.alloc(Positional, args.len);
        for (positionals) |*positional, i| {
            positional.text = args[i];
            positional.index = i + 1; // hmm
            positional.offset = 0;
        }
        return positionals;
    }

    pub fn next(pi: *PositionalIter) ?Positional {
        pi.offset = 0;
        if (pi.index >= pi.args.len) {
            if (pi.index == pi.args.len) pi.index += 1;
            return null;
        }
        defer pi.index += 1;
        return pi.args[pi.index];
    }
    pub fn readValue(pi: *PositionalIter, first: Positional, expected: []const u8) !?Positional {
        if (std.mem.eql(u8, first.text, expected)) {
            return pi.next() orelse error.NoValue;
        }
        if (std.mem.startsWith(u8, first.text, expected) and std.mem.startsWith(u8, first.text[expected.len..], "=")) {
            pi.offset = expected.len + 1;
            const v = first.text[expected.len + 1 ..];
            if (v.len == 0) return error.NoValue;
            return Positional{ .text = v, .index = pi.index, .offset = first.offset + expected.len + 1 };
        }
        return null;
    }
    pub fn err(pi: *PositionalIter, msg: []const u8) ReportedError {
        return reportError(pi, pi.index, pi.offset, msg);
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
    args_iter: *PositionalIter,
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

            var positionals = try PositionalIter.positionalsFromArgs(args, alloc);
            defer alloc.free(positionals);

            var ai = PositionalIter{ .args = positionals, .report_info = args };
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
    progress: @import("progress.zig"),
    spinner: @import("spinner.zig"),
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
            if (std.mem.eql(u8, field.name, progname.text)) {
                try field.field_type.exec(exec_args);
                break;
            }
        } else return ai.err("bad program name. check --help.");
    }
}.mainfn);

fn testReadNumber(args: []const []const u8, expected: ?[]const u8) void {
    const alloc = std.testing.allocator;
    var positionals = PositionalIter.positionalsFromArgs(args, alloc) catch @panic("oom");
    defer alloc.free(positionals);
    var ai = PositionalIter{ .args = positionals, .report_info = args };
    const valu = (ai.readValue(ai.next() orelse @panic("fail"), "--number") catch @panic("fail"));
    if (valu) |v| if (expected) |e| std.testing.expectEqualStrings(v.text, e) else @panic("fail") //
    else if (expected) |e| @panic("fail") else {}
}

test "args iter" {
    testReadNumber(&[_][]const u8{ "--number", "2" }, "2");
    testReadNumber(&[_][]const u8{"--number=2"}, "2");
    testReadNumber(&[_][]const u8{"--something-else"}, null);
}
// testpanic "" { testReadNumber(…) } // would be useful to have
