pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/wedge.png"));
    errdefer image.free(gpa.allocator());

    seizer.setDeinit(deinit);
}

/// This is a global deinit, not window specific. This is important because windows can hold onto Graphics resources.
fn deinit() void {
    image.free(gpa.allocator());
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    canvas.blit(.{ 50, 50 }, image.asSlice());

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
