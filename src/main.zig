const std = @import("std");

const ReportedError = error{ReportedError};
pub fn reportError(ai: *ArgsIter, idx: usize, msg: []const u8) ReportedError {
    printReportErrMsg(ai, idx, msg) catch return ReportedError.ReportedError;
    return ReportedError.ReportedError;
}
fn printReportErrMsg(ai: *ArgsIter, idx: usize, msg: []const u8) !void {
    // idx - 1 is the ai.args[i] that it is referring to
    // if idx is 0, it is not referring to any specific arg
    const out = std.io.getStdErr().writer();
    try out.writeAll("\x1b[1m\x1b[31mError:\x1b(B\x1b[m ");
    try out.writeAll(msg);
    try out.writeAll("\n");

    var len: usize = 0;
    var arrow_pos: usize = undefined;

    for (ai.args) |arg, i| {
        if (i + 1 == idx) arrow_pos = len;

        if (i == 0) {
            try out.writeAll("\x1b[1m\x1b[97m");

            try out.writeAll(arg);
            len += arg.len;
        } else {
            if (i + 1 == idx) try out.writeAll(" \x1b[31m") //
            else try out.writeAll(" \x1b[36m");
            try out.writeAll(arg);
            len += arg.len;
        }
        try out.writeAll("\x1b(B\x1b[m");
        len += 1;
    }
    try out.writeAll("\n");

    if (idx != 0) for (range(arrow_pos)) |_| try out.writeAll(" ");
    try out.writeAll("\x1b[1m\x1b[92m^\x1b(B\x1b[m");
    try out.writeAll("\n");
}

pub const ArgsIter = struct {
    args: []const []const u8,
    index: usize = 0,
    pub fn next(ai: *ArgsIter) ?[]const u8 {
        if (ai.index >= ai.args.len) return null;
        defer ai.index += 1;
        return ai.args[ai.index];
    }
    pub fn err(ai: *ArgsIter, msg: []const u8) ReportedError {
        return reportError(ai, ai.index, msg);
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

const MainFn = fn (alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) anyerror!void;

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

            const os = std.io.getStdOut().outStream();

            var ai = ArgsIter{ .args = args };
            _ = ai.next() orelse @panic("no arg 0");

            mainFn(alloc, &ai, os) catch |e| switch (e) {
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
    clreol: ClrEol,
    @"--help": HelpPage,
};

const ClrEol = struct {
    fn exec(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) anyerror!void {
        if (ai.next()) |arg| return reportError(ai, ai.index, "Args not allowed");
        try out.writeAll("\x1b[K");
    }
    const shortdesc = "same as `tput el`";
};
const HelpPage = struct {
    fn exec(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) anyerror!void {
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
    fn mainfn(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) anyerror!void {
        const progname = ai.next() orelse {
            return HelpPage.exec(alloc, ai, out);
        };
        inline for (@typeInfo(Programs).Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, progname)) {
                try field.field_type.exec(alloc, ai, out);
                break;
            }
        } else return reportError(ai, ai.index, "bad program name. check --help.");
    }
}.mainfn);
