const std = @import("std");
const Builder = std.build.Builder;

fn toolMainFile(tool: []const u8) []const u8 {
    if (std.mem.eql(u8, tool, "z")) return "main";
    return tool;
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    // const tools = (list files in src/*.zig, then add `zig build zcho` commands eg and `zig build assetgen` default `zig build z`)

    const tool = b.option([]const u8, "tool", "the tool to build. z, zcho, zigsh, assetgen, …") orelse "z";
    var mainfile = std.ArrayList(u8).init(b.allocator);
    mainfile.appendSlice("src/") catch unreachable;
    mainfile.appendSlice(toolMainFile(tool)) catch unreachable;
    mainfile.appendSlice(".zig") catch unreachable;

    const exe = b.addExecutable(tool, mainfile.items);
    exe.setTarget(target);
    exe.setBuildMode(mode);

    if (std.mem.eql(u8, tool, "assetgen")) {
        exe.linkLibC();
        exe.addIncludeDir("src/lib/assetgen");
        exe.addCSourceFile("src/lib/assetgen/c.c", &[_][]const u8{});
    }

    exe.install();
}
