pub const Buffer = @import("./Display/Buffer.zig");
pub const ToplevelSurface = @import("./Display/ToplevelSurface.zig");

allocator: std.mem.Allocator,
connection: shimizu.Connection,
connection_recv_completion: xev.Completion,

registry: shimizu.Object.WithInterface(wayland.wl_registry),
registry_listener: shimizu.Listener,
globals: Globals,

xdg_wm_base_listener: shimizu.Listener,

seat: ?Seat,

surfaces: std.AutoHashMapUnmanaged(shimizu.Object.WithInterface(wayland.wl_surface), void),

pub fn init(this: *@This(), allocator: std.mem.Allocator, loop: *xev.Loop) !void {
    this.* = .{
        .allocator = allocator,
        .connection = undefined,
        .connection_recv_completion = undefined,

        .registry = @enumFromInt(0),
        .registry_listener = undefined,

        .globals = .{},
        .xdg_wm_base_listener = undefined,
        .seat = null,

        .surfaces = .{},
    };

    // open connection to wayland server
    this.connection = try shimizu.openConnection(allocator, .{});
    errdefer this.connection.close();

    this.connection.allocator = allocator;
    const display = this.connection.getDisplayProxy();
    const registry = try display.sendRequest(.get_registry, .{});
    this.registry = registry.id;
    registry.setEventListener(&this.registry_listener, onRegistryEvent, this);

    {
        var sync_is_done: bool = false;
        var wl_callback_listener: shimizu.Listener = undefined;
        const wl_callback = display.sendRequest(.sync, .{}) catch |err| switch (err) {
            else => |e| std.debug.panic("Unexpected error: {}", .{e}),
        };
        wl_callback.setEventListener(&wl_callback_listener, onWlCallbackSetTrue, &sync_is_done);
        while (!sync_is_done) {
            this.connection.recv() catch |err| switch (err) {
                else => |e| std.debug.panic("Unexpected error: {}", .{e}),
            };
        }
    }
    if (this.globals.wl_compositor == null) {
        log.warn("wayland: wl_compositor global missing", .{});
        return error.ExtensionMissing;
    }
    if (this.globals.xdg_wm_base == null) {
        log.warn("wayland: xdg_wm_base global missing", .{});
        return error.ExtensionMissing;
    }
    if (this.globals.wl_shm == null) {
        log.warn("wayland: wl_shm global missing", .{});
        return error.ExtensionMissing;
    }

    const xdg_wm_base = shimizu.Proxy(xdg_shell.xdg_wm_base){ .connection = &this.connection, .id = this.globals.xdg_wm_base.? };
    xdg_wm_base.setEventListener(&this.xdg_wm_base_listener, onXdgWmBaseEvent, null);

    this.connection_recv_completion = .{
        .op = .{ .recvmsg = .{
            .fd = this.connection.socket,
            .msghdr = this.connection.getRecvMsgHdr(),
        } },
        .callback = onConnectionRecvMessage,
    };
    loop.add(&this.connection_recv_completion);
}

pub fn deinit(this: *@This()) void {
    this.surfaces.deinit(this.allocator);
    this.connection.close();
}

