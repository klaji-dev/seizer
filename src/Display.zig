pub const Buffer = @import("./Display/Buffer.zig");
pub const ToplevelSurface = @import("./Display/ToplevelSurface.zig");
pub const Surface = @import("./Display/Surface.zig");
pub const Swapchain = @import("Display/Swapchain.zig");

allocator: std.mem.Allocator,
connection: shimizu.Connection,
connection_recv_completion: xev.Completion,

registry: shimizu.Object.WithInterface(wayland.wl_registry),
registry_listener: shimizu.Listener,
globals: Globals,

xdg_wm_base_listener: shimizu.Listener,

seat: ?Seat,

toplevel: std.AutoHashMapUnmanaged(shimizu.Object.WithInterface(wayland.wl_surface), *ToplevelSurface),

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

        .toplevel = .{},
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
    if (this.seat) |*seat| {
        seat.deinit();
    }
    this.toplevel.deinit(this.allocator);
    this.connection.close();
}

pub fn initToplevelSurface(this: *@This(), toplevel_surface: *ToplevelSurface, options: ToplevelSurface.InitOptions) !void {
    try this.toplevel.ensureUnusedCapacity(this.allocator, 1);

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

        .current_configuration = .{
            .window_size = .{ 0, 0 },
            .decoration_mode = .client_side,
        },
        .new_configuration = .{
            .window_size = options.size,
            .decoration_mode = .client_side,
        },

        .framebuffer = .{
            .tiles = undefined,
            .size_px = .{ 0, 0 },
        },
        .swapchain = .{},

        .close_listener = null,
        .on_render_listener = null,
        .on_input_listener = null,

        .command = .{},
        .command_hash = .{},
        .command_hash_prev = .{},
    };

    try toplevel_surface.command.ensureTotalCapacity(this.allocator, 1024);
    try toplevel_surface.command_hash.ensureTotalCapacity(this.allocator, 2048); // enough room for 4k stuff
    try toplevel_surface.command_hash_prev.ensureTotalCapacity(this.allocator, 2048); // enough room for 4k stuff

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
    this.toplevel.putAssumeCapacity(wl_surface.id, toplevel_surface);
}

pub fn initSurface(this: *@This(), surface: *Surface, options: Surface.InitOptions) !void {
    const wl_surface = this.connection.sendRequest(wayland.wl_compositor, this.globals.wl_compositor.?, .create_surface, .{}) catch return error.ConnectionLost;
    wl_surface.sendRequest(.commit, .{}) catch return error.ConnectionLost;

    const fb = try seizer.image.Linear(seizer.color.argbf32_premultiplied).alloc(this.allocator, options.size);

    surface.* = .{
        .display = this,
        .wl_surface = wl_surface.id,
        .swapchain = .{},
        .framebuffer = fb,
        .on_render_listener = null,
        .size = options.size,
    };
    surface.swapchain.size = .{ 0, 0 };
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
                if (this.seat != null) {
                    log.warn("multiple seats detected; multiple seat handling not implemented.", .{});
                    return;
                }
                const wl_seat = try registry.connection.createObject(wayland.wl_seat);
                try registry.sendRequest(.bind, .{ .name = global.name, .id = wl_seat.id.asGenericNewId() });

                this.seat = .{
                    .wl_seat = wl_seat.id,
                };
                wl_seat.setEventListener(&this.seat.?.listener, onWlSeatEvent, this);
                return;
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
        return if (this.toplevel.count() > 0) .rearm else .disarm;
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

    pointer_pos: [2]f64 = .{ 0, 0 },
    scroll_vector: [2]f64 = .{ 0, 0 },
    cursor_wl_surface: ?*Surface = null,
    wp_viewport: ?shimizu.Object.WithInterface(viewporter.wp_viewport) = null,

    pointer_focus: ?shimizu.Object.WithInterface(wayland.wl_surface) = null,
    pointer_listener: shimizu.Listener = undefined,
    pointer_serial: u32 = 0,
    cursor_hotspot: [2]i32 = .{ 0, 0 },
    cursor_fractional_scale: ?shimizu.Object.WithInterface(fractional_scale_v1.wp_fractional_scale_v1) = null,
    cursor_fractional_scale_listener: shimizu.Listener = undefined,
    pointer_scale: u32 = 120,

    keyboard_listener: shimizu.Listener = undefined,
    keymap: ?xkb.Keymap = null,
    keymap_state: xkb.Keymap.State = undefined,
    keyboard_repeat_rate: u32 = 0,
    keyboard_repeat_delay: u32 = 0,

    fn deinit(this: *@This()) void {
        if (this.keymap) |*keymap| keymap.deinit();
    }
};

