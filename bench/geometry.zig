var prng = std.Random.DefaultPrng.init(419621509410522679);

const BOX_COUNT = 1024 * 64;

var overlap_f32_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_f64_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_i32_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_i64_aabbs: [BOX_COUNT / 2]bool = undefined;

var f32_aabbs: [BOX_COUNT]geometry.AABB(f32) = undefined;
var f64_aabbs: [BOX_COUNT]geometry.AABB(f64) = undefined;
var i32_aabbs: [BOX_COUNT]geometry.AABB(i32) = undefined;
var i64_aabbs: [BOX_COUNT]geometry.AABB(i64) = undefined;

var overlap_f32_simd_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_f64_simd_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_i32_simd_aabbs: [BOX_COUNT / 2]bool = undefined;
var overlap_i64_simd_aabbs: [BOX_COUNT / 2]bool = undefined;

var f32_simd_aabbs: [BOX_COUNT]geometry.SIMD_AABB(f32) = undefined;
var f64_simd_aabbs: [BOX_COUNT]geometry.SIMD_AABB(f64) = undefined;
var i32_simd_aabbs: [BOX_COUNT]geometry.SIMD_AABB(i32) = undefined;
var i64_simd_aabbs: [BOX_COUNT]geometry.SIMD_AABB(i64) = undefined;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    var boxes_f32: [BOX_COUNT][4]f32 = undefined;
    var boxes_f64: [BOX_COUNT][4]f64 = undefined;
    var boxes_i32: [BOX_COUNT][4]i32 = undefined;
    var boxes_i64: [BOX_COUNT][4]i64 = undefined;

    for (&boxes_f32, &boxes_f64, &boxes_i32, &boxes_i64) |*bf32, *bf64, *bi32, *bi64| {
        bf64.*[0] = prng.random().float(f32);
        bf64.*[1] = prng.random().float(f32);
        bf64.*[2] = prng.random().float(f32);
        bf64.*[3] = prng.random().float(f32);

        bf32.*[0] = @floatCast(bf64.*[0]);
        bf32.*[1] = @floatCast(bf64.*[1]);
        bf32.*[2] = @floatCast(bf64.*[2]);
        bf32.*[3] = @floatCast(bf64.*[3]);

        bi32.*[0] = @intFromFloat(bf64.*[0] * 512);
        bi32.*[1] = @intFromFloat(bf64.*[1] * 512);
        bi32.*[2] = @intFromFloat(bf64.*[2] * 512);
        bi32.*[3] = @intFromFloat(bf64.*[3] * 512);

        bi64.*[0] = @intFromFloat(bf64.*[0] * 1024);
        bi64.*[1] = @intFromFloat(bf64.*[1] * 1024);
        bi64.*[2] = @intFromFloat(bf64.*[2] * 1024);
        bi64.*[3] = @intFromFloat(bf64.*[3] * 1024);
    }

    for (&f32_aabbs, &f64_aabbs, &boxes_f32, &boxes_f64) |*aabbf32, *aabbf64, bf32, bf64| {
        aabbf32.* = geometry.AABB(f32).init(.{ bf32[0..2].*, bf32[2..4].* });
        aabbf64.* = geometry.AABB(f64).init(.{ bf64[0..2].*, bf64[2..4].* });
    }

    for (&f32_simd_aabbs, &f64_simd_aabbs, &boxes_f32, &boxes_f64) |*aabbf32, *aabbf64, bf32, bf64| {
        aabbf32.* = geometry.SIMD_AABB(f32).init(bf32[0..2].*, bf32[2..4].*);
        aabbf64.* = geometry.SIMD_AABB(f64).init(bf64[0..2].*, bf64[2..4].*);
    }

    for (&i32_aabbs, &i64_aabbs, &boxes_i32, &boxes_i64) |*aabbi32, *aabbi64, bi32, bi64| {
        aabbi32.* = geometry.AABB(i32).init(.{ bi32[0..2].*, bi32[2..4].* });
        aabbi64.* = geometry.AABB(i64).init(.{ bi64[0..2].*, bi64[2..4].* });
    }

    for (&i32_simd_aabbs, &i64_simd_aabbs, &boxes_i32, &boxes_i64) |*aabbi32, *aabbi64, bi32, bi64| {
        aabbi32.* = geometry.SIMD_AABB(i32).init(bi32[0..2].*, bi32[2..4].*);
        aabbi64.* = geometry.SIMD_AABB(i64).init(bi64[0..2].*, bi64[2..4].*);
    }

    @memset(&overlap_f32_aabbs, false);
    @memset(&overlap_f64_aabbs, false);
    @memset(&overlap_i32_aabbs, false);
    @memset(&overlap_i64_aabbs, false);
    @memset(&overlap_f32_simd_aabbs, false);
    @memset(&overlap_f64_simd_aabbs, false);
    @memset(&overlap_i32_simd_aabbs, false);
    @memset(&overlap_i64_simd_aabbs, false);

    try bench.add("AABB(f32) overlap", @"AABB(f32) overlap", .{});
    try bench.add("AABB(f64) overlap", @"AABB(f64) overlap", .{});
    try bench.add("AABB(i32) overlap", @"AABB(i32) overlap", .{});
    try bench.add("AABB(i64) overlap", @"AABB(i64) overlap", .{});

    try bench.add("SIMD_AABB(f32) overlap", @"SIMD_AABB(f32) overlap", .{});
    try bench.add("SIMD_AABB(f64) overlap", @"SIMD_AABB(f64) overlap", .{});
    try bench.add("SIMD_AABB(i32) overlap", @"SIMD_AABB(i32) overlap", .{});
    try bench.add("SIMD_AABB(i64) overlap", @"SIMD_AABB(i64) overlap", .{});

    try bench.add("AABB(f32) intersection", @"AABB(f32) intersection", .{});
    try bench.add("AABB(f64) intersection", @"AABB(f64) intersection", .{});
    try bench.add("SIMD_AABB(f32) intersection", @"SIMD_AABB(f32) intersection", .{});
    try bench.add("SIMD_AABB(f64) intersection", @"SIMD_AABB(f64) intersection", .{});

    try stdout.writeAll("\n");
    try bench.run(stdout);

    var sum_f32_aabb_overlaps: usize = 0;
    var sum_f64_aabb_overlaps: usize = 0;
    var sum_i32_aabb_overlaps: usize = 0;
    var sum_i64_aabb_overlaps: usize = 0;

    var sum_f32_simd_aabb_overlaps: usize = 0;
    var sum_f64_simd_aabb_overlaps: usize = 0;
    var sum_i32_simd_aabb_overlaps: usize = 0;
    var sum_i64_simd_aabb_overlaps: usize = 0;
    for (
        overlap_f32_aabbs,
        overlap_f64_aabbs,
        overlap_i32_aabbs,
        overlap_i64_aabbs,

        overlap_f32_simd_aabbs,
        overlap_f64_simd_aabbs,
        overlap_i32_simd_aabbs,
        overlap_i64_simd_aabbs,
    ) |of32, of64, oi32, oi64, osf32, osf64, osi32, osi64| {
        sum_f32_aabb_overlaps += if (of32) 1 else 0;
        sum_f64_aabb_overlaps += if (of64) 1 else 0;
        sum_i32_aabb_overlaps += if (oi32) 1 else 0;
        sum_i64_aabb_overlaps += if (oi64) 1 else 0;

        sum_f32_simd_aabb_overlaps += if (osf32) 1 else 0;
        sum_f64_simd_aabb_overlaps += if (osf64) 1 else 0;
        sum_i32_simd_aabb_overlaps += if (osi32) 1 else 0;
        sum_i64_simd_aabb_overlaps += if (osi64) 1 else 0;
    }

    try stdout.print(
        \\Overlaps detected:
        \\|{0s:16}|{2s:16}|{4s:16}|{6s:16}|{8s:16}|{10s:16}|{12s:16}|{14s:16}|
        \\|{1:16}|{3:16}|{5:16}|{7:16}|{9:16}|{11:16}|{13:16}|{15:16}|
    , .{
        "AABB(f32)",
        sum_f32_aabb_overlaps,
        "AABB(f64)",
        sum_f64_aabb_overlaps,
        "AABB(i32)",
        sum_i32_aabb_overlaps,
        "AABB(i64)",
        sum_i64_aabb_overlaps,
        "SIMD_AABB(f32)",
        sum_f32_simd_aabb_overlaps,
        "SIMD_AABB(f64)",
        sum_f64_simd_aabb_overlaps,
        "SIMD_AABB(i32)",
        sum_i32_simd_aabb_overlaps,
        "SIMD_AABB(i64)",
        sum_i64_simd_aabb_overlaps,
    });
    try stdout.writeAll("\n");
}

