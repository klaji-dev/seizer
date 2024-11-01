wl_buffer: shimizu.Proxy(shimizu.core.wl_buffer),
size: [2]u32,
pixels: [*]seizer.color.argb8888,

pub fn clear(this: @This(), color: seizer.color.argb) void {
    @memset(this.pixels[0 .. this.size[0] * this.size[1]], color.toArgb8888());
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
    .texture_rect = canvas_textureRect,
    .fill_rect = canvas_fillRect,
    .line = canvas_line,
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

pub fn canvas_fillRect(this_opaque: ?*anyopaque, pos: [2]f64, size: [2]f64, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const a = [2]i32{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) };
    const b = [2]i32{ @intFromFloat(pos[0] + size[0]), @intFromFloat(pos[1] + size[1]) };

    this.image().drawFillRect(a, b, options.color.toArgb8888());
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, src_image: seizer.Image, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const start_pos = [2]u32{
        @min(@as(u32, @intFromFloat(@floor(@max(@min(dst_pos[0], dst_pos[0] + dst_size[0]), 0)))), this.size[0]),
        @min(@as(u32, @intFromFloat(@floor(@max(@min(dst_pos[1], dst_pos[1] + dst_size[1]), 0)))), this.size[1]),
    };
    const end_pos = [2]u32{
        @min(@as(u32, @intFromFloat(@floor(@max(dst_pos[0], dst_pos[0] + dst_size[0], 0)))), this.size[0]),
        @min(@as(u32, @intFromFloat(@floor(@max(dst_pos[1], dst_pos[1] + dst_size[1], 0)))), this.size[1]),
    };

    const src_size = [2]f64{
        @floatFromInt(src_image.size[0]),
        @floatFromInt(src_image.size[1]),
    };

    const color_mask = options.color.toArgb8888();

    for (start_pos[1]..end_pos[1]) |y| {
        for (start_pos[0]..end_pos[0]) |x| {
            const pos = [2]f64{ @floatFromInt(x), @floatFromInt(y) };
            const texture_coord = [2]f64{
                std.math.clamp(((pos[0] - dst_pos[0]) / dst_size[0]) * src_size[0], 0, src_size[0]),
                std.math.clamp(((pos[1] - dst_pos[1]) / dst_size[1]) * src_size[1], 0, src_size[1]),
            };
            const dst_pixel = this.image().getPixel(.{ @intCast(x), @intCast(y) });
            const src_pixel = src_image.getPixel(.{
                @intFromFloat(texture_coord[0]),
                @intFromFloat(texture_coord[1]),
            });
            const src_pixel_tint = seizer.color.tint(src_pixel, color_mask);
            this.image().setPixel(.{ @intCast(x), @intCast(y) }, seizer.color.compositeSrcOver(
                dst_pixel,
                src_pixel_tint,
            ));
        }
    }
}

pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const start_i = [2]i32{
        @intFromFloat(@floor(start[0])),
        @intFromFloat(@floor(start[1])),
    };
    const end_i = [2]i32{
        @intFromFloat(@floor(end[0])),
        @intFromFloat(@floor(end[1])),
    };

    this.image().drawLine(start_i, end_i, options.color.toArgb8888());
}

const seizer = @import("../seizer.zig");
const shimizu = @import("shimizu");
const std = @import("std");
