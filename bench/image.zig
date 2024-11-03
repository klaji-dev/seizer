var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var prng = std.Random.DefaultPrng.init(2958574218529385335);

var sample_64x64_image: ImageArgb8888 = undefined;
var sample_640x480_image: ImageArgb8888 = undefined;
var sample_1280x960_image: ImageArgb8888 = undefined;

var sample_16x16_image_f32: ImageArgbF32 = undefined;
var sample_64x64_image_f32: ImageArgbF32 = undefined;
var sample_640x480_image_f32: ImageArgbF32 = undefined;
var sample_1280x960_image_f32: ImageArgbF32 = undefined;

var sample_64x64_image_tiled: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)) = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();

    // init argb8888 image samples
    sample_64x64_image = try ImageArgb8888.alloc(gpa.allocator(), .{ 64, 64 });
    defer sample_64x64_image.free(gpa.allocator());
    for (sample_64x64_image.pixels[0 .. sample_64x64_image.size[0] * sample_64x64_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f64).fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    sample_640x480_image = try ImageArgb8888.alloc(gpa.allocator(), .{ 640, 480 });
    defer sample_640x480_image.free(gpa.allocator());
    for (sample_640x480_image.pixels[0 .. sample_640x480_image.size[0] * sample_640x480_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f64).fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    sample_1280x960_image = try ImageArgb8888.alloc(gpa.allocator(), .{ 1280, 960 });
    defer sample_1280x960_image.free(gpa.allocator());
    for (sample_1280x960_image.pixels[0 .. sample_1280x960_image.size[0] * sample_1280x960_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f64).fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    // init argb4xf32 image samples
    sample_16x16_image_f32 = try ImageArgbF32.alloc(gpa.allocator(), .{ 16, 16 });
    defer sample_16x16_image_f32.free(gpa.allocator());
    for (sample_16x16_image_f32.pixels[0 .. sample_16x16_image_f32.size[0] * sample_16x16_image_f32.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
    }

    sample_64x64_image_f32 = try ImageArgbF32.alloc(gpa.allocator(), .{ 64, 64 });
    defer sample_64x64_image_f32.free(gpa.allocator());
    for (sample_64x64_image_f32.pixels[0 .. sample_64x64_image_f32.size[0] * sample_64x64_image_f32.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
    }

    sample_640x480_image_f32 = try ImageArgbF32.alloc(gpa.allocator(), .{ 640, 480 });
    defer sample_640x480_image_f32.free(gpa.allocator());
    for (sample_640x480_image_f32.pixels[0 .. sample_640x480_image_f32.size[0] * sample_640x480_image_f32.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
    }

    sample_1280x960_image_f32 = try ImageArgbF32.alloc(gpa.allocator(), .{ 1280, 960 });
    defer sample_1280x960_image_f32.free(gpa.allocator());
    for (sample_1280x960_image_f32.pixels[0 .. sample_1280x960_image_f32.size[0] * sample_1280x960_image_f32.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
    }

    // init argb4xf32 tiled image samples
    sample_64x64_image_tiled = try seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(gpa.allocator(), .{ 64, 64 });
    defer sample_64x64_image_tiled.free(gpa.allocator());
    for (0..sample_64x64_image_tiled.size_px[1]) |y| {
        for (0..sample_64x64_image_tiled.size_px[0]) |x| {
            sample_64x64_image_tiled.setPixel(.{ @intCast(x), @intCast(y) }, seizer.color.argb(f32).fromRGBUnassociatedAlpha(
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
            ));
        }
    }

    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer bench.deinit();

    try bench.add("linear  argb8888            copy    1  640x480 to 640x480", copy_640x480_to_640x480, .{});
    try bench.add("linear  argb8888            copy    1  640x480 to slice of 1280x960", copy_640x480_to_slice_of_1280x960, .{});
    try bench.add("linear  argb8888       composite    1  640x480 to 640x480", composite_640x480_to_640x480, .{});
    try bench.add("linear  argb8888       composite    1  640x480 to slice of 1280x960", composite_640x480_to_slice_of_1280x960, .{});
    try bench.add("linear  argb8888       composite    1 1280x960 to 1280x960", composite_1280x960_to_1280x960, .{});
    try bench.add("linear  argb8888       composite 4096   64x64  to 640x480", composite_4096_64x64_to_640x480, .{});
    try bench.add("linear  argb8888       composite 4096   64x64  to 1280x960", composite_4096_64x64_to_1280x960, .{});
    try bench.add("linear argb(f32)       composite 4096   16x16  to 1280x960", composite_4096_16x16_to_1280x960_f32, .{});
    try bench.add("linear argb(f32)       composite 4096   64x64  to 1280x960", composite_4096_64x64_to_1280x960_f32, .{});
    try bench.add(" tiled argb(f32) compositeLinear 4096   16x16  to 1280x960", composite_4096_16x16_to_1280x960_tiled_f32, .{});
    try bench.add(" tiled argb(f32) compositeLinear 4096   64x64  to 1280x960", composite_4096_64x64_to_1280x960_tiled_f32, .{});
    try bench.add(" tiled argb(f32)       composite 4096   64x64 tiled to 1280x960", tiled_composite_4096_64x64_to_1280x960, .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn copy_640x480_to_640x480(allocator: std.mem.Allocator) void {
    const new_640x480_image = ImageArgb8888.alloc(allocator, .{ 640, 480 }) catch unreachable;
    defer new_640x480_image.free(allocator);

    new_640x480_image.copy(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_640x480_image.pixels);
}

fn copy_640x480_to_slice_of_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = ImageArgb8888.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    const pos = [2]u32{
        prng.random().uintAtMostBiased(u32, 640),
        prng.random().uintAtMostBiased(u32, 480),
    };

    new_1280x960_image.slice(pos, .{ 640, 480 }).copy(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_640x480_to_640x480(allocator: std.mem.Allocator) void {
    const new_640x480_image = ImageArgb8888.alloc(allocator, .{ 640, 480 }) catch unreachable;
    defer new_640x480_image.free(allocator);

    new_640x480_image.composite(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_640x480_image.pixels);
}

fn composite_640x480_to_slice_of_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = ImageArgb8888.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    const pos = [2]u32{
        prng.random().uintAtMostBiased(u32, 640),
        prng.random().uintAtMostBiased(u32, 480),
    };

    new_1280x960_image.slice(pos, .{ 640, 480 }).composite(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_1280x960_to_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = ImageArgb8888.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    new_1280x960_image.composite(sample_1280x960_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_4096_64x64_to_640x480(allocator: std.mem.Allocator) void {
    const framebuffer = ImageArgb8888.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);
    @memset(framebuffer.pixels[0 .. framebuffer.size[0] * framebuffer.size[1]], seizer.color.argb8888.BLACK);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size[0] - sample_64x64_image.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size[1] - sample_64x64_image.size[1]),
        };

        framebuffer.slice(pos, sample_64x64_image.size).composite(sample_64x64_image);

        std.mem.doNotOptimizeAway(framebuffer.pixels);
    }
}

fn composite_4096_64x64_to_1280x960(allocator: std.mem.Allocator) void {
    const framebuffer = ImageArgb8888.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size[0] - sample_64x64_image.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size[1] - sample_64x64_image.size[1]),
        };

        framebuffer.slice(pos, sample_64x64_image.size).composite(sample_64x64_image);

        std.mem.doNotOptimizeAway(framebuffer.pixels);
    }
}

fn composite_4096_16x16_to_1280x960_f32(allocator: std.mem.Allocator) void {
    const framebuffer = ImageArgbF32.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size[0] - sample_16x16_image_f32.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size[1] - sample_16x16_image_f32.size[1]),
        };

        framebuffer.slice(pos, sample_16x16_image_f32.size).composite(sample_16x16_image_f32);

        std.mem.doNotOptimizeAway(framebuffer.pixels);
    }
}

fn composite_4096_64x64_to_1280x960_f32(allocator: std.mem.Allocator) void {
    const framebuffer = ImageArgbF32.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size[0] - sample_64x64_image_f32.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size[1] - sample_64x64_image_f32.size[1]),
        };

        framebuffer.slice(pos, sample_64x64_image_f32.size).composite(sample_64x64_image_f32);

        std.mem.doNotOptimizeAway(framebuffer.pixels);
    }
}

