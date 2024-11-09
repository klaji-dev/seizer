//! A module for handling colors.
//!
//! Must read resources for understanding blending, gamma, and colorspaces:
//!
//! - https://ciechanow.ski/alpha-compositing/
//! - https://blog.johnnovak.net/2016/09/21/what-every-coder-should-know-about-gamma/
//! - https://bottosson.github.io/posts/colorwrong/
//! - https://mina86.com/2019/srgb-xyz-conversion/

/// Linear f32 RGB color premultiplied with an f32 alpha component.
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
///   light behind it (`a`)". See `Alpha` for more details.
pub const argbf32_premultiplied = argb(f32, .premultiplied, f32);

/// Convert an sRGB encoded color into a linear color with f32 components.
///
/// Most of the time an RGB colors are sRGB encoded. For example, PNG and CSS
/// colors are sRGB encoded.
///
/// **sRGB colors are not linear**! You **should not** do arithmetic on sRGB encoded
/// values unless you **know** that is what you want!
pub fn fromSRGB(r: u8, g: u8, b: u8, a: u8) argbf32_premultiplied {
    return argb(sRGB8, .straight, u8)
        .init(@enumFromInt(b), @enumFromInt(g), @enumFromInt(r), a)
        .convertColorTo(f32)
        .convertAlphaTo(f32)
        .convertAlphaModelTo(.premultiplied);
}

/// An enum used to specify which alpha model a pixel format is using.
pub const Alpha = enum {
    /// Also known as "associated alpha".
    ///
    /// You can think of premultiplied colors as encoding the following:
    ///
    ///  1. The amount of light reflected or emitted by an object (the color components)
    ///  2. The amount of light blocked by an object (the alpha component)
    ///
    /// In this alpha model color components "contain" the alpha value already. Transforming
    /// from a `straight` alpha model involves multiplying each color component by the alpha
    /// value (e.g. `r * a`, `g * a`, `b * a`). This has several implications, one of which
    /// is that there is a single transparent color, which is the one with all components
    /// set to 0 (as `x * 0 = 0`).
    ///
    /// This color model is extremely useful when compositing images, as it remove a multiply
    /// and a division from each calculation. For example, it changes the `xor` compositing
    /// operation from:
    ///
    /// ```
    /// const out_alpha = src_alpha * (1 - dst_alpha) + dst_alpha * (1 - src_alpha);
    /// const out_color = (src_color * src_alpha * (1 - dst_alpha) + dst_color * dst_alpha * (1 - src_alpha)) / out_alpha;
    /// ```
    ///
    /// to:
    ///
    /// ```
    /// const out_alpha = src_alpha * (1 - dst_alpha) + dst_alpha * (1 - src_alpha);
    /// const out_color = src_color * (1 - dst_alpha) + dst_color * (1 - src_alpha);
    /// ```
    ///
    /// which is a huge win for performance.
    premultiplied,

    /// Also known as "unassociated alpha" or "non-premultiplied alpha".
    ///
    /// This color model is often used by image formats. PNG uses this color model, for example.
    ///
    /// The reason to include this is so we can model those pixels as a distinct type, and [have
    /// a place to clarify potential ambiguity][nigel-tao].
    ///
    /// [nigel-tao]: https://nigeltao.github.io/blog/2022/premultiplied-alpha.html
    straight,
};

