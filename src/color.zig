pub const argb = extern struct {
    b: f64,
    g: f64,
    r: f64,
    a: f64,

    pub const WHITE: argb = .{ .b = 1, .g = 1, .r = 1, .a = 1 };
    pub const BLACK: argb = .{ .b = 0, .g = 0, .r = 0, .a = 1 };

    pub fn fromArray(array: [4]f64) @This() {
        return .{ .b = array[0], .g = array[1], .r = array[2], .a = array[3] };
    }

    pub fn toArray(this: @This()) [4]f64 {
        return .{ this.b, this.g, this.r, this.a };
    }

    // TODO: make `argb` have linear encoding, use non-linear encoding for argb8888?
    pub fn toArgb8888(this: @This()) argb8888 {
        return .{
            .b = @intFromFloat(this.b * std.math.maxInt(u8)),
            .g = @intFromFloat(this.g * std.math.maxInt(u8)),
            .r = @intFromFloat(this.r * std.math.maxInt(u8)),
            .a = @intFromFloat(this.a * std.math.maxInt(u8)),
        };
    }
};

/// Assumes premultiplied alpha
pub const argb8888 = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8,

    pub const BLACK = .{ .b = 0, .g = 0, .r = 0, .a = 1 };

    pub fn fromBytes(bytes: [4]u8) @This() {
        return .{ .b = bytes[0], .g = bytes[1], .r = bytes[2], .a = bytes[3] };
    }

    pub fn toBytes(this: @This()) [4]u8 {
        return .{ this.b, this.g, this.r, this.a };
    }
};

pub fn tint(src: argb8888, mask: argb8888) argb8888 {
    return argb8888{
        .b = @intCast((@as(u16, src.b) * @as(u16, mask.b)) >> 8),
        .g = @intCast((@as(u16, src.g) * @as(u16, mask.g)) >> 8),
        .r = @intCast((@as(u16, src.r) * @as(u16, mask.r)) >> 8),
        .a = @intCast((@as(u16, src.a) * @as(u16, mask.a)) >> 8),
    };
}

pub fn compositeSrcOver(dst: argb8888, src: argb8888) argb8888 {
    const one_minus_src_a: u16 = 0xFF - src.a;
    return argb8888{
        .b = @intCast(src.b + ((@as(u16, dst.b) * one_minus_src_a) >> 8)),
        .g = @intCast(src.g + ((@as(u16, dst.g) * one_minus_src_a) >> 8)),
        .r = @intCast(src.r + ((@as(u16, dst.r) * one_minus_src_a) >> 8)),
        .a = @intCast(src.a + ((@as(u16, dst.a) * one_minus_src_a) >> 8)),
    };
}

const probes = @import("probes");
const std = @import("std");
