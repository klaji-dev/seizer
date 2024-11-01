const std = @import("std");
const Builder = std.Build;

const Example = enum {
    clear,
    blit,
    texture_rect,
    bitmap_font,
    sprite_batch,
    bicubic_filter,
    tinyvg,
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

    const xkb_dep = b.dependency("xkb", .{
        .target = target,
        .optimize = optimize,
    });

    const angelcode_font_module = b.addModule("AngelCodeFont", .{
        .root_source_file = b.path("dep/AngelCodeFont.zig"),
    });

    const generate_wayland_step = b.step("generate-wayland-protocols", "Generate wayland-protocols and copy files to source repository. Does nothing if `generate-wayland-protocols` option is false.");

    const shimizu_dep = b.dependency("shimizu", .{
        .target = target,
        .optimize = optimize,
    });

    // generate additional wayland protocol definitions with shimizu-scanner
    const generate_wayland_unstable_zig_cmd = b.addRunArtifact(shimizu_dep.artifact("shimizu-scanner"));
    generate_wayland_unstable_zig_cmd.addFileArg(b.path("dep/wayland-protocols/xdg-decoration-unstable-v1.xml"));
    generate_wayland_unstable_zig_cmd.addFileArg(b.path("dep/wayland-protocols/fractional-scale-v1.xml"));
    generate_wayland_unstable_zig_cmd.addArgs(&.{ "--interface-version", "zxdg_decoration_manager_v1", "1" });
    generate_wayland_unstable_zig_cmd.addArgs(&.{ "--interface-version", "wp_fractional_scale_manager_v1", "1" });

    generate_wayland_unstable_zig_cmd.addArg("--import");
    generate_wayland_unstable_zig_cmd.addFileArg(b.path("dep/wayland-protocols/wayland.xml"));
    generate_wayland_unstable_zig_cmd.addArg("@import(\"core\")");

    generate_wayland_unstable_zig_cmd.addArg("--import");
    generate_wayland_unstable_zig_cmd.addFileArg(b.path("dep/wayland-protocols/xdg-shell.xml"));
    generate_wayland_unstable_zig_cmd.addArg("@import(\"wayland-protocols\").xdg_shell");

    generate_wayland_unstable_zig_cmd.addArg("--output");
    const wayland_unstable_dir = generate_wayland_unstable_zig_cmd.addOutputDirectoryArg("wayland-unstable");

    const wayland_unstable_module = b.addModule("wayland-unstable", .{
        .root_source_file = wayland_unstable_dir.path(b, "root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wire", .module = shimizu_dep.module("wire") },
            .{ .name = "core", .module = shimizu_dep.module("core") },
            .{ .name = "wayland-protocols", .module = shimizu_dep.module("wayland-protocols") },
        },
    });

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
            .{ .name = "xev", .module = libxev.module("xev") },
            .{ .name = "AngelCodeFont", .module = angelcode_font_module },
        },
    });

    if (import_wayland) {
        module.addImport("shimizu", shimizu_dep.module("shimizu"));
        module.addImport("wayland-protocols", shimizu_dep.module("wayland-protocols"));
        module.addImport("wayland-unstable", wayland_unstable_module);
        module.addImport("xkb", xkb_dep.module("xkb"));
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

        // build
        const build_step = b.step("example-" ++ tag_name, "Build the " ++ tag_name ++ " example");

        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);
        build_step.dependOn(&install_exe.step);

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
}
