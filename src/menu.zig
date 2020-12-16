const std = @import("std");
const help = @import("main.zig");
const PositionalIter = help.PositionalIter;
const Positional = help.Positional;
const cli = @import("lib/cli.zig");

pub const main = help.anyMain(exec);

const Config = struct {
    flag_enabled: bool = false,
};

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdErr().writer();

    var cfg = Config{};
    var parsing_args = true;
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (parsing_args and std.mem.startsWith(u8, arg.text, "-")) {
            if (std.mem.eql(u8, arg.text, "--")) {
                parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--raw") catch return ai.err("Expected value", .{})) |rawv| {
                try positionals.append(rawv);
                continue;
            }
            if (std.mem.startsWith(u8, arg.text, "--help")) {
                try out.writeAll("glhf, read the source code or something.");
                return;
            }
            return ai.err("Bad arg. See --help", .{});
        }
        try positionals.append(arg);
    }
    var oi = PositionalIter{ .args = positionals.toOwnedSlice(), .report_info = ai.report_info };

    const MenuChoice = struct { name: []const u8, value: []const u8 };
    var menu_choices = std.ArrayList(MenuChoice).init(alloc);
    while (oi.next()) |item| {
        if (std.mem.eql(u8, item.text, "[")) {
            const namev = oi.next() orelse return ai.err("Expected name", .{});
            const valuev = oi.next() orelse return ai.err("Expected value", .{});
            const rbracket = oi.next() orelse return ai.err("Expected `]`", .{});
            if (!std.mem.eql(u8, rbracket.text, "]")) return rbracket.err(ai, "Expected `]`", .{});
            try menu_choices.append(.{ .name = namev.text, .value = valuev.text });
        } else {
            try menu_choices.append(.{ .name = item.text, .value = item.text });
        }
    }
    if (menu_choices.items.len == 0) return oi.err("Expected list of choices", .{});

    var line: usize = 0;
    var cpos = menu_choices.items.len - 1;

    for (menu_choices.items) |choice, i| {
        if (i < 9) {
            try out.print("[ {}: ", .{i + 1});
        } else {
            try out.writeAll("[ …: ");
        }
        try out.writeAll(choice.name);
        try out.writeAll(" ]\n");
    }
    try out.writeAll("\x1b[A\x1b[2C");

    const stdinF = std.io.getStdIn();

    const ot: ?std.os.linux.termios = cli.enterRawMode(stdinF) catch |e| null;
    defer if (ot) |o| cli.exitRawMode(stdinF, o) catch @panic("failed to exit");

    try fitLineToCpos(out, line, &cpos);

    while (try cli.nextEvent(stdinF)) |ev| {
        if (ev.is("ctrl+c")) {
            try out.writeAll("\x1b[2D");
            try fitLineToCpos(out, menu_choices.items.len, &cpos);
            return error.ReportedError;
        }
        if (ev.is("down")) {
            if (line + 1 < menu_choices.items.len) line += 1;
        } else if (ev.is("up")) {
            if (line > 0) line -= 1;
        } else if (ev.is("enter")) {
            break;
        } else if (ev == .key and ev.key.keycode == .character and std.meta.eql(ev.key.modifiers, cli.Event.KeyModifiers{})) {
            if (std.fmt.charToDigit(@truncate(u8, ev.key.keycode.character), 10)) |digit| {
                line = digit;
                if (line > menu_choices.items.len) line = menu_choices.items.len;
                if (line > 0) line -= 1;
            } else |e| {}
        }
        try fitLineToCpos(out, line, &cpos);
    }
    try out.writeAll("\x1b[2D");
    try fitLineToCpos(out, menu_choices.items.len, &cpos);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(menu_choices.items[line].value);
    try stdout.writeAll("\n");
}

pub fn fitLineToCpos(out: anytype, line: usize, cpos: *usize) !void {
    if (line > cpos.*) {
        try out.print("\x1b[{}B", .{line - cpos.*});
    } else if (line < cpos.*) {
        try out.print("\x1b[{}A", .{cpos.* - line});
    }
    cpos.* = line;
}