pub fn initToplevelSurface(this: *@This(), toplevel_surface: *ToplevelSurface, options: ToplevelSurface.InitOptions) !void {
    try this.surfaces.ensureUnusedCapacity(this.allocator, 1);

    const wl_surface = this.connection.sendRequest(wayland.wl_compositor, this.globals.wl_compositor.?, .create_surface, .{}) catch return error.ConnectionLost;
    const xdg_surface = this.connection.sendRequest(xdg_shell.xdg_wm_base, this.globals.xdg_wm_base.?, .get_xdg_surface, .{ .surface = wl_surface.id }) catch return error.ConnectionLost;
    const xdg_toplevel = xdg_surface.sendRequest(.get_toplevel, .{}) catch return error.ConnectionLost;

    // const xdg_toplevel_decoration: ?shimizu.Proxy(xdg_decoration.zxdg_toplevel_decoration_v1) = if (this.globals.xdg_decoration_manager) |deco_man|
    //     this.connection.sendRequest(xdg_decoration.zxdg_decoration_manager_v1, deco_man, .get_toplevel_decoration, .{ .toplevel = xdg_toplevel.id }) catch return error.ConnectionLost
    // else
    //     null;

    // const wp_viewport: ?shimizu.Proxy(viewporter.wp_viewport) = if (this.globals.wp_viewporter) |wp_viewporter|
    //     this.connection.sendRequest(viewporter.wp_viewporter, wp_viewporter, .get_viewport, .{ .surface = wl_surface.id }) catch return error.ConnectionLost
    // else
    //     null;

    // const wp_fractional_scale: ?shimizu.Proxy(fractional_scale_v1.wp_fractional_scale_v1) = if (this.globals.wp_fractional_scale_manager_v1) |scale_man|
    //     this.connection.sendRequest(fractional_scale_v1.wp_fractional_scale_manager_v1, scale_man, .get_fractional_scale, .{ .surface = wl_surface.id }) catch return error.ConnectionLost
    // else
    //     null;

    wl_surface.sendRequest(.commit, .{}) catch return error.ConnectionLost;

    toplevel_surface.* = .{
        .display = this,

        .wl_surface = wl_surface.id,
        .xdg_surface = xdg_surface.id,
        .xdg_toplevel = xdg_toplevel.id,
        // .xdg_toplevel_decoration = xdg_toplevel_decoration,
        // .wp_viewport = wp_viewport,
        // .wp_fractional_scale = wp_fractional_scale,

        .xdg_surface_listener = undefined,
        .xdg_toplevel_listener = undefined,

        .frame_callback = null,
        .frame_callback_listener = undefined,

        // .on_event = options.on_event,
        // .on_render = options.on_render,
        // .on_destroy = options.on_destroy,

        .current_configuration = .{
            .window_size = .{ 0, 0 },
            .decoration_mode = .client_side,
        },
        .new_configuration = .{
            .window_size = options.size,
            .decoration_mode = .client_side,
        },

        .swapchain = .{},
        .on_render_listener = null,
    };

    xdg_surface.setEventListener(&toplevel_surface.xdg_surface_listener, ToplevelSurface.onXdgSurfaceEvent, null);
    xdg_toplevel.setEventListener(&toplevel_surface.xdg_toplevel_listener, ToplevelSurface.onXdgToplevelEvent, null);

    // if (toplevel_surface.xdg_toplevel_decoration) |decoration| {
    //     decoration.setEventListener(&toplevel_surface.xdg_toplevel_decoration_listener, ToplevelSurface.onXdgToplevelDecorationEvent, null);
    // }
    // if (toplevel_surface.wp_fractional_scale) |frac_scale| {
    //     frac_scale.setEventListener(&toplevel_surface.wp_fractional_scale_listener, ToplevelSurface.onWpFractionalScale, null);
    // }

    // xdg_toplevel.sendRequest(.set_title, .{ .title = options.title }) catch return error.ConnectionLost;
    // if (options.app_name) |app_name| {
    //     xdg_toplevel.sendRequest(.set_app_id, .{ .app_id = app_name }) catch return error.ConnectionLost;
    // }
    this.surfaces.putAssumeCapacity(wl_surface.id, {});
}

const Globals = struct {
    wl_compositor: ?shimizu.Object.WithInterface(wayland.wl_compositor) = null,
    xdg_wm_base: ?shimizu.Object.WithInterface(xdg_shell.xdg_wm_base) = null,
    wl_shm: ?shimizu.Object.WithInterface(wayland.wl_shm) = null,
    xdg_decoration_manager: ?shimizu.Object.WithInterface(xdg_decoration.zxdg_decoration_manager_v1) = null,

    wp_viewporter: ?shimizu.Object.WithInterface(viewporter.wp_viewporter) = null,
    wp_fractional_scale_manager_v1: ?shimizu.Object.WithInterface(fractional_scale_v1.wp_fractional_scale_manager_v1) = null,
};

fn onXdgWmBaseEvent(listener: *shimizu.Listener, xdg_wm_base: shimizu.Proxy(xdg_shell.xdg_wm_base), event: xdg_shell.xdg_wm_base.Event) !void {
    _ = listener;
    switch (event) {
        .ping => |conf| {
            try xdg_wm_base.sendRequest(.pong, .{ .serial = conf.serial });
        },
    }
}

