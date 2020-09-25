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
    preset_speed_override: ?u32 = null,
    todo: enum { normal, list_presets } = .normal,
    _: []const Positional = &[_]Positional{},
};
const Positional = struct { text: []const u8, pos: usize };

const helppage =
    \\Usage: spinner [options]
    \\Options:
    \\    --demo: demo the spinner
    \\    --preset [preset]: use a preset
    \\    --list-presets: list presets. use with --demo to demo all.
    \\    --speed [ms]: use a custom speed
    \\    --custom { …[pieces] }: use a custom spinner
;

// fn readArray should read from `{` to `}`. oh wait it needs to be able to escape things. uuh.
// eg --custom=[1 2 3]
// eg --custom [1 2 3]
// eg --custom { 1 2 3 }
// eg --custom { ,{ ,} ,{ } uuh. what if ,
//    --custom={,1 ,2 ,3}
// uuh idk
// we need to use `[`/`]` or `(`/`)` because fish doesn't work with `{`/`}`

// what if z spinner --exec sleep 10
// and it would draw the spinner while sleep 10 was running
// or even better if zigsh had something for that
// whilerunning sleep 10
//    tput <-- idk
//    z spinner
// end

// to make a better --list-presets --demo,
//   enter fullscreen
//   support scrolling
//   sleep the minimum time for any of the current presets displayed on the screen, then update
// what if z list-interactive (z spinner --list-presets) '(z spinner $0)
// that would be neat
fn listPresets(out: anytype, demo: bool) @TypeOf(out).Error!void {
    for (spinners.keys) |key| {
        if (demo) {
            try out.writeAll(getFrame(spinners.get(key).?).frame);
            try out.writeAll("  ");
        }
        try out.writeAll(key);
        try out.writeAll("\n");
    }
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
            if (ai.readValue(arg, "--speed") catch return ai.err("Expected number")) |speedms| {
                cfg.preset_speed_override = std.fmt.parseInt(u32, speedms, 10) catch return ai.err("Invalid number. Expected speed in ms.");
                continue;
            }
            if (ai.readValue(arg, "--preset") catch return ai.err("Expected preset name")) |presetname| {
                cfg.preset = spinners.get(presetname) orelse return ai.err("Invalid preset name. List of presets in --list-presets");
                continue;
            }
            if (std.mem.eql(u8, arg, "--list-presets")) {
                cfg.todo = .list_presets;
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
    if (cfg.preset_speed_override) |so| cfg.preset.interval = so;

    switch (cfg.todo) {
        .list_presets => {
            try listPresets(out, cfg.demo);
            return;
        },
        .normal => {},
    }

    if (cfg._.len > 0) return reportError(ai, cfg._[0].pos, "usage eg: spinner");
    while (true) {
        const spin = getFrame(cfg.preset);
        try out.writeAll(spin.frame);
        if (cfg.demo) {
            std.time.sleep(spin.delay_ns);
            for (range(help.unicodeLen(spin.frame))) |_| try out.writeAll("\x1b[D");
        } else break;
    }
}

fn getFrame(preset: Spinner) struct { delay_ns: u64, frame: []const u8 } {
    const current_time = @bitCast(u64, std.time.milliTimestamp());
    const spinner = &preset;
    const frame = @divFloor(current_time, spinner.interval) % spinner.frames.len;
    const thisframe = spinner.frames[frame];

    const delay_time_ns = (spinner.interval - (current_time - (@divFloor(current_time, spinner.interval) * spinner.interval))) * std.time.ns_per_ms;

    return .{ .frame = thisframe, .delay_ns = delay_time_ns };
}
