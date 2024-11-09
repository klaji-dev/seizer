var prng = std.Random.DefaultPrng.init(419621509410522679);

const NUM_SAMPLES = 4096;
var argb_dst_samples: [NUM_SAMPLES]argbf32_premultiplied = undefined;
var argb_src_samples: [NUM_SAMPLES]argbf32_premultiplied = undefined;
var argb8888_dst_samples: [NUM_SAMPLES]argb8 = undefined;
var argb8888_src_samples: [NUM_SAMPLES]argb8 = undefined;

var argb_dst_b: [NUM_SAMPLES]f32 = undefined;
var argb_dst_g: [NUM_SAMPLES]f32 = undefined;
var argb_dst_r: [NUM_SAMPLES]f32 = undefined;
var argb_dst_a: [NUM_SAMPLES]f32 = undefined;

var argb_src_b: [NUM_SAMPLES]f32 = undefined;
var argb_src_g: [NUM_SAMPLES]f32 = undefined;
var argb_src_r: [NUM_SAMPLES]f32 = undefined;
var argb_src_a: [NUM_SAMPLES]f32 = undefined;

pub fn main() !void {
    for (argb_dst_samples[0..], &argb_dst_b, &argb_dst_g, &argb_dst_r, &argb_dst_a) |*dst, *b, *g, *r, *a| {
        dst.* = seizer.color.argb(f32, .straight, f32).init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);
        b.* = dst.b;
        g.* = dst.g;
        r.* = dst.r;
        a.* = dst.a;
    }
    for (argb_src_samples[0..], &argb_src_b, &argb_src_g, &argb_src_r, &argb_src_a) |*src, *b, *g, *r, *a| {
        src.* = seizer.color.argb(f32, .straight, f32).init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);
        b.* = src.b;
        g.* = src.g;
        r.* = src.r;
        a.* = src.a;
    }
    for (argb8888_dst_samples[0..], argb_dst_samples[0..]) |*encoded, linear| {
        encoded.* = linear.convertColorTo(seizer.color.sRGB8).convertAlphaTo(u8);
    }
    for (argb8888_src_samples[0..], argb_src_samples[0..]) |*encoded, linear| {
        encoded.* = linear.convertColorTo(seizer.color.sRGB8).convertAlphaTo(u8);
    }

    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("sRGB8 roundtrip f32 naive", sRGB_roundtrip_naive_f32, .{});
    try bench.add("sRGB8 roundtrip f64 naive", sRGB_roundtrip_naive_f64, .{});
    try bench.add("argb compositeSrcOver", argb_compositeSrcOver, .{});
    try bench.add("argb compositeXor", argb_compositeXor, .{});
    try bench.add("argb8888 to argb", argb8888_to_argb, .{});
    try bench.add("argb to argb8888", argb_to_argb8888, .{});
    try bench.add("sRGB encode naive", @"sRGB Encode Naive", .{});
    try bench.add("x^2.2 encode approximation", @"x^2.2 encode approximation", .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn sRGB_roundtrip_naive_f32(_: std.mem.Allocator) void {
    var i: u8 = 0;
    while (true) : (i += 1) {
        std.mem.doNotOptimizeAway(seizer.color.sRGB8.encodeNaive(f32, seizer.color.sRGB8.decodeNaive(@enumFromInt(i), f32)));
        if (i == std.math.maxInt(u8)) break;
    }
}

fn sRGB_roundtrip_naive_f64(_: std.mem.Allocator) void {
    var i: u8 = 0;
    while (true) : (i += 1) {
        std.mem.doNotOptimizeAway(seizer.color.sRGB8.encodeNaive(f64, seizer.color.sRGB8.decodeNaive(@enumFromInt(i), f64)));
        if (i == std.math.maxInt(u8)) break;
    }
}

fn argb_compositeSrcOver(_: std.mem.Allocator) void {
    for (argb_dst_samples, argb_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(argbf32_premultiplied.compositeSrcOver(dst, src));
    }
}

fn argb_compositeXor(_: std.mem.Allocator) void {
    for (argb_dst_samples, argb_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(argbf32_premultiplied.compositeXor(dst, src));
    }
}

fn argb8888_to_argb(_: std.mem.Allocator) void {
    for (argb8888_src_samples) |argb8888_sample| {
        std.mem.doNotOptimizeAway(argb8888_sample.convertColorTo(f32).convertAlphaTo(f32));
    }
}

fn argb_to_argb8888(_: std.mem.Allocator) void {
    for (argb_src_samples) |argb_sample| {
        std.mem.doNotOptimizeAway(argb_sample.convertColorTo(seizer.color.sRGB8).convertAlphaTo(u8));
    }
}

fn @"sRGB Encode Naive"(_: std.mem.Allocator) void {
    for (argb_src_samples) |argb_sample| {
        const encoded = [3]seizer.color.sRGB8{
            seizer.color.sRGB8.encodeNaive(f32, argb_sample.b),
            seizer.color.sRGB8.encodeNaive(f32, argb_sample.g),
            seizer.color.sRGB8.encodeNaive(f32, argb_sample.r),
        };
        std.mem.doNotOptimizeAway(encoded);
        const alpha_u8: u8 = @intFromFloat(argb_sample.a * std.math.maxInt(u8));
        std.mem.doNotOptimizeAway(alpha_u8);
    }
}

fn @"x^2.2 encode approximation"(_: std.mem.Allocator) void {
    for (argb_src_samples) |argb_sample| {
        const encoded = [3]seizer.color.sRGB8{
            seizer.color.sRGB8.encodeFast22Approx(f32, argb_sample.b),
            seizer.color.sRGB8.encodeFast22Approx(f32, argb_sample.g),
            seizer.color.sRGB8.encodeFast22Approx(f32, argb_sample.r),
        };
        std.mem.doNotOptimizeAway(encoded);
        const alpha_u8: u8 = @intFromFloat(argb_sample.a * std.math.maxInt(u8));
        std.mem.doNotOptimizeAway(alpha_u8);
    }
}

const argb8 = seizer.color.argb(seizer.color.sRGB8, .premultiplied, u8);
const argbf32_premultiplied = seizer.color.argbf32_premultiplied;

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
