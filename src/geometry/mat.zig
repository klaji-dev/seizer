//! Matrix math operations

pub fn mul(comptime M: usize, comptime N: usize, comptime P: usize, comptime T: type, a: [N][M]T, b: [P][N]T) [P][M]T {
    const a_t = transpose(N, M, T, a);

    var res: [P][M]T = undefined;

    for (&res, 0..) |*column, i| {
        const vb: @Vector(N, T) = b[i];
        for (column, 0..) |*c, j| {
            const va: @Vector(N, T) = a_t[j];

            c.* = @reduce(.Add, va * vb);
        }
    }

    return res;
}

pub fn transpose(comptime N: usize, comptime M: usize, comptime T: type, matrix: [N][M]T) [M][N]T {
    var result: [M][N]T = undefined;

    for (0..M) |i| {
        for (0..N) |j| {
            result[i][j] = matrix[j][i];
        }
    }

    return result;
}

test {
    try std.testing.expectEqualDeep([2][3]f32{
        .{ 7, 9, 11 },
        .{ 8, 10, 12 },
    }, transpose(3, 2, f32, .{
        .{ 7, 8 },
        .{ 9, 10 },
        .{ 11, 12 },
    }));
}

const std = @import("std");

test mul {
    try std.testing.expectEqualDeep([3][4]f32{
        .{ 5, 8, 6, 11 },
        .{ 4, 9, 5, 9 },
        .{ 3, 5, 3, 6 },
    }, mul(
        4,
        3,
        3,
        f32,
        .{
            .{ 1, 2, 0, 1 },
            .{ 0, 1, 1, 1 },
            .{ 1, 1, 1, 2 },
        },
        .{
            .{ 1, 2, 4 },
            .{ 2, 3, 2 },
            .{ 1, 1, 2 },
        },
    ));

    try std.testing.expectEqualDeep([1][4]f32{
        .{ 1, 2, 3, 4 },
    }, mul(
        4,
        4,
        1,
        f32,
        .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
        .{
            .{ 1, 2, 3, 4 },
        },
    ));

    try std.testing.expectEqualDeep([4][4]f32{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 7, 9, 11, 1 },
    }, mul(
        4,
        4,
        4,
        f32,
        .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 2, 3, 4, 1 },
        },
        .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 5, 6, 7, 1 },
        },
    ));

    try std.testing.expectEqualDeep([4][4]f32{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 5, 6, 7, 0 },
    }, mul(
        4,
        4,
        4,
        f32,
        .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 2, 3, 4, 0 },
        },
        .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 5, 6, 7, 0 },
        },
    ));
}
