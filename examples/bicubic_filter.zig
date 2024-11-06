pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var image: seizer.image.Image(seizer.color.argbf32_premultiplied) = undefined;
var bicubic_upscale: seizer.image.Image(seizer.color.argbf32_premultiplied) = undefined;
var bicubic_downscale: seizer.image.Image(seizer.color.argbf32_premultiplied) = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    image = try seizer.image.Image(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/wedge.png"));
    errdefer image.free(gpa.allocator());

    bicubic_upscale = try seizer.image.Image(seizer.color.argbf32_premultiplied).alloc(gpa.allocator(), .{ 5 * image.size[0], 5 * image.size[1] });
    errdefer bicubic_upscale.free(gpa.allocator());
    bicubic_upscale.resize(image);

    bicubic_downscale = try seizer.image.Image(seizer.color.argbf32_premultiplied).alloc(gpa.allocator(), .{ image.size[0] / 2, image.size[1] / 2 });
    errdefer bicubic_downscale.free(gpa.allocator());
    bicubic_downscale.resize(image);

    seizer.setDeinit(deinit);
}

fn deinit() void {
    bicubic_downscale.free(gpa.allocator());
    bicubic_upscale.free(gpa.allocator());
    image.free(gpa.allocator());
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    const sizef = canvas.size();
    canvas.textureRect(.{ 0, 0.0 * sizef[1] / 3.0 }, .{ sizef[0], sizef[1] / 3.0 }, bicubic_downscale, .{});
    canvas.textureRect(.{ 0, 1.0 * sizef[1] / 3.0 }, .{ sizef[0], sizef[1] / 3.0 }, image, .{});
    canvas.textureRect(.{ 0, 2.0 * sizef[1] / 3.0 }, .{ sizef[0], sizef[1] / 3.0 }, bicubic_upscale, .{});

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
