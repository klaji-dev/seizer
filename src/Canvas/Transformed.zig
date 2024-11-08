parent: seizer.Canvas,
transform: [4][4]f64,
clip_area: seizer.geometry.AABB(f64),

pub const InitOptions = struct {
    clip: seizer.geometry.AABB(f64),
    transform: [4][4]f64 = seizer.geometry.mat4.identity(f64),
};

pub fn init(parent: seizer.Canvas, options: InitOptions) @This() {
    return .{
        .parent = parent,
        .transform = options.transform,
        .clip_area = options.clip,
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

pub fn canvas_fillRect(this_opaque: ?*anyopaque, area: seizer.geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: seizer.Canvas.FillRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const transformed_area = seizer.geometry.AABB(f64).init(.{
        seizer.geometry.mat4.mulVec(f64, this.transform, area.min ++ .{ 0, 1 })[0..2].*,
        seizer.geometry.mat4.mulVec(f64, this.transform, area.max ++ .{ 0, 1 })[0..2].*,
    });

    const clipped_area = transformed_area.clamp(this.clip_area);

    return this.parent.fillRect(clipped_area, color, options);
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_area: seizer.geometry.AABB(f64), src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: seizer.Canvas.TextureRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const dst_area_t = seizer.geometry.AABB(f64){
        .min = seizer.geometry.mat4.mulVec(f64, this.transform, dst_area.min ++ .{ 0, 1 })[0..2].*,
        .max = seizer.geometry.mat4.mulVec(f64, this.transform, dst_area.max ++ .{ 0, 1 })[0..2].*,
    };

    if (!dst_area_t.overlaps(this.clip_area)) {
        return;
    }

    const dst_area_clipped = dst_area_t.clamp(this.clip_area);

    const src_area = options.src_area orelse seizer.geometry.AABB(f64){
        .min = .{ 0, 0 },
        .max = .{ @floatFromInt(src_image.size[0]), @floatFromInt(src_image.size[1]) },
    };
    const src_area_clipped = src_area.inset(.{
        .min = .{
            ((dst_area_clipped.min[0] - dst_area_t.min[0]) / dst_area_t.size()[0]) * src_area.size()[0],
            ((dst_area_clipped.min[1] - dst_area_t.min[1]) / dst_area_t.size()[1]) * src_area.size()[1],
        },
        .max = .{
            ((dst_area_clipped.max[0] - dst_area_t.max[0]) / dst_area_t.size()[0]) * src_area.size()[0],
            ((dst_area_clipped.max[1] - dst_area_t.max[1]) / dst_area_t.size()[1]) * src_area.size()[1],
        },
    });

    this.parent.textureRect(dst_area_clipped, src_image, .{
        .src_area = src_area_clipped,
        .color = options.color,
        .depth = options.depth,
    });
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
