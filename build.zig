const std = @import("std");
const fs = std.fs;
const Builder = std.build.Builder;

fn toolMainFile(tool: []const u8) []const u8 {
    if (std.mem.eql(u8, tool, "z")) return "main";
    return tool;
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    // const tools = (list files in src/*.zig, then add `zig build zcho` commands eg and `zig build assetgen` default `zig build z`)

    var dir = fs.cwd().openDir("src/", .{ .iterate = true }) catch unreachable;
    defer dir.close();

    var dir_iter = dir.iterate();
    while (dir_iter.next() catch unreachable) |entry| {
        if (entry.kind != .File) continue;
        const filename = std.mem.dupe(b.allocator, u8, entry.name) catch unreachable;
        if (!std.mem.endsWith(u8, filename, ".zig")) continue;
        var tool: []const u8 = filename[0 .. filename.len - ".zig".len];
        if (std.mem.eql(u8, tool, "main")) tool = "z";

        const fullpath = std.fmt.allocPrint(b.allocator, "src/{s}", .{filename}) catch unreachable;

        const exe = b.addExecutable(tool, fullpath);
        exe.setTarget(target);
        exe.setBuildMode(mode);

        if (std.mem.eql(u8, tool, "assetgen")) {
            exe.linkLibC();
            exe.addIncludeDir("src/lib/assetgen");
            exe.addCSourceFile("src/lib/assetgen/c.c", &[_][]const u8{});
        }

        exe.install();

        const description = std.fmt.allocPrint(b.allocator, "Build {s} → {s}", .{ fullpath, tool }) catch unreachable;

        const build_step = b.step(tool, description);
        build_step.dependOn(&exe.install_step.?.step);
    }
}
