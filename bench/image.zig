var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var prng: std.Random.DefaultPrng = undefined;

var src_linear_argbf32: ImageArgbF32 = undefined;
var src_tiled_argbf32: seizer.image.Tiled(.{ 16, 16 }, argbf32_premultiplied) = undefined;
var src_zordered_argbf32: seizer.image.ZOrdered(argbf32_premultiplied) = undefined;
var src_planar_argbf32: seizer.image.Planar(argbf32_premultiplied) = undefined;

var dst_linear_argbf32: ImageArgbF32 = undefined;
var dst_tiled_argbf32: seizer.image.Tiled(.{ 16, 16 }, argbf32_premultiplied) = undefined;
var dst_zordered_argbf32: seizer.image.ZOrdered(argbf32_premultiplied) = undefined;
var dst_planar_argbf32: seizer.image.Planar(argbf32_premultiplied) = undefined;

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
    src_linear_argbf32 = try ImageArgbF32.alloc(gpa.allocator(), src_size);
    defer src_linear_argbf32.free(gpa.allocator());

    src_tiled_argbf32 = try seizer.image.Tiled(.{ 16, 16 }, argbf32_premultiplied).alloc(gpa.allocator(), src_size);
    defer src_tiled_argbf32.free(gpa.allocator());

    src_zordered_argbf32 = try seizer.image.ZOrdered(argbf32_premultiplied).alloc(gpa.allocator(), src_size);
    defer src_zordered_argbf32.free(gpa.allocator());

    src_planar_argbf32 = try seizer.image.Planar(argbf32_premultiplied).alloc(gpa.allocator(), src_size);
    defer src_planar_argbf32.free(gpa.allocator());

    for (0..src_size[1]) |y| {
        for (0..src_size[0]) |x| {
            const pos = [2]u32{ @intCast(x), @intCast(y) };
            const pixel = seizer.color.argb(f32, .straight, f32).init(
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
            ).convertAlphaModelTo(.premultiplied);

            src_linear_argbf32.setPixel(pos, pixel);
            src_tiled_argbf32.setPixel(pos, pixel);
            src_zordered_argbf32.setPixel(pos, pixel);
            src_planar_argbf32.setPixel(pos, pixel);
        }
    }

    // init dst images
    dst_linear_argbf32 = try ImageArgbF32.alloc(gpa.allocator(), dst_size);
    defer dst_linear_argbf32.free(gpa.allocator());

    dst_tiled_argbf32 = try seizer.image.Tiled(.{ 16, 16 }, argbf32_premultiplied).alloc(gpa.allocator(), dst_size);
    defer dst_tiled_argbf32.free(gpa.allocator());

    dst_zordered_argbf32 = try seizer.image.ZOrdered(argbf32_premultiplied).alloc(gpa.allocator(), dst_size);
    defer dst_zordered_argbf32.free(gpa.allocator());

    dst_planar_argbf32 = try seizer.image.Planar(argbf32_premultiplied).alloc(gpa.allocator(), dst_size);
    defer dst_planar_argbf32.free(gpa.allocator());

    // create benchmarks
    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer bench.deinit();

    try bench.add("composite Linear(argb(f32))", linearArgbF32Composite, .{});
    try bench.add("composite Tiled(.{16,16},argb(f32))", tiled16x16ArgbF32Composite, .{});
    try bench.add("compositeLinear Tiled(.{16,16},argb(f32))", tiled16x16ArgbF32CompositeLinear, .{});
    try bench.add("compositeZOrder Tiled(.{16,16},argb(f32))", tiled16x16ArgbF32CompositeZOrder, .{});
    try bench.add("composite ZOrdered(argb(f32))", zorderedArgbF32Composite, .{});
    try bench.add("composite Planar(argb(f32))", planarArgbF32Composite, .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn linearArgbF32Composite(_: std.mem.Allocator) void {
    dst_linear_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |pos| {
        dst_linear_argbf32.slice(pos, src_linear_argbf32.size).composite(src_linear_argbf32);
    }
    std.mem.doNotOptimizeAway(dst_linear_argbf32.pixels);
}

fn tiled16x16ArgbF32CompositeLinear(_: std.mem.Allocator) void {
    dst_tiled_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |pos| {
        dst_tiled_argbf32.slice(pos, src_linear_argbf32.size).compositeLinear(src_linear_argbf32);
    }
    std.mem.doNotOptimizeAway(dst_tiled_argbf32.tiles);
}

fn tiled16x16ArgbF32Composite(_: std.mem.Allocator) void {
    dst_tiled_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |pos| {
        dst_tiled_argbf32.slice(pos, src_tiled_argbf32.size_px).composite(src_tiled_argbf32);
    }
    std.mem.doNotOptimizeAway(dst_tiled_argbf32.tiles);
}

fn tiled16x16ArgbF32CompositeZOrder(_: std.mem.Allocator) void {
    dst_tiled_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |pos| {
        dst_tiled_argbf32.slice(pos, src_zordered_argbf32.size).compositeZOrder(src_zordered_argbf32);
    }
    std.mem.doNotOptimizeAway(dst_tiled_argbf32.tiles);
}

fn zorderedArgbF32Composite(_: std.mem.Allocator) void {
    dst_zordered_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |slice_pos| {
        const dst_slice = dst_zordered_argbf32.slice(slice_pos, src_zordered_argbf32.size);
        for (0..src_zordered_argbf32.size[1]) |y| {
            for (0..src_zordered_argbf32.size[0]) |x| {
                const pos = [2]u32{
                    @intCast(x),
                    @intCast(y),
                };
                const src_pixel = src_zordered_argbf32.getPixel(pos);
                const dst_pixel = dst_slice.getPixel(pos);
                dst_slice.setPixel(pos, dst_pixel.compositeSrcOver(src_pixel));
            }
        }
        std.mem.doNotOptimizeAway(dst_zordered_argbf32.pixels);
    }
}

fn planarArgbF32Composite(_: std.mem.Allocator) void {
    src_planar_argbf32.clear(argbf32_premultiplied.BLACK);
    for (ops_pos) |slice_pos| {
        dst_planar_argbf32.slice(slice_pos, src_planar_argbf32.size).composite(src_planar_argbf32);
    }
    std.mem.doNotOptimizeAway(dst_planar_argbf32.pixels);
}

const argb8 = seizer.color.argb(seizer.color.sRGB8, .premultiplied, u8);
const argbf32_premultiplied = seizer.color.argbf32_premultiplied;
const ImageArgb8 = seizer.image.Image(seizer.color.argb(seizer.color.sRGB8, .premultiplied, u8));
const ImageArgbF32 = seizer.image.Image(argbf32_premultiplied);

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
