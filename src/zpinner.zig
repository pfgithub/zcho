const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;
const reportError = help.reportError;
const spinners_file = @import("spinners.zig");
const Spinner = spinners_file.Spinner;
const spinners = spinners_file.spinners;
const range = help.range;

pub const main = help.anyMain(exec);

// progressbar 24.8% "_" "=" {width: , direction: ltr}

const Percentage = struct {
    data: u64,
    max: u64,
    // base 10 "float"
    // or just don't do this and use a float because it's easier
};

const Config = struct {
    parsing_args: bool = true,
    demo: bool = false,
    preset: Spinner = spinners.get("dotsWindows").?,
    _: []const Positional = &[_]Positional{},
};
const Positional = struct { text: []const u8, pos: usize };

const helppage =
    \\Usage: spinner [options]
    \\Options:
    \\    --demo: demo the spinner
    \\    --preset [preset]: use a preset
    \\    --list-presets: list presets. use with --demo to demo.
    \\    --speed [ms]: use a custom speed
    \\    --custom { …[pieces] }: use a custom spinner
;

/// readArgOneValue(u8, arg, "--preset") catch return ai.err("Expected preset name")
fn readArgOneValue(arg: []const u8, ai: *ArgsIter, comptime expcdt: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, arg, expcdt)) {
        return ai.next() orelse return error.ExpectedValue;
    }
    if (std.mem.startsWith(u8, arg, expcdt ++ "=")) {
        ai.subindex = expcdt.len + 1;
        const v = arg[expcdt.len + 1 ..];
        if (v.len == 0) return error.ExpectedValue;
        return v;
    }
    return null;
}

pub fn exec(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) !void {
    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args) {
            if (std.mem.eql(u8, arg, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (std.mem.eql(u8, arg, "--demo")) {
                cfg.demo = true;
                continue;
            }
            if (readArgOneValue(arg, ai, "--preset") catch return ai.err("Expected preset name")) |presetname| {
                cfg.preset = spinners.get(presetname) orelse return ai.err("Invalid preset name. List of presets in --list-presets");
                continue;
            }
            if (std.mem.eql(u8, arg, "--help")) {
                try out.writeAll(helppage);
                return;
            }
            if (std.mem.startsWith(u8, arg, "-")) {
                return help.reportError(ai, ai.index, "Bad arg. See --help");
            }
        }
        try positionals.append(.{ .text = arg, .pos = ai.index });
    }
    cfg._ = positionals.toOwnedSlice();

    if (cfg._.len > 0) return reportError(ai, cfg._[0].pos, "usage eg: spinner");
    while (true) {
        const current_time = @bitCast(u64, std.time.milliTimestamp());
        const spinner = &cfg.preset;
        const frame = @divFloor(current_time, spinner.interval) % spinner.frames.len;
        const thisframe = spinner.frames[frame];
        try out.writeAll(thisframe);
        if (cfg.demo) {
            const delay_time_ns = (spinner.interval - (current_time - (@divFloor(current_time, spinner.interval) * spinner.interval))) * std.time.ns_per_ms;
            std.time.sleep(delay_time_ns);
            for (range(help.unicodeLen(thisframe))) |_| try out.writeAll("\x1b[D");
        } else break;
    }
}
