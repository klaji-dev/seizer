pub fn compositeAOverB(a: [4]u8, b: [4]u8) [4]u8 {
    const a_mult: @Vector(3, u16) = @splat(a[3]);
    const b_mult: @Vector(3, u16) = @splat((@as(u16, b[3]) * (0xFF - a[3])) >> 8);

    const a_vec: @Vector(3, u16) = a[0..3].*;
    const b_vec: @Vector(3, u16) = b[0..3].*;
    const out: [3]u16 = (a_vec * a_mult + b_vec * b_mult) / (a_mult + b_mult);
    const out_alpha: [3]u16 = a_mult + b_mult;
    return .{ @intCast(out[0]), @intCast(out[1]), @intCast(out[2]), @intCast(out_alpha[0]) };
}

const std = @import("std");
