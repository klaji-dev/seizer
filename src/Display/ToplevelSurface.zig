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
framebuffer: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied),
swapchain: Swapchain,
close_listener: ?*CloseListener,
on_render_listener: ?*OnRenderListener,
on_input_listener: ?*OnInputListener,

pub const InitOptions = struct {
    size: [2]u32 = .{ 640, 480 },
};

pub const CloseListener = struct {
    callback: CallbackFn,

    pub const CallbackFn = *const fn (*CloseListener, *ToplevelSurface) anyerror!void;
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
    this.hide();

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

pub fn setOnClose(this: *@This(), close_listener: *CloseListener, callback: CloseListener.CallbackFn) void {
    close_listener.* = .{
        .callback = callback,
    };
    this.close_listener = close_listener;
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

    // Make sure this surface is in the list of active surfaces

    try this.display.surfaces.put(this.display.allocator, this.wl_surface, this);
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

    _ = this.display.surfaces.remove(this.wl_surface);
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

    this.framebuffer.drawFillRect(a, b, options.color);
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_posf: [2]f64, dst_sizef: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    std.debug.assert(dst_sizef[0] >= 0 and dst_sizef[1] >= 0);

    const src_sizef: [2]f32 = .{
        @floatFromInt(src_image.size[0]),
        @floatFromInt(src_image.size[1]),
    };

    const window_sizef = [2]f64{
        @floatFromInt(this.current_configuration.window_size[0]),
        @floatFromInt(this.current_configuration.window_size[1]),
    };

    const dst_start_clamped = .{
        std.math.clamp(dst_posf[0], 0, window_sizef[0]),
        std.math.clamp(dst_posf[1], 0, window_sizef[1]),
    };
    const dst_end_clamped = .{
        std.math.clamp(dst_posf[0] + dst_sizef[0], 0, window_sizef[0]),
        std.math.clamp(dst_posf[1] + dst_sizef[1], 0, window_sizef[1]),
    };

    const dst_start_pos = [2]u32{
        @intFromFloat(dst_start_clamped[0]),
        @intFromFloat(dst_start_clamped[1]),
    };
    const dst_end_pos = [2]u32{
        @intFromFloat(dst_end_clamped[0]),
        @intFromFloat(dst_end_clamped[1]),
    };

    const dst_size = [2]u32{
        dst_end_pos[0] - dst_start_pos[0],
        dst_end_pos[1] - dst_start_pos[1],
    };
    if (dst_size[0] == 0 or dst_size[1] == 0) return;

    const src_start_offset = .{
        dst_start_clamped[0] - dst_posf[0],
        dst_start_clamped[1] - dst_posf[1],
    };
    const src_end_offset = .{
        dst_end_clamped[0] - (dst_posf[0] + dst_sizef[0]),
        dst_end_clamped[1] - (dst_posf[1] + dst_sizef[1]),
    };
    const src_start_pos = [2]u32{
        @intFromFloat(src_start_offset[0]),
        @intFromFloat(src_start_offset[1]),
    };
    const src_end_pos = [2]u32{
        @intFromFloat(src_sizef[0] + src_end_offset[0]),
        @intFromFloat(src_sizef[1] + src_end_offset[1]),
    };
    const src_size = [2]u32{
        src_end_pos[0] - src_start_pos[0],
        src_end_pos[1] - src_start_pos[1],
    };
    if (src_size[0] == 0 or src_size[1] == 0) return;

    const dst = this.framebuffer.slice(dst_start_pos, dst_size);
    const src = src_image.slice(src_start_pos, src_size);

    const Linear = seizer.image.Linear(seizer.color.argbf32_premultiplied);
    const Sampler = struct {
        texture: Linear,
        stride_f: [2]f32,
        tint: seizer.color.argbf32_premultiplied,

        pub fn sample(sampler: *const @This(), pos: [2]u32, sample_rect: Linear) void {
            for (0..sample_rect.size[1]) |sample_y| {
                for (0..sample_rect.size[0]) |sample_x| {
                    const sample_posf = [2]f32{
                        @floatFromInt(pos[0] + sample_x),
                        @floatFromInt(pos[1] + sample_y),
                    };
                    const src_posf = .{
                        sample_posf[0] * sampler.stride_f[0],
                        sample_posf[1] * sampler.stride_f[1],
                    };
                    const src_pixel = sampler.texture.getPixel(.{
                        @intFromFloat(src_posf[0]),
                        @intFromFloat(src_posf[1]),
                    });
                    sample_rect.setPixel(
                        .{ @intCast(sample_x), @intCast(sample_y) },
                        src_pixel.tint(sampler.tint),
                    );
                }
            }
        }
    };
    dst.compositeSampler(
        *const Sampler,
        Sampler.sample,
        &.{
            .texture = src,
            .stride_f = .{
                @floatCast((src_sizef[0] + src_end_offset[0] - src_start_offset[0]) / (dst_end_clamped[0] - dst_start_clamped[0])),
                @floatCast((src_sizef[1] + src_end_offset[1] - src_start_offset[1]) / (dst_end_clamped[1] - dst_start_clamped[1])),
            },
            .tint = options.color,
        },
    );
}

pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const start_f = [2]f32{
        @floatCast(start[0]),
        @floatCast(start[1]),
    };
    const end_f = [2]f32{
        @floatCast(end[0]),
        @floatCast(end[1]),
    };
    const end_color = options.end_color orelse options.color;
    const width: f32 = @floatCast(options.width);
    const end_width: f32 = @floatCast(options.end_width orelse width);

    this.framebuffer.drawLine(start_f, end_f, .{ width, end_width }, .{ options.color, end_color });
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
        .close => if (this.close_listener) |close_listener| {
            close_listener.callback(close_listener, this) catch |err| {
                std.debug.print("{}\n", .{err});
                if (@errorReturnTrace()) |error_trace_ptr| {
                    std.debug.dumpStackTrace(error_trace_ptr.*);
                }
            };
        } else {
            // default behavior when no close listener is set
            this.hide();
        },
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