fn onRegistryEvent(registry_listener: *shimizu.Listener, registry: shimizu.Proxy(wayland.wl_registry), event: wayland.wl_registry.Event) !void {
    const this: *@This() = @fieldParentPtr("registry_listener", registry_listener);

    switch (event) {
        .global => |global| {
            if (std.mem.eql(u8, global.interface, wayland.wl_seat.NAME) and global.version >= wayland.wl_seat.VERSION) {
                log.debug("{s}:{} unimplemented", .{ @src().file, @src().line });
                // this.seats.ensureUnusedCapacity(this.allocator, 1) catch return;

                // const seat = this.allocator.create(Seat) catch return;
                // const wl_seat = try registry.connection.createObject(wayland.wl_seat);
                // try registry.sendRequest(.bind, .{ .name = global.name, .id = wl_seat.id.asGenericNewId() });

                // seat.* = .{
                //     .wayland_manager = this,
                //     .wl_seat = wl_seat,
                //     .focused_window = null,
                // };
                // wl_seat.setEventListener(&seat.listener, Seat.onSeatCallback, seat);

                // this.seats.appendAssumeCapacity(seat);
            } else inline for (@typeInfo(Globals).Struct.fields) |field| {
                if (@typeInfo(field.type) != .Optional) continue;
                const INTERFACE = @typeInfo(field.type).Optional.child._SPECIFIED_INTERFACE;

                if (std.mem.eql(u8, global.interface, INTERFACE.NAME) and global.version >= INTERFACE.VERSION) {
                    const object = try registry.connection.createObject(INTERFACE);
                    try registry.sendRequest(.bind, .{ .name = global.name, .id = object.id.asGenericNewId() });
                    @field(this.globals, field.name) = object.id;
                    return;
                }
            }
        },
        .global_remove => {},
    }
}

fn onConnectionRecvMessage(userdata: ?*anyopaque, loop: *xev.Loop, completion: *xev.Completion, result: xev.Result) xev.CallbackAction {
    _ = userdata;
    _ = loop;
    const this: *@This() = @fieldParentPtr("connection_recv_completion", completion);
    if (result.recvmsg) |num_bytes_read| {
        this.connection.processRecvMsgReturn(num_bytes_read) catch |err| {
            log.warn("error processing messages from wayland: {}", .{err});
        };
        this.connection_recv_completion.op.recvmsg.msghdr = this.connection.getRecvMsgHdr();
        return if (this.surfaces.count() > 0) .rearm else .disarm;
    } else |err| {
        log.err("error receiving messages from wayland compositor: {}", .{err});
        return .disarm;
    }
}

const Seat = struct {
    wl_seat: shimizu.Object.WithInterface(wayland.wl_seat),
    wl_pointer: ?shimizu.Object.WithInterface(wayland.wl_pointer) = null,
    wl_keyboard: ?shimizu.Object.WithInterface(wayland.wl_keyboard) = null,

    listener: shimizu.Listener = undefined,

    pointer_pos: [2]f32 = .{ 0, 0 },
    scroll_vector: [2]f32 = .{ 0, 0 },
    cursor_wl_surface: ?shimizu.Object.WithInterface(wayland.wl_surface) = null,
    wp_viewport: ?shimizu.Object.WithInterface(viewporter.wp_viewport) = null,

    pointer_listener: shimizu.Listener = undefined,
    pointer_serial: u32 = 0,
    cursor_fractional_scale: ?shimizu.Object.WithInterface(fractional_scale_v1.wp_fractional_scale_v1) = null,
    cursor_fractional_scale_listener: shimizu.Listener = undefined,
    pointer_scale: u32 = 120,

    keyboard_listener: shimizu.Listener = undefined,
    keymap: ?xkb.Keymap = null,
    keymap_state: xkb.Keymap.State = undefined,
    keyboard_repeat_rate: u32 = 0,
    keyboard_repeat_delay: u32 = 0,

    fn destroy(this: *@This()) void {
        if (this.keymap) |*keymap| keymap.deinit();
        this.wayland_manager.allocator.destroy(this);
    }
};

