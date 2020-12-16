const std = @import("std");
const help = @import("main.zig");

pub const main = help.anyMain(exec);

const Config = struct {
    parsing_args: bool = true,
    _: []const Positional = &[_]Positional{},
};
const Positional = help.Positional;

pub fn exec(exec_args: help.MainFnArgs) !void {
    const ai = exec_args.args_iter;
    const alloc = exec_args.arena_allocator;
    const out = std.io.getStdOut().writer();

    var cfg = Config{};
    var positionals = std.ArrayList(Positional).init(alloc);
    while (ai.next()) |arg| {
        if (cfg.parsing_args and std.mem.startsWith(u8, arg.text, "-")) {
            if (std.mem.eql(u8, arg.text, "--")) {
                cfg.parsing_args = false;
                continue;
            }
            if (ai.readValue(arg, "--raw") catch return ai.err("Expected value", .{})) |rawv| {
                try positionals.append(arg);
                continue;
            }
            return ai.err("Bad arg. See --help", .{});
        }
        try positionals.append(arg);
    }
    cfg._ = positionals.toOwnedSlice(); // TODO delete this and do a positionaliter instead

    const base_folder = try std.fs.cwd().openDir(cfg._[0].text, .{});

    var list = std.ArrayList(Entry).init(exec_args.allocator);
    defer list.deinit();

    // while (true) {}
}
const Entry = struct { _todo: u1 };

// breadth first find
// scores where to search first based on:
// - number of files in the folder
// - number of folders in the chain

// something like this might be neat idk
//
// ai.auto(Config, out, struct {
//     fn @"--help"(ai: *ArgsIter, cfg: Config, o: anytype) !void {
//         try o.writeAll("Help!");
//         return error.ReportedError;
//     }
// });
//
// this is where I want a feature uilang has though
// is even better because you can break from it and
// there would be no issue with capturing variables
// ai.auto(Config, out, .{
//     .@"--help" = || {}
// })
