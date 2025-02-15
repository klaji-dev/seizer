const std = @import("std");
const Builder = std.Build;

const Example = enum {
    clear,
    blit,
    fill_rect,
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
    canvas,
    cutscene,
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

    const shimizu_dep = b.dependency("shimizu", .{
        .target = target,
        .optimize = optimize,
    });

    const zigcoro_dep = b.dependency("zigcoro", .{
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

    // seizer
    const module = b.addModule("seizer", .{
        .root_source_file = b.path("src/seizer.zig"),
        .imports = &.{
            .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            .{ .name = "tvg", .module = tinyvg.module("tvg") },
            .{ .name = "xev", .module = libxev.module("xev") },
            .{ .name = "AngelCodeFont", .module = angelcode_font_module },
            .{ .name = "libcoro", .module = zigcoro_dep.module("libcoro") },
        },
    });

    if (import_wayland) {
        module.addImport("shimizu", shimizu_dep.module("shimizu"));
        module.addImport("wayland-protocols", shimizu_dep.module("wayland-protocols"));
        module.addImport("wayland-unstable", wayland_unstable_module);
        module.addImport("xkb", xkb_dep.module("xkb"));
    }

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
    }

    // test seizer module
    const module_test_exe = b.addTest(.{
        .root_source_file = b.path("./src/seizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_test_exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    const run_module_test_exe = b.addRunArtifact(module_test_exe);

    const test_step = b.step("test", "Run seizer module tests");
    test_step.dependOn(&run_module_test_exe.step);

    // benchmarks
    const benchmark_optimize = b.option(std.builtin.OptimizeMode, "bench-optimize", "The optimization mode to use for the benchmarks (default ReleaseFast)") orelse .ReleaseFast;
    const zbench_dep = b.dependency("zbench", .{
        .target = target,
        .optimize = benchmark_optimize,
    });

    // color benchmarks
    const bench_color_exe = b.addExecutable(.{
        .name = "bench_color",
        .root_source_file = b.path("./bench/color.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    bench_color_exe.root_module.addImport("seizer", module);
    bench_color_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    b.installArtifact(bench_color_exe);

    const run_bench_color_exe = b.addRunArtifact(bench_color_exe);

    const bench_color_step = b.step("bench-color", "Run color benchmarks");
    bench_color_step.dependOn(&run_bench_color_exe.step);

    // image benchmarks
    const bench_image_exe = b.addExecutable(.{
        .name = "bench_image",
        .root_source_file = b.path("./bench/image.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    bench_image_exe.root_module.addImport("seizer", module);
    bench_image_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    b.installArtifact(bench_image_exe);

    const run_bench_image_exe = b.addRunArtifact(bench_image_exe);
    if (b.args) |args| {
        run_bench_image_exe.addArgs(args);
    }

    const bench_image_step = b.step("bench-image", "Run image benchmarks");
    bench_image_step.dependOn(&run_bench_image_exe.step);

    // image benchmarks
    const bench_geometry_exe = b.addExecutable(.{
        .name = "bench_geometry",
        .root_source_file = b.path("./bench/geometry.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    bench_geometry_exe.root_module.addImport("seizer", module);
    bench_geometry_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    b.installArtifact(bench_geometry_exe);

    const run_bench_geometry_exe = b.addRunArtifact(bench_geometry_exe);
    if (b.args) |args| {
        run_bench_geometry_exe.addArgs(args);
    }

    const bench_geometry_step = b.step("bench-geometry", "Run geometry benchmarks");
    bench_geometry_step.dependOn(&run_bench_geometry_exe.step);

    // Compile everything without installing it, so we can skip the LLVM output
    const check_step = b.step("check", "check that everything compiles");

    const check_module_test_exe = b.addTest(.{
        .root_source_file = b.path("./src/seizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    check_module_test_exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    check_step.dependOn(&check_module_test_exe.step);

    const check_bench_color_exe = b.addExecutable(.{
        .name = "bench_color",
        .root_source_file = b.path("./bench/color.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    check_bench_color_exe.root_module.addImport("seizer", module);
    check_bench_color_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    check_step.dependOn(&check_bench_color_exe.step);

    const check_bench_image_exe = b.addExecutable(.{
        .name = "bench_image",
        .root_source_file = b.path("./bench/image.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    check_bench_image_exe.root_module.addImport("seizer", module);
    check_bench_image_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    check_step.dependOn(&check_bench_image_exe.step);

    const check_bench_geometry_exe = b.addExecutable(.{
        .name = "bench_geometry",
        .root_source_file = b.path("./bench/geometry.zig"),
        .target = target,
        .optimize = benchmark_optimize,
    });
    check_bench_geometry_exe.root_module.addImport("seizer", module);
    check_bench_geometry_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));
    check_step.dependOn(&check_bench_geometry_exe.step);

    inline for (example_fields) |tag| {
        // check that this example compiles, but skip llvm output that takes a while to run
        const exe_check = b.addExecutable(.{
            .name = tag.name,
            .root_source_file = b.path("examples/" ++ tag.name ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_check.root_module.addImport("seizer", module);
        check_step.dependOn(&exe_check.step);
    }
}
