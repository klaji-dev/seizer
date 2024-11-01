pub fn compositeAOverB(a: [4]u8, b: [4]u8) [4]u8 {
    const a_alpha = @as(f64, @floatFromInt(a[3])) / std.math.maxInt(u8);
    const b_alpha = @as(f64, @floatFromInt(b[3])) / std.math.maxInt(u8);

    const a_mult: @Vector(3, f64) = @splat(a_alpha);
    const b_mult: @Vector(3, f64) = @splat(b_alpha * (1.0 - a_alpha));

    var a_vec: @Vector(3, f64) = @floatFromInt(@as(@Vector(3, u8), a[0..3].*));
    a_vec /= @splat(std.math.maxInt(u8));

    var b_vec: @Vector(3, f64) = @floatFromInt(@as(@Vector(3, u8), b[0..3].*));
    b_vec /= @splat(std.math.maxInt(u8));

    const out: [3]u8 = @as(@Vector(3, u8), @intFromFloat(((a_vec * a_mult + b_vec * b_mult) / (a_mult + b_mult)) * @as(@Vector(3, f64), @splat(std.math.maxInt(u8)))));
    const out_alpha: [3]f64 = a_mult + b_mult;

    return .{ out[0], out[1], out[2], @intFromFloat(out_alpha[0] * std.math.maxInt(u8)) };
}

pub fn fx4FromUx4(F: type, U: type, a: [4]U) [4]F {
    return .{
        @as(F, @floatFromInt(a[0])) / std.math.maxInt(U),
        @as(F, @floatFromInt(a[1])) / std.math.maxInt(U),
        @as(F, @floatFromInt(a[2])) / std.math.maxInt(U),
        @as(F, @floatFromInt(a[3])) / std.math.maxInt(U),
    };
}

pub fn ux4FromFx4(U: type, F: type, a: [4]F) [4]U {
    return .{
        @intFromFloat(a[0] * std.math.maxInt(U)),
        @intFromFloat(a[1] * std.math.maxInt(U)),
        @intFromFloat(a[2] * std.math.maxInt(U)),
        @intFromFloat(a[3] * std.math.maxInt(U)),
    };
}

const std = @import("std");
