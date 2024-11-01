pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("sRGB roundtrip f64 naive", sRGB_roundtrip_naive_f64, .{});
    try bench.add("sRGB roundtrip f32 naive", sRGB_roundtrip_naive_f32, .{});
    try bench.add("sRGB roundtrip u12", sRGB_roundtrip_u12, .{});
    try bench.add("argb8888 compositeSrcOver", argb8888_compositeSrcOver, .{});
    try bench.add("argb8888 f64 compositeSrcOver", argb8888_compositeSrcOverF64, .{});

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

fn argb8888_compositeSrcOver(_: std.mem.Allocator) void {
    const NUM_SAMPLES = 128;
    for (0..NUM_SAMPLES) |i| {
        const src = seizer.color.argb8888{
            .b = @enumFromInt(@as(u8, @truncate(i))),
            .g = @enumFromInt(@as(u8, @truncate(i))),
            .r = @enumFromInt(@as(u8, @truncate(i))),
            .a = @truncate(i),
        };
        const dst = seizer.color.argb8888{
            .b = @enumFromInt(@as(u8, @truncate(i + 1))),
            .g = @enumFromInt(@as(u8, @truncate(i + 1))),
            .r = @enumFromInt(@as(u8, @truncate(i + 1))),
            .a = @truncate(i + 1),
        };
        const blended = seizer.color.compositeSrcOver(dst, src);
        std.mem.doNotOptimizeAway(blended);
    }
}

fn argb8888_compositeSrcOverF64(_: std.mem.Allocator) void {
    const NUM_SAMPLES = 128;
    for (0..NUM_SAMPLES) |i| {
        const src = seizer.color.argb8888{
            .b = @enumFromInt(@as(u8, @truncate(i))),
            .g = @enumFromInt(@as(u8, @truncate(i))),
            .r = @enumFromInt(@as(u8, @truncate(i))),
            .a = @truncate(i),
        };
        const dst = seizer.color.argb8888{
            .b = @enumFromInt(@as(u8, @truncate(i + 1))),
            .g = @enumFromInt(@as(u8, @truncate(i + 1))),
            .r = @enumFromInt(@as(u8, @truncate(i + 1))),
            .a = @truncate(i + 1),
        };
        const blended = seizer.color.compositeSrcOverF64(dst, src);
        std.mem.doNotOptimizeAway(blended);
    }
}

const seizer = @import("seizer");
const std = @import("std");
const zbench = @import("zbench");
