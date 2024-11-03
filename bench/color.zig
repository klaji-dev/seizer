var prng = std.Random.DefaultPrng.init(419621509410522679);

const NUM_SAMPLES = 4096;
var argb_dst_samples: [NUM_SAMPLES]seizer.color.argb(f64) = undefined;
var argb_src_samples: [NUM_SAMPLES]seizer.color.argb(f64) = undefined;
var argb8888_dst_samples: [NUM_SAMPLES]seizer.color.argb8888 = undefined;
var argb8888_src_samples: [NUM_SAMPLES]seizer.color.argb8888 = undefined;

var argb_dst_b: [NUM_SAMPLES]f64 = undefined;
var argb_dst_g: [NUM_SAMPLES]f64 = undefined;
var argb_dst_r: [NUM_SAMPLES]f64 = undefined;
var argb_dst_a: [NUM_SAMPLES]f64 = undefined;

var argb_src_b: [NUM_SAMPLES]f64 = undefined;
var argb_src_g: [NUM_SAMPLES]f64 = undefined;
var argb_src_r: [NUM_SAMPLES]f64 = undefined;
var argb_src_a: [NUM_SAMPLES]f64 = undefined;

pub fn main() !void {
    for (argb_dst_samples[0..], &argb_dst_b, &argb_dst_g, &argb_dst_r, &argb_dst_a) |*dst, *b, *g, *r, *a| {
        dst.* = seizer.color.argb(f64).fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        );
        b.* = dst.b;
        g.* = dst.g;
        r.* = dst.r;
        a.* = dst.a;
    }
    for (argb_src_samples[0..], &argb_src_b, &argb_src_g, &argb_src_r, &argb_src_a) |*src, *b, *g, *r, *a| {
        src.* = seizer.color.argb(f64).fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        );
        b.* = src.b;
        g.* = src.g;
        r.* = src.r;
        a.* = src.a;
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

    try bench.add("argb compositeSrcOverVec", argb_compositeSrcOverVec, .{});
    try bench.add("argb compositeSrcOverVecPlanar", argb_compositeSrcOverVecPlanar, .{});
    try bench.add("argb compositeSrcOverPlanar", argb_compositeSrcOverPlanar, .{});

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
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeSrcOver(dst, src));
    }
}

fn argb_compositeXor(_: std.mem.Allocator) void {
    for (argb_dst_samples, argb_src_samples) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeXor(dst, src));
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

fn argb_compositeSrcOverVec(_: std.mem.Allocator) void {
    const vector_len = std.simd.suggestVectorLength(f64) orelse 4;

    const vectorized_loop_count = argb_dst_samples.len / vector_len;
    for (0..vectorized_loop_count) |i| {
        const dst = argb_dst_samples[i * vector_len ..][0..vector_len];
        const src = argb_src_samples[i * vector_len ..][0..vector_len];
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeSrcOverVec(vector_len, dst.*, src.*));
    }
    const end_of_vectorized = vectorized_loop_count * vector_len;
    for (argb_dst_samples[end_of_vectorized..], argb_src_samples[end_of_vectorized..]) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeSrcOver(dst, src));
    }
}

fn argb_compositeSrcOverVecPlanar(_: std.mem.Allocator) void {
    const vector_len = std.simd.suggestVectorLength(f64) orelse 4;

    const vectorized_loop_count = argb_dst_samples.len / vector_len;
    for (0..vectorized_loop_count) |i| {
        const dst = seizer.color.argb(f64).Vectorized(vector_len){
            .b = argb_dst_b[i * vector_len ..][0..vector_len].*,
            .g = argb_dst_g[i * vector_len ..][0..vector_len].*,
            .r = argb_dst_r[i * vector_len ..][0..vector_len].*,
            .a = argb_dst_a[i * vector_len ..][0..vector_len].*,
        };
        const src = seizer.color.argb(f64).Vectorized(vector_len){
            .b = argb_src_b[i * vector_len ..][0..vector_len].*,
            .g = argb_src_g[i * vector_len ..][0..vector_len].*,
            .r = argb_src_r[i * vector_len ..][0..vector_len].*,
            .a = argb_src_a[i * vector_len ..][0..vector_len].*,
        };
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeSrcOverVecPlanar(vector_len, dst, src));
    }
    const end_of_vectorized = vectorized_loop_count * vector_len;
    for (argb_dst_samples[end_of_vectorized..], argb_src_samples[end_of_vectorized..]) |dst, src| {
        std.mem.doNotOptimizeAway(seizer.color.argb(f64).compositeSrcOver(dst, src));
    }
}

fn argb_compositeSrcOverPlanar(_: std.mem.Allocator) void {
    var result_b: [NUM_SAMPLES]f64 = undefined;
    var result_g: [NUM_SAMPLES]f64 = undefined;
    var result_r: [NUM_SAMPLES]f64 = undefined;
    var result_a: [NUM_SAMPLES]f64 = undefined;

    // for (
    //     &result_b,
    //     &result_g,
    //     &result_r,
    //     &result_a,
    //     argb_dst_b,
    //     argb_dst_g,
    //     argb_dst_r,
    //     argb_dst_a,
    //     argb_src_b,
    //     argb_src_g,
    //     argb_src_r,
    //     argb_src_a,
    // ) |*res_b, *res_g, *res_r, *res_a, dst_b, dst_g, dst_r, dst_a, src_b, src_g, src_r, src_a| {
    //     res_b.* = src_b + dst_b * (1.0 - src_a);
    //     res_g.* = src_g + dst_g * (1.0 - src_a);
    //     res_r.* = src_r + dst_r * (1.0 - src_a);
    //     res_a.* = src_a + dst_a * (1.0 - src_a);
    // }

    for (
        &result_b,
        argb_dst_b,
        argb_src_b,
        argb_src_a,
    ) |*res_b, dst_b, src_b, src_a| {
        res_b.* = src_b + dst_b * (1.0 - src_a);
    }

    for (
        &result_g,
        argb_dst_g,
        argb_src_g,
        argb_src_a,
    ) |*res_g, dst_g, src_g, src_a| {
        res_g.* = src_g + dst_g * (1.0 - src_a);
    }

    for (
        &result_r,
        argb_dst_r,
        argb_src_r,
        argb_src_a,
    ) |*res_r, dst_r, src_r, src_a| {
        res_r.* = src_r + dst_r * (1.0 - src_a);
    }

    for (
        &result_a,
        argb_dst_a,
        argb_src_a,
    ) |*res_a, dst_a, src_a| {
        res_a.* = src_a + dst_a * (1.0 - src_a);
    }

    std.mem.doNotOptimizeAway(result_b);
    std.mem.doNotOptimizeAway(result_g);
    std.mem.doNotOptimizeAway(result_r);
    std.mem.doNotOptimizeAway(result_a);
}

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