fn onWlSeatEvent(listener: *shimizu.Listener, wl_seat: shimizu.Proxy(wayland.wl_seat), event: wayland.wl_seat.Event) !void {
    const this: *@This() = @ptrCast(@alignCast(listener.userdata));
    const seat: *Seat = @fieldParentPtr("listener", listener);
    std.debug.assert(&this.seat.? == seat);
    switch (event) {
        .capabilities => |capabilities| {
            if (capabilities.capabilities.keyboard) {
                if (seat.wl_keyboard == null) {
                    const wl_keyboard = try wl_seat.sendRequest(.get_keyboard, .{});
                    seat.wl_keyboard = wl_keyboard.id;
                    wl_keyboard.setEventListener(&seat.keyboard_listener, onKeyboardCallback, this);
                }
            } else {
                if (seat.wl_keyboard) |wl_keyboard_id| {
                    const wl_keyboard: shimizu.Proxy(wayland.wl_keyboard) = .{ .connection = &this.connection, .id = wl_keyboard_id };
                    try wl_keyboard.sendRequest(.release, .{});
                    seat.wl_keyboard = null;
                }
            }

            if (capabilities.capabilities.pointer) {
                if (seat.wl_pointer == null) {
                    const wl_pointer = try wl_seat.sendRequest(.get_pointer, .{});
                    seat.wl_pointer = wl_pointer.id;
                    wl_pointer.setEventListener(&seat.pointer_listener, onPointerCallback, this);
                }
                if (seat.cursor_wl_surface == null) {
                    // const cursor_surface = try this.connection.sendRequest(wayland.wl_compositor, this.globals.wl_compositor.?, .create_surface, .{});
                    // seat.cursor_wl_surface = cursor_surface.id;

                    // if (this.globals.wp_viewporter) |wp_viewporter| {
                    //     seat.wp_viewport = try seat.wayland_manager.connection.sendRequest(viewporter.wp_viewporter, wp_viewporter, .get_viewport, .{ .surface = seat.cursor_wl_surface.?.id });
                    // }

                    // if (seat.wayland_manager.globals.wp_fractional_scale_manager_v1) |scale_man| {
                    //     seat.cursor_fractional_scale = try seat.wayland_manager.connection.sendRequest(fractional_scale_v1.wp_fractional_scale_manager_v1, scale_man, .get_fractional_scale, .{ .surface = seat.cursor_wl_surface.?.id });
                    //     // seat.cursor_fractional_scale.?.userdata = seat;
                    //     // seat.cursor_fractional_scale.?.on_event = onCursorFractionalScaleEvent;
                    // }
                }
            } else {
                if (seat.wl_pointer) |pointer_id| {
                    try this.connection.sendRequest(wayland.wl_pointer, pointer_id, .release, .{});
                    seat.wl_pointer = null;
                }
                // if (seat.wp_viewport) |wp_viewport_id| {
                //     try this.connection.sendRequest(viewporter.wp_viewport, wp_viewport_id, .release, .{});
                //     seat.wp_viewport = null;
                // }
                // if (seat.cursor_fractional_scale) |frac_scale| {
                //     frac_scale.sendRequest(.destroy, .{}) catch {};
                //     seat.cursor_fractional_scale = null;
                // }
                // if (seat.cursor_wl_surface) |surface| {
                //     surface.sendRequest(.destroy, .{}) catch {};
                //     seat.cursor_wl_surface = null;
                // }
            }
        },
        .name => {},
    }
}

fn onKeyboardCallback(listener: *shimizu.Listener, wl_keyboard: shimizu.Proxy(wayland.wl_keyboard), event: wayland.wl_keyboard.Event) !void {
    const this: *@This() = @ptrCast(@alignCast(listener.userdata));
    const seat: *Seat = @fieldParentPtr("keyboard_listener", listener);
    std.debug.assert(&this.seat.? == seat);
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

            if (seat.keymap) |*old_keymap| {
                old_keymap.deinit();
                seat.keymap = null;
            }
            seat.keymap = xkb.Keymap.fromString(this.allocator, new_keymap_source) catch |err| {
                log.warn("failed to parse keymap: {}", .{err});
                if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace.*);
                return;
            };
        },
        .repeat_info => |repeat_info| {
            seat.keyboard_repeat_rate = @intCast(repeat_info.rate);
            seat.keyboard_repeat_delay = @intCast(repeat_info.delay);
        },
        .modifiers => |m| {
            seat.keymap_state = xkb.Keymap.State{
                .base_modifiers = @bitCast(m.mods_depressed),
                .latched_modifiers = @bitCast(m.mods_latched),
                .locked_modifiers = @bitCast(m.mods_locked),
                .group = @intCast(m.group),
            };
        },
        .key => |k| if (seat.keymap) |keymap| {
            const scancode = evdevToSeizer(k.key);
            const symbol = keymap.getSymbol(@enumFromInt(k.key + 8), seat.keymap_state) orelse return;
            const key = xkbSymbolToSeizerKey(symbol);
            const xkb_modifiers = seat.keymap_state.getModifiers();

            const pointer_focus_id = seat.pointer_focus orelse return;
            const pointer_focus = this.toplevel.get(pointer_focus_id) orelse return;
            const input_listener = pointer_focus.on_input_listener orelse return;

            input_listener.callback(input_listener, pointer_focus, .{ .key = .{
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
            } }) catch |err| {
                std.debug.print("{s}\n", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            };

            if (symbol.character) |character| {
                if (k.state == .pressed) {
                    var text_utf8 = std.BoundedArray(u8, 16){};
                    text_utf8.resize(std.unicode.utf8CodepointSequenceLength(character) catch unreachable) catch unreachable;
                    _ = std.unicode.utf8Encode(character, text_utf8.slice()) catch unreachable;

                    input_listener.callback(input_listener, pointer_focus, .{
                        .text = .{
                            .text = text_utf8,
                        },
                    }) catch |err| {
                        std.debug.print("{s}\n", .{@errorName(err)});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    };
                }
            }
        },
        else => {},
    }
}