fn composite_4096_16x16_to_1280x960_tiled_f32(allocator: std.mem.Allocator) void {
    const framebuffer = seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[0] - sample_16x16_image_f32.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[1] - sample_16x16_image_f32.size[1]),
        };

        framebuffer.slice(pos, sample_16x16_image_f32.size).compositeLinear(sample_16x16_image_f32);

        std.mem.doNotOptimizeAway(framebuffer.tiles);
    }
}

fn composite_4096_64x64_to_1280x960_tiled_f32(allocator: std.mem.Allocator) void {
    const framebuffer = seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[0] - sample_64x64_image_f32.size[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[1] - sample_64x64_image_f32.size[1]),
        };

        framebuffer.slice(pos, sample_64x64_image_f32.size).compositeLinear(sample_64x64_image_f32);

        std.mem.doNotOptimizeAway(framebuffer.tiles);
    }
}

fn tiled_composite_4096_64x64_to_1280x960(allocator: std.mem.Allocator) void {
    const framebuffer = seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer framebuffer.free(allocator);

    for (0..4096) |_| {
        const pos = [2]u32{
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[0] - sample_64x64_image_tiled.size_px[0]),
            prng.random().uintAtMostBiased(u32, framebuffer.size_px[1] - sample_64x64_image_tiled.size_px[1]),
        };

        framebuffer.slice(pos, sample_64x64_image_tiled.size_px).composite(sample_64x64_image_tiled);

        std.mem.doNotOptimizeAway(framebuffer.tiles);
    }
}

const ImageArgb8888 = seizer.image.Image(seizer.color.argb8888);
const ImageArgbF32 = seizer.image.Image(seizer.color.argb(f32));

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
