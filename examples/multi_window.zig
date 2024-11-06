pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;

var font: seizer.Canvas.Font = undefined;

var next_window_id: usize = 0;
var open_window_count: usize = 0;

const WindowData = struct {
    title: ?[:0]const u8 = null,
    toplevel_surface: seizer.Display.ToplevelSurface,
    close_listener: seizer.Display.ToplevelSurface.CloseListener,
    event_listener: seizer.Display.ToplevelSurface.OnInputListener,
    render_listener: seizer.Display.ToplevelSurface.OnRenderListener,
};

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer font.deinit();

    try createNewWindow(null);

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    font.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn createNewWindow(title: ?[:0]const u8) !void {
    const window_data = try gpa.allocator().create(WindowData);
    errdefer gpa.allocator().destroy(window_data);

    window_data.* = .{
        .title = title,
        .toplevel_surface = undefined,
        .close_listener = undefined,
        .event_listener = undefined,
        .render_listener = undefined,
    };

    try display.initToplevelSurface(&window_data.toplevel_surface, .{});
    window_data.toplevel_surface.setOnClose(&window_data.close_listener, onToplevelClose);
    window_data.toplevel_surface.setOnInput(&window_data.event_listener, onToplevelInputEvent, null);
    window_data.toplevel_surface.setOnRender(&window_data.render_listener, onRender, null);

    next_window_id += 1;
    open_window_count += 1;
}

fn onToplevelClose(close_listener: *seizer.Display.ToplevelSurface.CloseListener, surface: *seizer.Display.ToplevelSurface) !void {
    const window_data: *WindowData = @fieldParentPtr("close_listener", close_listener);
    _ = surface;

    window_data.toplevel_surface.deinit();
    if (window_data.title) |title| gpa.allocator().free(title);
    gpa.allocator().destroy(window_data);
    open_window_count -= 1;
}

fn onToplevelInputEvent(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    _ = surface;
    switch (event) {
        .key => |key| switch (key.key) {
            .unicode => |unicode| switch (unicode) {
                'n' => if (key.action == .press) {
                    const title = try std.fmt.allocPrintZ(gpa.allocator(), "Window {}", .{next_window_id});
                    errdefer gpa.allocator().free(title);

                    try createNewWindow(title);
                },
                else => {},
            },
            else => {},
        },

        else => {},
    }
}

fn onRender(render_listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    const window_data: *WindowData = @fieldParentPtr("render_listener", render_listener);

    const canvas = try surface.canvas();
    const window_size = canvas.size();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    if (window_data.title) |title| {
        _ = canvas.writeText(&font, .{ window_size[0] / 2, window_size[1] / 2 }, title, .{
            .scale = 3,
            .@"align" = .center,
            .baseline = .middle,
        });
    } else {
        _ = canvas.writeText(&font, .{ window_size[0] / 2, window_size[1] / 2 }, "Press N to spawn new window", .{
            .scale = 3,
            .@"align" = .center,
            .baseline = .middle,
        });
    }

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
