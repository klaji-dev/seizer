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
pub fn argb(F: type) type {
    return extern struct {
        /// How much `blue` light this object is emitting/reflecting
        b: F,
        /// How much `green` light this object is emitting/reflecting
        g: F,
        /// How much `red` light this object is emitting/reflecting
        r: F,
        /// How much of the light this object blocks from objects behind it.
        a: F,

        pub const WHITE: @This() = .{ .b = 1, .g = 1, .r = 1, .a = 1 };
        pub const BLACK: @This() = .{ .b = 0, .g = 0, .r = 0, .a = 1 };

        pub fn fromArray(array: [4]F) @This() {
            return .{ .b = array[0], .g = array[1], .r = array[2], .a = array[3] };
        }

        pub fn toArray(this: @This()) [4]F {
            return .{ this.b, this.g, this.r, this.a };
        }

        /// Convert from sRGB encoded values to linear sRGB values.
        ///
        /// Necessary to support use in seizer.image.Image
        pub fn fromArgb8888(encoded: argb8888) @This() {
            return .{
                .b = sRGB.decodeNaive(F, encoded.b),
                .g = sRGB.decodeNaive(F, encoded.g),
                .r = sRGB.decodeNaive(F, encoded.r),
                .a = @as(F, @floatFromInt(encoded.a)) / std.math.maxInt(u8),
            };
        }

        /// Convert from sRGB encoded values to linear sRGB values.
        ///
        /// Necessary to support use in seizer.image.Image
        pub fn toArgb8888(this: @This()) argb8888 {
            return .{
                .b = sRGB.encodeFast(F, this.b),
                .g = sRGB.encodeFast(F, this.g),
                .r = sRGB.encodeFast(F, this.r),
                .a = @intFromFloat(this.a * std.math.maxInt(u8)),
            };
        }

        /// use `@floatCast` on each component
        pub fn floatCast(this: @This(), comptime OtherF: type) argb(OtherF) {
            return .{
                .b = @floatCast(this.b),
                .g = @floatCast(this.g),
                .r = @floatCast(this.r),
                .a = @floatCast(this.a),
            };
        }

        pub fn fromRGBUnassociatedAlpha(r: F, g: F, b: F, a: F) @This() {
            return .{
                .b = b * a,
                .g = g * a,
                .r = r * a,
                .a = a,
            };
        }

        pub fn tint(this: @This(), color_mask: @This()) @This() {
            return .{
                .b = this.b * color_mask.b,
                .g = this.g * color_mask.g,
                .r = this.r * color_mask.r,
                .a = this.a * color_mask.a,
            };
        }

        pub fn compositeSrcOverVec(
            comptime L: usize,
            dst: [L]@This(),
            src: [L]@This(),
        ) [L]@This() {
            var dst_b: [L]F = undefined;
            var dst_g: [L]F = undefined;
            var dst_r: [L]F = undefined;
            var dst_a: [L]F = undefined;
            for (dst, &dst_b, &dst_g, &dst_r, &dst_a) |px, *b, *g, *r, *a| {
                b.* = px.b;
                g.* = px.g;
                r.* = px.r;
                a.* = px.a;
            }
            var src_b: [L]F = undefined;
            var src_g: [L]F = undefined;
            var src_r: [L]F = undefined;
            var src_a: [L]F = undefined;
            for (src, &src_b, &src_g, &src_r, &src_a) |px, *b, *g, *r, *a| {
                b.* = px.b;
                g.* = px.g;
                r.* = px.r;
                a.* = px.a;
            }

            const src_av: @Vector(L, F) = src_a;
            const dst_av: @Vector(L, F) = dst_a;
            const res_a: [L]F = src_av + dst_av * (@as(@Vector(L, F), @splat(1.0)) - src_av);

            const dst_bv: @Vector(L, F) = dst_b;
            const src_bv: @Vector(L, F) = src_b;
            const res_b: [L]F = src_bv + dst_bv * (@as(@Vector(L, F), @splat(1.0)) - src_av);

            const dst_gv: @Vector(L, F) = dst_g;
            const src_gv: @Vector(L, F) = src_g;
            const res_g: [L]F = src_gv + dst_gv * (@as(@Vector(L, F), @splat(1.0)) - src_av);

            const dst_rv: @Vector(L, F) = dst_r;
            const src_rv: @Vector(L, F) = src_r;
            const res_r: [L]F = src_rv + dst_rv * (@as(@Vector(L, F), @splat(1.0)) - src_av);

            var res: [L]@This() = undefined;
            for (&res, res_b, res_g, res_r, res_a) |*px, b, g, r, a| {
                px.* = .{ .b = b, .g = g, .r = r, .a = a };
            }
            return res;
        }

        pub const SUGGESTED_VECTOR_LEN = std.simd.suggestVectorLength(F) orelse 16;
        pub fn Vectorized(comptime L: usize) type {
            return struct {
                b: @Vector(L, F),
                g: @Vector(L, F),
                r: @Vector(L, F),
                a: @Vector(L, F),
            };
        }
        pub fn compositeSrcOverVecPlanar(
            comptime L: usize,
            dst: Vectorized(L),
            src: Vectorized(L),
        ) Vectorized(L) {
            return .{
                .b = src.b + dst.b * (@as(@Vector(L, F), @splat(1.0)) - src.a),
                .g = src.g + dst.g * (@as(@Vector(L, F), @splat(1.0)) - src.a),
                .r = src.r + dst.r * (@as(@Vector(L, F), @splat(1.0)) - src.a),
                .a = src.a + dst.a * (@as(@Vector(L, F), @splat(1.0)) - src.a),
            };
        }

        pub fn compositeSrcOver(dst: @This(), src: @This()) @This() {
            return .{
                .b = src.b + dst.b * (1.0 - src.a),
                .g = src.g + dst.g * (1.0 - src.a),
                .r = src.r + dst.r * (1.0 - src.a),
                .a = src.a + dst.a * (1.0 - src.a),
            };
        }

        pub fn compositeXor(dst: @This(), src: @This()) @This() {
            return .{
                .b = src.b * (1.0 - dst.a) + dst.b * (1.0 - src.a),
                .g = src.g * (1.0 - dst.a) + dst.g * (1.0 - src.a),
                .r = src.r * (1.0 - dst.a) + dst.r * (1.0 - src.a),
                .a = src.a * (1.0 - dst.a) + dst.a * (1.0 - src.a),
            };
        }
    };
}

