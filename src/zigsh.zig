const std = @import("std");

const help = @import("main.zig");
const cli = @import("lib/cli.zig");

// the main initial goal of zigsh is to have really good support for tab completion with other z programs
// like
//    z s|pinner
//    z progress |[1 / 10]
// and stuff like that
// brackets would be examples
// and then also another goal is like async support
//   during (curl "url.com"); echo (terminfo cursor_start_of_line)(spinner)" Loading…"(terminfo clr_eol); sleep 0.1; end
// and stream stuff
//   for (tree /) |file|; echo file; end
// (that wouldn't have to wait until tree / is done before running echo file)
// and other stuff like that
// mainly good tab completion and error underlining and whatever to start though

// https://man7.org/linux/man-pages/man5/terminfo.5.html

pub const main = help.anyMain(exec);

pub fn exec(exec_args: help.MainFnArgs) !void {
    const alloc = exec_args.allocator;
    const ai = exec_args.args_iter;

    if (ai.next()) |_| return ai.err("unsupported argument. todo -c");

    const stdin = std.io.getStdIn();

    const rawMode = try cli.enterRawMode(stdin);
    defer cli.exitRawMode(stdin, rawMode) catch @panic("could not exit raw mode");

    while (try cli.nextEvent(stdin)) |ev| {
        if (ev.is("ctrl+c")) break;
        std.debug.warn("Event: {}\r\n", .{ev});
    }
}