fn onSeatCallback(listener: *shimizu.Listener, wl_seat: shimizu.Proxy(wayland.wl_seat), event: wayland.wl_seat.Event) !void {
    const this: *Seat = @fieldParentPtr("listener", listener);
    _ = wl_seat;
    switch (event) {
        .capabilities => |capabilities| {
            if (capabilities.capabilities.keyboard) {
                if (this.wl_keyboard == null) {
                    this.wl_keyboard = try this.wl_seat.sendRequest(.get_keyboard, .{});
                    this.wl_keyboard.?.setEventListener(&this.keyboard_listener, Seat.onKeyboardCallback, this);
                }
            } else {
                if (this.wl_keyboard) |keyboard| {
                    try keyboard.sendRequest(.release, .{});
                    this.wl_keyboard = null;
                }
            }

            if (capabilities.capabilities.pointer) {
                if (this.wl_pointer == null) {
                    this.wl_pointer = try this.wl_seat.sendRequest(.get_pointer, .{});
                    this.wl_pointer.?.setEventListener(&this.pointer_listener, Seat.onPointerCallback, null);
                }
                if (this.cursor_wl_surface == null) {
                    this.cursor_wl_surface = try this.wayland_manager.connection.sendRequest(wayland.wl_compositor, this.wayland_manager.globals.wl_compositor.?, .create_surface, .{});

                    if (this.wayland_manager.globals.wp_viewporter) |wp_viewporter| {
                        this.wp_viewport = try this.wayland_manager.connection.sendRequest(viewporter.wp_viewporter, wp_viewporter, .get_viewport, .{ .surface = this.cursor_wl_surface.?.id });
                    }

                    if (this.wayland_manager.globals.wp_fractional_scale_manager_v1) |scale_man| {
                        this.cursor_fractional_scale = try this.wayland_manager.connection.sendRequest(fractional_scale_v1.wp_fractional_scale_manager_v1, scale_man, .get_fractional_scale, .{ .surface = this.cursor_wl_surface.?.id });
                        // this.cursor_fractional_scale.?.userdata = this;
                        // this.cursor_fractional_scale.?.on_event = onCursorFractionalScaleEvent;
                    }
                }
            } else {
                if (this.wl_pointer) |pointer| {
                    pointer.sendRequest(.release, .{}) catch {};
                    this.wl_pointer = null;
                }
                if (this.wp_viewport) |wp_viewport| {
                    wp_viewport.sendRequest(.destroy, .{}) catch {};
                    this.wp_viewport = null;
                }
                if (this.cursor_fractional_scale) |frac_scale| {
                    frac_scale.sendRequest(.destroy, .{}) catch {};
                    this.cursor_fractional_scale = null;
                }
                if (this.cursor_wl_surface) |surface| {
                    surface.sendRequest(.destroy, .{}) catch {};
                    this.cursor_wl_surface = null;
                }
            }
        },
        .name => {},
    }
}

