//! Defines geometry primitives

pub const mat = @import("./geometry/mat.zig");
pub const mat3 = @import("./geometry/mat3.zig");
pub const mat4 = @import("./geometry/mat4.zig");
pub const vec = @import("./geometry/vec.zig");

pub fn Rect(comptime T: type) type {
    return struct {
        pos: [2]T,
        size: [2]T,

        pub fn contains(this: @This(), point: [2]T) bool {
            return point[0] >= this.pos[0] and
                point[1] >= this.pos[1] and
                point[0] <= this.pos[0] + this.size[0] and
                point[1] <= this.pos[1] + this.size[1];
        }

        pub fn topLeft(this: @This()) [2]T {
            return this.pos;
        }

        pub fn topRight(this: @This()) [2]T {
            return [2]T{
                this.pos[0] + this.size[0],
                this.pos[1],
            };
        }

        pub fn bottomLeft(this: @This()) [2]T {
            return [2]T{
                this.pos[0],
                this.pos[1] + this.size[1],
            };
        }

        pub fn bottomRight(this: @This()) [2]T {
            return [2]T{
                this.pos[0] + this.size[0],
                this.pos[1] + this.size[1],
            };
        }

        pub fn clampRect(value: @This(), bounds: @This()) @This() {
            const bounds_end = .{
                bounds.pos[0] + bounds.size[0],
                bounds.pos[1] + bounds.size[1],
            };

            const start_clamped = .{
                std.math.clamp(value.pos[0], bounds.pos[0], bounds_end[0]),
                std.math.clamp(value.pos[1], bounds.pos[1], bounds_end[1]),
            };
            const end_clamped = .{
                std.math.clamp(value.pos[0] + value.size[0], bounds.pos[0], bounds_end[0]),
                std.math.clamp(value.pos[1] + value.size[1], bounds.pos[1], bounds_end[1]),
            };

            return .{
                .pos = start_clamped,
                .size = .{
                    end_clamped[0] - start_clamped[0],
                    end_clamped[1] - start_clamped[1],
                },
            };
        }

        pub fn translate(this: @This(), amount: [2]T) @This() {
            return @This(){
                .pos = [2]T{
                    this.pos[0] + amount[0],
                    this.pos[1] + amount[1],
                },
                .size = this.size,
            };
        }

        pub fn eq(this: @This(), other: @This()) bool {
            return this.pos[0] == other.pos[0] and
                this.pos[1] == other.pos[1] and
                this.size[0] == other.size[0] and
                this.size[1] == other.size[1];
        }

        pub fn toAABB(this: @This()) AABB(T) {
            return AABB(T){
                .min = this.topLeft(),
                .max = .{
                    this.pos[0] + this.size[0] - 1,
                    this.pos[1] + this.size[1] - 1,
                },
            };
        }
    };
}

