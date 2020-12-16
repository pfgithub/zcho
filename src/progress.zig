const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;
const range = help.range;
const progress_import = @import("lib/progress.zig");
const Progress = progress_import.Progress;
const presets = progress_import.presets;

pub const main = help.anyMain(exec);

// progressbar 24.8% "_" "=" {width: , direction: ltr}

// usage: progressbar 70 / 100 "-" "-" --transition (set_color black)
//        progressbar 12% --chars [ " " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█" ]
//        progressbar 10 --load --chars ['⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' ]
//        progressbar 10 --load --preset dots
//        progressbar 70% --chars [ " " "╴" "─" ]
// add some from here https://jsfiddle.net/sindresorhus/2eLtsbey/embedded/result/ like dotswindows and material as a different name maybe idk
// https://github.com/sindresorhus/cli-spinners/blob/HEAD/spinners.json
// for progressbar, the first arg should be the speed or something. zrogress can decide what frame to put based on system time.
//     zrogress --spinner
//     zrogress 25%
//     zrogress 25% --preset bar
//     zrogress 25% --chars [ " " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█" ]
// ideas for how [ ] could work
//    --raw "[" --raw "]" --raw "--" -- --raw no longer works

const Preset = enum { default, bar };
const Config = struct {
    parsing_args: bool = true,
    demo: bool = false,
    width: u16 = 20,
    todo: enum { normal, list_presets } = .normal,
    preset: Progress = presets.get("smooth").?,
    _: []const Positional = &[_]Positional{},
};
const Positional = help.Positional;
const PMax = struct { progress: u16, max: u16 };

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdOut().writer();

    const cmd_idx = ai.index;
    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args) {
            if (std.mem.eql(u8, arg.text, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--preset") catch return ai.err("Expected preset name", .{})) |presetname| {
                cfg.preset = presets.get(presetname.text) orelse return presetname.err(ai, "Invalid preset name. List of presets in --list-presets", .{});
                continue;
            }
            if (ai.readValue(arg, "--width") catch return ai.err("Expected width value", .{})) |widthstr| {
                cfg.width = std.fmt.parseInt(u16, widthstr.text, 10) catch |e| switch (e) {
                    error.Overflow => return ai.err("Maximum width is {}", .{std.math.maxInt(u16)}),
                    error.InvalidCharacter => return ai.err("Expected a number", .{}),
                };
                continue;
            }
            if (std.mem.eql(u8, arg.text, "--list-presets")) {
                cfg.todo = .list_presets;
                continue;
            }
            if (std.mem.eql(u8, arg.text, "--demo")) {
                cfg.demo = true;
                continue;
            }
            if (std.mem.startsWith(u8, arg.text, "-")) {
                return arg.err(ai, "Bad arg. See --help", .{});
            }
        }
        try positionals.append(arg);
    }
    cfg._ = positionals.toOwnedSlice();

    const p_max: ?PMax = switch (cfg._.len) {
        0 => null,
        1 => blk: {
            // expect percentage.
            // maybe in the future support 1/2 or 1/ 2 or something? probably not, 1 / 2 is fine
            const parg = cfg._[0];
            if (!std.mem.endsWith(u8, parg.text, "%")) return parg.err(ai, "Expected 25% or something. see --help", .{});
            const number = std.fmt.parseFloat(f64, parg.text[0 .. parg.text.len - 1]) catch |e| switch (e) {
                error.InvalidCharacter => return parg.err(ai, "This is not a number. see --help", .{}),
            };
            const umax = std.math.maxInt(u16);
            var fval = number * umax / 100;
            if (fval > umax) fval = std.math.maxInt(u16) //
            else if (fval < 0) fval = 0;
            break :blk PMax{ .progress = @floatToInt(u16, fval), .max = umax };
        },
        3 => blk: {
            if (!std.mem.eql(u8, "/", cfg._[1].text)) return cfg._[1].err(ai, "Expected eg 1 / 2. See --help", .{});
            const left = std.fmt.parseInt(u16, cfg._[0].text, 10) catch |e| switch (e) {
                error.InvalidCharacter => return cfg._[0].err(ai, "This is not a number.", .{}),
                error.Overflow => return cfg._[0].err(ai, "Number too big. Max is {}", .{std.math.maxInt(u16)}),
            };
            const right = std.fmt.parseInt(u16, cfg._[2].text, 10) catch |e| switch (e) {
                error.InvalidCharacter => return cfg._[2].err(ai, "This is not a number.", .{}),
                error.Overflow => return cfg._[2].err(ai, "Number too big. Max is {}", .{std.math.maxInt(u16)}),
            };
            break :blk PMax{ .progress = left, .max = right };
        },
        else => {
            return cfg._[cfg._.len - 1].err(ai, "Expected 1 / 2 or 25% or something. see --help", .{});
        },
    };

    switch (cfg.todo) {
        .list_presets => {
            const pmx = p_max orelse PMax{ .progress = 23, .max = 100 };
            for (presets.keys) |key, i| {
                if (cfg.demo) {
                    try out.writeAll("[");
                    try printProgress(out, presets.get(key).?, cfg.width, pmx.progress, pmx.max);
                    try out.writeAll("]  --preset=");
                }
                try out.writeAll(key);
                try out.writeAll("\n");
            }
            return;
        },
        .normal => {},
    }
    const pmx = p_max orelse {
        if (cfg._.len > 0) unreachable; // I think this should get reported
        return ai.err("Expected progress, eg 25 / 100 or 25%. See --help", .{});
    };

    // ok what to do:
    // support 25% (:: 25 / 100)
    // support 25 / 100 (:: 25 / 100)
    // support 0.25 / 1 (:: 0.25 / 1)

    var progress: u16 = pmx.progress;
    var max: u16 = pmx.max;
    while (true) {
        try printProgress(out, cfg.preset, cfg.width, progress, max);
        if (cfg.demo) {
            std.time.sleep(50 * std.time.ns_per_ms);
            progress = @intCast(u16, (progress + @as(u32, std.math.max(@divFloor(max, 50), 1))) % max);
            for (range(cfg.width)) |_| try out.writeAll("\x1b[D");
        } else break;
    }
}

