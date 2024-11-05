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
    const BLUE = seizer.color.argbFromRGBUnassociatedAlpha(91, 206, 250, 255);
    const PINK = seizer.color.argbFromRGBUnassociatedAlpha(245, 169, 184, 255);

    canvas.line(.{ 5, 5 }, .{ 200, 200 }, .{
        .color = BLUE.floatCast(f64),
        .end_color = PINK.floatCast(f64),
    });
    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
