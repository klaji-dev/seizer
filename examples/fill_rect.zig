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

/// This is a global deinit, not window specific. This is important because windows can hold onto Graphics resources.
fn deinit() void {
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    const color_square = seizer.geometry.AABB(f64).init(.{ .{ 0, 0 }, .{ 25, 25 } });

    canvas.fillRect(color_square.translate(.{ 25, 25 }), .{ .r = 1, .g = 0, .b = 0, .a = 1 }, .{});
    canvas.fillRect(color_square.translate(.{ 75, 25 }), .{ .r = 0, .g = 1, .b = 0, .a = 1 }, .{});
    canvas.fillRect(color_square.translate(.{ 125, 25 }), .{ .r = 0, .g = 0, .b = 1, .a = 1 }, .{});
    canvas.fillRect(color_square.translate(.{ 175, 25 }), .{ .r = 0, .g = 0, .b = 0, .a = 1 }, .{});
    canvas.fillRect(color_square.translate(.{ 225, 25 }), .{ .r = 0, .g = 0, .b = 0, .a = 0 }, .{});

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
