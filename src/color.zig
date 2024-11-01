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

    pub const TRANSPARENT: @This() = .{ .b = @enumFromInt(0x00), .g = @enumFromInt(0x00), .r = @enumFromInt(0x00), .a = 0x00 };
    pub const BLACK: @This() = .{ .b = @enumFromInt(0x00), .g = @enumFromInt(0x00), .r = @enumFromInt(0x00), .a = 0xFF };
    pub const WHITE: @This() = .{ .b = @enumFromInt(0xFF), .g = @enumFromInt(0xFF), .r = @enumFromInt(0xFF), .a = 0xFF };

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
        .b = sRGB.encodeU12(@truncate(src[0] + ((dst[0] * (0xFF - src[3])) / 0xFF))),
        .g = sRGB.encodeU12(@truncate(src[1] + ((dst[1] * (0xFF - src[3])) / 0xFF))),
        .r = sRGB.encodeU12(@truncate(src[2] + ((dst[2] * (0xFF - src[3])) / 0xFF))),
        .a = @intCast(src[3] + ((dst[3] * (0xFF - src[3])) / 0xFF)),
    };
}

test compositeSrcOver {
    try std.testing.expectEqual(argb8888.TRANSPARENT, compositeSrcOver(argb8888.TRANSPARENT, argb8888.TRANSPARENT));
    try std.testing.expectEqual(argb8888.WHITE, compositeSrcOver(argb8888.WHITE, argb8888.TRANSPARENT));
    try std.testing.expectEqual(argb8888.BLACK, compositeSrcOver(argb8888.TRANSPARENT, argb8888.BLACK));
    try std.testing.expectEqual(argb8888.BLACK, compositeSrcOver(argb8888.WHITE, argb8888.BLACK));
}

pub fn compositeXor(dst_encoded: argb8888, src_encoded: argb8888) argb8888 {
    const dst_alpha_reciprocal: u32 = 0xFF - dst_encoded.a;
    const src_alpha_reciprocal: u32 = 0xFF - src_encoded.a;

    const dst: [3]u32 = .{
        dst_encoded.b.decodeU12(),
        dst_encoded.g.decodeU12(),
        dst_encoded.r.decodeU12(),
    };
    const src: [3]u32 = .{
        src_encoded.b.decodeU12(),
        src_encoded.g.decodeU12(),
        src_encoded.r.decodeU12(),
    };

    const dst_blend = [3]u12{
        @intCast((dst[0] * src_alpha_reciprocal) / 0xFF),
        @intCast((dst[1] * src_alpha_reciprocal) / 0xFF),
        @intCast((dst[2] * src_alpha_reciprocal) / 0xFF),
    };
    const src_blend = [3]u12{
        @intCast((src[0] * dst_alpha_reciprocal) / 0xFF),
        @intCast((src[1] * dst_alpha_reciprocal) / 0xFF),
        @intCast((src[2] * dst_alpha_reciprocal) / 0xFF),
    };

    return argb8888{
        .b = sRGB.encodeU12(src_blend[0] + dst_blend[0]),
        .g = sRGB.encodeU12(src_blend[1] + dst_blend[1]),
        .r = sRGB.encodeU12(src_blend[2] + dst_blend[2]),
        .a = @intCast(((src_encoded.a * dst_alpha_reciprocal) / 0xFF) + ((dst_encoded.a * src_alpha_reciprocal) / 0xFF)),
    };
}

test compositeXor {
    try std.testing.expectEqual(argb8888.TRANSPARENT, compositeXor(argb8888.TRANSPARENT, argb8888.TRANSPARENT));
    try std.testing.expectEqual(argb8888.WHITE, compositeXor(argb8888.WHITE, argb8888.TRANSPARENT));
    try std.testing.expectEqual(argb8888.BLACK, compositeXor(argb8888.TRANSPARENT, argb8888.BLACK));
    try std.testing.expectEqual(argb8888.TRANSPARENT, compositeXor(argb8888.WHITE, argb8888.BLACK));
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

// TODO: add testing based on microsofts float -> srgb specification https://microsoft.github.io/DirectX-Specs/d3d/archive/D3D11_3_FunctionalSpec.htm#FLOATtoSRGB

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

    test encodeU12 {
        try std.testing.expectEqual(@as(sRGB, @enumFromInt(0)), encodeU12(0));
        try std.testing.expectEqual(@as(sRGB, @enumFromInt(std.math.maxInt(u8))), encodeU12(std.math.maxInt(u12)));
    }

    /// Converts a color component from a compressed 8-bit encoding to a linear u12 value.
    pub fn decodeU12(component_srgb: sRGB) u12 {
        return DECODE_U8_SRGB_TO_U12_LINEAR[@intFromEnum(component_srgb)];
    }

    test decodeU12 {
        try std.testing.expectEqual(@as(u12, 0), decodeU12(@enumFromInt(0)));
        try std.testing.expectEqual(@as(u12, std.math.maxInt(u12)), decodeU12(@enumFromInt(std.math.maxInt(u8))));
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn encodeNaive(comptime F: type, component_linear: F) sRGB {
        const srgb_float = linearToSRGBFloat(F, component_linear);
        const srgb_int: u8 = @intFromFloat(srgb_float * std.math.maxInt(u8));
        return @enumFromInt(srgb_int);
    }

    test encodeNaive {
        try std.testing.expectEqual(@as(sRGB, @enumFromInt(0x00)), encodeNaive(f64, 0.0));
        try std.testing.expectEqual(@as(sRGB, @enumFromInt(0xFF)), encodeNaive(f64, 1.0));
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn linearToSRGBFloat(comptime F: type, component_linear: F) F {
        if (component_linear <= 0.0031308) {
            // lower end of the sRGB encoding is linear
            return component_linear * 12.92;
        } else if (component_linear < 1.0) {
            // higher end of value range is exponential
            return std.math.pow(F, 1.055 * component_linear, 1.0 / 2.4) - 0.055;
        } else {
            return 1.0;
        }
    }

    const DECODE_U8_SRGB_TO_U12_LINEAR = createDecodeTable(u12);
    fn createDecodeTable(Int: type) [std.math.maxInt(u8) + 1]Int {
        @setEvalBranchQuota(100_000);
        var table: [std.math.maxInt(u8) + 1]Int = undefined;
        for (table[0..], 0..) |*val, idx| {
            val.* = @as(u12, @intFromFloat(decodeNaive(f64, @enumFromInt(idx)) * std.math.maxInt(Int)));
        }
        return table;
    }

    const ENCODE_U12_LINEAR_TO_U8_SRGB = createEncodeTable(u12);
    fn createEncodeTable(Int: type) [std.math.maxInt(Int) + 1]sRGB {
        @setEvalBranchQuota(1_000_000);
        var table: [std.math.maxInt(Int) + 1]sRGB = undefined;
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