fn printProgress(out: anytype, preset: Progress, width_chars: u16, raw_progress: u16, raw_max: u16) @TypeOf(out).Error!void {
    const progress: u32 = @as(u32, raw_progress) * width_chars;
    const max: u32 = @as(u32, raw_max) * width_chars;
    const step = raw_max;

    for (range(width_chars)) |_, i| {
        const value = i * step;
        if (value + step >= progress) {
            if (value >= progress) {
                try out.writeAll(preset[0]);
            } else {
                const stage = progress - value;
                const sidx = @divFloor(stage * (preset.len - 1), raw_max);
                try out.writeAll(preset[sidx]);
            }
        } else {
            try out.writeAll(preset[preset.len - 1]);
        }
    }
}

fn testPrintProgress(preset: Progress, width_chars: u16, raw_progress: u16, raw_max: u16, expected: []const u8) !void {
    const alloc = std.testing.allocator;
    var al = std.ArrayList(u8).init(alloc);
    defer al.deinit();
    const out = al.writer();
    try printProgress(out, preset, width_chars, raw_progress, raw_max);
    std.testing.expectEqualStrings(expected, al.items);
}

test "progress" {
    // test .{.width = 20, .max = 100, .progress = 5} == "         "… eg
    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 1, 0, 2, "0");
    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 1, 1, 2, "1");
    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 1, 2, 2, "2");

    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 2, 0, 2, "00");
    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 2, 1, 2, "20");
    try testPrintProgress(&[_][]const u8{ "0", "1", "2" }, 2, 2, 2, "22");
}
