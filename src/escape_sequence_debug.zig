const std = @import("std");
const cli = @import("lib/cli.zig");
const help = @import("main.zig");

pub const main = help.anyMain(exec);

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;

    const stdinF = std.io.getStdIn();
    const stdin = stdinF.reader();
    const stdoutF = std.io.getStdOut();
    const stdout = stdoutF.writer();

    const ot = try cli.enterRawMode(stdinF);
    defer cli.exitRawMode(stdinF, ot) catch @panic("failed to exit");

    var mouseMode = false;
    var eventMode = false;
    while (ai.next()) |arg| {
        // std.debug.warn("ARG: {s}\n", .{arg});
        if (std.mem.eql(u8, arg, "--mouse")) {
            mouseMode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--event")) {
            eventMode = true;
            continue;
        }
        return ai.err("Bad arg. Args: --mouse, --event");
    }

    if (mouseMode) try cli.startCaptureMouse();
    defer if (mouseMode) cli.stopCaptureMouse() catch @panic("failed to stop mouse capture");

    try stdout.print("Escape sequence debug started. Window size is: {}\n", .{try cli.winSize(stdoutF)});

    if (eventMode) {
        try cli.mainLoop(false, struct {
            pub fn f(data: anytype, ev: cli.Event) bool {
                const stdoutF2 = std.io.getStdOut();
                const stdout2 = stdoutF2.writer();

                stdout2.print("{}\n", .{ev}) catch return false;
                if (ev.is("ctrl+c")) {
                    return false;
                }
                if (ev.is("ctrl+p")) @panic("panic test");
                return true;
            }
        }.f, stdinF);
        return;
    }
    const escape_start = "\x1b[34m\\\x1b[94m";
    const escape_end = "\x1b(B\x1b[m";

    while (true) {
        const rb = try stdin.readByte();
        switch (rb) {
            3 => break,
            32...126 => |c| try stdout.print("{c}", .{c}),
            '\t' => try stdout.print(escape_start ++ "t" ++ escape_end, .{}),
            '\r' => try stdout.print(escape_start ++ "r" ++ escape_end, .{}),
            '\n' => try stdout.print(escape_start ++ "n" ++ escape_end, .{}),
            else => |c| try stdout.print(escape_start ++ "x{x:0>2}" ++ escape_end, .{c}),
        }
    }
}