// Defines a rectangular region, like a `Rect`, but stores the min and max coordinates instead of the
// position and size.
pub fn AABB(comptime T: type) type {
    return struct {
        min: [2]T,
        max: [2]T,

        pub fn init(points: [2][2]T) @This() {
            const min = .{ @min(points[0][0], points[1][0]), @min(points[0][1], points[1][1]) };
            const max = .{ @max(points[0][0], points[1][0]), @max(points[0][1], points[1][1]) };
            return .{
                .min = min,
                .max = max,
            };
        }

        /// Converts each component T of AABB(T) to T2 and returns AABB(T2)
        pub fn into(this: @This(), comptime T2: type) AABB(T2) {
            const t = @typeInfo(T);
            const t2 = @typeInfo(T2);
            if (t2 == .Int or t == .ComptimeInt) {
                return if (t == .Int or t == .ComptimeInt)
                    .{
                        .min = .{ @intCast(this.min[0]), @intCast(this.min[1]) },
                        .max = .{ @intCast(this.max[0]), @intCast(this.max[1]) },
                    }
                else
                    .{
                        .min = .{ @intFromFloat(this.min[0]), @intFromFloat(this.min[1]) },
                        .max = .{ @intFromFloat(this.max[0]), @intFromFloat(this.max[1]) },
                    };
            } else if (t2 == .Float or t == .ComptimeFloat) {
                return if (t == .Float or t == .ComptimeFloat)
                    .{
                        .min = .{ @floatCast(this.min[0]), @floatCast(this.min[1]) },
                        .max = .{ @floatCast(this.max[0]), @floatCast(this.max[1]) },
                    }
                else
                    .{
                        .min = .{ @floatFromInt(this.min[0]), @floatFromInt(this.min[1]) },
                        .max = .{ @floatFromInt(this.max[0]), @floatFromInt(this.max[1]) },
                    };
            }
        }

        pub fn fromRect(rect: Rect(T)) @This() {
            return AABB(T){
                .min = rect.pos,
                .max = .{
                    rect.pos[0] + rect.size[0] - 1,
                    rect.pos[1] + rect.size[1] - 1,
                },
            };
        }

        pub fn translate(this: @This(), amount: [2]T) @This() {
            return @This(){
                .min = [2]T{
                    this.min[0] + amount[0],
                    this.min[1] + amount[1],
                },
                .max = [2]T{
                    this.max[0] + amount[0],
                    this.max[1] + amount[1],
                },
            };
        }

        pub fn inset(this: @This(), amount: Inset(T)) @This() {
            return @This(){
                .min = [2]T{
                    this.min[0] + amount.min[0],
                    this.min[1] + amount.min[1],
                },
                .max = [2]T{
                    this.max[0] - amount.max[0],
                    this.max[1] - amount.max[1],
                },
            };
        }

        pub fn contains(this: @This(), point: [2]T) bool {
            return point[0] >= this.min[0] and
                point[1] >= this.min[1] and
                point[0] <= this.max[0] and
                point[1] <= this.max[1];
        }

        pub fn overlaps(this: @This(), other: @This()) bool {
            const each_axis = .{
                this.min[0] <= other.max[0] and this.max[0] >= other.min[0],
                this.min[1] <= other.max[1] and this.max[1] >= other.min[1],
            };
            return each_axis[0] and each_axis[1];
        }

        pub fn topLeft(this: @This()) [2]T {
            return this.min;
        }

        pub fn bottomRight(this: @This()) [2]T {
            return this.max;
        }

        /// Gets the size as (max - min)
        pub fn size(this: @This()) [2]T {
            return [2]T{
                this.max[0] - this.min[0],
                this.max[1] - this.min[1],
            };
        }

        /// Gets the size as (max - min) + the smallest value the child type can represent (e.g. 1 for integer, `std.math.epsilon()` for floats)
        pub fn sizePlusEpsilon(this: @This()) [2]T {
            const MAX = switch (@typeInfo(T)) {
                .Int => std.math.maxInt(T),
                .Float => std.math.inf(T),
                else => @compileError("unsupported type " ++ @typeName(T)),
            };
            return .{
                std.math.nextAfter(T, this.max[0] - this.min[0], MAX),
                std.math.nextAfter(T, this.max[1] - this.min[1], MAX),
            };
        }

        pub fn clamp(value: @This(), bounds: @This()) @This() {
            std.debug.assert(value.min[0] <= value.max[0]);
            std.debug.assert(value.min[1] <= value.max[1]);
            std.debug.assert(bounds.min[0] <= bounds.max[0]);
            std.debug.assert(bounds.min[1] <= bounds.max[1]);
            return .{
                .min = .{
                    std.math.clamp(value.min[0], bounds.min[0], bounds.max[0]),
                    std.math.clamp(value.min[1], bounds.min[1], bounds.max[1]),
                },
                .max = .{
                    std.math.clamp(value.max[0], bounds.min[0], bounds.max[0]),
                    std.math.clamp(value.max[1], bounds.min[1], bounds.max[1]),
                },
            };
        }

        pub fn pointClamp(bounds: @This(), point: [2]T) [2]T {
            return .{
                std.math.clamp(point[0], bounds.min[0], bounds.max[0]),
                std.math.clamp(point[1], bounds.min[1], bounds.max[1]),
            };
        }
    };
}

