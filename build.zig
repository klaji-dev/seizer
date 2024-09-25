const std = @import("std");
const Builder = std.Build;

const Example = enum {
    clear,
    textures,
    bitmap_font,
    sprite_batch,
    tinyvg,
    gamepad,
    clicker,
    ui_stage,
    multi_window,
    file_browser,
    ui_view_image,
    ui_plot_sine,
    colormapped_image,
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const import_wayland = b.option(bool, "wayland", "enable wayland display backend (defaults to true on linux)") orelse switch (target.result.os.tag) {
        .linux => true,
        .windows => false,
        else => false,
    };

    // Dependencies
    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const tinyvg = b.dependency("tinyvg", .{
        .target = target,
        .optimize = optimize,
    });

    const libxev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const vkzig_dep = b.dependency("vulkan_zig", .{
        .registry = @as([]const u8, b.pathFromRoot("dep/vk.xml")),
    });
    const vkzig_bindings = vkzig_dep.module("vulkan-zig");

    const gl_module = b.addModule("gl", .{
        .root_source_file = b.path("dep/gles3v0.zig"),
    });

    const dynamic_library_utils_module = b.addModule("dynamic-library-utils", .{
        .root_source_file = b.path("dep/dynamic-library-utils.zig"),
    });

    const renderdoc_app_module = b.addModule("renderdoc_app", .{
        .root_source_file = b.path("dep/renderdoc_app.zig"),
        .imports = &.{
            .{ .name = "dynamic-library-utils", .module = dynamic_library_utils_module },
        },
    });

    const egl_module = b.addModule("EGL", .{
        .root_source_file = b.path("dep/EGL.zig"),
        .imports = &.{
            .{ .name = "dynamic-library-utils", .module = dynamic_library_utils_module },
        },
    });

    const xkb_module = b.addModule("xkb", .{
        .root_source_file = b.path("dep/xkb/xkb.zig"),
    });

    const wayland_module = b.addModule("wayland", .{
        .root_source_file = b.path("dep/wayland/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "xev", .module = libxev.module("xev") },
        },
    });

    const wayland_protocols_module = b.addModule("wayland-protocols", .{
        .root_source_file = b.path("dep/wayland-protocols/protocols.zig"),
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
                .root_source_file = b.path("tools/generate-wayland.zig"),
                .target = target,
                .optimize = optimize,
            });
            generate_wayland_exe.root_module.addImport("xml", xml.module("xml"));

            const write_wayland_protocols = b.addNamedWriteFiles("wayland-protocols");

            write_wayland_protocols.addBytesToSource(
                \\pub const stable = @import("./stable/protocols.zig");
                \\pub const unstable = @import("./unstable/protocols.zig");
                \\pub const staging = @import("./staging/protocols.zig");
                \\
            ,
                "dep/wayland-protocols/protocols.zig",
            );

            write_wayland_protocols.addBytesToSource(
                \\pub const @"xdg-shell" = @import("./xdg-shell.zig");
                \\pub const @"linux-dmabuf-v1" = @import("./linux-dmabuf-v1.zig");
                \\pub const @"viewporter" = @import("./viewporter.zig");
                \\
            ,
                "dep/wayland-protocols/stable/protocols.zig",
            );

            write_wayland_protocols.addBytesToSource(
                \\pub const @"xdg-decoration-unstable-v1" = @import("./xdg-decoration-unstable-v1.zig");
                \\
            ,
                "dep/wayland-protocols/unstable/protocols.zig",
            );

            write_wayland_protocols.addBytesToSource(
                \\pub const @"fractional-scale-v1" = @import("./fractional-scale-v1.zig");
                \\
            ,
                "dep/wayland-protocols/staging/protocols.zig",
            );

            // generate wayland core protocol
            const generate_protocol_wayland = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_wayland.addFileArg(b.path("dep/wayland/src/wayland.xml"));
            generate_protocol_wayland.addArg("4");
            generate_protocol_wayland.addArg("wl_shm@1");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_wayland.captureStdOut(), "dep/wayland/src/wayland.zig");

            // generate xdg-shell protocol
            const generate_protocol_xdg_shell = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_xdg_shell.addFileArg(b.path("dep/wayland-protocols/stable/xdg-shell.xml"));
            generate_protocol_xdg_shell.addArg("1");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_xdg_shell.captureStdOut(), "dep/wayland-protocols/stable/xdg-shell.zig");

            // generate linux dmabuf protocol
            const generate_protocol_linux_dmabuf_v1 = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_linux_dmabuf_v1.addFileArg(b.path("dep/wayland-protocols/stable/linux-dmabuf-v1.xml"));
            generate_protocol_linux_dmabuf_v1.addArg("4");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_linux_dmabuf_v1.captureStdOut(), "dep/wayland-protocols/stable/linux-dmabuf-v1.zig");

            // generate viewporter protocol
            const generate_protocol_viewporter = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_viewporter.addFileArg(b.path("dep/wayland-protocols/stable/viewporter.xml"));
            generate_protocol_viewporter.addArg("4");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_viewporter.captureStdOut(), "dep/wayland-protocols/stable/viewporter.zig");

            // generate xdg-decoration protocol
            const generate_protocol_xdg_decoration = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_xdg_decoration.addFileArg(b.path("dep/wayland-protocols/unstable/xdg-decoration-unstable-v1.xml"));
            generate_protocol_xdg_decoration.addArg("1");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_xdg_decoration.captureStdOut(), "dep/wayland-protocols/unstable/xdg-decoration-unstable-v1.zig");

            const generate_protocol_fractional_scale_v1 = b.addRunArtifact(generate_wayland_exe);
            generate_protocol_fractional_scale_v1.addFileArg(b.path("dep/wayland-protocols/staging/fractional-scale-v1.xml"));
            generate_protocol_fractional_scale_v1.addArg("1");
            write_wayland_protocols.addCopyFileToSource(generate_protocol_fractional_scale_v1.captureStdOut(), "dep/wayland-protocols/staging/fractional-scale-v1.zig");

            const fmt_protocol_files = b.addFmt(.{ .paths = &.{
                "dep/wayland/src/wayland.zig",
                "dep/wayland-protocols/stable/xdg-shell.zig",
                "dep/wayland-protocols/stable/linux-dmabuf-v1.zig",
                "dep/wayland-protocols/stable/viewporter.zig",
                "dep/wayland-protocols/unstable/xdg-decoration.zig",
                "dep/wayland-protocols/staging/viewporter.zig",
            } });
            fmt_protocol_files.step.dependOn(&write_wayland_protocols.step);

            generate_wayland_step.dependOn(&fmt_protocol_files.step);
        }
    }

    // a tool that bundles a wasm binary into an html file
    const bundle_webpage_exe = b.addExecutable(.{
        .name = "bundle-webpage",
        .root_source_file = b.path("tools/bundle-webpage.zig"),
        .target = b.graph.host,
    });
    b.installArtifact(bundle_webpage_exe);

    // seizer
    const module = b.addModule("seizer", .{
        .root_source_file = b.path("src/seizer.zig"),
        .imports = &.{
            .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            .{ .name = "tvg", .module = tinyvg.module("tvg") },
            .{ .name = "renderdoc", .module = renderdoc_app_module },
            .{ .name = "gl", .module = gl_module },
            .{ .name = "xev", .module = libxev.module("xev") },
            .{ .name = "dynamic-library-utils", .module = dynamic_library_utils_module },
        },
    });
    module.link_libc = true;

    if (target.result.os.tag == .wasi) {
        module.export_symbol_names = &.{
            "_render",
            "_key_event",
            "_dispatch_read_file_completion",
            "_dispatch_write_file_completion",
        };
    }

    const import_egl = target.result.os.tag != .wasi;
    if (import_egl) {
        module.addImport("EGL", egl_module);
    }

    const vulkan_compile_shaders_step = b.step("vulkan-compile-shaders", "Compile Canvas shaders to SPIR-V using glslc (requires glslc to be installed)");
    const vulkan_compile_shaders = b.option(bool, "vulkan-compile-shaders", "Make examples depend on vulkan shaders being built") orelse false;
    {
        const compile_vertex_shader = b.addSystemCommand(&.{ "glslc", "-fshader-stage=vertex", "src/Canvas/default_shader.vertex.vulkan.glsl", "-o", "src/Canvas/default_shader.vertex.vulkan.spv" });
        const compile_fragment_shader = b.addSystemCommand(&.{ "glslc", "-fshader-stage=fragment", "src/Canvas/default_shader.fragment.vulkan.glsl", "-o", "src/Canvas/default_shader.fragment.vulkan.spv" });

        vulkan_compile_shaders_step.dependOn(&compile_vertex_shader.step);
        vulkan_compile_shaders_step.dependOn(&compile_fragment_shader.step);
    }

    const import_vulkan = true;
    if (import_vulkan) {
        module.addImport("vulkan", vkzig_bindings);
    }

    if (import_wayland) {
        module.addImport("wayland", wayland_module);
        module.addImport("wayland-protocols", wayland_protocols_module);
        module.addImport("xkb", xkb_module);
    }

    const check_step = b.step("check", "check that everything compiles");

    const example_fields = @typeInfo(Example).Enum.fields;
    inline for (example_fields) |tag| {
        const tag_name = tag.name;
        const exe = b.addExecutable(.{
            .name = tag_name,
            .root_source_file = b.path("examples/" ++ tag_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("seizer", module);
        exe.step.dependOn(generate_wayland_step);
        if (vulkan_compile_shaders) {
            exe.step.dependOn(vulkan_compile_shaders_step);
        }

        if (target.result.os.tag == .wasi) {
            exe.wasi_exec_model = .reactor;
        }

        // build
        const build_step = b.step("example-" ++ tag_name, "Build the " ++ tag_name ++ " example");

        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);
        build_step.dependOn(&install_exe.step);

        // additionally generate an HTML file with the wasm module embedded when we use the wasi target
        if (target.result.os.tag == .wasi) {
            const bundle_webpage = b.addRunArtifact(bundle_webpage_exe);
            bundle_webpage.addArtifactArg(exe);

            const install_html = b.addInstallFile(bundle_webpage.captureStdOut(), "www/" ++ tag_name ++ ".html");
            b.getInstallStep().dependOn(&install_html.step);
            build_step.dependOn(&install_html.step);
        }

        // run
        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("example-" ++ tag_name ++ "-run", "Run the " ++ tag_name ++ " example");
        run_step.dependOn(&run_cmd.step);

        // check that this example compiles, but skip llvm output that takes a while to run
        const exe_check = b.addExecutable(.{
            .name = tag_name,
            .root_source_file = b.path("examples/" ++ tag_name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_check.root_module.addImport("seizer", module);
        exe_check.step.dependOn(generate_wayland_step);

        check_step.dependOn(&exe_check.step);
    }

    const test_all = b.step("test-all", "run all tests");

    const test_xkb_exe = b.addTest(.{
        .root_source_file = b.path("dep/xkb/xkb.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_xkb_run_exe = b.addRunArtifact(test_xkb_exe);
    const test_xkb = b.step("test-xkb", "Run xkb tests");
    test_xkb.dependOn(&test_xkb_run_exe.step);

    test_all.dependOn(test_xkb);
}
