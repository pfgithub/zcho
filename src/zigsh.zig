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
    const stdout = std.io.getStdOut();
    const out = stdout.writer();

    const rawMode = try cli.enterRawMode(stdin);
    defer cli.exitRawMode(stdin, rawMode) catch @panic("could not exit raw mode");

    var prompt = Prompt.init(alloc);
    defer prompt.deinit();

    try prompt.updateDisplay(out, true);
    while (cli.nextEvent(stdin) catch cli.Event{ .none = {} }) |ev| {
        if (ev.is("ctrl+d")) break //
        else if (ev.is("ctrl+c")) {
            try out.writeAll("\x1b[7m^C\x1b(B\x1b[m\x1b[J\n"); // ^C(tput ed)
            prompt.clear();
        } else if (ev.is("enter")) {
            try prompt.updateDisplay(out, false);
            prompt.clear();
            try out.writeAll("\n");
            // execute the command and wait for it to return
            // after it returns, \x1b[6n check the cursor position and if x != 0, print "⏎ \n"
        } else if (ev.is("home")) prompt.cursor = prompt.findStop(prompt.cursor, .left, .line) //
        else if (ev.is("ctrl+a")) prompt.cursor = prompt.findStop(prompt.cursor, .left, .line) //
        else if (ev.is("end")) prompt.cursor = prompt.findStop(prompt.cursor, .right, .line) //
        else if (ev.is("ctrl+e")) prompt.cursor = prompt.findStop(prompt.cursor, .right, .line) //
        else switch (ev) {
            .key => |kev| switch (kev.keycode) {
                .character => |codepoint| {
                    // try command.writer().print("{u}", .{uc});
                    // ha jk #6390 isn't merged yet
                    try prompt.insert(codepoint);
                },
                .left => prompt.cursor = prompt.findStop(prompt.cursor, .left, if (kev.modifiers.ctrl) .word else .char),
                .right => prompt.cursor = prompt.findStop(prompt.cursor, .right, if (kev.modifiers.ctrl) .word else .char),
                .backspace => {
                    const deleteTo = prompt.findStop(prompt.cursor, .left, if (kev.modifiers.ctrl) .word else .char);
                    prompt.deleteRange(deleteTo, prompt.cursor);
                },
                .delete => {
                    const deleteTo = prompt.findStop(prompt.cursor, .right, if (kev.modifiers.ctrl) .word else .char);
                    prompt.deleteRange(prompt.cursor, deleteTo);
                },
                else => {
                    var temp = std.ArrayList(u8).init(alloc);
                    defer temp.deinit();
                    try temp.writer().print("{}", .{ev});
                    try prompt.insertText(temp.items);
                },
            },
            else => {},
        }
        try prompt.updateDisplay(out, true);
    }
}

const ArgsIter = struct {
    const Arg = union(enum) {
        flag: []const u8,
        text: []const u8,
    };
    args: []Arg,
    i: usize,
};

const ProgramOptions = struct {
    request: enum { run, completion },
    args: *ArgsIter,
};

const ProgramExitResult = union(enum) {
    ran_program: struct {},
    tab_completion: struct {},
};

fn demoProgram(args: ProgramOptions) ProgramExitResult {
    const Config = struct {
        parsing_args: bool,
        _: []const []const u8,
    };
    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |argitm| { // variables (eg ls $folder) are passed in differently
        const arg = argitm.text;
        if (!arg.variable and cfg.parsing_args and std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--raw") catch return ai.expect("[value]", "Expected value")) |rawv| {
                try positionals.append(.{ .text = rawv, .pos = ai.index, .epos = ai.subindex });
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--help")) {
                cfg.todo = .display_help; // stops parsing any other arguments in case there are errors
                // ArgsIter will know this and be able to show that the args are unused with different coloring
                break;
            }
            return ai.suggest(&[_][]const u8{ "-help", "-raw", "-" }, "Bad arg. See --help");
        }
        try positionals.append(.{ .text = arg, .pos = ai.index });
    }
    cfg._ = positionals.toOwnedSlice();
}

