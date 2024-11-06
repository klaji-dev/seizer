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

        pub fn intToFloat(this: @This(), comptime F: type) Inset(F) {
            return .{
                .min = .{ @floatFromInt(this.min[0]), @floatFromInt(this.min[1]) },
                .max = .{ @floatFromInt(this.max[0]), @floatFromInt(this.max[1]) },
            };
        }
    };
}
