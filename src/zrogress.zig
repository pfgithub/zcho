const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;
const reportError = help.reportError;
const range = help.range;
const progress_import = @import("progress.zig");
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
const Positional = struct { text: []const u8, pos: usize };

pub fn exec(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) !void {
    const cmd_idx = ai.index;
    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args) {
            if (std.mem.eql(u8, arg, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--preset") catch return ai.err("Expected preset name")) |presetname| {
                cfg.preset = presets.get(presetname) orelse return ai.err("Invalid preset name. List of presets in --list-presets");
                continue;
            }
            if (std.mem.eql(u8, arg, "--list-presets")) {
                cfg.todo = .list_presets;
                continue;
            }
            if (std.mem.eql(u8, arg, "--demo")) {
                cfg.demo = true;
                continue;
            }
            if (std.mem.startsWith(u8, arg, "-")) {
                return help.reportError(ai, ai.index, "Bad arg. See --help");
            }
        }
        try positionals.append(.{ .text = arg, .pos = ai.index });
    }
    cfg._ = positionals.toOwnedSlice();

    switch (cfg.todo) {
        .list_presets => {
            for (presets.keys) |key, i| {
                if (cfg.demo) {
                    try out.writeAll("[");
                    try printProgress(out, presets.get(key).?, 18, 25, 100);
                    try out.writeAll("] (25%)  --preset=");
                }
                try out.writeAll(key);
                try out.writeAll("\n");
            }
            return;
        },
        .normal => {},
    }

    // ok what to do:
    // support 25% (:: 25 / 100)
    // support 25 / 100 (:: 25 / 100)
    // support 0.25 / 1 (:: 0.25 / 1)

    var progress: u16 = 25;
    var max: u16 = 200;
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
    const progress: u32 = raw_progress * width_chars;
    const max: u32 = raw_max * width_chars;
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
