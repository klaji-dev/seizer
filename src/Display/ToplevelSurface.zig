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

// Cached software rendering
command: std.MultiArrayList(Command),
command_hash: std.ArrayListUnmanaged(std.hash.Fnv1a_32),
command_hash_prev: std.ArrayListUnmanaged(std.hash.Fnv1a_32),

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

    this.command.deinit(this.display.allocator);
    this.command_hash.deinit(this.display.allocator);
    this.command_hash_prev.deinit(this.display.allocator);

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

    try wl_surface.sendRequest(.commit, .{});
}

pub fn present(this: *@This()) !void {
    try this.executeCanvasCommands();

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

const Command = struct {
    tag: Tag,
    renderRect: seizer.geometry.AABB(u32),
    renderData: Data,

    const Tag = enum {
        blit,
        line,
        rect_texture,
        rect_fill,
        rect_clear,

        // TODO: Implement these commands
        rect_stroke,
        rect_fill_stroke,
    };

    const Data = union {
        blit: struct {
            pos: [2]f64,
            src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied),
        },
        line: struct {
            point: [2][2]f32,
            color: [2]seizer.color.argbf32_premultiplied,
            radii: [2]f32,
        },
        rect_texture: struct {
            rect_dst: seizer.geometry.Rect(f64),
            src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied),
            color: seizer.color.argbf32_premultiplied,
        },
        rect_fill: struct {
            rect_dst: seizer.geometry.Rect(f64),
            color: seizer.color.argbf32_premultiplied,
        },
        rect_clear: struct {
            area: seizer.geometry.AABB(u32),
            color: seizer.color.argbf32_premultiplied,
        },

        // TODO: Implement these commands
        // rect_stroke,
        // rect_fill_stroke,
    };
};

pub fn canvas_size(this_opaque: ?*anyopaque) [2]f64 {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    return .{ @floatFromInt(this.current_configuration.window_size[0]), @floatFromInt(this.current_configuration.window_size[1]) };
}

pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argbf32_premultiplied) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const area = seizer.geometry.AABB(u32){ .min = .{ 0, 0 }, .max = this.current_configuration.window_size };
    this.command.appendAssumeCapacity(.{
        .tag = .rect_clear,
        .renderRect = area,
        .renderData = .{ .rect_clear = .{ .area = area, .color = color } },
    });
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied)) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.command.appendAssumeCapacity(.{
        .tag = .blit,
        .renderRect = .{
            .min = .{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) },
            .max = src_image.size,
        },
        .renderData = .{ .blit = .{ .pos = pos, .src_image = src_image } },
    });
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, pos: [2]f64, size: [2]f64, options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    this.command.appendAssumeCapacity(.{
        .tag = .rect_fill,
        .renderRect = .{
            .min = .{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) },
            .max = .{ @intFromFloat(pos[0] + size[0]), @intFromFloat(pos[1] + size[1]) },
        },
        .renderData = .{ .rect_fill = .{
            .rect_dst = .{ .pos = pos, .size = size },
            .color = options.color,
        } },
    });
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_posf: [2]f64, dst_sizef: [2]f64, src_image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: seizer.Canvas.RectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    this.command.appendAssumeCapacity(.{
        .tag = .rect_texture,
        .renderRect = .{
            .min = .{ @intFromFloat(dst_posf[0]), @intFromFloat(dst_posf[1]) },
            .max = .{ @intFromFloat(dst_posf[0] + dst_sizef[0]), @intFromFloat(dst_posf[1] + dst_sizef[1]) },
        },
        .renderData = .{ .rect_texture = .{
            .rect_dst = .{ .pos = dst_posf, .size = dst_sizef },
            .src_image = src_image,
            .color = options.color,
        } },
    });
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

    const rmax = @max(width, end_width);
    const px0: u32 = @intFromFloat(@max(0, @floor(@min(start_f[0], end_f[0]) - rmax)));
    const px1: u32 = @intFromFloat(@max(0, @ceil(@max(start_f[0], end_f[0]) + rmax)));
    const py0: u32 = @intFromFloat(@max(0, @floor(@min(start_f[1], end_f[1]) - rmax)));
    const py1: u32 = @intFromFloat(@max(0, @ceil(@max(start_f[1], end_f[1]) + rmax)));

    this.command.appendAssumeCapacity(.{
        .tag = .line,
        .renderRect = .{
            .min = .{ px0, py0 },
            .max = .{ px1, py1 },
        },
        .renderData = .{
            .line = .{
                .point = .{ start_f, end_f },
                .color = .{ options.color, end_color },
                .radii = .{ width, end_width },
            },
        },
    });
}

