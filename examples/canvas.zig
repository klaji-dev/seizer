pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    seizer.setDeinit(deinit);
}

fn deinit() void {
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 });
    const BLUE = seizer.color.fromSRGB(91, 206, 250, 255);
    const PINK = seizer.color.fromSRGB(245, 169, 184, 255);
    const WHITE = seizer.color.fromSRGB(255, 255, 255, 255);

    canvas.line(.{ 5.5, 5.5 }, .{ 200.5, 200.5 }, .{
        .color = BLUE,
        .end_color = PINK,
    });

    canvas.line(.{ 200.5, 200.5 }, .{ 200.5, 400.5 }, .{
        .color = PINK,
        .end_color = WHITE,
        .width = 2,
    });

    canvas.line(.{ 200.5, 400.5 }, .{ 400.5, 200.5 }, .{
        .color = WHITE,
        .end_color = PINK,
        .width = 4,
    });

    canvas.line(.{ 400.5, 200.5 }, .{ 400.5, 5.5 }, .{
        .color = PINK,
        .end_color = BLUE,
        .width = 8,
    });

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
