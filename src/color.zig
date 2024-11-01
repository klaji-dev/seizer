//! A module for handling colors.
//!
//! Must read resources for understanding blending, gamma, and colorspaces:
//!
//! - https://ciechanow.ski/alpha-compositing/
//! - https://blog.johnnovak.net/2016/09/21/what-every-coder-should-know-about-gamma/
//! - https://bottosson.github.io/posts/colorwrong/
//! - https://mina86.com/2019/srgb-xyz-conversion/

/// Linear RGB color premultiplied with an alpha component.
///
/// Breaking down the jargon:
/// - **linear**: calculating the halfway point of two `argb` colors is as simple as
///   `(a + b) / 2`, as opposed to an sRGB encoded color, where using the same
///   equation will give an invalid result (you end up computing
///   `(a^(1/2.4) + b^(1/2.4)) / 2`).
/// - **RGB**: The color is specified using three components: the amount of `red` light,
///   the amount of `green` light, and the amount of `blue` light.
/// - **premultiplied alpha**: Sometimes called "associated alpha". The color channels
///   already have the alpha factored into them. You can think of this in terms of
///   "this object emits this much light (`r`, `g`, and `b`), and blocks X% of the
///   light behind it (`a`)".
///
/// The component order (BGRA) was chosen to match Linux's DRM_FOURCC `argb8888` format.
pub const argb = extern struct {
    /// How much `blue` light this object is emitting/reflecting
    b: f64,
    /// How much `green` light this object is emitting/reflecting
    g: f64,
    /// How much `red` light this object is emitting/reflecting
    r: f64,
    /// How much of the light this object blocks from objects behind it.
    a: f64,

    pub const WHITE: argb = .{ .b = 1, .g = 1, .r = 1, .a = 1 };
    pub const BLACK: argb = .{ .b = 0, .g = 0, .r = 0, .a = 1 };

    pub fn fromArray(array: [4]f64) @This() {
        return .{ .b = array[0], .g = array[1], .r = array[2], .a = array[3] };
    }

    pub fn toArray(this: @This()) [4]f64 {
        return .{ this.b, this.g, this.r, this.a };
    }

    pub fn toArgb8888(this: @This()) argb8888 {
        return .{
            .b = sRGB.encodeNaive(f64, this.b),
            .g = sRGB.encodeNaive(f64, this.g),
            .r = sRGB.encodeNaive(f64, this.r),
            .a = @intFromFloat(this.a * std.math.maxInt(u8)),
        };
    }

    pub fn fromRGBUnassociatedAlpha(r: f64, g: f64, b: f64, a: f64) @This() {
        return .{
            .b = b * a,
            .g = g * a,
            .r = r * a,
            .a = a,
        };
    }
};

/// 3 8-bit sRGB encoded colors premultiplied with an linear 8-bit alpha component.
///
/// Breaking down the jargon:
/// - **sRGB encoded**: The standard RGB encoding used for consumer devices, it
///   allocates a limited value range (usually the 8-bit `0..256` value range) towards
///   darker values that humans can more easily distinguish. Doing arithmetic on these
///   encoded values will produce incorrect results, though artists may occasionally
///   use it intentionally. However, in general, **convert sRGB values to linear RGB
///   values before doing math on them**!
/// - **RGB**: The color is specified using three components: the amount of `red` light,
///   the amount of `green` light, and the amount of `blue` light.
/// - **premultiplied alpha**: Sometimes called "associated alpha". The color channels
///   already have the alpha factored into them. You can think of this in terms of
///   "this object emits this much light (`r`, `g`, and `b`), and blocks X% of the
///   light behind it (`a`)".
/// - **linear alpha**: The alpha component is not encoded, and the `0..256` range can
///   be converted to `0..1` using `a / 0xFF`.
///
/// The component order (BGRA) was chosen to match Linux's DRM_FOURCC `argb8888` format.
pub const argb8888 = packed struct(u32) {
    b: sRGB,
    g: sRGB,
    r: sRGB,
    a: u8,

    pub const BLACK = .{ .b = 0, .g = 0, .r = 0, .a = 1 };

    /// Convert from sRGB encoded values to linear RGB values.
    pub fn toArgb(this: @This()) argb {
        return .{
            .b = sRGB.decodeNaive(f64, this.b),
            .g = sRGB.decodeNaive(f64, this.g),
            .r = sRGB.decodeNaive(f64, this.r),
            .a = @as(f64, @floatFromInt(this.a)) / std.math.maxInt(u8),
        };
    }
};

