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

    try this.display.toplevel.put(this.display.allocator, this.wl_surface, this);
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

    _ = this.display.toplevel.remove(this.wl_surface);
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
            src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied),
        },
        line: struct {
            point: [2][2]f32,
            color: [2]seizer.color.argbf32_premultiplied,
            radii: [2]f32,
        },
        rect_texture: struct {
            dst_area: seizer.geometry.AABB(f64),
            src_area: seizer.geometry.AABB(f64),
            src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied),
            color: seizer.color.argbf32_premultiplied,
        },
        rect_fill: struct {
            area: seizer.geometry.AABB(f64),
            color: seizer.color.argbf32_premultiplied,
        },
        rect_clear: struct {
            area: seizer.geometry.AABB(u32),
            color: seizer.color.argbf32_premultiplied,
        },

        // TODO: Implement these commands
        // rect_stroke,
        // rect_fill_stroke,

        pub fn asBytes(this: *const @This(), tag: Tag) []const u8 {
            return switch (tag) {
                .blit => std.mem.asBytes(&this.blit),
                .line => std.mem.asBytes(&this.line),
                .rect_texture => std.mem.asBytes(&this.rect_texture),
                .rect_fill => std.mem.asBytes(&this.rect_fill),
                .rect_clear => std.mem.asBytes(&this.rect_clear),

                // TODO: Implement these commands
                .rect_stroke,
                .rect_fill_stroke,
                => unreachable,
            };
        }
    };
};

pub fn canvas_size(this_opaque: ?*anyopaque) [2]f64 {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    return .{ @floatFromInt(this.current_configuration.window_size[0]), @floatFromInt(this.current_configuration.window_size[1]) };
}

pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argbf32_premultiplied) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    const area = seizer.geometry.AABB(u32){ .min = .{ 0, 0 }, .max = this.current_configuration.window_size };

    const index = this.command.addOneAssumeCapacity();

    const slice = this.command.slice();
    slice.items(.tag)[index] = .rect_clear;
    slice.items(.renderRect)[index] = area;

    slice.items(.renderData)[index] = .{ .rect_clear = .{ .area = area, .color = color } };
}

pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied)) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    var rect = seizer.geometry.Rect(f64){ .pos = pos, .size = seizer.geometry.vec.into(f64, src_image.size) };
    rect = rect.translate(pos);
    this.command.appendAssumeCapacity(.{
        .tag = .blit,
        .renderRect = rect.toAABB().into(u32),
        .renderData = .{ .blit = .{ .pos = pos, .src_image = src_image } },
    });
}

pub fn canvas_fillRect(this_opaque: ?*anyopaque, area: seizer.geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: seizer.Canvas.FillRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));
    _ = options;

    std.debug.assert(area.min[0] < area.max[0]);
    std.debug.assert(area.min[1] < area.max[1]);

    const canvas_clip = seizer.geometry.AABB(f64){ .min = .{ 0, 0 }, .max = .{
        @floatFromInt(this.current_configuration.window_size[0] - 1),
        @floatFromInt(this.current_configuration.window_size[1] - 1),
    } };

    this.command.appendAssumeCapacity(.{
        .tag = .rect_fill,
        .renderRect = area.clamp(canvas_clip).into(u32),
        .renderData = .{ .rect_fill = .{
            .area = area.clamp(canvas_clip),
            .color = color,
        } },
    });
}

pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_area: seizer.geometry.AABB(f64), src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied), options: seizer.Canvas.TextureRectOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const canvas_clip = seizer.geometry.AABB(f64){ .min = .{ 0, 0 }, .max = .{
        @floatFromInt(this.current_configuration.window_size[0] - 1),
        @floatFromInt(this.current_configuration.window_size[1] - 1),
    } };

    var render_rect = dst_area.clamp(canvas_clip).into(u32);
    render_rect.min[0] -|= 1;
    render_rect.min[1] -|= 1;
    render_rect.max[0] +|= 1;
    render_rect.max[1] +|= 1;

    this.command.appendAssumeCapacity(.{
        .tag = .rect_texture,
        .renderRect = render_rect,
        .renderData = .{ .rect_texture = .{
            .dst_area = dst_area,
            .src_area = options.src_area orelse .{
                .min = .{ 0, 0 },
                .max = .{ @floatFromInt(src_image.size[0] - 1), @floatFromInt(src_image.size[1] - 1) },
            },
            .src_image = src_image,
            .color = options.color,
        } },
    });
}

pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
    const this: *@This() = @ptrCast(@alignCast(this_opaque));

    const start_f = seizer.geometry.vec.into(f32, start);
    const end_f = seizer.geometry.vec.into(f32, end);
    const end_color = options.end_color orelse options.color;
    const width: f32 = @floatCast(options.width);
    const end_width: f32 = @floatCast(options.end_width orelse width);

    const canvas_clip = seizer.geometry.AABB(u32){ .min = .{ 0, 0 }, .max = .{
        this.current_configuration.window_size[0] - 1,
        this.current_configuration.window_size[1] - 1,
    } };
    const rmax = @max(width, end_width);
    const area_line = seizer.geometry.AABB(f32).init(.{ .{
        @floor(@min(start_f[0], end_f[0]) - rmax),
        @floor(@min(start_f[1], end_f[1]) - rmax),
    }, .{
        @ceil(@max(start_f[0], end_f[0]) + rmax),
        @ceil(@max(start_f[1], end_f[1]) + rmax),
    } });
    const clipped = area_line.clamp(canvas_clip.into(f32)).into(u32);

    this.command.appendAssumeCapacity(.{
        .tag = .line,
        .renderRect = clipped,
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
const bin_aabb = seizer.geometry.AABB(u32).init(.{ .{ 0, 0 }, .{ binning_size - 1, binning_size - 1 } });

fn executeCanvasCommands(this: *ToplevelSurface) !void {
    const allocator = this.display.allocator;
    const window_size = this.current_configuration.window_size;
    const bin_count = .{
        @divFloor(window_size[0], binning_size) + 1,
        @divFloor(window_size[1], binning_size) + 1,
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
        hash.update(data.asBytes(tag));
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

    const canvas_clip = seizer.geometry.AABB(u32){
        .min = .{ 0, 0 },
        .max = .{ this.current_configuration.window_size[0] - 1, this.current_configuration.window_size[1] - 1 },
    };
    if (this.command_hash.items.len == this.command_hash_prev.items.len) {
        // See if the we can skip rendering
        for (this.command_hash.items, this.command_hash_prev.items, 0..) |*h, *hp, i| {
            if (h.final() != hp.final()) {
                const bin_x = i % bin_count[0];
                const bin_y = i / bin_count[0];
                const px_pos = [2]u32{
                    @intCast(bin_x * binning_size),
                    @intCast(bin_y * binning_size),
                };

                const clip = bin_aabb.translate(px_pos).clamp(canvas_clip);
                // Hash mismatch! This bin needs to be updated
                for (command.items(.tag), command.items(.renderData)) |tag, data| {
                    this.executeCanvasCommand(tag, data, clip);
                }
            }
        }
    } else {
        for (command.items(.tag), command.items(.renderData)) |tag, data| {
            this.executeCanvasCommand(tag, data, canvas_clip);
        }
    }

    // Swap the memory used for current and previous hash lists
    std.mem.swap(std.ArrayListUnmanaged(std.hash.Fnv1a_32), &this.command_hash_prev, &this.command_hash);

    this.command.shrinkRetainingCapacity(0);
}

fn executeCanvasCommand(this: *ToplevelSurface, tag: Command.Tag, data: Command.Data, clip: seizer.geometry.AABB(u32)) void {
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
            const dest_end = [2]u32{
                dest_offset[0] + src_size[0] - 1,
                dest_offset[1] + src_size[1] - 1,
            };

            const src = src_image.slice(src_offset, src_size);

            this.framebuffer.compositeLinear(.{ .min = dest_offset, .max = dest_end }, src);
        },
        .line => {
            const start = data.line.point[0];
            const end = data.line.point[1];
            const radii = data.line.radii;
            const color = data.line.color;

            this.framebuffer.drawLine(clip, start, end, radii, color);
        },
        .rect_texture => {
            const dst_area = data.rect_texture.dst_area;
            const src_area = data.rect_texture.src_area;
            const src_image = data.rect_texture.src_image;
            const color = data.rect_texture.color;

            std.debug.assert(dst_area.sizePlusEpsilon()[0] >= 0 and dst_area.sizePlusEpsilon()[1] >= 0);

            const dst_area_clamped = dst_area.clamp(clip.into(f64));

            const Linear = seizer.image.Linear(seizer.color.argbf32_premultiplied);
            const Sampler = struct {
                texture: seizer.image.Slice(seizer.color.argbf32_premultiplied),
                dst_offset: [2]f64,
                // dst_size: [2]f64,
                src_area: seizer.geometry.AABB(f64),
                tint: seizer.color.argbf32_premultiplied,
                // bin_clip: seizer.geometry.AABB(u32),
                // bin_count: [2]f32,

                pub fn sample(sampler: *const @This(), start: [2]f64, end: [2]f64, sample_rect: Linear) void {
                    // _ = sampler;
                    const stridef = [2]f64{
                        (end[0] - start[0]) / @as(f64, @floatFromInt(sample_rect.size[0])),
                        (end[1] - start[1]) / @as(f64, @floatFromInt(sample_rect.size[1])),
                    };
                    for (0..sample_rect.size[1]) |sample_y| {
                        for (0..sample_rect.size[0]) |sample_x| {
                            const src_posf = .{
                                sampler.src_area.min[0] + (start[0] + stridef[0] * @as(f64, @floatFromInt(sample_x))) * sampler.src_area.size()[0],
                                sampler.src_area.min[1] + (start[1] + stridef[1] * @as(f64, @floatFromInt(sample_y))) * sampler.src_area.size()[1],
                            };
                            const src_pixel = sampler.texture.getPixel(.{
                                @min(@as(u32, @intFromFloat(@max(src_posf[0], 0))), sampler.texture.size[0] - 1),
                                @min(@as(u32, @intFromFloat(@max(src_posf[1], 0))), sampler.texture.size[1] - 1),
                            });
                            sample_rect.setPixel(
                                .{ @intCast(sample_x), @intCast(sample_y) },
                                src_pixel.tint(sampler.tint),
                            );

                            // const posf = [2]f32{
                            //     @floatFromInt(pos[0]),
                            //     @floatFromInt(pos[1]),
                            // };
                            // const sample_posf = [2]f32{
                            //     @floatFromInt(sample_x),
                            //     @floatFromInt(sample_y),
                            // };
                            // const sample_sizef = [2]f32{
                            //     @floatFromInt(sample_rect.size[0]),
                            //     @floatFromInt(sample_rect.size[1]),
                            // };
                            // _ = pos;
                            // sample_rect.setPixel(
                            //     .{ @intCast(sample_x), @intCast(sample_y) },
                            //     seizer.color.argbf32_premultiplied.init(
                            //         0,
                            //         @floatCast(src_posf[0]),
                            //         @floatCast(src_posf[1]),
                            //         1.0,
                            //     ),
                            // );
                        }
                    }
                }
            };

            this.framebuffer.compositeSampler(
                dst_area_clamped.into(u32),
                *const Sampler,
                Sampler.sample,
                &.{
                    .texture = src_image,
                    .dst_offset = .{
                        // 0, 0,
                        dst_area_clamped.min[0] - dst_area.min[0],
                        dst_area_clamped.min[1] - dst_area.min[1],
                    },
                    // .dst_size = dst_area.size(),
                    .src_area = src_area,
                    .tint = color,
                    // .bin_clip = clip,
                    // .bin_count = .{ @floatFromInt(bin_count[0]), @floatFromInt(bin_count[1]) },
                },
            );
        },
        .rect_fill => {
            const area = data.rect_fill.area;
            const color = data.rect_fill.color;

            this.framebuffer.drawFillRect(area.into(u32), color);
        },
        .rect_clear => {
            const d = data.rect_clear;
            this.framebuffer.set(d.area.clamp(clip), d.color);
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
                this.command_hash_prev.shrinkRetainingCapacity(0);
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
