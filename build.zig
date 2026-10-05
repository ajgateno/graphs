const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Look up the dependency declared in build.zig.zon.
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    // The package exposes two things:
    // - a Zig module (the bindings you @import)
    // - a compiled C library artifact (raylib itself)
    const raylib_module = raylib_dep.module("raylib");
    const raylib_lib = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "graphs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.linkLibrary(raylib_lib);
    exe.root_module.addImport("raylib", raylib_module);

    b.installArtifact(exe);

    // `zig build run` compiles and launches the program.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
