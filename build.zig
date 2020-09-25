const Builder = @import("std").build.Builder;

const Command = enum { zcho, zrogress };

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zcho", "src/zcho.zig");
    exe.setTarget(target);
    exe.addBuildOption(Command, "command", .zcho);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
