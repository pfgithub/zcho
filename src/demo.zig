const std = @import("std");
const help = @import("main.zig");
const ArgsIter = help.ArgsIter;

pub const main = help.anyMain(exec);

const Config = struct {
    parsing_args: bool = true,
    _: []const Positional = &[_]Positional{},
};
const Positional = struct { text: []const u8, pos: usize, epos: usize = 0 };

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdOut().writer();

    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args and std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--raw") catch return ai.err("Expected value")) |rawv| {
                try positionals.append(.{ .text = rawv, .pos = ai.index, .epos = ai.subindex });
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--help")) {
                try out.writeAll("Help.");
                return;
            }
            return ai.err("Bad arg. See --help");
        }
        try positionals.append(.{ .text = arg, .pos = ai.index });
    }
    cfg._ = positionals.toOwnedSlice();

    try out.writeAll("TODO code here.");
}