fn onPointerCallback(listener: *shimizu.Listener, wl_pointer: shimizu.Proxy(wayland.wl_pointer), event: wayland.wl_pointer.Event) !void {
    const this: *@This() = @ptrCast(@alignCast(listener.userdata));
    const seat: *Seat = @fieldParentPtr("pointer_listener", listener);
    _ = wl_pointer;
    switch (event) {
        .enter => |enter| {
            seat.pointer_focus = enter.surface;
            seat.pointer_serial = enter.serial;
            this.updateCursorImage(seat) catch |e| {
                log.warn("Unable to update cursor, {!}", .{e});
            };
        },
        .leave => |leave| {
            if (seat.pointer_focus == leave.surface) {
                seat.pointer_focus = null;
            }
        },
        .motion => |motion| {
            const pointer_focus_id = seat.pointer_focus orelse return;
            const pointer_focus = this.toplevel.get(pointer_focus_id) orelse return;
            const input_listener = pointer_focus.on_input_listener orelse return;

            seat.pointer_pos = [2]f64{ motion.surface_x.toFloat(f64), motion.surface_y.toFloat(f64) };
            input_listener.callback(input_listener, pointer_focus, .{ .hover = .{
                .pos = seat.pointer_pos,
                .modifiers = .{ .left = false, .right = false, .middle = false },
            } }) catch |err| {
                std.debug.print("{s}\n", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            };
        },
        .button => |button| {
            const pointer_focus_id = seat.pointer_focus orelse return;
            const pointer_focus = this.toplevel.get(pointer_focus_id) orelse return;
            const input_listener = pointer_focus.on_input_listener orelse return;

            input_listener.callback(input_listener, pointer_focus, .{ .click = .{
                .pos = seat.pointer_pos,
                .button = @enumFromInt(button.button),
                .pressed = button.state == .pressed,
            } }) catch |err| {
                std.debug.print("{s}\n", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            };
        },
        .axis => |axis| {
            switch (axis.axis) {
                .horizontal_scroll => seat.scroll_vector[0] += axis.value.toFloat(f32),
                .vertical_scroll => seat.scroll_vector[1] += axis.value.toFloat(f32),
            }

            defer seat.scroll_vector = .{ 0, 0 };
            const pointer_focus_id = seat.pointer_focus orelse return;
            const pointer_focus = this.toplevel.get(pointer_focus_id) orelse return;
            const input_listener = pointer_focus.on_input_listener orelse return;

            input_listener.callback(input_listener, pointer_focus, .{ .scroll = .{
                .offset = seat.scroll_vector,
            } }) catch |err| {
                std.debug.print("{s}\n", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            };
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

fn updateCursorImage(this: *@This(), seat: *Seat) !void {
    const wl_pointer_id = seat.wl_pointer orelse return;
    const cursor_surface = seat.cursor_wl_surface orelse return;

    _ = cursor_surface.on_render_listener orelse return;
    try cursor_surface.on_render_listener.?.callback(cursor_surface.on_render_listener.?, seat.cursor_wl_surface.?);

    const wl_pointer = shimizu.Proxy(shimizu.core.wl_pointer){
        .connection = &this.connection,
        .id = wl_pointer_id,
    };
    try wl_pointer.sendRequest(.set_cursor, .{
        .serial = seat.pointer_serial,
        .surface = cursor_surface.wl_surface,
        .hotspot_x = seat.cursor_hotspot[0],
        .hotspot_y = seat.cursor_hotspot[1],
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
