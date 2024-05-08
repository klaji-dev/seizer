const std = @import("std");
const Builder = std.Build;

const Example = enum {
    clear,
    textures,
    bitmap_font,
    sprite_batch,
    tinyvg,
    gamepad,
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const tinyvg = b.dependency("tinyvg", .{
        .target = target,
        .optimize = optimize,
    });

    const zflecs = b.dependency("zflecs", .{
        .target = target,
        .optimize = optimize,
    });

    const gl_module = b.addModule("gl", .{
        .root_source_file = .{ .path = "dep/gles3v0.zig" },
    });

    const egl_module = b.addModule("EGL", .{
        .root_source_file = .{ .path = "dep/EGL.zig" },
    });

    const wayland_module = b.addModule("wayland", .{
        .root_source_file = .{ .path = "dep/wayland/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const wayland_protocols_module = b.addModule("wayland-protocols", .{
        .root_source_file = .{ .path = "dep/wayland-protocols/protocols.zig" },
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wayland", .module = wayland_module },
        },
    });

    const generate_wayland_step = b.step("generate-wayland-protocols", "Generate wayland-protocols and copy files to source repository. Does nothing if `generate-wayland-protocols` option is false.");

    const should_generate_wayland_protocols = b.option(bool, "generate-wayland-protocols", "should the wayland protocols be generated from xml? (default: false)") orelse false;
    if (should_generate_wayland_protocols) {
        if (b.lazyDependency("zig-xml", .{
            .target = target,
            .optimize = optimize,
        })) |xml| {
            const generate_wayland_exe = b.addExecutable(.{
                .name = "generate-wayland",
                .root_source_file = .{ .path = "tools/generate-wayland.zig" },
                .target = target,
                .optimize = optimize,
            });
            generate_wayland_exe.root_module.addImport("xml", xml.module("xml"));

            const write_wayland_protocols = b.addNamedWriteFiles("wayland-protocols");

            write_wayland_protocols.addBytesToSource(
                \\pub const stable = @import("./stable/protocols.zig");
                \\
            ,
                "dep/wayland-protocols/protocols.zig",
            );

            write_wayland_protocols.addBytesToSource(
                \\pub const @"xdg-shell" = @import("./xdg-shell.zig");
                \\pub const @"linux-dmabuf-v1" = @import("./linux-dmabuf-v1.zig");
                \\
            ,
                "dep/wayland-protocols/stable/protocols.zig",
            );

            // generate wayland core protocol
            const generate_protocol_wayland = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_wayland.addFileArg(b.path("dep/wayland/src/wayland.xml"));
            generate_protocol_wayland.addArg("5");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_wayland.captureStdOut(), "dep/wayland/src/wayland.zig");

            // generate xdg-shell protocol
            const generate_protocol_xdg_shell = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_xdg_shell.addFileArg(b.path("dep/wayland-protocols/stable/xdg-shell.xml"));
            generate_protocol_xdg_shell.addArg("2");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_xdg_shell.captureStdOut(), "dep/wayland-protocols/stable/xdg-shell.zig");

            // generate linux dmabuf protocol
            const generate_protocol_linux_dmabuf_v1 = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_linux_dmabuf_v1.addFileArg(b.path("dep/wayland-protocols/stable/linux-dmabuf-v1.xml"));
            generate_protocol_linux_dmabuf_v1.addArg("4");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_linux_dmabuf_v1.captureStdOut(), "dep/wayland-protocols/stable/linux-dmabuf-v1.zig");

            const fmt_protocol_files = b.addFmt(.{ .paths = &.{
                "dep/wayland/src/wayland.zig",
                "dep/wayland-protocols/stable/xdg-shell.zig",
                "dep/wayland-protocols/stable/linux-dmabuf-v1.zig",
            } });
            fmt_protocol_files.step.dependOn(&write_wayland_protocols.step);

            generate_wayland_step.dependOn(&fmt_protocol_files.step);
        }
    }

    // seizer
    const module = b.addModule("seizer", .{
        .root_source_file = .{ .path = "src/seizer.zig" },
        .imports = &.{
            .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            .{ .name = "tvg", .module = tinyvg.module("tvg") },
            .{ .name = "gl", .module = gl_module },
            .{ .name = "EGL", .module = egl_module },
            .{ .name = "zflecs", .module = zflecs.module("zflecs") },
            .{ .name = "wayland", .module = wayland_module },
            .{ .name = "wayland-protocols", .module = wayland_protocols_module },
        },
    });

    const example_fields = @typeInfo(Example).Enum.fields;
    inline for (example_fields) |tag| {
        const tag_name = tag.name;
        const exe = b.addExecutable(.{
            .name = tag_name,
            .root_source_file = .{ .path = "examples/" ++ tag_name ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("seizer", module);
        exe.step.dependOn(generate_wayland_step);

        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);

        // build
        const build_step = b.step("example-" ++ tag_name, "Build the " ++ tag_name ++ " example");
        build_step.dependOn(&install_exe.step);

        // run
        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("example-" ++ tag_name ++ "-run", "Run the " ++ tag_name ++ " example");
        run_step.dependOn(&run_cmd.step);
    }

    const test_all = b.step("test-all", "run all tests");

    const test_gamepad_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/Gamepad.zig" },
        .target = target,
        .optimize = optimize,
    });
    const test_gamepad_run_exe = b.addRunArtifact(test_gamepad_exe);
    const test_gamepad = b.step("test-gamepad", "Run gamepad tests");
    test_gamepad.dependOn(&test_gamepad_run_exe.step);

    test_all.dependOn(test_gamepad);
}