test "argb(f32).compositeSrcOverVec" {
    var prng = std.Random.DefaultPrng.init(438626002704109799);

    const vector_len = std.simd.suggestVectorLength(f32) orelse 4;

    var dst_array: [vector_len]argb(f32) = undefined;
    var src_array: [vector_len]argb(f32) = undefined;
    var result_array: [vector_len]argb(f32) = undefined;
    for (&result_array, &dst_array, &src_array) |*res, *dst, *src| {
        dst.* = argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
        src.* = argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
        res.* = dst.compositeSrcOver(src.*);
    }

    const result_vec: [vector_len]argb(f32) = argb(f32).compositeSrcOverVec(vector_len, dst_array, src_array);
    try std.testing.expectEqualSlices(argb(f32), &result_array, &result_vec);
}

test "argb(f32).compositeSrcOverVecPlanar" {
    var prng = std.Random.DefaultPrng.init(438626002704109799);

    const vector_len = std.simd.suggestVectorLength(f32) orelse 4;

    var dst_array: [vector_len]argb(f32) = undefined;
    var src_array: [vector_len]argb(f32) = undefined;
    var result_array: [vector_len]argb(f32) = undefined;
    for (&result_array, &dst_array, &src_array) |*res, *dst, *src| {
        dst.* = argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
        src.* = argb(f32).fromRGBUnassociatedAlpha(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        );
        res.* = dst.compositeSrcOver(src.*);
    }

    var dst_b_array: [vector_len]f32 = undefined;
    var dst_g_array: [vector_len]f32 = undefined;
    var dst_r_array: [vector_len]f32 = undefined;
    var dst_a_array: [vector_len]f32 = undefined;
    for (&dst_b_array, &dst_g_array, &dst_r_array, &dst_a_array, dst_array) |*b, *g, *r, *a, px| {
        b.* = px.b;
        g.* = px.g;
        r.* = px.r;
        a.* = px.a;
    }
    const dst_vec: argb(f32).Vectorized(vector_len) = .{
        .b = dst_b_array,
        .g = dst_g_array,
        .r = dst_r_array,
        .a = dst_a_array,
    };

    var src_b_array: [vector_len]f32 = undefined;
    var src_g_array: [vector_len]f32 = undefined;
    var src_r_array: [vector_len]f32 = undefined;
    var src_a_array: [vector_len]f32 = undefined;
    for (&src_b_array, &src_g_array, &src_r_array, &src_a_array, src_array) |*b, *g, *r, *a, px| {
        b.* = px.b;
        g.* = px.g;
        r.* = px.r;
        a.* = px.a;
    }
    const src_vec: argb(f32).Vectorized(vector_len) = .{
        .b = src_b_array,
        .g = src_g_array,
        .r = src_r_array,
        .a = src_a_array,
    };

    const result_vec: argb(f32).Vectorized(vector_len) = argb(f32).compositeSrcOverVecPlanar(vector_len, dst_vec, src_vec);

    var result_vec_array: [vector_len]argb(f32) = undefined;
    const result_b_array: [vector_len]f32 = result_vec.b;
    const result_g_array: [vector_len]f32 = result_vec.g;
    const result_r_array: [vector_len]f32 = result_vec.r;
    const result_a_array: [vector_len]f32 = result_vec.a;
    for (&result_vec_array, result_b_array, result_g_array, result_r_array, result_a_array) |*px, b, g, r, a| {
        px.* = .{
            .b = b,
            .g = g,
            .r = r,
            .a = a,
        };
    }

    try std.testing.expectEqualSlices(argb(f32), &result_array, &result_vec_array);
}

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

    /// Necessary for seizer.image.Image type
    pub fn fromArgb8888(encoded: argb8888) @This() {
        return encoded;
    }

    /// Necessary for seizer.image.Image type
    pub fn toArgb8888(this: @This()) argb8888 {
        return this;
    }

    /// Convert from sRGB encoded values to linear RGB values.
    pub fn toArgb(this: @This(), comptime T: type) argb(T) {
        return .{
            .b = sRGB.decodeNaive(f32, this.b),
            .g = sRGB.decodeNaive(f32, this.g),
            .r = sRGB.decodeNaive(f32, this.r),
            .a = @as(f32, @floatFromInt(this.a)) / std.math.maxInt(u8),
        };
    }

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
        return argb8888{
            .b = sRGB.encodeU12(@truncate(src[0] + ((dst[0] * (0xFF - src_encoded.a)) / 0xFF))),
            .g = sRGB.encodeU12(@truncate(src[1] + ((dst[1] * (0xFF - src_encoded.a)) / 0xFF))),
            .r = sRGB.encodeU12(@truncate(src[2] + ((dst[2] * (0xFF - src_encoded.a)) / 0xFF))),
            .a = @truncate(@as(u16, src_encoded.a) + ((@as(u16, dst_encoded.a) * (0xFF - src_encoded.a)) / 0xFF)),
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

        const dst_blend = [3]u32{
            dst[0] * src_alpha_reciprocal,
            dst[1] * src_alpha_reciprocal,
            dst[2] * src_alpha_reciprocal,
        };
        const src_blend = [3]u32{
            src[0] * dst_alpha_reciprocal,
            src[1] * dst_alpha_reciprocal,
            src[2] * dst_alpha_reciprocal,
        };

        return argb8888{
            .b = sRGB.encodeU12(@truncate((src_blend[0] + dst_blend[0]) / 0xFF)),
            .g = sRGB.encodeU12(@truncate((src_blend[1] + dst_blend[1]) / 0xFF)),
            .r = sRGB.encodeU12(@truncate((src_blend[2] + dst_blend[2]) / 0xFF)),
            .a = @truncate(((src_encoded.a * dst_alpha_reciprocal) + (dst_encoded.a * src_alpha_reciprocal)) / 0xFF),
        };
    }

    test compositeXor {
        try std.testing.expectEqual(argb8888.TRANSPARENT, compositeXor(argb8888.TRANSPARENT, argb8888.TRANSPARENT));
        try std.testing.expectEqual(argb8888.WHITE, compositeXor(argb8888.WHITE, argb8888.TRANSPARENT));
        try std.testing.expectEqual(argb8888.BLACK, compositeXor(argb8888.TRANSPARENT, argb8888.BLACK));
        try std.testing.expectEqual(argb8888.TRANSPARENT, compositeXor(argb8888.WHITE, argb8888.BLACK));
    }

    // TODO: add testing based on microsofts float -> srgb specification https://microsoft.github.io/DirectX-Specs/d3d/archive/D3D11_3_FunctionalSpec.htm#FLOATtoSRGB

    test "u32 compositing introduces minimal error" {
        // TODO: use std.testing.fuzz in 0.14
        var prng = std.Random.DefaultPrng.init(789725665931731016);
        const ITERATIONS = 1_000;
        for (0..ITERATIONS) |_| {
            // convert to argb8888 and back because we aren't interested in how shrinking the
            // data into 8-bits reduces precision, just if the u12 algorithm introduces any
            // extra error
            const dst = argb(f64).fromRGBUnassociatedAlpha(
                prng.random().float(f64),
                prng.random().float(f64),
                prng.random().float(f64),
                prng.random().float(f64),
            ).toArgb8888().toArgb();
            const src = argb(f64).fromRGBUnassociatedAlpha(
                prng.random().float(f64),
                prng.random().float(f64),
                prng.random().float(f64),
                prng.random().float(f64),
            ).toArgb8888().toArgb();

            const result_using_u12 = argb8888.compositeSrcOver(dst.toArgb8888(), src.toArgb8888());
            const result_using_f64 = dst.compositeSrcOver(src).toArgb8888();
            try std.testing.expectEqual(result_using_f64, result_using_u12);
        }
    }
};

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
    pub fn encodeFast(comptime F: type, component_linear: F) sRGB {
        const max_value = comptime (1.0 - std.math.floatEps(f32));
        const min_value = comptime std.math.pow(f32, 2, -13);
        // written as `!(>)` because of nans
        var in = component_linear;
        if (!(component_linear > min_value)) {
            in = min_value;
        }
        if (in > max_value) {
            in = max_value;
        }
        const bits: u32 = @bitCast(in);
        std.debug.assert(@as(u32, @bitCast(min_value)) <= bits and bits <= @as(u32, @bitCast(max_value)));

        const entry = TO_SRGB8_TABLE[(bits - @as(u32, @bitCast(min_value))) >> 20];
        const bias = (entry >> 16) << 9;
        const scale = entry & 0xffff;

        // const srgb_float = std.math.pow(F, component_linear, 1.0 / 2.2);
        // const srgb_int: u8 = @intFromFloat(srgb_float * std.math.maxInt(u8));
        // std.math.lerp(, , )

        // lerp
        const t = (bits >> 12) & 0xff;
        const res = (bias + scale * t) >> 16;
        return @enumFromInt(@as(u8, @intCast(res)));
    }

    const TO_SRGB8_TABLE: [104]u32 = .{
        0x0073000d, 0x007a000d, 0x0080000d, 0x0087000d, 0x008d000d, 0x0094000d, 0x009a000d, 0x00a1000d,
        0x00a7001a, 0x00b4001a, 0x00c1001a, 0x00ce001a, 0x00da001a, 0x00e7001a, 0x00f4001a, 0x0101001a,
        0x010e0033, 0x01280033, 0x01410033, 0x015b0033, 0x01750033, 0x018f0033, 0x01a80033, 0x01c20033,
        0x01dc0067, 0x020f0067, 0x02430067, 0x02760067, 0x02aa0067, 0x02dd0067, 0x03110067, 0x03440067,
        0x037800ce, 0x03df00ce, 0x044600ce, 0x04ad00ce, 0x051400ce, 0x057b00c5, 0x05dd00bc, 0x063b00b5,
        0x06970158, 0x07420142, 0x07e30130, 0x087b0120, 0x090b0112, 0x09940106, 0x0a1700fc, 0x0a9500f2,
        0x0b0f01cb, 0x0bf401ae, 0x0ccb0195, 0x0d950180, 0x0e56016e, 0x0f0d015e, 0x0fbc0150, 0x10630143,
        0x11070264, 0x1238023e, 0x1357021d, 0x14660201, 0x156601e9, 0x165a01d3, 0x174401c0, 0x182401af,
        0x18fe0331, 0x1a9602fe, 0x1c1502d2, 0x1d7e02ad, 0x1ed4028d, 0x201a0270, 0x21520256, 0x227d0240,
        0x239f0443, 0x25c003fe, 0x27bf03c4, 0x29a10392, 0x2b6a0367, 0x2d1d0341, 0x2ebe031f, 0x304d0300,
        0x31d105b0, 0x34a80555, 0x37520507, 0x39d504c5, 0x3c37048b, 0x3e7c0458, 0x40a8042a, 0x42bd0401,
        0x44c20798, 0x488e071e, 0x4c1c06b6, 0x4f76065d, 0x52a50610, 0x55ac05cc, 0x5892058f, 0x5b590559,
        0x5e0c0a23, 0x631c0980, 0x67db08f6, 0x6c55087f, 0x70940818, 0x74a007bd, 0x787d076c, 0x7c330723,
    };

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

comptime {
    if (builtin.is_test) {
        _ = argb;
        _ = argb8888;
        _ = sRGB;
    }
}

const builtin = @import("builtin");
const probes = @import("probes");
const std = @import("std");
