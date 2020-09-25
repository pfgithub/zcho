const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;
const reportError = help.reportError;

pub const main = help.anyMain(exec);

// progressbar 24.8% "_" "=" {width: , direction: ltr}

const Percentage = struct {
    data: u64,
    max: u64,
    // base 10 "float"
    // or just don't do this and use a float because it's easier
};

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

const Preset = enum { default, bar };
const Config = struct {
    parsing_args: bool = true,
    kind: enum { bar, spinner } = .bar,
    kind_index: usize = 0,
    demo: bool = false,
    preset: Preset = .default,
    _: []const []const u8 = &[_][]const u8{},
};

pub fn exec(alloc: *std.mem.Allocator, ai: *ArgsIter, out: anytype) !void {
    var cfg = Config{};
    var positionals = std.ArrayList([]const u8).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args) {
            if (std.mem.eql(u8, arg, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if(std.mem.eql(u8, arg, "--spinner")) {
                cfg.kind = .spinner;
                cfg.kind_index = ai.index;
            }
            if (std.mem.startsWith(u8, arg, "-")) {
                return help.reportError(ai, ai.index, "Bad arg. See --help");
            }
        }
        try positionals.append(arg);
    }
    cfg._ = positionals.toOwnedSlice();
    
    switch(cfg.kind) {
        .spinner => {
            return reportError(ai, cfg.kind_index, "TODO support spinner");
        },
        .bar => {
            return reportError(ai, cfg.kind_index, "TODO support bar");
        },
    }
}
