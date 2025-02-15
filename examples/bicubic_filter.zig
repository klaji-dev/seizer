pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
var bicubic_upscale: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
var bicubic_downscale: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/wedge.png"));
    errdefer image.free(gpa.allocator());

    bicubic_upscale = try seizer.image.Linear(seizer.color.argbf32_premultiplied).alloc(gpa.allocator(), .{ 5 * image.size[0], 5 * image.size[1] });
    errdefer bicubic_upscale.free(gpa.allocator());
    bicubic_upscale.asSlice().resize(image.asSlice());

    bicubic_downscale = try seizer.image.Linear(seizer.color.argbf32_premultiplied).alloc(gpa.allocator(), .{ image.size[0] / 2, image.size[1] / 2 });
    errdefer bicubic_downscale.free(gpa.allocator());
    bicubic_downscale.asSlice().resize(image.asSlice());

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
    const y = [4]f64{
        0,
        sizef[1] * 1.0 / 3.0,
        sizef[1] * 2.0 / 3.0,
        sizef[1],
    };
    canvas.textureRect(seizer.geometry.AABB(f64).init(.{ 0, y[0] }, .{ sizef[0], y[1] }), bicubic_downscale.asSlice(), .{});
    canvas.textureRect(seizer.geometry.AABB(f64).init(.{ 0, y[1] }, .{ sizef[0], y[2] }), image.asSlice(), .{});
    canvas.textureRect(seizer.geometry.AABB(f64).init(.{ 0, y[2] }, .{ sizef[0], y[3] }), bicubic_upscale.asSlice(), .{});

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
