parent: seizer.Canvas,
transform: [4][4]f64,
clip_area: seizer.geometry.AABB(f64),

pub const InitOptions = struct {
    clip: seizer.geometry.Rect(f64),
    transform: [4][4]f64 = seizer.geometry.mat4.identity(f64),
};

pub fn init(parent: seizer.Canvas, options: InitOptions) @This() {
    return .{
        .parent = parent,
        .transform = options.transform,
        .clip_area = options.clip.toAABB(),
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

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied)) void {
    _ = this_opaque;
    _ = pos;
    _ = src_image;
    std.debug.panic("Canvas.Transformed does not support blitting at this time", .{});
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, pos: [2]f64, size: [2]f64, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const transformed_start_pos = seizer.geometry.mat4.mulVec(f64, this.transform, pos ++ .{ 0, 1 });
    const transformed_size = seizer.geometry.mat4.mulVec(f64, this.transform, size ++ .{ 0, 0 });

    const clipped_start_pos = .{
        std.math.clamp(transformed_start_pos[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(transformed_start_pos[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const clipped_end_pos = .{
        std.math.clamp(transformed_start_pos[0] + transformed_size[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(transformed_start_pos[1] + transformed_size[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const clipped_size = .{
        clipped_end_pos[0] - clipped_start_pos[0],
        clipped_end_pos[1] - clipped_start_pos[1],
    };

    return this.parent.fillRect(clipped_start_pos, clipped_size, options);
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const dst_rect_t = seizer.geometry.Rect(f64){
        .pos = seizer.geometry.mat4.mulVec(f64, this.transform, dst_pos ++ .{ 0, 1 })[0..2].*,
        .size = seizer.geometry.mat4.mulVec(f64, this.transform, dst_size ++ .{ 0, 0 })[0..2].*,
    };

    const src_sizef = [2]f64{
        @floatFromInt(src_image.size[0]),
        @floatFromInt(src_image.size[1]),
    };
    // const src_sizef_t = seizer.geometry.mat4.mulVec(f64, this.transform, src_sizef ++ .{ 0, 0 })[0..2].*;

    if (!dst_rect_t.toAABB().overlaps(this.clip_area)) {
        return;
    }

    const dst_clipped_start_pos = .{
        std.math.clamp(dst_rect_t.pos[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(dst_rect_t.pos[1], this.clip_area.min[1], this.clip_area.max[1]),
    };
    const dst_clipped_end_pos = .{
        std.math.clamp(dst_rect_t.bottomRight()[0], this.clip_area.min[0], this.clip_area.max[0]),
        std.math.clamp(dst_rect_t.bottomRight()[1], this.clip_area.min[1], this.clip_area.max[1]),
    };

    const src_clipped_offset = .{
        ((dst_clipped_start_pos[0] - dst_rect_t.pos[0]) / dst_rect_t.size[0]) * src_sizef[0],
        ((dst_clipped_start_pos[1] - dst_rect_t.pos[1]) / dst_rect_t.size[1]) * src_sizef[1],
    };
    const src_clipped_end_offset = .{
        ((dst_rect_t.bottomRight()[0] - dst_clipped_end_pos[0]) / dst_rect_t.size[0]) * src_sizef[0],
        ((dst_rect_t.bottomRight()[1] - dst_clipped_end_pos[1]) / dst_rect_t.size[1]) * src_sizef[1],
    };
    const src_clipped_size = .{
        src_sizef[0] - src_clipped_end_offset[0] - src_clipped_offset[0],
        src_sizef[1] - src_clipped_end_offset[1] - src_clipped_offset[1],
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

    const start_t = seizer.geometry.mat4.mulVec(f64, this.transform, start ++ .{ 0, 1 })[0..2].*;
    const end_t = seizer.geometry.mat4.mulVec(f64, this.transform, end ++ .{ 0, 1 })[0..2].*;

    this.parent.line(start_t, end_t, options);
}

const log = std.log.scoped(.seizer);

const seizer = @import("../seizer.zig");
const std = @import("std");
