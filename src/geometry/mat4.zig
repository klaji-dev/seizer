pub fn identity(comptime T: type) [4][4]T {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn mulVec(comptime T: type, a: [4][4]T, b: [4]T) [4]T {
    return mat.mul(4, 4, 1, T, a, .{b})[0];
}

pub fn mul(comptime T: type, a: [4][4]T, b: [4][4]T) [4][4]T {
    return mat.mul(4, 4, 4, T, a, b);
}

/// Multiply all matrices in a list together
pub fn mulAll(comptime T: type, matrices: []const [4][4]T) [4][4]T {
    var res: [4][4]T = matrices[matrices.len - 1];

    for (0..matrices.len - 1) |i| {
        const inverse_i = (matrices.len - 2) - i;
        const left_matrix = matrices[inverse_i];
        res = mul(T, left_matrix, res);
    }

    return res;
}

pub fn translate(comptime T: type, translation: [3]T) [4][4]T {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        translation ++ .{1},
    };
}

pub fn scale(comptime T: type, scaling: [3]T) [4][4]T {
    return .{
        .{ scaling[0], 0, 0, 0 },
        .{ 0, scaling[1], 0, 0 },
        .{ 0, 0, scaling[2], 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotateZ(comptime T: type, turns: T) [4][4]T {
    return .{
        .{ @cos(turns * std.math.tau), @sin(turns * std.math.tau), 0, 0 },
        .{ -@sin(turns * std.math.tau), @cos(turns * std.math.tau), 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

const std = @import("std");
const vec = @import("./vec.zig");
const mat = @import("./mat.zig");

test translate {
    try std.testing.expectEqualDeep(
        [4]f32{ 7, 9, 11, 1 },
        mulVec(
            f32,
            translate(f32, .{ 2, 3, 4 }),
            .{ 5, 6, 7, 1 },
        ),
    );
}

test mulAll {
    try std.testing.expectEqualDeep(
        mul(
            f32,
            mul(
                f32,
                translate(f32, .{
                    20.0 / 2.0,
                    20.0 / 2.0,
                    0,
                }),
                scale(f32, .{
                    640.0 / 4096.0,
                    500.0 / 2080.0,
                    1,
                }),
            ),
            mul(
                f32,
                scale(f32, .{
                    2.0,
                    2.0,
                    1.0,
                }),
                translate(f32, .{
                    4096.0 / 2.0,
                    2080.0 / 2.0,
                    0,
                }),
            ),
        ),
        mulAll(f32, &.{
            translate(f32, .{
                20.0 / 2.0,
                20.0 / 2.0,
                0,
            }),
            scale(f32, .{
                640.0 / 4096.0,
                500.0 / 2080.0,
                1,
            }),
            scale(f32, .{
                2.0,
                2.0,
                1.0,
            }),
            translate(f32, .{
                4096.0 / 2.0,
                2080.0 / 2.0,
                0,
            }),
        }),
    );
}