fn onKeyboardCallback(listener: *shimizu.Listener, wl_keyboard: shimizu.Proxy(wayland.wl_keyboard), event: wayland.wl_keyboard.Event) !void {
    const this: *@This() = @fieldParentPtr("keyboard_listener", listener);
    _ = wl_keyboard;
    switch (event) {
        .keymap => |keymap_info| {
            defer std.posix.close(@intCast(@intFromEnum(keymap_info.fd)));
            if (keymap_info.format != .xkb_v1) return;

            const new_keymap_source = std.posix.mmap(null, keymap_info.size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, @intFromEnum(keymap_info.fd), 0) catch |err| {
                log.warn("Failed to mmap keymap from wayland compositor: {}", .{err});
                return;
            };
            defer std.posix.munmap(new_keymap_source);

            if (this.keymap) |*old_keymap| {
                old_keymap.deinit();
                this.keymap = null;
            }
            this.keymap = xkb.Keymap.fromString(this.wayland_manager.allocator, new_keymap_source) catch |err| {
                log.warn("failed to parse keymap: {}", .{err});
                if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
                return;
            };
        },
        .repeat_info => |repeat_info| {
            this.keyboard_repeat_rate = @intCast(repeat_info.rate);
            this.keyboard_repeat_delay = @intCast(repeat_info.delay);
        },
        .modifiers => |m| {
            this.keymap_state = xkb.Keymap.State{
                .base_modifiers = @bitCast(m.mods_depressed),
                .latched_modifiers = @bitCast(m.mods_latched),
                .locked_modifiers = @bitCast(m.mods_locked),
                .group = @intCast(m.group),
            };
        },
        .key => |k| if (this.keymap) |keymap| {
            const scancode = evdevToSeizer(k.key);
            const symbol = keymap.getSymbol(@enumFromInt(k.key + 8), this.keymap_state) orelse return;
            const key = xkbSymbolToSeizerKey(symbol);
            const xkb_modifiers = this.keymap_state.getModifiers();

            if (this.focused_window) |window| {
                if (window.on_event) |on_event| {
                    on_event(@ptrCast(window), .{ .input = seizer.input.Event{ .key = .{
                        .key = key,
                        .scancode = scancode,
                        .action = switch (k.state) {
                            .pressed => .press,
                            .released => .release,
                        },
                        .mods = .{
                            .shift = xkb_modifiers.shift,
                            .caps_lock = xkb_modifiers.lock,
                            .control = xkb_modifiers.control,
                        },
                    } } }) catch |err| {
                        std.debug.print("{s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    };
                }
            }

            if (this.focused_window) |window| {
                if (window.on_event) |on_event| {
                    if (symbol.character) |character| {
                        if (k.state == .pressed) {
                            var text_utf8 = std.BoundedArray(u8, 16){};
                            text_utf8.resize(std.unicode.utf8CodepointSequenceLength(character) catch unreachable) catch unreachable;
                            _ = std.unicode.utf8Encode(character, text_utf8.slice()) catch unreachable;

                            on_event(@ptrCast(window), .{ .input = seizer.input.Event{ .text = .{
                                .text = text_utf8,
                            } } }) catch |err| {
                                std.debug.print("{s}\n", .{@errorName(err)});
                                if (@errorReturnTrace()) |trace| {
                                    std.debug.dumpStackTrace(trace.*);
                                }
                            };
                        }
                    }
                }
            }
        },
        else => {},
    }
}

fn onPointerCallback(listener: *shimizu.Listener, pointer: shimizu.Proxy(wayland.wl_pointer), event: wayland.wl_pointer.Event) !void {
    const this: *@This() = @fieldParentPtr("pointer_listener", listener);
    _ = pointer;
    switch (event) {
        .enter => |enter| {
            this.focused_window = this.wayland_manager.windows.get(enter.surface);
            this.pointer_serial = enter.serial;
            this.updateCursorImage() catch {};
        },
        .leave => |leave| {
            const left_window = this.wayland_manager.windows.get(leave.surface);
            if (std.meta.eql(left_window, this.focused_window)) {
                this.focused_window = null;
            }
        },
        .motion => |motion| {
            if (this.focused_window) |window| {
                if (window.on_event) |on_event| {
                    this.pointer_pos = [2]f32{ motion.surface_x.toFloat(f32), motion.surface_y.toFloat(f32) };
                    on_event(@ptrCast(window), seizer.Display.Window.Event{ .input = .{ .hover = .{
                        .pos = this.pointer_pos,
                        .modifiers = .{ .left = false, .right = false, .middle = false },
                    } } }) catch |err| {
                        std.debug.print("{s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    };
                }
            }
        },
        .button => |button| {
            if (this.focused_window) |window| {
                if (window.on_event) |on_event| {
                    on_event(@ptrCast(window), seizer.Display.Window.Event{ .input = .{ .click = .{
                        .pos = this.pointer_pos,
                        .button = @enumFromInt(button.button),
                        .pressed = button.state == .pressed,
                    } } }) catch |err| {
                        std.debug.print("{s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    };
                }
            }
        },
        .axis => |axis| {
            switch (axis.axis) {
                .horizontal_scroll => this.scroll_vector[0] += axis.value.toFloat(f32),
                .vertical_scroll => this.scroll_vector[1] += axis.value.toFloat(f32),
            }
            // },
            // .frame => {
            if (this.focused_window) |window| {
                if (window.on_event) |on_event| {
                    on_event(@ptrCast(window), seizer.Display.Window.Event{ .input = .{ .scroll = .{
                        .offset = this.scroll_vector,
                    } } }) catch |err| {
                        std.debug.print("{s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    };
                }
            }
            this.scroll_vector = .{ 0, 0 };
        },
        else => {},
    }
}

fn onCursorFractionalScaleEvent(wp_fractional_scale: *fractional_scale_v1.wp_fractional_scale_v1, userdata: ?*anyopaque, event: fractional_scale_v1.wp_fractional_scale_v1.Event) void {
    const this: *@This() = @ptrCast(@alignCast(userdata.?));
    _ = wp_fractional_scale;
    switch (event) {
        .preferred_scale => |preferred| {
            this.pointer_scale = preferred.scale;
            this.updateCursorImage() catch {};
        },
    }
}

fn updateCursorImage(this: *@This()) !void {
    if (!this.wayland_manager._isCreateBufferFromOpaqueFdSupported()) return;

    const width_hint: seizer.tvg.rendering.SizeHint = if (this.wp_viewport != null) .{ .width = (32 * this.pointer_scale) / 120 } else .inherit;
    // set cursor image
    var default_cursor_image = try seizer.tvg.rendering.renderBuffer(
        seizer.platform.allocator(),
        seizer.platform.allocator(),
        width_hint,
        .x16,
        @embedFile("./cursor_none.tvg"),
    );
    defer default_cursor_image.deinit(seizer.platform.allocator());

    const pixel_bytes = std.mem.sliceAsBytes(default_cursor_image.pixels);

    const default_cursor_image_fd = try std.posix.memfd_create("default_cursor", 0);
    defer std.posix.close(default_cursor_image_fd);

    try std.posix.ftruncate(default_cursor_image_fd, pixel_bytes.len);

    const fd_bytes = std.posix.mmap(null, @intCast(pixel_bytes.len), std.posix.PROT.WRITE | std.posix.PROT.READ, .{ .TYPE = .SHARED }, default_cursor_image_fd, 0) catch @panic("could not mmap cursor fd");
    defer std.posix.munmap(fd_bytes);

    @memcpy(fd_bytes, pixel_bytes);

    const wl_shm_pool = this.wayland_manager.connection.sendRequest(
        wayland.wl_shm,
        this.wayland_manager.globals.wl_shm.?,
        .create_pool,
        .{
            .fd = @enumFromInt(default_cursor_image_fd),
            .size = @intCast(pixel_bytes.len),
        },
    ) catch return error.ConnectionLost;
    defer wl_shm_pool.sendRequest(.destroy, .{}) catch {};

    const cursor_buffer = try wl_shm_pool.sendRequest(.create_buffer, .{
        .offset = 0,
        .width = @intCast(default_cursor_image.width),
        .height = @intCast(default_cursor_image.height),
        .stride = @intCast(default_cursor_image.width * @sizeOf(seizer.tvg.rendering.Color8)),
        .format = .argb8888,
    });

    const surface = this.cursor_wl_surface orelse return;

    try surface.sendRequest(.attach, .{ .buffer = cursor_buffer.id, .x = 0, .y = 0 });
    try surface.sendRequest(.damage_buffer, .{ .x = 0, .y = 0, .width = std.math.maxInt(i32), .height = std.math.maxInt(i32) });
    if (this.wp_viewport) |viewport| {
        try viewport.sendRequest(.set_source, .{
            .x = shimizu.Fixed.fromInt(0, 0),
            .y = shimizu.Fixed.fromInt(0, 0),
            .width = shimizu.Fixed.fromInt(@intCast(default_cursor_image.width), 0),
            .height = shimizu.Fixed.fromInt(@intCast(default_cursor_image.height), 0),
        });
        try viewport.sendRequest(.set_destination, .{
            .width = 32,
            .height = 32,
        });
    }
    try surface.sendRequest(.commit, .{});
    try this.wl_pointer.?.sendRequest(.set_cursor, .{
        .serial = this.pointer_serial,
        .surface = this.cursor_wl_surface.?.id,
        .hotspot_x = 9,
        .hotspot_y = 5,
    });
}

fn onWlCallbackSetTrue(listener: *shimizu.Listener, wl_callback: shimizu.Proxy(wayland.wl_callback), event: wayland.wl_callback.Event) !void {
    _ = wl_callback;
    _ = event;

    const bool_ptr: *bool = @ptrCast(listener.userdata);
    bool_ptr.* = true;
}

const log = std.log.scoped(.seizer);

const evdevToSeizer = @import("./Display/evdev_to_seizer.zig").evdevToSeizer;
const xkbSymbolToSeizerKey = @import("./Display/xkb_to_seizer.zig").xkbSymbolToSeizerKey;

const wayland = shimizu.core;

// stable protocols
const viewporter = @import("wayland-protocols").viewporter;
const xdg_shell = @import("wayland-protocols").xdg_shell;

// unstable protocols
const xdg_decoration = @import("wayland-unstable").xdg_decoration_unstable_v1;
const fractional_scale_v1 = @import("wayland-unstable").fractional_scale_v1;

const builtin = @import("builtin");
const seizer = @import("./seizer.zig");
const shimizu = @import("shimizu");
const std = @import("std");
const xev = @import("xev");
const xkb = @import("xkb");
