const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tilo = b.addExecutable(.{
        .name = "tilo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .use_llvm = true,
        .use_lld = true,
    });

    tilo.root_module.linkSystemLibrary("wayland-server", .{});
    tilo.root_module.linkSystemLibrary("wlroots-0.20", .{});
    tilo.root_module.linkSystemLibrary("xkbcommon", .{});

    b.installArtifact(tilo);

    const run_cmd = b.addRunArtifact(tilo);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
