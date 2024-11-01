var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var prng = std.Random.DefaultPrng.init(2958574218529385335);

var sample_64x64_image: seizer.Image = undefined;
var sample_640x480_image: seizer.Image = undefined;
var sample_1280x960_image: seizer.Image = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();

    sample_64x64_image = try seizer.Image.alloc(gpa.allocator(), .{ 64, 64 });
    for (sample_64x64_image.pixels[0 .. sample_64x64_image.size[0] * sample_64x64_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    sample_640x480_image = try seizer.Image.alloc(gpa.allocator(), .{ 640, 480 });
    for (sample_640x480_image.pixels[0 .. sample_640x480_image.size[0] * sample_640x480_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    sample_1280x960_image = try seizer.Image.alloc(gpa.allocator(), .{ 1280, 960 });
    for (sample_1280x960_image.pixels[0 .. sample_1280x960_image.size[0] * sample_1280x960_image.size[1]]) |*pixel| {
        pixel.* = seizer.color.argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
    }

    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer bench.deinit();

    try bench.add("copy 640x480 to 640x480", copy_640x480_to_640x480, .{});
    try bench.add("copy 640x480 to slice of 1280x960", copy_640x480_to_slice_of_1280x960, .{});
    try bench.add("composite 640x480 to 640x480", composite_640x480_to_640x480, .{});
    try bench.add("composite 640x480 to slice of 1280x960", composite_640x480_to_slice_of_1280x960, .{});
    try bench.add("composite 1280x960 to 1280x960", composite_1280x960_to_1280x960, .{});
    try bench.add("composite 4096 64x64 to 640x480", composite_4096_64x64_to_640x480, .{});
    try bench.add("composite 4096 64x64 to 1280x960", composite_4096_64x64_to_1280x960, .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn copy_640x480_to_640x480(allocator: std.mem.Allocator) void {
    const new_640x480_image = seizer.Image.alloc(allocator, .{ 640, 480 }) catch unreachable;
    defer new_640x480_image.free(allocator);

    new_640x480_image.copy(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_640x480_image.pixels);
}

fn copy_640x480_to_slice_of_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = seizer.Image.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    const pos = [2]u32{
        prng.random().uintAtMostBiased(u32, 640),
        prng.random().uintAtMostBiased(u32, 480),
    };

    new_1280x960_image.slice(pos, .{ 640, 480 }).copy(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_640x480_to_640x480(allocator: std.mem.Allocator) void {
    const new_640x480_image = seizer.Image.alloc(allocator, .{ 640, 480 }) catch unreachable;
    defer new_640x480_image.free(allocator);

    new_640x480_image.composite(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_640x480_image.pixels);
}

fn composite_640x480_to_slice_of_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = seizer.Image.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    const pos = [2]u32{
        prng.random().uintAtMostBiased(u32, 640),
        prng.random().uintAtMostBiased(u32, 480),
    };

    new_1280x960_image.slice(pos, .{ 640, 480 }).composite(sample_640x480_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_1280x960_to_1280x960(allocator: std.mem.Allocator) void {
    const new_1280x960_image = seizer.Image.alloc(allocator, .{ 1280, 960 }) catch unreachable;
    defer new_1280x960_image.free(allocator);

    new_1280x960_image.composite(sample_1280x960_image);
    std.mem.doNotOptimizeAway(new_1280x960_image.pixels);
}

fn composite_4096_64x64_to_640x480(allocator: std.mem.Allocator) void {
    const framebuffer = seizer.Image.alloc(allocator, .{ 1280, 960 }) catch unreachable;
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
    const framebuffer = seizer.Image.alloc(allocator, .{ 1280, 960 }) catch unreachable;
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

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