const binning_size = 64;

fn executeCanvasCommands(this: *ToplevelSurface) !void {
    const allocator = this.display.allocator;
    const window_size = this.current_configuration.window_size;
    const bin_count = .{
        @divFloor(window_size[0], binning_size),
        @divFloor(window_size[1], binning_size),
    };
    try this.command_hash.resize(allocator, bin_count[0] * bin_count[1]);

    for (this.command_hash.items) |*h| {
        h.* = std.hash.Fnv1a_32.init();
    }

    const command = this.command.slice();

    for (command.items(.tag), command.items(.renderRect), command.items(.renderData)) |tag, rect, data| {
        // Compute hash of the render command
        var hash = std.hash.Fnv1a_32.init();
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&data));
        const h = hash.final();

        const update_x_start: usize = rect.min[0] / binning_size;
        const update_y_start: usize = rect.min[1] / binning_size;
        const update_x_end: usize = @min(bin_count[0], (rect.max[0] / binning_size) + 1);
        const update_y_end: usize = @min(bin_count[1], (rect.max[1] / binning_size) + 1);

        for (update_y_start..update_y_end) |y| {
            for (update_x_start..update_x_end) |x| {
                this.command_hash.items[x + y * bin_count[0]].update(std.mem.asBytes(&h));
            }
        }
    }

    //const tiles_per_bin = seizer.image.Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).sizeInTiles(.{ binning_size, binning_size });
    //if (this.command_hash.items.len == this.command_hash_prev.items.len) {
    //    // See if the we can skip rendering
    //    for (this.command_hash.items, this.command_hash_prev.items, 0..) |*h, *hp, i| {
    //        if (h.final() != hp.final()) {
    //            const bin_x = i % bin_count[0];
    //            const bin_y = i / bin_count[1];
    //            const tile_start_x: u32 = @intCast(bin_x * tiles_per_bin[0]);
    //            const tile_start_y: u32 = @intCast(bin_y * tiles_per_bin[1]);
    //            const tile_offset = [2]u32{ tile_start_x, tile_start_y };
    //            const tile_slice = this.framebuffer.slice(tile_offset, tiles_per_bin);
    //            // Hash mismatch! This bin needs to be updated
    //            for (command.items(.tag), command.items(.renderData)) |tag, data| {
    //                this.executeCanvasCommand(tag, data, tile_slice);
    //            }
    //        }
    //    }
    //} else {
    // First frame or resized, draw everything
    for (command.items(.tag), command.items(.renderData)) |tag, data| {
        this.executeCanvasCommand(tag, data, this.framebuffer);
    }
    //}

    // Swap the memory used for current and previous hash lists
    const hash_list = this.command_hash_prev;
    this.command_hash_prev = this.command_hash;
    this.command_hash = hash_list;

    this.command.shrinkRetainingCapacity(0);
}

fn executeCanvasCommand(this: *ToplevelSurface, tag: Command.Tag, data: Command.Data, fb: seizer.image.Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied)) void {
    switch (tag) {
        .blit => {
            const pos = data.blit.pos;
            const src_image = data.blit.src_image;
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
            const dest = fb.slice(dest_offset, src_size);

            dest.compositeLinear(src);
        },
        .line => {
            const start = data.line.point[0];
            const end = data.line.point[1];
            const radii = data.line.radii;
            const color = data.line.color;

            fb.drawLine(start, end, radii, color);
        },
        .rect_texture => {
            const dst_posf = data.rect_texture.rect_dst.pos;
            const dst_sizef = data.rect_texture.rect_dst.size;
            const src_image = data.rect_texture.src_image;
            const color = data.rect_texture.color;

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
                    .tint = color,
                },
            );
        },
        .rect_fill => {
            const pos = data.rect_fill.rect_dst.pos;
            const size = data.rect_fill.rect_dst.size;
            const color = data.rect_fill.color;
            const a = [2]i32{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) };
            const b = [2]i32{ @intFromFloat(pos[0] + size[0]), @intFromFloat(pos[1] + size[1]) };

            fb.drawFillRect(a, b, color);
        },
        .rect_clear => {
            const d = data.rect_clear;
            fb.clear(d.area, d.color);
        },
        .rect_stroke => {
            // TODO
        },
        .rect_fill_stroke => {
            // TODO
        },
    }
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