/// Component order (BGRA) was chosen to match Linux's DRM_FOURCC `argb8888` format.
pub fn argb(ColorData: type, comptime alpha_model: Alpha, comptime AlphaData: type) type {
    const D_ZERO: ColorData = switch (@typeInfo(ColorData)) {
        .Int => 0,
        .Float => 0.0,
        .Enum => ColorData.ZERO,
        else => @compileError("Unsupported color D type: " ++ @typeName(ColorData)),
    };
    const D_ONE: ColorData = switch (@typeInfo(ColorData)) {
        .Int => std.math.maxInt(ColorData),
        .Float => 1.0,
        .Enum => ColorData.ONE,
        else => @compileError("Unsupported color D type: " ++ @typeName(ColorData)),
    };
    const A_ZERO: AlphaData = switch (@typeInfo(AlphaData)) {
        .Int => 0,
        .Float => 0.0,
        else => @compileError("Unsupported color A type: " ++ @typeName(AlphaData)),
    };
    const A_ONE: AlphaData = switch (@typeInfo(AlphaData)) {
        .Int => std.math.maxInt(AlphaData),
        .Float => 1.0,
        else => @compileError("Unsupported color A type: " ++ @typeName(AlphaData)),
    };
    return extern struct {
        b: ColorData,
        g: ColorData,
        r: ColorData,
        a: AlphaData,

        pub const TRANSPARENT: @This() = .{ .b = D_ZERO, .g = D_ZERO, .r = D_ZERO, .a = A_ZERO };
        pub const WHITE: @This() = .{ .b = D_ONE, .g = D_ONE, .r = D_ONE, .a = A_ONE };
        pub const BLACK: @This() = .{ .b = D_ZERO, .g = D_ZERO, .r = D_ZERO, .a = A_ONE };

        pub fn init(b: ColorData, g: ColorData, r: ColorData, a: AlphaData) @This() {
            return .{ .b = b, .g = g, .r = r, .a = a };
        }

        pub fn fromArray(array: [4]ColorData) @This() {
            return .{ .b = array[0], .g = array[1], .r = array[2], .a = array[3] };
        }

        pub fn toArray(this: @This()) [4]ColorData {
            return .{ this.b, this.g, this.r, this.a };
        }

        pub fn convertColorTo(this: @This(), OtherColorData: type) argb(OtherColorData, alpha_model, AlphaData) {
            if (OtherColorData == ColorData) return this;

            return switch (@typeInfo(OtherColorData)) {
                .Float => switch (@typeInfo(ColorData)) {
                    .Float => argb(OtherColorData, alpha_model, AlphaData){
                        .b = @floatCast(this.b),
                        .g = @floatCast(this.g),
                        .r = @floatCast(this.r),
                        .a = this.a,
                    },
                    .Enum => {
                        if (!@hasDecl(ColorData, "toOptical")) @compileError("Cannot convert from " ++ @typeName(ColorData) ++ " to " ++ @typeName(OtherColorData));
                        return argb(OtherColorData, alpha_model, AlphaData){
                            .b = this.b.toOptical(OtherColorData),
                            .g = this.g.toOptical(OtherColorData),
                            .r = this.r.toOptical(OtherColorData),
                            .a = this.a,
                        };
                    },
                    else => @compileError("Cannot convert from " ++ @typeName(ColorData) ++ " to " ++ @typeName(OtherColorData)),
                },
                .Enum => {
                    if (!@hasDecl(OtherColorData, "fromOptical")) @compileError("Cannot convert from " ++ @typeName(ColorData) ++ " to " ++ @typeName(OtherColorData));
                    return argb(OtherColorData, alpha_model, AlphaData){
                        .b = OtherColorData.fromOptical(ColorData, this.b),
                        .g = OtherColorData.fromOptical(ColorData, this.g),
                        .r = OtherColorData.fromOptical(ColorData, this.r),
                        .a = this.a,
                    };
                },
                else => @compileError("Cannot convert from " ++ @typeName(ColorData) ++ " to " ++ @typeName(OtherColorData)),
            };
        }

        pub fn convertAlphaTo(this: @This(), OtherAlphaData: type) argb(ColorData, alpha_model, OtherAlphaData) {
            if (OtherAlphaData == AlphaData) return this;

            return switch (@typeInfo(OtherAlphaData)) {
                .Float => switch (@typeInfo(AlphaData)) {
                    .Float => argb(ColorData, alpha_model, OtherAlphaData){
                        .b = this.b,
                        .g = this.g,
                        .r = this.r,
                        .a = @floatCast(this.a),
                    },
                    .Int => argb(ColorData, alpha_model, OtherAlphaData){
                        .b = this.b,
                        .g = this.g,
                        .r = this.r,
                        .a = @as(OtherAlphaData, @floatFromInt(this.a)) / std.math.maxInt(AlphaData),
                    },
                    else => @compileError("Cannot convert from AlphaData type " ++ @typeName(AlphaData) ++ " to " ++ @typeName(OtherAlphaData)),
                },
                .Int => |other_a_int_info| switch (@typeInfo(AlphaData)) {
                    .Int => |a_int_info| {
                        const AMax = @Type(.{ .Int = .{
                            .signedness = .unsigned,
                            .bits = @max(a_int_info.bits, other_a_int_info.bits),
                        } });
                        return .{
                            .b = this.b,
                            .g = this.g,
                            .r = this.r,
                            .a = std.math.mulWide(AMax, this.a, std.math.maxInt(AlphaData)) / std.math.maxInt(OtherAlphaData),
                        };
                    },
                    .Float => .{
                        .b = this.b,
                        .g = this.g,
                        .r = this.r,
                        .a = @intFromFloat(this.a * std.math.maxInt(OtherAlphaData)),
                    },
                    else => @compileError("Cannot convert from AlphaData type " ++ @typeName(AlphaData) ++ " to " ++ @typeName(OtherAlphaData)),
                },
                else => @compileError("Cannot convert from AlphaData type " ++ @typeName(AlphaData) ++ " to " ++ @typeName(OtherAlphaData)),
            };
        }

        pub fn convertAlphaModelTo(this: @This(), comptime other_alpha_model: Alpha) argb(ColorData, other_alpha_model, AlphaData) {
            if (other_alpha_model == alpha_model) return this;

            std.debug.assert(@typeInfo(ColorData) == .Float); // Only operations on (linear) numeric types are supported
            std.debug.assert(@typeInfo(AlphaData) == .Int or @typeInfo(AlphaData) == .Float); // Only operations on (linear) numeric types are supported

            const Conversion = enum {
                premultiplied_to_straight,
                straight_to_premultiplied,
            };
            const conversion: Conversion = switch (alpha_model) {
                .premultiplied => switch (other_alpha_model) {
                    .premultiplied => unreachable,
                    .straight => .premultiplied_to_straight,
                },
                .straight => switch (other_alpha_model) {
                    .straight => unreachable,
                    .premultiplied => .straight_to_premultiplied,
                },
            };

            const alpha_as_float: ColorData = switch (@typeInfo(AlphaData)) {
                .Int => @as(ColorData, @floatFromInt(this.a)) / std.math.maxInt(AlphaData),
                .Float => @floatCast(this.a),
                else => @compileError("Unsupported type for Alpha model conversion: " ++ @typeName(AlphaData)),
            };

            return switch (conversion) {
                .premultiplied_to_straight => if (alpha_as_float != 0) .{
                    .b = this.b / alpha_as_float,
                    .g = this.g / alpha_as_float,
                    .r = this.r / alpha_as_float,
                    .a = this.a,
                } else .{
                    .b = 0,
                    .g = 0,
                    .r = 0,
                    .a = 0,
                },
                .straight_to_premultiplied => .{
                    .b = this.b * alpha_as_float,
                    .g = this.g * alpha_as_float,
                    .r = this.r * alpha_as_float,
                    .a = this.a,
                },
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

        pub fn blend(this: @This(), other: @This(), f: ColorData) @This() {
            const clamped: ColorData = std.math.clamp(f, 0.0, 1.0);
            return .{
                .b = std.math.lerp(this.b, other.b, clamped),
                .g = std.math.lerp(this.g, other.g, clamped),
                .r = std.math.lerp(this.r, other.r, clamped),
                .a = std.math.lerp(this.a, other.a, clamped),
            };
        }

        pub fn compositeSrcOverVec(
            comptime L: usize,
            dst: [L]@This(),
            src: [L]@This(),
        ) [L]@This() {
            var dst_b: [L]ColorData = undefined;
            var dst_g: [L]ColorData = undefined;
            var dst_r: [L]ColorData = undefined;
            var dst_a: [L]ColorData = undefined;
            for (dst, &dst_b, &dst_g, &dst_r, &dst_a) |px, *b, *g, *r, *a| {
                b.* = px.b;
                g.* = px.g;
                r.* = px.r;
                a.* = px.a;
            }
            var src_b: [L]ColorData = undefined;
            var src_g: [L]ColorData = undefined;
            var src_r: [L]ColorData = undefined;
            var src_a: [L]ColorData = undefined;
            for (src, &src_b, &src_g, &src_r, &src_a) |px, *b, *g, *r, *a| {
                b.* = px.b;
                g.* = px.g;
                r.* = px.r;
                a.* = px.a;
            }

            const src_av: @Vector(L, ColorData) = src_a;
            const dst_av: @Vector(L, ColorData) = dst_a;
            const res_a: [L]ColorData = src_av + dst_av * (@as(@Vector(L, ColorData), @splat(1.0)) - src_av);

            const dst_bv: @Vector(L, ColorData) = dst_b;
            const src_bv: @Vector(L, ColorData) = src_b;
            const res_b: [L]ColorData = src_bv + dst_bv * (@as(@Vector(L, ColorData), @splat(1.0)) - src_av);

            const dst_gv: @Vector(L, ColorData) = dst_g;
            const src_gv: @Vector(L, ColorData) = src_g;
            const res_g: [L]ColorData = src_gv + dst_gv * (@as(@Vector(L, ColorData), @splat(1.0)) - src_av);

            const dst_rv: @Vector(L, ColorData) = dst_r;
            const src_rv: @Vector(L, ColorData) = src_r;
            const res_r: [L]ColorData = src_rv + dst_rv * (@as(@Vector(L, ColorData), @splat(1.0)) - src_av);

            var res: [L]@This() = undefined;
            for (&res, res_b, res_g, res_r, res_a) |*px, b, g, r, a| {
                px.* = .{ .b = b, .g = g, .r = r, .a = a };
            }
            return res;
        }

        pub const SUGGESTED_VECTOR_LEN = std.simd.suggestVectorLength(ColorData) orelse 16;
        pub fn Vectorized(comptime L: usize) type {
            return struct {
                b: @Vector(L, ColorData),
                g: @Vector(L, ColorData),
                r: @Vector(L, ColorData),
                a: @Vector(L, ColorData),
            };
        }
        pub fn compositeSrcOverVecPlanar(
            comptime L: usize,
            dst: Vectorized(L),
            src: Vectorized(L),
        ) Vectorized(L) {
            return .{
                .b = src.b + dst.b * (@as(@Vector(L, ColorData), @splat(1.0)) - src.a),
                .g = src.g + dst.g * (@as(@Vector(L, ColorData), @splat(1.0)) - src.a),
                .r = src.r + dst.r * (@as(@Vector(L, ColorData), @splat(1.0)) - src.a),
                .a = src.a + dst.a * (@as(@Vector(L, ColorData), @splat(1.0)) - src.a),
            };
        }

        pub fn compositeSrcOver(dst: @This(), src: @This()) @This() {
            return switch (alpha_model) {
                .premultiplied => .{
                    .b = src.b + dst.b * (1.0 - src.a),
                    .g = src.g + dst.g * (1.0 - src.a),
                    .r = src.r + dst.r * (1.0 - src.a),
                    .a = src.a + dst.a * (1.0 - src.a),
                },
                .straight => {
                    const out_a = src.a + dst.a * (1.0 - src.a);
                    return .{
                        .b = (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a,
                        .g = (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a,
                        .r = (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a,
                        .a = out_a,
                    };
                },
            };
        }

        pub fn compositeXor(dst: @This(), src: @This()) @This() {
            return switch (alpha_model) {
                .premultiplied => .{
                    .b = src.b * (1.0 - dst.a) + dst.b * (1.0 - src.a),
                    .g = src.g * (1.0 - dst.a) + dst.g * (1.0 - src.a),
                    .r = src.r * (1.0 - dst.a) + dst.r * (1.0 - src.a),
                    .a = src.a * (1.0 - dst.a) + dst.a * (1.0 - src.a),
                },
                .straight => {
                    const out_a = src.a * (1.0 - dst.a) + dst.a * (1.0 - src.a);
                    return .{
                        .b = (src.b * src.a * (1.0 - dst.a) + dst.b * dst.a * (1.0 - src.a)) / out_a,
                        .g = (src.g * src.a * (1.0 - dst.a) + dst.g * dst.a * (1.0 - src.a)) / out_a,
                        .r = (src.r * src.a * (1.0 - dst.a) + dst.r * dst.a * (1.0 - src.a)) / out_a,
                        .a = out_a,
                    };
                },
            };
        }
    };
}

test "convert sRGB8 to linear f32" {
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(1, 1, 1, 1),
        argb(sRGB8, .straight, f32).init(@enumFromInt(0xff), @enumFromInt(0xff), @enumFromInt(0xff), 1).convertColorTo(f32),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32){ .b = 0.21586053, .g = 0.21586053, .r = 0.21586053, .a = 0.5 },
        argb(sRGB8, .straight, f32).init(@enumFromInt(0x80), @enumFromInt(0x80), @enumFromInt(0x80), 0.5).convertColorTo(f32),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32){ .b = 0, .g = 0, .r = 0, .a = 1 },
        argb(sRGB8, .straight, f32).init(@enumFromInt(0x00), @enumFromInt(0x00), @enumFromInt(0x00), 1).convertColorTo(f32),
    );
}

test "convert linear f32 to sRGB8" {
    try std.testing.expectEqual(
        argb(sRGB8, .straight, f32).init(@enumFromInt(0xff), @enumFromInt(0xff), @enumFromInt(0xff), 1),
        argb(f32, .straight, f32).init(1, 1, 1, 1).convertColorTo(sRGB8),
    );
    try std.testing.expectEqual(
        argb(sRGB8, .straight, f32).init(@enumFromInt(0x80), @enumFromInt(0x80), @enumFromInt(0x80), 0.5),
        argb(f32, .straight, f32).init(0.21586053, 0.21586053, 0.21586053, 0.5).convertColorTo(sRGB8),
    );
    try std.testing.expectEqual(
        argb(sRGB8, .straight, f32).init(@enumFromInt(0x00), @enumFromInt(0x00), @enumFromInt(0x00), 1),
        argb(f32, .straight, f32).init(0, 0, 0, 1).convertColorTo(sRGB8),
    );
}

test "convert straight alpha to premultiplied alpha" {
    try std.testing.expectEqual(
        argb(f32, .premultiplied, f32){ .b = 0, .g = 0, .r = 0, .a = 0 },
        argb(f32, .straight, f32).init(1, 1, 1, 0).convertAlphaModelTo(.premultiplied),
    );
    try std.testing.expectEqual(
        argb(f32, .premultiplied, f32){ .b = 0.5, .g = 0.5, .r = 0.5, .a = 0.5 },
        argb(f32, .straight, f32).init(1, 1, 1, 0.5).convertAlphaModelTo(.premultiplied),
    );
    try std.testing.expectEqual(
        argb(f32, .premultiplied, f32){ .b = 0.25, .g = 0.25, .r = 0.25, .a = 0.5 },
        argb(f32, .straight, f32).init(0.5, 0.5, 0.5, 0.5).convertAlphaModelTo(.premultiplied),
    );
}

test "convert premultiplied alpha to straight alpha" {
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(0, 0, 0, 0),
        argb(f32, .premultiplied, f32).init(0, 0, 0, 0).convertAlphaModelTo(.straight),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(1, 1, 1, 0.5),
        argb(f32, .premultiplied, f32).init(0.5, 0.5, 0.5, 0.5).convertAlphaModelTo(.straight),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(0.5, 0.5, 0.5, 0.5),
        argb(f32, .premultiplied, f32).init(0.25, 0.25, 0.25, 0.5).convertAlphaModelTo(.straight),
    );
}

test "convert linear u8 alpha to linear f32 alpha" {
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(1, 1, 1, 1),
        argb(f32, .straight, u8).init(1, 1, 1, 0xff).convertAlphaTo(f32),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(1, 1, 1, 0),
        argb(f32, .straight, u8).init(1, 1, 1, 0x00).convertAlphaTo(f32),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, f32).init(1, 1, 1, 128.0 / 255.0),
        argb(f32, .straight, u8).init(1, 1, 1, 0x80).convertAlphaTo(f32),
    );
}

