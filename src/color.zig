pub fn compositeAOverB(a: [4]u8, b: [4]u8) [4]u8 {
    const a_mult: @Vector(3, u16) = @splat(a[3]);
    const b_mult: @Vector(3, u16) = @splat((@as(u16, b[3]) * (0xFF - a[3])) >> 8);

    const a_vec: @Vector(3, u16) = a[0..3].*;
    const b_vec: @Vector(3, u16) = b[0..3].*;
    const out: [3]u16 = (a_vec * a_mult + b_vec * b_mult) / (a_mult + b_mult);
    const out_alpha: [3]u16 = a_mult + b_mult;
    return .{ @intCast(out[0]), @intCast(out[1]), @intCast(out[2]), @intCast(out_alpha[0]) };
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
