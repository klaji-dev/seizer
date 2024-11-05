const ToplevelSurface = @This();

display: *Display,
wl_surface: shimizu.Object.WithInterface(shimizu.core.wl_surface),
xdg_surface: shimizu.Object.WithInterface(xdg_shell.xdg_surface),
xdg_toplevel: shimizu.Object.WithInterface(xdg_shell.xdg_toplevel),

xdg_surface_listener: shimizu.Listener,
xdg_toplevel_listener: shimizu.Listener,

frame_callback: ?shimizu.Object.WithInterface(wayland.wl_callback),
frame_callback_listener: shimizu.Listener,

current_configuration: Configuration,
new_configuration: Configuration,

/// This framebuffer is used for compositing. The buffer that will be sent to the compositor
/// will need to be have a linear layout and be `argb8888` encoded.
framebuffer: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argb(f32)),
swapchain: Swapchain,
on_render_listener: ?*OnRenderListener,
on_input_listener: ?*OnInputListener,

pub const InitOptions = struct {
    size: [2]u32 = .{ 640, 480 },
};

pub const OnRenderListener = struct {
    callback: CallbackFn,
    userdata: ?*anyopaque,

    pub const CallbackFn = *const fn (*OnRenderListener, *ToplevelSurface) anyerror!void;
};

pub const OnInputListener = struct {
    callback: CallbackFn,
    userdata: ?*anyopaque,

    pub const CallbackFn = *const fn (*OnInputListener, *ToplevelSurface, seizer.input.Event) anyerror!void;
};

pub fn deinit(this: *@This()) void {
    // TODO: Object.asProxy
    const wl_surface: shimizu.Proxy(wayland.wl_surface) = .{ .connection = &this.display.connection, .id = this.wl_surface };
    const xdg_surface: shimizu.Proxy(xdg_shell.xdg_surface) = .{ .connection = &this.display.connection, .id = this.xdg_surface };
    const xdg_toplevel: shimizu.Proxy(xdg_shell.xdg_toplevel) = .{ .connection = &this.display.connection, .id = this.xdg_toplevel };

    // destroy surfaces
    // if (this.xdg_toplevel_decoration) |decoration| decoration.sendRequest(.destroy, .{}) catch {};
    xdg_toplevel.sendRequest(.destroy, .{}) catch {};
    xdg_surface.sendRequest(.destroy, .{}) catch {};
    wl_surface.sendRequest(.destroy, .{}) catch {};

    // TODO: remove event listeners from surfaces
    // window.xdg_toplevel.userdata = null;
    // window.xdg_surface.userdata = null;
    // window.wl_surface.userdata = null;

    // window.xdg_toplevel.on_event = null;
    // window.xdg_surface.on_event = null;
    // window.wl_surface.on_event = null;

    // if (window.frame_callback) |frame_callback| {
    //     frame_callback.userdata = null;
    //     frame_callback.on_event = null;
    // }
    this.framebuffer.free(this.display.allocator);
    this.swapchain.deinit();
}

pub fn setOnRender(this: *@This(), on_render_listener: *OnRenderListener, callback: OnRenderListener.CallbackFn, userdata: ?*anyopaque) void {
    on_render_listener.* = .{
        .callback = callback,
        .userdata = userdata,
    };
    this.on_render_listener = on_render_listener;
}

pub fn setOnInput(this: *@This(), input_listener: *OnInputListener, callback: OnInputListener.CallbackFn, userdata: ?*anyopaque) void {
    input_listener.* = .{
        .callback = callback,
        .userdata = userdata,
    };
    this.on_input_listener = input_listener;
}

pub fn canvas(this: *@This()) !seizer.Canvas {
    try this.framebuffer.ensureSize(this.display.allocator, this.current_configuration.window_size);
    return .{
        .ptr = this,
        .interface = CANVAS_INTERFACE,
    };
}

pub fn requestAnimationFrame(this: *@This()) !void {
    if (this.frame_callback != null) return;
    const wl_surface = shimizu.Proxy(wayland.wl_surface){ .connection = &this.display.connection, .id = this.wl_surface };

    const frame_callback = try wl_surface.sendRequest(.frame, .{});
    frame_callback.setEventListener(&this.frame_callback_listener, onFrameCallback, this);

    this.frame_callback = frame_callback.id;
}