pub fn tint(src_encoded: argb8888, mask_encoded: argb8888) argb8888 {
    // TODO: Research tinting. Should the mask be sRGB encoded or linear?
    const src: [4]u32 = .{
        src_encoded.b.decodeU12(),
        src_encoded.g.decodeU12(),
        src_encoded.r.decodeU12(),
        src_encoded.a,
    };
    const mask: [4]u32 = .{
        mask_encoded.b.decodeU12(),
        mask_encoded.g.decodeU12(),
        mask_encoded.r.decodeU12(),
        mask_encoded.a,
    };
    return argb8888{
        .b = sRGB.encodeU12(@truncate((src[0] * mask[0]) >> 12)),
        .g = sRGB.encodeU12(@truncate((src[1] * mask[1]) >> 12)),
        .r = sRGB.encodeU12(@truncate((src[2] * mask[2]) >> 12)),
        .a = @truncate((src[3] * mask[3]) >> 8),
    };
}

pub fn compositeSrcOver(dst_encoded: argb8888, src_encoded: argb8888) argb8888 {
    const dst: [4]u32 = .{
        dst_encoded.b.decodeU12(),
        dst_encoded.g.decodeU12(),
        dst_encoded.r.decodeU12(),
        dst_encoded.a,
    };
    const src: [4]u32 = .{
        src_encoded.b.decodeU12(),
        src_encoded.g.decodeU12(),
        src_encoded.r.decodeU12(),
        src_encoded.a,
    };
    return argb8888{
        .b = sRGB.encodeU12(@truncate(src[0] + ((dst[0] * (0xFF - src[3])) >> 8))),
        .g = sRGB.encodeU12(@truncate(src[1] + ((dst[1] * (0xFF - src[3])) >> 8))),
        .r = sRGB.encodeU12(@truncate(src[2] + ((dst[2] * (0xFF - src[3])) >> 8))),
        .a = @intCast(src[3] + ((dst[3] * (0xFF - src[3])) >> 8)),
    };
}

pub fn compositeSrcOverF64(dst_encoded: argb8888, src_encoded: argb8888) argb8888 {
    const dst = dst_encoded.toArgb();
    const src = src_encoded.toArgb();
    return (argb{
        .b = src.b + dst.b * (1.0 - src.a),
        .g = src.g + dst.g * (1.0 - src.a),
        .r = src.r + dst.r * (1.0 - src.a),
        .a = src.a + dst.a * (1.0 - src.a),
    }).toArgb8888();
}

test "u32 compositing introduces minimal error" {
    // TODO: use std.testing.fuzz in 0.14
    var prng = std.Random.DefaultPrng.init(789725665931731016);
    const ITERATIONS = 1_000;
    for (0..ITERATIONS) |_| {
        const dst = argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();
        const src = argb.fromRGBUnassociatedAlpha(
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
            prng.random().float(f64),
        ).toArgb8888();

        const result_using_u12 = compositeSrcOver(dst, src);
        const result_using_f64 = compositeSrcOverF64(dst, src);
        try std.testing.expectApproxEqRel(@as(f64, @floatFromInt(@intFromEnum(result_using_f64.b))), @as(f64, @floatFromInt(@intFromEnum(result_using_u12.b))), 0.6);
        try std.testing.expectApproxEqRel(@as(f64, @floatFromInt(@intFromEnum(result_using_f64.g))), @as(f64, @floatFromInt(@intFromEnum(result_using_u12.g))), 0.6);
        try std.testing.expectApproxEqRel(@as(f64, @floatFromInt(@intFromEnum(result_using_f64.r))), @as(f64, @floatFromInt(@intFromEnum(result_using_u12.r))), 0.6);
        try std.testing.expectApproxEqRel(@as(f64, @floatFromInt(result_using_f64.a)), @as(f64, @floatFromInt(result_using_u12.a)), 0.6);
    }
}