// TODO: terminfo I guess
// https://github.com/ziglang/zig/pull/6150/files
// would it be helpful to use \x1b[6n to check if the cursor is at the position we expect it
// to be?

const Prompt = struct {
    text: std.ArrayList(u8),
    cursor: usize,
    has_written_prompt: bool = false,
    fn init(alloc: *std.mem.Allocator) Prompt {
        return Prompt{
            .text = std.ArrayList(u8).init(alloc),
            .cursor = 0,
        };
    }
    fn deinit(prompt: *Prompt) void {
        prompt.text.deinit();
        prompt.* = undefined;
    }

    fn clear(prompt: *Prompt) void {
        prompt.text.shrinkRetainingCapacity(0);
        prompt.cursor = 0;
        prompt.has_written_prompt = false;
    }

    const StopMode = enum { word, char, line };
    fn findStop(prompt: *Prompt, from: usize, direction: enum { left, right }, mode: StopMode) usize {
        var i = from;
        while (switch (direction) {
            .left => i > 0,
            .right => i < prompt.text.items.len,
        }) {
            switch (direction) {
                .left => i -= 1,
                .right => i += 1,
            }
            if (i == prompt.text.items.len) return i;
            if (i > prompt.text.items.len) unreachable;
            const char = prompt.text.items[i];

            if (char < 0b01111111) switch (mode) { // ascii character, 0b0xxxxxxx
                .word => switch (char) {
                    'A'...'Z', 'a'...'z', '0'...'9' => {},
                    else => break,
                },
                .line => switch (char) {
                    '\n' => break,
                    else => {},
                },
                .char => break,
            } else if (char & 0b01000000 != 0) break; // utf-8 start character, 0b11xxxxxx
        }
        return i;
    }

    fn deleteRange(prompt: *Prompt, from: usize, to: usize) void {
        if (to < from) unreachable; // bad
        if (to - from == 0) return; // nothing to do;

        if (prompt.cursor > to) prompt.cursor -= to - from //
        else if (prompt.cursor > from) prompt.cursor = from;

        std.mem.copy(u8, prompt.text.items[from..], prompt.text.items[to..]);
        prompt.text.items.len -= to - from;
    }

    fn insert(prompt: *Prompt, char: u21) !void {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(char, buf[0..]) catch unreachable;
        const encoded = @as(*const [4]u8, &buf)[0..len];
        try prompt.insertText(encoded);
    }
    fn insertText(prompt: *Prompt, text: []const u8) !void {
        try prompt.text.insertSlice(prompt.cursor, text);
        prompt.cursor += text.len;
    }

    // maybe a seperate promptDisplay that tracks the current display state
    // and stuff? idk maybe not
    fn updateDisplay(prompt: *Prompt, out: anytype, show_hints: bool) !void {
        if (prompt.has_written_prompt) {
            try out.writeAll("\x1b8");
        } else {
            try out.writeAll("\r");
            try printPrompt(out);
            try out.writeAll("\x1b7"); // tput sc
            prompt.has_written_prompt = true;
        }
        try out.writeAll(prompt.text.items);
        try out.writeAll("\x1b[K");
        try out.writeAll("\x1b8"); // tput rc
        const unilen = help.unicodeLen(prompt.text.items[0..prompt.cursor]);
        if (unilen > 0) try out.print("\x1b[{}C", .{unilen});
    }
    fn printPrompt(out: anytype) !void {
        const collapsedPath = "*/"; // ~/D/N/…
        const finalPath = "demo";
        try out.writeAll("\x1b(B\x1b[m\x1b[38;2;153;153;153m\x1b[48;2;51;51;51m ");
        try out.writeAll(collapsedPath);
        try out.writeAll("\x1b[1m\x1b[38;2;255;255;255m\x1b[48;2;51;51;51m");
        try out.writeAll(finalPath);
        try out.writeAll(" \x1b(B\x1b[m\x1b[38;2;51;51;51m\xee\x82\xb0 \x1b(B\x1b[m");
    }
};
