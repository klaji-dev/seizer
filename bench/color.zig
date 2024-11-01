var prng = std.Random.DefaultPrng.init(419621509410522679);

const NUM_SAMPLES = 4096;
var argb_dst_samples: [NUM_SAMPLES]seizer.color.argb = undefined;
var argb_src_samples: [NUM_SAMPLES]seizer.color.argb = undefined;
var argb8888_dst_samples: [NUM_SAMPLES]seizer.color.argb8888 = undefined;
var argb8888_src_samples: [NUM_SAMPLES]seizer.color.argb8888 = undefined;

pub fn main() !void {
    for (argb_dst_samples[0..], argb_src_samples[0..]) |*dst, *src| {
        dst.* = seizer.color.argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        );
        src.* = seizer.color.argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        );
    }
    for (argb8888_dst_samples[0..], argb_dst_samples[0..]) |*encoded, linear| {
        encoded.* = linear.toArgb8888();
    }
    for (argb8888_src_samples[0..], argb_src_samples[0..]) |*encoded, linear| {
        encoded.* = linear.toArgb8888();
    }

    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("sRGB roundtrip f64 naive", sRGB_roundtrip_naive_f64, .{});
    try bench.add("sRGB roundtrip f32 naive", sRGB_roundtrip_naive_f32, .{});
    try bench.add("sRGB roundtrip u12", sRGB_roundtrip_u12, .{});
    try bench.add("argb compositeSrcOver", argb_compositeSrcOver, .{});
    try bench.add("argb compositeXor", argb_compositeXor, .{});
    try bench.add("argb8888 compositeSrcOver", argb8888_compositeSrcOver, .{});
    try bench.add("argb8888 compositeXor", argb8888_compositeXor, .{});
    try bench.add("argb8888 to argb", argb8888_to_argb, .{});
    try bench.add("argb to argb8888", argb_to_argb8888, .{});
    try bench.add("argb8888 to linear u12", argb8888_to_linear_u12, .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);
}

fn sRGB_roundtrip_naive_f64(_: std.mem.Allocator) void {
    var i: u8 = 0;
    while (true) : (i += 1) {
        std.mem.doNotOptimizeAway(seizer.color.sRGB.encodeNaive(f64, seizer.color.sRGB.decodeNaive(f64, @enumFromInt(i))));
        if (i == std.math.maxInt(u8)) break;
    }
}

fn sRGB_roundtrip_naive_f32(_: std.mem.Allocator) void {
    var i: u8 = 0;
    while (true) : (i += 1) {
        std.mem.doNotOptimizeAway(seizer.color.sRGB.encodeNaive(f32, seizer.color.sRGB.decodeNaive(f32, @enumFromInt(i))));
        if (i == std.math.maxInt(u8)) break;
    }
}

fn sRGB_roundtrip_u12(_: std.mem.Allocator) void {
    var srgb_value: u8 = 0;
    while (true) : (srgb_value += 1) {
        const linear_value = seizer.color.sRGB.decodeU12(@enumFromInt(srgb_value));
        std.mem.doNotOptimizeAway(linear_value);

        const re_encoded_value = seizer.color.sRGB.encodeU12(srgb_value);
        std.mem.doNotOptimizeAway(re_encoded_value);

        if (srgb_value == std.math.maxInt(u8)) break;
    }
}

fn argb_compositeSrcOver(_: std.mem.Allocator) void {
    for (argb_dst_samples, argb_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb.compositeSrcOver(dst, src));
    }
}

fn argb_compositeXor(_: std.mem.Allocator) void {
    for (argb_dst_samples, argb_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb.compositeXor(dst, src));
    }
}

fn argb8888_compositeSrcOver(_: std.mem.Allocator) void {
    for (argb8888_dst_samples, argb8888_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb8888.compositeSrcOver(dst, src));
    }
}

fn argb8888_compositeXor(_: std.mem.Allocator) void {
    for (argb8888_dst_samples, argb8888_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb8888.compositeXor(dst, src));
    }
}

fn argb8888_to_argb(_: std.mem.Allocator) void {
    for (argb8888_src_samples) |argb8888_sample| {
        std.mem.doNotOptimizeAway(argb8888_sample.toArgb());
    }
}

fn argb_to_argb8888(_: std.mem.Allocator) void {
    for (argb_src_samples) |argb_sample| {
        std.mem.doNotOptimizeAway(argb_sample.toArgb8888());
    }
}

fn argb8888_to_linear_u12(_: std.mem.Allocator) void {
    for (argb8888_src_samples) |argb8888_sample| {
        std.mem.doNotOptimizeAway(argb8888_sample.b.decodeU12());
        std.mem.doNotOptimizeAway(argb8888_sample.g.decodeU12());
        std.mem.doNotOptimizeAway(argb8888_sample.r.decodeU12());
        std.mem.doNotOptimizeAway(argb8888_sample.a);
    }
}

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
