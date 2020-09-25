const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;
const reportError = help.reportError;
const spinners_file = @import("spinners.zig");
const Spinner = spinners_file.Spinner;
const spinners = spinners_file.spinners;

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
            if (std.mem.eql(u8, arg, "--preset")) {
                const presetname = ai.next() orelse return ai.err("Expected preset name");
                cfg.preset = spinners.get(presetname) orelse return ai.err("Invalid preset name. List of presets in --list-presets");
                continue;
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
            var view = (std.unicode.Utf8View.init(thisframe) catch unreachable).iterator();
            while (view.nextCodepoint()) |_| try out.writeAll("\x1b[D");
        } else break;
    }
}
