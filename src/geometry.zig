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
                .max = this.bottomRight(),
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

        pub fn init(min: [2]T, max: [2]T) @This() {
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
            return .{
                .min = rect.topLeft(),
                .max = rect.bottomRight(),
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

        pub fn size(this: @This()) [2]T {
            return [2]T{
                this.max[0] - this.min[0],
                this.max[1] - this.min[1],
            };
        }

        pub fn clamp(value: @This(), bounds: @This()) @This() {
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
    };
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