fn @"AABB(f32) overlap"(_: std.mem.Allocator) void {
    for (&overlap_f32_aabbs, f32_aabbs[0 .. BOX_COUNT / 2], f32_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"AABB(f64) overlap"(_: std.mem.Allocator) void {
    for (&overlap_f64_aabbs, f64_aabbs[0 .. BOX_COUNT / 2], f64_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"SIMD_AABB(f32) overlap"(_: std.mem.Allocator) void {
    for (&overlap_f32_simd_aabbs, f32_simd_aabbs[0 .. BOX_COUNT / 2], f32_simd_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"SIMD_AABB(f64) overlap"(_: std.mem.Allocator) void {
    for (&overlap_f64_simd_aabbs, f64_simd_aabbs[0 .. BOX_COUNT / 2], f64_simd_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"AABB(f32) intersection"(_: std.mem.Allocator) void {
    for (f32_aabbs[0 .. BOX_COUNT / 2], f32_aabbs[BOX_COUNT / 2 ..]) |b1, b2| {
        std.mem.doNotOptimizeAway(b1.clamp(b2));
    }
}

fn @"AABB(f64) intersection"(_: std.mem.Allocator) void {
    for (f64_aabbs[0 .. BOX_COUNT / 2], f64_aabbs[BOX_COUNT / 2 ..]) |b1, b2| {
        std.mem.doNotOptimizeAway(b1.clamp(b2));
    }
}

fn @"SIMD_AABB(f32) intersection"(_: std.mem.Allocator) void {
    for (f32_simd_aabbs[0 .. BOX_COUNT / 2], f32_simd_aabbs[BOX_COUNT / 2 ..]) |b1, b2| {
        std.mem.doNotOptimizeAway(b1.intersection(b2));
    }
}

fn @"SIMD_AABB(f64) intersection"(_: std.mem.Allocator) void {
    for (f64_simd_aabbs[0 .. BOX_COUNT / 2], f64_simd_aabbs[BOX_COUNT / 2 ..]) |b1, b2| {
        std.mem.doNotOptimizeAway(b1.intersection(b2));
    }
}

fn @"AABB(i32) overlap"(_: std.mem.Allocator) void {
    for (&overlap_i32_aabbs, i32_aabbs[0 .. BOX_COUNT / 2], i32_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"AABB(i64) overlap"(_: std.mem.Allocator) void {
    for (&overlap_i64_aabbs, i64_aabbs[0 .. BOX_COUNT / 2], i64_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"SIMD_AABB(i32) overlap"(_: std.mem.Allocator) void {
    for (&overlap_i32_simd_aabbs, i32_simd_aabbs[0 .. BOX_COUNT / 2], i32_simd_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

fn @"SIMD_AABB(i64) overlap"(_: std.mem.Allocator) void {
    for (&overlap_i64_simd_aabbs, i64_simd_aabbs[0 .. BOX_COUNT / 2], i64_simd_aabbs[BOX_COUNT / 2 ..]) |*overlaps, b1, b2| {
        overlaps.* = b1.overlaps(b2);
    }
}

const seizer = @import("seizer");
const geometry = seizer.geometry;
const std = @import("std");
const zbench = @import("zbench");
