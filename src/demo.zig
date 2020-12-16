const std = @import("std");
const help = @import("main.zig");
const PositionalIter = help.PositionalIter;
const Positional = help.Positional;

pub const main = help.anyMain(exec);

const Config = struct {
    flag_enabled: bool = false,
};

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdOut().writer();

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
                try out.writeAll("Help.");
                return;
            }
            return ai.err("Bad arg. See --help", .{});
        }
        try positionals.append(arg);
    }
    var oi = PositionalIter{ .args = positionals.toOwnedSlice(), .report_info = ai.report_info };
    if (oi.next()) |nxt| return nxt.err(&oi, "Too many arguments", .{});

    try out.writeAll("TODO code here.\n");
}
