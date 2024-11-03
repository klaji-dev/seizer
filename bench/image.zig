var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var prng: std.Random.DefaultPrng = undefined;

var src_linear_argb8888: ImageArgb8888 = undefined;
var src_linear_argbf32: ImageArgbF32 = undefined;
var src_tiled_argbf32: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)) = undefined;

var dst_linear_argb8888: ImageArgb8888 = undefined;
var dst_linear_argbf32: ImageArgbF32 = undefined;
var dst_tiled_argbf32: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)) = undefined;

var ops_pos: []const [2]u32 = &.{};

pub fn main() !void {
    defer _ = gpa.deinit();
    const stdout = std.io.getStdOut().writer();

    var src_size = [2]u32{ 64, 64 };
    var dst_size = [2]u32{ 1280, 800 };
    var seed: u64 = 2958574218529385335;
    var num_operations: u32 = 4096;

    var arg_iter = try std.process.argsWithAllocator(gpa.allocator());
    defer arg_iter.deinit();
    _ = arg_iter.skip();
    while (arg_iter.next()) |flag| {
        if (std.mem.eql(u8, flag, "--src-width")) {
            const src_width_text = arg_iter.next() orelse {
                std.debug.print("flag `--src-width` missing argument\n", .{});
                std.process.exit(1);
            };
            src_size[0] = try std.fmt.parseInt(u32, src_width_text, 0);
        } else if (std.mem.eql(u8, flag, "--src-height")) {
            const src_height_text = arg_iter.next() orelse {
                std.debug.print("flag `--src-height` missing argument\n", .{});
                std.process.exit(1);
            };
            src_size[1] = try std.fmt.parseInt(u32, src_height_text, 0);
        } else if (std.mem.eql(u8, flag, "--dst-width")) {
            const dst_width_text = arg_iter.next() orelse {
                std.debug.print("flag `--dst-width` missing argument\n", .{});
                std.process.exit(1);
            };
            dst_size[0] = try std.fmt.parseInt(u32, dst_width_text, 0);
        } else if (std.mem.eql(u8, flag, "--dst-height")) {
            const dst_height_text = arg_iter.next() orelse {
                std.debug.print("flag `--dst-height` missing argument\n", .{});
                std.process.exit(1);
            };
            dst_size[1] = try std.fmt.parseInt(u32, dst_height_text, 0);
        } else if (std.mem.eql(u8, flag, "--seed")) {
            const seed_text = arg_iter.next() orelse {
                std.debug.print("flag `--seed` missing argument\n", .{});
                std.process.exit(1);
            };
            seed = try std.fmt.parseInt(u64, seed_text, 0);
        } else if (std.mem.eql(u8, flag, "--num-ops")) {
            const num_ops_text = arg_iter.next() orelse {
                std.debug.print("flag `--num-ops` missing argument\n", .{});
                std.process.exit(1);
            };
            num_operations = try std.fmt.parseInt(u32, num_ops_text, 0);
        } else {
            std.debug.print("unknown flag \"{}\"\n", .{std.zig.fmtEscapes(flag)});
            std.process.exit(1);
        }
    }

    try stdout.print(
        \\seed = {}
        \\dst_size = <{}, {}>
        \\src_size = <{}, {}>
        \\num_operations = {}
        \\
    ,
        .{ seed, dst_size[0], dst_size[1], src_size[0], src_size[1], num_operations },
    );

    prng = std.Random.DefaultPrng.init(seed);

    // init operation positions
    const ops_pos_buffer = try gpa.allocator().alloc([2]u32, num_operations);
    for (ops_pos_buffer) |*pos| {
        pos.* = [2]u32{
            prng.random().uintLessThan(u32, dst_size[0] - src_size[0]),
            prng.random().uintLessThan(u32, dst_size[1] - src_size[1]),
        };
    }
    ops_pos = ops_pos_buffer;

    // init src images
    src_linear_argb8888 = try ImageArgb8888.alloc(gpa.allocator(), src_size);
    defer src_linear_argb8888.free(gpa.allocator());

    src_linear_argbf32 = try ImageArgbF32.alloc(gpa.allocator(), src_size);
    defer src_linear_argbf32.free(gpa.allocator());

    src_tiled_argbf32 = try seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(gpa.allocator(), src_size);
    defer src_tiled_argbf32.free(gpa.allocator());

    for (0..src_size[1]) |y| {
        for (0..src_size[0]) |x| {
            const pos = [2]u32{ @intCast(x), @intCast(y) };
            const pixel = seizer.color.argb(f32).fromRGBUnassociatedAlpha(
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
            );

            src_linear_argb8888.setPixel(pos, pixel.toArgb8888());
            src_linear_argbf32.setPixel(pos, pixel);
            src_tiled_argbf32.setPixel(pos, pixel);
        }
    }

    // init dst images
    dst_linear_argb8888 = try ImageArgb8888.alloc(gpa.allocator(), dst_size);
    defer dst_linear_argb8888.free(gpa.allocator());

    dst_linear_argbf32 = try ImageArgbF32.alloc(gpa.allocator(), dst_size);
    defer dst_linear_argbf32.free(gpa.allocator());

    dst_tiled_argbf32 = try seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)).alloc(gpa.allocator(), dst_size);
    defer dst_tiled_argbf32.free(gpa.allocator());

    // create benchmarks
    var bench = zbench.Benchmark.init(gpa.allocator(), .{
        .hooks = .{
            .before_each = clearDstImages,
        },
    });
    defer bench.deinit();

    try bench.add("copy Linear(argb8888)", linearArgb8888Copy, .{});
    try bench.add("composite Linear(argb8888)", linearArgb8888Composite, .{});
    try bench.add("composite Linear(argb(f32))", linearArgbF32Composite, .{});
    try bench.add("compositeLinear Tiled(.{16,16},argb(f32))", tiled16x16ArgbF32CompositeLinear, .{});
    try bench.add("composite Tiled(.{16,16},argb(f32))", tiled16x16ArgbF32Composite, .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn clearDstImages() void {
    dst_linear_argb8888.clear(seizer.color.argb8888.BLACK);
    dst_linear_argbf32.clear(seizer.color.argb(f32).BLACK);
    dst_tiled_argbf32.clear(seizer.color.argb(f32).BLACK);
}

fn linearArgb8888Copy(_: std.mem.Allocator) void {
    for (ops_pos) |pos| {
        dst_linear_argb8888.slice(pos, src_linear_argb8888.size).copy(src_linear_argb8888);
        std.mem.doNotOptimizeAway(dst_linear_argb8888.pixels);
    }
}

fn linearArgb8888Composite(_: std.mem.Allocator) void {
    for (ops_pos) |pos| {
        dst_linear_argb8888.slice(pos, src_linear_argb8888.size).composite(src_linear_argb8888);
        std.mem.doNotOptimizeAway(dst_linear_argb8888.pixels);
    }
}

fn linearArgbF32Composite(_: std.mem.Allocator) void {
    for (ops_pos) |pos| {
        dst_linear_argbf32.slice(pos, src_linear_argbf32.size).composite(src_linear_argbf32);
        std.mem.doNotOptimizeAway(dst_linear_argbf32.pixels);
    }
}

fn tiled16x16ArgbF32CompositeLinear(_: std.mem.Allocator) void {
    for (ops_pos) |pos| {
        dst_tiled_argbf32.slice(pos, src_linear_argbf32.size).compositeLinear(src_linear_argbf32);
        std.mem.doNotOptimizeAway(dst_tiled_argbf32.tiles);
    }
}

fn tiled16x16ArgbF32Composite(_: std.mem.Allocator) void {
    for (ops_pos) |pos| {
        dst_tiled_argbf32.slice(pos, src_tiled_argbf32.size_px).composite(src_tiled_argbf32);
        std.mem.doNotOptimizeAway(dst_tiled_argbf32.tiles);
    }
}

const ImageArgb8888 = seizer.image.Image(seizer.color.argb8888);
const ImageArgbF32 = seizer.image.Image(seizer.color.argb(f32));

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
