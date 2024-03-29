const std = @import("std");
const help = @import("main.zig");
const PositionalIter = help.PositionalIter;
const Positional = help.Positional;
const cli = @import("lib/cli.zig");

pub const main = help.anyMain(exec);

const Config = struct {
    default_value: ?Positional = null,
};
const MenuChoice = struct {
    name: []const u8,
    value: []const u8,
    // hotkey: u21,
};

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdErr().writer();

    var cfg = Config{};
    var parsing_args = true;

    var menu_choices = std.ArrayList(MenuChoice).init(alloc);

    while (ai.next()) |arg| {
        if (parsing_args and std.mem.startsWith(u8, arg.text, "-")) {
            if (std.mem.eql(u8, arg.text, "--")) {
                parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--default") catch return ai.err("Expected value", .{})) |rawv| {
                if (cfg.default_value) |dv| return dv.err(ai, "Default value set twice", .{});
                cfg.default_value = rawv;
                continue;
            }
            if (std.mem.startsWith(u8, arg.text, "--help")) {
                try out.writeAll("glhf, read the source code or something.");
                return;
            }
            return ai.err("Bad arg. See --help", .{});
        }
        if (std.mem.eql(u8, arg.text, "[")) {
            const namev = ai.next() orelse return ai.err("Expected name", .{});
            const valuev = ai.next() orelse return ai.err("Expected value", .{});
            const rbracket = ai.next() orelse return ai.err("Expected `]`", .{});
            if (!std.mem.eql(u8, rbracket.text, "]")) return rbracket.err(ai, "Expected `]`", .{});
            try menu_choices.append(.{ .name = namev.text, .value = valuev.text });
        } else {
            try menu_choices.append(.{ .name = arg.text, .value = arg.text });
        }
    }

    if (menu_choices.items.len == 0) return ai.err("Expected list of choices", .{});

    var line: usize = 0;
    var cpos = menu_choices.items.len - 1;

    if (cfg.default_value) |dv| {
        line = for (menu_choices.items) |choice, i| {
            if (std.mem.eql(u8, choice.value, dv.text)) {
                break i;
            }
        } else return dv.err(ai, "Default value was not found in item list", .{});
    }

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

    const ot: ?std.os.termios = cli.enterRawMode(stdinF) catch null;
    defer if (ot) |o| cli.exitRawMode(stdinF, o) catch @panic("failed to exit");

    // get current cursor position. this is the end of the list.
    // UH OH. todo fix :: if there is queued input getCursorPosition might read text that should have been read
    // by stdin. eg spam the 1 key
    const end_pos = (cli.getCursorPosition(stdinF, out) catch |e| switch (e) {
        error.NotATTY => cli.RowCol{ .lyn = 0, .col = 0 },
        else => return e,
    }).lyn;
    const start_pos = if (menu_choices.items.len > end_pos) 0 else end_pos - menu_choices.items.len + 1;

    try fitLineToCpos(out, line, &cpos);

    cli.startCaptureMouse() catch {};
    defer cli.stopCaptureMouse() catch {};

    var mouse_selection: ?usize = null;

    while (cli.nextEvent(stdinF) catch @as(cli.Event, .none)) |ev| {
        if (ev.is("ctrl+c")) {
            try out.writeAll("\x1b[2D");
            try fitLineToCpos(out, menu_choices.items.len, &cpos);
            return error.ReportedError;
        }
        switch (ev) {
            .mouse => |mev| {
                const y = mev.y;
                // end_pos col: 25
                // y: 25
                if (y > end_pos) {
                    // off the edge of the screen. deselect.
                    mouse_selection = null;
                } else if (y < start_pos) {
                    mouse_selection = null;
                } else {
                    mouse_selection = y - start_pos;
                }

                if (mev.button == .left) {
                    // click
                    if (mouse_selection) |mslxn| {
                        line = mslxn;
                        if (mev.direction == .up) break;
                    }
                }
            },
            else => {},
        }
        if (ev.is("down")) {
            if (line + 1 < menu_choices.items.len) line += 1;
        } else if (ev.is("up")) {
            if (line > 0) line -= 1;
        } else if (ev.is("enter")) {
            break;
        } else if (ev == .key and ev.key.keycode == .character and std.meta.eql(ev.key.modifiers, cli.Event.KeyModifiers{})) {
            if (ev.key.keycode.character > '0' and ev.key.keycode.character < '9') {
                const digit = @intCast(u8, ev.key.keycode.character - '0');
                if (digit <= menu_choices.items.len and digit > 0) {
                    if (line == digit - 1) break;
                    line = digit - 1;
                }
            }
        }
        try fitLineToCpos(out, line, &cpos);
    }
    try out.writeAll("\x1b[2D");
    try fitLineToCpos(out, menu_choices.items.len, &cpos);
    for (menu_choices.items) |_| {
        try out.writeAll("\x1b[A\x1b[2K");
    }

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
