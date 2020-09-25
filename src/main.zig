const std = @import("std");

const ReportedError = error{ReportedError};
pub fn reportError(ai: ArgsIter, msg: []const u8) ReportedError {
    printReportErrMsg(ai, msg) catch return ReportedError.ReportedError;
    return ReportedError.ReportedError;
}
fn printReportErrMsg(ai: ArgsIter, msg: []const u8) !void {
    const out = std.io.getStdErr().writer();
    try out.writeAll("Error: ");
    try out.writeAll(msg);
    try out.writeAll("\n");
    for (ai.args) |arg, i| {
        if (i != 0) try out.writeAll(" ");
        try out.writeAll(arg);
    }
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
};

pub fn range(max: usize) []const void {
    return @as([]const void, &[_]void{}).ptr[0..max];
}

pub fn allocDupe(alloc: *Alloc, a: anytype) !*@TypeOf(a) {
    const c = try alloc.create(@TypeOf(a));
    c.* = a;
    return c;
}

const MainFn = fn (alloc: *std.mem.Allocator, args: []const []const u8, out: anytype) anyerror!void;

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
            try mainFn(alloc, args, os);

            return 0;
        }
    }.main;
}

pub const main = anyMain(switch (@import("build_options").command) {
    .zcho => @import("zcho.zig").exec,
    .zrogress => @import("zrogress.zig").exec,
});
