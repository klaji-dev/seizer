const Surface = @This();

display: *seizer.Display,
wl_surface: shimizu.Object.WithInterface(shimizu.core.wl_surface),
swapchain: Swapchain,
framebuffer: seizer.image.Linear(seizer.color.argbf32_premultiplied),
on_render_listener: ?*OnRenderListener,
size: [2]u32,

pub const InitOptions = struct {
    size: [2]u32 = .{ 32, 32 },
};

pub const OnRenderListener = struct {
    callback: CallbackFn,
    userdata: ?*anyopaque,

    pub const CallbackFn = *const fn (*OnRenderListener, *Surface) anyerror!void;
};

pub fn deinit(this: *@This()) void {
    this.swapchain.deinit();
    this.framebuffer.free(this.display.allocator);
}

pub fn setOnRender(this: *@This(), on_render_listener: *OnRenderListener, callback: OnRenderListener.CallbackFn, userdata: ?*anyopaque) void {
    on_render_listener.* = .{
        .callback = callback,
        .userdata = userdata,
    };
    this.on_render_listener = on_render_listener;
}

pub fn canvas(this: *@This()) !seizer.Canvas {
    // try this.framebuffer.resize(this.display.allocator, this.size);
    return .{
        .ptr = this,
        .interface = CANVAS_INTERFACE,
    };
}

pub fn present(this: *@This()) !void {
    if (this.swapchain.size[0] != this.framebuffer.size[0] or
        this.swapchain.size[1] != this.framebuffer.size[1])
    {
        this.swapchain.deinit();
        try this.swapchain.allocate(.{ .connection = &this.display.connection, .id = this.display.globals.wl_shm.? }, this.framebuffer.size, 3);
    }

    const buffer = try this.swapchain.getBuffer();
    for (0..buffer.size[1]) |y| {
        const row = buffer.pixels[y * buffer.size[0] ..][0..buffer.size[0]];
        for (row, 0..) |*px, x| {
            px.* = this.framebuffer.getPixel(.{ @intCast(x), @intCast(y) }).convertColorTo(seizer.color.sRGB8).convertAlphaTo(u8);
        }
    }

    try this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .attach, .{
        .x = 0,
        .y = 0,
        .buffer = buffer.wl_buffer.id,
    });
    try this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .damage_buffer, .{
        .x = 0,
        .y = 0,
        .width = @intCast(buffer.size[0]),
        .height = @intCast(buffer.size[1]),
    });
    try this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .commit, .{});
}

pub fn hide(this: *@This()) void {
    this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .attach, .{
        .x = 0,
        .y = 0,
        // shimizu: TODO: make properly nullable?
        .buffer = @enumFromInt(0),
    }) catch {};
    this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .damage_buffer, .{
        .x = 0,
        .y = 0,
        .width = std.math.maxInt(i32),
        .height = std.math.maxInt(i32),
    }) catch {};
    this.display.connection.sendRequest(wayland.wl_surface, this.wl_surface, .commit, .{}) catch {};
}

// Canvas implementation

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
    return seizer.geometry.vec.into(f64, this.framebuffer.size);
}

pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argbf32_premultiplied) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.framebuffer.clear(color);
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied)) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const pos_i = [2]i32{
        @intFromFloat(@floor(pos[0])),
        @intFromFloat(@floor(pos[1])),
    };
    const size_i = [2]i32{
        @intCast(this.framebuffer.size[0]),
        @intCast(this.framebuffer.size[1]),
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
    const dest = this.framebuffer.slice(dest_offset, src_size);

    dest.composite(src);
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, area: seizer.geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: seizer.Canvas.FillRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    _ = options;

    const area_u = area.into(i32);

    this.framebuffer.drawFillRect(area_u.min, area_u.max, color);
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_area: seizer.geometry.AABB(f64), src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: seizer.Canvas.TextureRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    _ = this;
    _ = dst_area;
    _ = src_image;
    _ = options;
}

pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const start_f = seizer.geometry.vec.into(f32, start);
    const end_f = seizer.geometry.vec.into(f32, end);
    const end_color = options.end_color orelse options.color;
    const width: f32 = @floatCast(options.width);
    const end_width: f32 = @floatCast(options.end_width orelse width);

    this.framebuffer.drawLine(.{ .min = .{ 0, 0 }, .max = this.framebuffer.size }, start_f, end_f, .{ width, end_width }, .{ options.color, end_color });
}

const Swapchain = @import("./Swapchain.zig");

const wayland = shimizu.core;

// stable protocols
const viewporter = @import("wayland-protocols").viewporter;
const linux_dmabuf_v1 = @import("wayland-protocols").linux_dmabuf_v1;
const xdg_shell = @import("wayland-protocols").xdg_shell;

// unstable protocols
const xdg_decoration = @import("wayland-unstable").xdg_decoration_unstable_v1;
const fractional_scale_v1 = @import("wayland-unstable").fractional_scale_v1;

const log = std.log.scoped(.seizer);

const seizer = @import("../seizer.zig");
const shimizu = @import("shimizu");
const std = @import("std");
const xev = @import("xev");
