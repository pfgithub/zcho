const std = @import("std");

pub const Progress = []const []const u8;

fn CustomStringMap(a: anytype, b: anytype) type {
    const csm = std.ComptimeStringMap(a, b);
    return struct {
        pub const has = csm.has;
        pub const get = csm.get;
        pub const keys = blk: {
            var res: []const []const u8 = &[_][]const u8{};
            for (b) |c| {
                res = res ++ &[_][]const u8{c[0]};
            }
            break :blk res;
        };
    };
}

pub const presets = CustomStringMap(Progress, .{
    .{ "smooth", &[_][]const u8{ " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" } },
    .{ "thin", &[_][]const u8{ " ", "╴", "─" } },
    .{ "boring", &[_][]const u8{ "-", "=" } },
});
