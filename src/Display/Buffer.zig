wl_buffer: shimizu.Proxy(shimizu.core.wl_buffer),
size: [2]u32,
pixels: [*]Pixel,

pub const Pixel = [4]u8;

pub fn clear(this: @This(), color: [4]f64) void {
    // TODO: stop assuming xrgb8888
    const color_u8 = [4]u8{
        @intFromFloat(color[2] * std.math.maxInt(u8)),
        @intFromFloat(color[1] * std.math.maxInt(u8)),
        @intFromFloat(color[0] * std.math.maxInt(u8)),
        @intFromFloat(color[3] * std.math.maxInt(u8)),
    };
    @memset(this.pixels[0 .. this.size[0] * this.size[1]], color_u8);
}

pub fn image(this: @This()) seizer.Image {
    return .{
        .size = this.size,
        .stride = this.size[0],
        .pixels = this.pixels,
    };
}

pub fn canvas(this: *@This()) seizer.Canvas {
    return .{
        .ptr = this,
        .interface = CANVAS_INTERFACE,
    };
}

const CANVAS_INTERFACE: *const seizer.Canvas.Interface = &.{
    .size = canvas_size,
    .blit = canvas_blit,
};

pub fn canvas_size(this_opaque: ?*anyopaque) [2]f64 {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    return .{ @floatFromInt(this.size[0]), @floatFromInt(this.size[1]) };
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.Image) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const pos_i = [2]i32{
        @intFromFloat(@floor(pos[0])),
        @intFromFloat(@floor(pos[1])),
    };
    const size_i = [2]i32{
        @intCast(this.size[0]),
        @intCast(this.size[1]),
    };

    if (pos_i[0] + size_i[0] <= 0 or pos_i[1] + size_i[1] <= 0) return;
    if (pos_i[0] >= size_i[0] or pos_i[1] >= size_i[1]) return;

    const src_size = [2]u32{
        @min(src_image.size[0], @as(u32, @intCast(size_i[0] - pos_i[0]))),
        @min(src_image.size[1], @as(u32, @intCast(size_i[1] - pos_i[1]))),
    };

    const src_offset = [2]u32{
        if (pos_i[0] < 0) @intCast(-pos_i[0]) else 0,
        if (pos_i[1] < 0) @intCast(-pos_i[1]) else 0,
    };
    const dest_offset = [2]u32{
        @intCast(@max(pos_i[0], 0)),
        @intCast(@max(pos_i[1], 0)),
    };

    const src = src_image.slice(src_offset, src_size);
    const dest = this.image().slice(dest_offset, src_size);

    dest.composite(src);
}

const seizer = @import("../seizer.zig");
const shimizu = @import("shimizu");
const std = @import("std");
