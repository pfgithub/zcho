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

    var mouseMode = false;
    var eventMode = false;
    var rawMode = true;
    while (ai.next()) |arg| {
        // std.debug.warn("ARG: {s}\n", .{arg});
        if (std.mem.eql(u8, arg.text, "--mouse")) {
            mouseMode = true;
            continue;
        }
        if (std.mem.eql(u8, arg.text, "--event")) {
            eventMode = true;
            continue;
        }
        if (std.mem.eql(u8, arg.text, "--no-raw")) {
            rawMode = false;
            continue;
        }
        return ai.err("Bad arg. Args: --mouse, --event, --no-raw", .{});
    }

    const ot: ?std.os.termios = if (rawMode) try cli.enterRawMode(stdinF) else null;
    defer if (ot) |o| cli.exitRawMode(stdinF, o) catch @panic("failed to exit");

    if (mouseMode) try cli.startCaptureMouse();
    defer if (mouseMode) cli.stopCaptureMouse() catch @panic("failed to stop mouse capture");

    try stdout.print("Escape sequence debug started. Window size is: {}\n", .{try cli.winSize(stdoutF)});

    if (eventMode) {
        while (try cli.nextEvent(stdinF)) |ev| {
            stdout.print("{}\n", .{ev}) catch break;
            if (ev.is("ctrl+c")) {
                break;
            }
            if (ev.is("ctrl+p")) @panic("panic test");
        }
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
