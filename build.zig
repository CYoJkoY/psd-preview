const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const dll = b.addLibrary(.{
        .name = "psd_preview",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    for ([_][]const u8{ "ole32", "advapi32", "user32", "gdi32", "msimg32", "shell32", "shlwapi", "windowscodecs" }) |library| {
        dll.root_module.linkSystemLibrary(library, .{});
    }
    b.installArtifact(dll);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/parser_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run PSD parser tests").dependOn(&run_tests.step);
}