/// sRGB encoding/decoding functions.
pub const sRGB = enum(u8) {
    _,

    /// Converts a color component from a linear u12 value to a compressed 8-bit encoding.
    pub fn encodeU12(component_linear: u12) sRGB {
        return ENCODE_U12_LINEAR_TO_U8_SRGB[component_linear];
    }

    /// Converts a color component from a compressed 8-bit encoding to a linear u12 value.
    pub fn decodeU12(component_srgb: sRGB) u12 {
        return DECODE_U8_SRGB_TO_U12_LINEAR[@intFromEnum(component_srgb)];
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn encodeNaive(comptime F: type, component_linear: F) sRGB {
        if (component_linear <= 0.0031308) {
            // lower end of the sRGB encoding is linear
            return @enumFromInt(@as(u8, @intFromFloat(component_linear * 12.92 * std.math.maxInt(u8))));
        }
        // higher end of value range is exponential
        return @enumFromInt(@as(u8, @intFromFloat((std.math.pow(F, 1.055 * component_linear, 1.0 / 2.4) - 0.055) * std.math.maxInt(u8))));
    }

    const DECODE_U8_SRGB_TO_U12_LINEAR = createDecodeTable(u12);
    fn createDecodeTable(Int: type) [std.math.maxInt(u8)]Int {
        @setEvalBranchQuota(100_000);
        var table: [std.math.maxInt(u8)]Int = undefined;
        for (table[0..], 0..) |*val, idx| {
            val.* = @as(u12, @intFromFloat(decodeNaive(f64, @enumFromInt(idx)) * std.math.maxInt(Int)));
        }
        return table;
    }

    const ENCODE_U12_LINEAR_TO_U8_SRGB = createEncodeTable(u12);
    fn createEncodeTable(Int: type) [std.math.maxInt(Int)]sRGB {
        @setEvalBranchQuota(1_000_000);
        var table: [std.math.maxInt(Int)]sRGB = undefined;
        for (table[0..], 0..) |*val, idx| {
            val.* = encodeNaive(f64, @as(f64, @floatFromInt(idx)) / std.math.maxInt(Int));
        }
        return table;
    }

    /// Converts a color component from a compressed 8-bit encoding into linear values.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn decodeNaive(comptime F: type, component_electronic_u8: sRGB) F {
        const component_electronic: F = @as(F, @floatFromInt(@intFromEnum(component_electronic_u8))) / std.math.maxInt(u8);
        if (component_electronic <= 0.04045) {
            // lower end of the sRGB encoding is linear
            return component_electronic / 12.92;
        }
        // higher end of value range is exponential
        return std.math.pow(F, (component_electronic + 0.055) / 1.055, 2.4);
    }

    test "u12 introduces minimal error" {
        // TODO: use std.testing.fuzz in 0.14
        var prng = std.Random.DefaultPrng.init(6431592643209124545);
        const ITERATIONS = 10_000;
        for (0..ITERATIONS) |_| {
            const original_linear = prng.random().float(f64);
            const encoded = encodeNaive(f64, original_linear);

            const decoded_f64 = decodeNaive(f64, encoded);
            const decoded_u12 = decodeU12(encoded);
            const decoded_u12_as_f64 = @as(f64, @floatFromInt(decoded_u12)) / std.math.maxInt(u12);

            try std.testing.expectApproxEqRel(decoded_f64, decoded_u12_as_f64, 1e-2);
        }
    }
};

const probes = @import("probes");
const std = @import("std");