pub fn present(this: *@This()) !void {
    if (!std.mem.eql(u32, &this.swapchain.size, &this.current_configuration.window_size)) {
        this.swapchain.deinit();
        try this.swapchain.allocate(.{ .connection = &this.display.connection, .id = this.display.globals.wl_shm.? }, this.current_configuration.window_size, 3);
    }

    const buffer = try this.swapchain.getBuffer();
    for (0..buffer.size[1]) |y| {
        const row = buffer.pixels[y * buffer.size[0] ..][0..buffer.size[0]];
        for (row, 0..) |*px, x| {
            px.* = this.framebuffer.getPixel(.{ @intCast(x), @intCast(y) }).toArgb8888();
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
    return .{ @floatFromInt(this.current_configuration.window_size[0]), @floatFromInt(this.current_configuration.window_size[1]) };
}

pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argb(f64)) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.framebuffer.clear(color.floatCast(f32));
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Image(seizer.color.argb(f32))) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const pos_i = [2]i32{
        @intFromFloat(@floor(pos[0])),
        @intFromFloat(@floor(pos[1])),
    };
    const size_i = [2]i32{
        @intCast(this.current_configuration.window_size[0]),
        @intCast(this.current_configuration.window_size[1]),
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

    dest.compositeLinear(src);
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, pos: [2]f64, size: [2]f64, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const a = [2]i32{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) };
    const b = [2]i32{ @intFromFloat(pos[0] + size[0]), @intFromFloat(pos[1] + size[1]) };

    this.framebuffer.drawFillRect(a, b, options.color.floatCast(f32));
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, src_image: seizer.image.Image(seizer.color.argb(f32)), options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const start_pos = [2]u32{
        @min(@as(u32, @intFromFloat(@floor(@max(@min(dst_pos[0], dst_pos[0] + dst_size[0]), 0)))), this.current_configuration.window_size[0]),
        @min(@as(u32, @intFromFloat(@floor(@max(@min(dst_pos[1], dst_pos[1] + dst_size[1]), 0)))), this.current_configuration.window_size[1]),
    };
    const end_pos = [2]u32{
        @min(@as(u32, @intFromFloat(@floor(@max(dst_pos[0], dst_pos[0] + dst_size[0], 0)))), this.current_configuration.window_size[0]),
        @min(@as(u32, @intFromFloat(@floor(@max(dst_pos[1], dst_pos[1] + dst_size[1], 0)))), this.current_configuration.window_size[1]),
    };

    const src_size = [2]f64{
        @floatFromInt(src_image.size[0]),
        @floatFromInt(src_image.size[1]),
    };

    const color_mask = options.color.floatCast(f32);

    for (start_pos[1]..end_pos[1]) |y| {
        for (start_pos[0]..end_pos[0]) |x| {
            const pos = [2]f64{ @floatFromInt(x), @floatFromInt(y) };
            const texture_coord = [2]f64{
                std.math.clamp(((pos[0] - dst_pos[0]) / dst_size[0]) * src_size[0], 0, src_size[0]),
                std.math.clamp(((pos[1] - dst_pos[1]) / dst_size[1]) * src_size[1], 0, src_size[1]),
            };
            const dst_pixel = this.framebuffer.getPixel(.{ @intCast(x), @intCast(y) });
            const src_pixel = src_image.getPixel(.{
                @intFromFloat(texture_coord[0]),
                @intFromFloat(texture_coord[1]),
            });
            const src_pixel_tint = src_pixel.tint(color_mask);
            this.framebuffer.setPixel(.{ @intCast(x), @intCast(y) }, dst_pixel.compositeSrcOver(src_pixel_tint));
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

    this.framebuffer.drawLine(start_i, end_i, options.color.floatCast(f32));
}

// shimizu callback functions

const Configuration = struct {
    window_size: [2]u32,
    decoration_mode: xdg_decoration.zxdg_toplevel_decoration_v1.Mode,
};

pub fn onXdgSurfaceEvent(listener: *shimizu.Listener, xdg_surface: shimizu.Proxy(xdg_shell.xdg_surface), event: xdg_shell.xdg_surface.Event) !void {
    const this: *@This() = @fieldParentPtr("xdg_surface_listener", listener);
    switch (event) {
        .configure => |conf| {
            // if (this.xdg_toplevel_decoration) |decoration| {
            //     if (this.current_configuration.decoration_mode != this.new_configuration.decoration_mode) {
            //         try decoration.sendRequest(.set_mode, .{ .mode = this.new_configuration.decoration_mode });
            //         this.current_configuration.decoration_mode = this.new_configuration.decoration_mode;
            //     }
            // }

            if (!std.mem.eql(u32, &this.current_configuration.window_size, &this.new_configuration.window_size)) {
                this.current_configuration.window_size = this.new_configuration.window_size;
                // if (this.on_event) |on_event| {
                //     on_event(@ptrCast(this), .{ .resize = [2]f32{
                //         @floatFromInt(this.current_configuration.window_size[0]),
                //         @floatFromInt(this.current_configuration.window_size[1]),
                //     } }) catch |err| {
                //         std.debug.print("error returned from window event: {}\n", .{err});
                //         if (@errorReturnTrace()) |err_ret_trace| {
                //             std.debug.dumpStackTrace(err_ret_trace.*);
                //         }
                //     };
                // }
            }

            try xdg_surface.sendRequest(.ack_configure, .{ .serial = conf.serial });

            if (this.frame_callback == null) {
                const frame_callback = try this.display.connection.getDisplayProxy().sendRequest(.sync, .{});
                this.frame_callback = frame_callback.id;
                frame_callback.setEventListener(&this.frame_callback_listener, onFrameCallback, null);
            }
        },
    }
}

pub fn onXdgToplevelEvent(listener: *shimizu.Listener, xdg_toplevel: shimizu.Proxy(xdg_shell.xdg_toplevel), event: xdg_shell.xdg_toplevel.Event) !void {
    const this: *@This() = @fieldParentPtr("xdg_toplevel_listener", listener);
    _ = xdg_toplevel;
    switch (event) {
        .close => _ = this.display.surfaces.remove(this.wl_surface),
        // if (this.on_event) |on_event| {
        //     on_event(@ptrCast(this), .should_close) catch |err| {
        //         std.debug.print("error returned from window event: {}\n", .{err});
        //         if (@errorReturnTrace()) |err_ret_trace| {
        //             std.debug.dumpStackTrace(err_ret_trace.*);
        //         }
        //     };
        // },
        .configure => |cfg| {
            if (cfg.width > 0 and cfg.height > 0) {
                this.new_configuration.window_size[0] = @intCast(cfg.width);
                this.new_configuration.window_size[1] = @intCast(cfg.height);
            }
        },
        else => {},
    }
}

// fn onXdgToplevelDecorationEvent(listener: *shimizu.Listener, xdg_toplevel_decoration: shimizu.Proxy(xdg_decoration.zxdg_toplevel_decoration_v1), event: xdg_decoration.zxdg_toplevel_decoration_v1.Event) !void {
//     const this: *@This() = @fieldParentPtr("xdg_toplevel_decoration_listener", listener);
//     _ = xdg_toplevel_decoration;
//     switch (event) {
//         .configure => |cfg| {
//             if (cfg.mode == .server_side) {
//                 this.new_configuration.decoration_mode = .server_side;
//             }
//         },
//     }
// }

// fn onWpFractionalScale(listener: *shimizu.Listener, wp_fractional_scale: shimizu.Proxy(fractional_scale_v1.wp_fractional_scale_v1), event: fractional_scale_v1.wp_fractional_scale_v1.Event) !void {
//     const this: *@This() = @fieldParentPtr("wp_fractional_scale_listener", listener);
//     _ = wp_fractional_scale;
//     switch (event) {
//         .preferred_scale => |preferred| {
//             this.preferred_scale = preferred.scale;
//             if (this.on_event) |on_event| {
//                 on_event(@ptrCast(this), .{ .rescale = @as(f32, @floatFromInt(this.preferred_scale)) / 120.0 }) catch |err| {
//                     std.debug.print("error returned from window event: {}\n", .{err});
//                     if (@errorReturnTrace()) |err_ret_trace| {
//                         std.debug.dumpStackTrace(err_ret_trace.*);
//                     }
//                 };
//             }
//         },
//     }
// }

fn onFrameCallback(listener: *shimizu.Listener, callback: shimizu.Proxy(wayland.wl_callback), event: wayland.wl_callback.Event) shimizu.Listener.Error!void {
    const this: *@This() = @fieldParentPtr("frame_callback_listener", listener);
    _ = callback;
    switch (event) {
        .done => {
            this.frame_callback = null;
            if (this.on_render_listener) |render_listener| {
                render_listener.callback(render_listener, this) catch |err| {
                    log.err("{}", .{err});
                    if (@errorReturnTrace()) |error_trace| {
                        std.debug.dumpStackTrace(error_trace.*);
                    }
                    return;
                };
            }
        },
    }
}

fn onWlBufferRelease(userdata: ?*anyopaque, wl_buffer: shimizu.Proxy(wayland.wl_buffer)) void {
    _ = userdata;
    wl_buffer.sendRequest(.destroy, .{});
}

const Display = @import("../Display.zig");
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