/// AABB type optimized for SIMD.
/// Stores max negated to reduce instructions for intersection/union operations.
/// Because of the negation, SIMD_AABB only works for signed data types.
/// [SIMD_AABB]: https://gist.github.com/mtsamis/441c16f3d6fc86566eaa2a302ed247c9
pub fn SIMD_AABB(comptime T: type) type {
    return struct {
        /// Stores min and max as an array of 4 values with the 2 max values inverted.
        /// A direct initialization would look like this:
        /// `const simd_aabb = .{ .data = .{ min_x, min_y, -max_x, -max_y } };`
        data: @Vector(4, T),

        /// Initialize from two points
        pub fn init(a: [2]T, b: [2]T) @This() {
            const min_x = @min(a[0], b[0]);
            const max_x = @max(a[0], b[0]);
            const min_y = @min(a[1], b[1]);
            const max_y = @max(a[1], b[1]);
            return .{ .data = .{
                min_x,
                min_y,
                -max_x,
                -max_y,
            } };
        }

        /// Return the minimum point of the AABB as array with layout `.{ x, y }`.
        pub fn min(this: @This()) [2]T {
            return this.data[0..2];
        }

        /// Return the maximum point of the AABB as array with layout `.{ x, y }`.
        pub fn max(this: @This()) [2]T {
            const vec_this: @Vector(4, T) = this.data;
            const neg = -vec_this;
            return neg[2..4];
        }

        /// Returns true if the AABBs are overlapping.
        /// Returns false if the AABBs are not overlapping.
        pub fn overlaps(a: @This(), b: @This()) bool {
            const vec_a: @Vector(4, T) = a.data;
            const vec_b: @Vector(4, T) = b.data;
            const vec_b_shuf = @shuffle(T, vec_b, undefined, [4]u8{ 2, 3, 0, 1 });
            return @reduce(.And, vec_a <= -vec_b_shuf);
        }

        /// Returns the area covered by both `a` and `b`.
        pub fn intersection(a: @This(), b: @This()) @This() {
            return .{ .data = @min(a.data, b.data) };
        }
    };
}