test "convert linear f32 alpha to linear u8 alpha " {
    try std.testing.expectEqual(
        argb(f32, .straight, u8).init(1, 1, 1, 0xff),
        argb(f32, .straight, f32).init(1, 1, 1, 1).convertAlphaTo(u8),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, u8).init(1, 1, 1, 0x00),
        argb(f32, .straight, f32).init(1, 1, 1, 0).convertAlphaTo(u8),
    );
    try std.testing.expectEqual(
        argb(f32, .straight, u8).init(1, 1, 1, 0x80),
        argb(f32, .straight, f32).init(1, 1, 1, 128.0 / 255.0).convertAlphaTo(u8),
    );
}

/// An sRGB encoded value stored in 8-bits
pub const sRGB8 = enum(u8) {
    _,

    pub const ZERO: @This() = @enumFromInt(0);
    pub const ONE: @This() = @enumFromInt(0xFF);

    pub fn toOptical(this: @This(), Optical: type) Optical {
        return switch (@typeInfo(Optical)) {
            .Float => this.decodeNaive(Optical),
            else => @compileError("Unsupported Optical type: " ++ @typeName(Optical)),
        };
    }

    pub fn fromOptical(Optical: type, optical: Optical) @This() {
        return switch (@typeInfo(Optical)) {
            .Float => encodeFast(Optical, optical),
            else => @compileError("Unsupported Optical type: " ++ @typeName(Optical)),
        };
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn encodeFast(comptime F: type, component_linear: F) sRGB8 {
        const max_value = comptime (1.0 - std.math.floatEps(f32));
        const min_value = comptime std.math.pow(f32, 2, -13);
        // written as `!(>)` because of nans
        var in: f32 = @floatCast(component_linear);
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

        // lerp
        const t = (bits >> 12) & 0xff;
        const res = (bias + scale * t) >> 16;
        return @enumFromInt(@as(u8, @intCast(res)));
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn encodeFast22Approx(comptime F: type, component_linear: F) sRGB8 {
        return @enumFromInt(@as(u8, @intFromFloat(std.math.pow(F, component_linear, 2.2) * std.math.maxInt(u8))));
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
    fn createEncodeTable(Int: type) [std.math.maxInt(Int) + 1]sRGB8 {
        @setEvalBranchQuota(1_000_000);
        var table: [std.math.maxInt(Int) + 1]sRGB8 = undefined;
        for (table[0..], 0..) |*val, idx| {
            val.* = encodeNaive(f64, @as(f64, @floatFromInt(idx)) / std.math.maxInt(Int));
        }
        return table;
    }

    /// Converts a color component from a linear 0..1 space to a compressed 8-bit encoding.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn encodeNaive(comptime F: type, component_linear: F) sRGB8 {
        const srgb_float = linearToSRGBFloat(F, component_linear);
        const srgb_int: u8 = @intFromFloat(srgb_float * std.math.maxInt(u8));
        return @enumFromInt(srgb_int);
    }

    test encodeNaive {
        try std.testing.expectEqual(@as(sRGB8, @enumFromInt(0x00)), encodeNaive(f64, 0.0));
        try std.testing.expectEqual(@as(sRGB8, @enumFromInt(0xFF)), encodeNaive(f64, 1.0));
    }

    /// Converts a color component from a compressed 8-bit encoding into linear values.
    ///
    /// > [!warn] Alpha is not a color component! It is generally linear even in 8-bit encodings.
    pub fn decodeNaive(component_electronic_u8: sRGB8, comptime F: type) F {
        const component_electronic: F = @as(F, @floatFromInt(@intFromEnum(component_electronic_u8))) / std.math.maxInt(u8);
        if (component_electronic <= 0.04045) {
            // lower end of the sRGB encoding is linear
            return component_electronic / 12.92;
        }
        // higher end of value range is exponential
        return std.math.pow(F, (component_electronic + 0.055) / 1.055, 2.4);
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
};

comptime {
    if (builtin.is_test) {
        _ = argb;
        _ = sRGB8;
    }
}

const builtin = @import("builtin");
const probes = @import("probes");
const std = @import("std");
