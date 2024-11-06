parent: seizer.Canvas,
clip_area: seizer.geometry.AABB(f64),

pub fn canvas(this: *@This()) seizer.Canvas {
    return .{
        .ptr = this,
        .interface = CANVAS_INTERFACE,
    };
}

const CANVAS_INTERFACE: *const seizer.Canvas.Interface = &.{
    .size = canvas_size,
    .clear = canvas_clear,
    .blit = canvas_blit,
    .texture_rect = canvas_textureRect,
    .fill_rect = canvas_fillRect,
    .line = canvas_line,
};

pub fn canvas_size(this_opaque: ?*anyopaque) [2]f64 {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    return this.clip_area.size();
}

pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argbf32_premultiplied) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.parent.clear(color);
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Image(seizer.color.argbf32_premultiplied)) void {
    _ = this_opaque;
    _ = pos;
    _ = src_image;
    std.debug.panic("Canvas.Transformed does not support blitting at this time", .{});
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, pos: [2]f64, size: [2]f64, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const clipped_start_pos = .{
        std.math.clamp(pos[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(pos[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const clipped_end_pos = .{
        std.math.clamp(pos[0] + size[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(pos[1] + size[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const clipped_size = .{
        clipped_end_pos[0] - clipped_start_pos[0],
        clipped_end_pos[1] - clipped_start_pos[1],
    };

    return this.parent.fillRect(clipped_start_pos, clipped_size, options);
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, src_image: seizer.image.Image(seizer.color.argbf32_premultiplied), options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const src_sizef = [2]f64{
        @floatFromInt(src_image.size[0]),
        @floatFromInt(src_image.size[1]),
    };

    const dst_end_pos = [2]f64{
        dst_pos[0] + dst_size[0],
        dst_pos[1] + dst_size[1],
    };

    const dst_clipped_start_pos = .{
        std.math.clamp(dst_pos[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(dst_pos[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const dst_clipped_end_pos = .{
        std.math.clamp(dst_end_pos[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(dst_end_pos[1], this.clip_area.min[1], this.clip_area.max[1]),
    };

    const src_clipped_offset = .{
        ((dst_clipped_start_pos[0] - dst_pos[0]) / dst_size[0]) * src_sizef[0],
        ((dst_clipped_start_pos[1] - dst_pos[1]) / dst_size[1]) * src_sizef[1],
    };
    const src_clipped_end_offset = .{
        ((dst_end_pos[0] - dst_clipped_end_pos[0]) / dst_size[0]) * src_sizef[0],
        ((dst_end_pos[1] - dst_clipped_end_pos[1]) / dst_size[1]) * src_sizef[1],
    };
    const src_clipped_size = .{
        src_sizef[0] - src_clipped_end_offset[0],
        src_sizef[1] - src_clipped_end_offset[1],
    };

    const dst_clipped_size = .{
        dst_clipped_end_pos[0] - dst_clipped_start_pos[0],
        dst_clipped_end_pos[1] - dst_clipped_start_pos[1],
    };

    const src_image_clipped = src_image.slice(.{
        @intFromFloat(src_clipped_offset[0]),
        @intFromFloat(src_clipped_offset[1]),
    }, .{
        @intFromFloat(src_clipped_size[0]),
        @intFromFloat(src_clipped_size[1]),
    });

    this.parent.textureRect(dst_clipped_start_pos, dst_clipped_size, src_image_clipped, options);
}

pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.parent.line(start, end, options);
}

const log = std.log.scoped(.seizer);

const seizer = @import("../seizer.zig");
const std = @import("std");