test "SIMD_AABB == AABB" {
    // Checks that AABB and SIMD_AABB compute the same result for
    // - Intersection of seperate boxes
    // - Intersection of overlapping boxes
    // - Overlap test of seperate boxes
    // - Overlap test of overlapping boxes
    const overlapped_a = [_]f32{ 0, 0, 7.5, 7.5 };
    const overlapped_b = [_]f32{ 2.5, 2.5, 10, 10 };
    const seperate_a = [_]f32{ 0, 0, 2.5, 2.5 };
    const seperate_b = [_]f32{ 7.5, 7.5, 10, 10 };

    const aabb_overlapped_a = AABB(f32).init(.{ overlapped_a[0..2].*, overlapped_a[2..4].* });
    const aabb_overlapped_b = AABB(f32).init(.{ overlapped_b[0..2].*, overlapped_b[2..4].* });
    const simd_aabb_overlapped_a = SIMD_AABB(f32).init(overlapped_a[0..2].*, overlapped_a[2..4].*);
    const simd_aabb_overlapped_b = SIMD_AABB(f32).init(overlapped_b[0..2].*, overlapped_b[2..4].*);

    const aabb_seperate_a = AABB(f32).init(.{ seperate_a[0..2].*, seperate_a[2..4].* });
    const aabb_seperate_b = AABB(f32).init(.{ seperate_b[0..2].*, seperate_b[2..4].* });
    const simd_aabb_seperate_a = SIMD_AABB(f32).init(seperate_a[0..2].*, seperate_a[2..4].*);
    const simd_aabb_seperate_b = SIMD_AABB(f32).init(seperate_b[0..2].*, seperate_b[2..4].*);

    try std.testing.expectEqual(@as(@Vector(4, f32), .{ 0, 0, -7.5, -7.5 }), simd_aabb_overlapped_a.data);
    try std.testing.expectEqual(@as(@Vector(4, f32), .{ 2.5, 2.5, -10, -10 }), simd_aabb_overlapped_b.data);
    try std.testing.expectEqual(@as(@Vector(4, f32), .{ 0, 0, -2.5, -2.5 }), simd_aabb_seperate_a.data);
    try std.testing.expectEqual(@as(@Vector(4, f32), .{ 7.5, 7.5, -10, -10 }), simd_aabb_seperate_b.data);

    try std.testing.expectEqual(aabb_overlapped_a.overlaps(aabb_overlapped_b), simd_aabb_overlapped_a.overlaps(simd_aabb_overlapped_b));
    try std.testing.expectEqual(aabb_overlapped_b.overlaps(aabb_overlapped_a), simd_aabb_overlapped_b.overlaps(simd_aabb_overlapped_a));

    try std.testing.expectEqual(aabb_seperate_a.overlaps(aabb_seperate_b), simd_aabb_seperate_a.overlaps(simd_aabb_seperate_b));
    try std.testing.expectEqual(aabb_seperate_b.overlaps(aabb_seperate_a), simd_aabb_seperate_b.overlaps(simd_aabb_seperate_a));
}

/// Defines a rectangular region relative to another rectangular region. In this case the numbers
/// represent how far inside another rectangle the min and max positions are.
pub fn Inset(comptime T: type) type {
    return struct {
        /// How far inward from the top left corner is this Inset?
        min: [2]T,
        /// How far inward from the bottom right corner is this Inset?
        max: [2]T,

        pub fn initXY(x: T, y: T) @This() {
            return .{
                .min = .{ x, y },
                .max = .{ x, y },
            };
        }

        /// Gives the extra size that this inset would add, or a negative number if it would decrease
        /// the size.
        pub fn size(this: @This()) [2]T {
            return .{
                this.min[0] + this.max[0],
                this.min[1] + this.max[1],
            };
        }

        pub fn scale(this: @This(), scalar: T) @This() {
            return .{
                .min = .{ this.min[0] * scalar, this.min[1] * scalar },
                .max = .{ this.max[0] * scalar, this.max[1] * scalar },
            };
        }

        /// Converts each component T of Inset(T) to T2 and returns Inset(T2)
        pub fn into(this: @This(), comptime T2: type) Inset(T2) {
            const t = @typeInfo(T);
            const t2 = @typeInfo(T2);
            if (t2 == .Int or t == .ComptimeInt) {
                return if (t == .Int or t == .ComptimeInt)
                    .{
                        .min = .{ @intCast(this.min[0]), @intCast(this.min[1]) },
                        .max = .{ @intCast(this.max[0]), @intCast(this.max[1]) },
                    }
                else
                    .{
                        .min = .{ @intFromFloat(this.min[0]), @intFromFloat(this.min[1]) },
                        .max = .{ @intFromFloat(this.max[0]), @intFromFloat(this.max[1]) },
                    };
            } else if (t2 == .Float or t == .ComptimeFloat) {
                return if (t == .Float or t == .ComptimeFloat)
                    .{
                        .min = .{ @floatCast(this.min[0]), @floatCast(this.min[1]) },
                        .max = .{ @floatCast(this.max[0]), @floatCast(this.max[1]) },
                    }
                else
                    .{
                        .min = .{ @floatFromInt(this.min[0]), @floatFromInt(this.min[1]) },
                        .max = .{ @floatFromInt(this.max[0]), @floatFromInt(this.max[1]) },
                    };
            }
        }
    };
}

const std = @import("std");
