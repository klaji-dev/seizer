pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var render_listener_cursor: seizer.Display.Surface.OnRenderListener = undefined;

var cursor_surface: seizer.Display.Surface = undefined;
var shield_tvg: seizer.image.TVG = undefined;
var cursor_tvg: seizer.image.TVG = undefined;
var shield_image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
var cursor_image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    shield_tvg = try seizer.image.TVG.fromMemory(gpa.allocator(), &shield_icon_tvg);
    errdefer shield_tvg.deinit(gpa.allocator());
    cursor_tvg = try seizer.image.TVG.fromMemory(gpa.allocator(), cursor_none_tvg);
    errdefer cursor_tvg.deinit(gpa.allocator());

    shield_image = try ImageLinear.alloc(gpa.allocator(), shield_tvg.size());
    cursor_image = try ImageLinear.alloc(gpa.allocator(), cursor_tvg.size());

    try shield_tvg.rasterize(&shield_image, .{});
    try cursor_tvg.rasterize(&cursor_image, .{});

    try display.initSurface(&cursor_surface, .{ .size = cursor_image.size });
    cursor_surface.setOnRender(&render_listener_cursor, onCursorRender, null);
    display.seat.?.cursor_wl_surface = &cursor_surface;
    display.seat.?.cursor_hotspot = .{ 9, 5 };

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    cursor_tvg.deinit(gpa.allocator());
    cursor_image.free(gpa.allocator());
    cursor_surface.deinit();

    shield_tvg.deinit(gpa.allocator());
    shield_image.free(gpa.allocator());

    toplevel_surface.deinit();

    display.deinit();

    _ = gpa.deinit();
}

fn onCursorRender(listener: *seizer.Display.Surface.OnRenderListener, surface: *seizer.Display.Surface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
    canvas.blit(.{ 0, 0 }, cursor_image.asSlice());

    try surface.present();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    canvas.blit(.{ 50, 50 }, shield_image.asSlice());
    canvas.blit(.{ 100, 50 }, cursor_image.asSlice());

    try surface.present();
}

const shield_icon_tvg = [_]u8{
    0x72, 0x56, 0x01, 0x42, 0x18, 0x18, 0x02, 0x29, 0xad, 0xff, 0xff, 0xff,
    0xf1, 0xe8, 0xff, 0x03, 0x02, 0x00, 0x04, 0x05, 0x03, 0x30, 0x04, 0x00,
    0x0c, 0x14, 0x02, 0x2c, 0x03, 0x0c, 0x42, 0x1b, 0x57, 0x30, 0x5c, 0x03,
    0x45, 0x57, 0x54, 0x42, 0x54, 0x2c, 0x02, 0x14, 0x45, 0x44, 0x03, 0x40,
    0x4b, 0x38, 0x51, 0x30, 0x54, 0x03, 0x28, 0x51, 0x20, 0x4b, 0x1b, 0x44,
    0x03, 0x1a, 0x42, 0x19, 0x40, 0x18, 0x3e, 0x03, 0x18, 0x37, 0x23, 0x32,
    0x30, 0x32, 0x03, 0x3d, 0x32, 0x48, 0x37, 0x48, 0x3e, 0x03, 0x47, 0x40,
    0x46, 0x42, 0x45, 0x44, 0x30, 0x14, 0x03, 0x36, 0x14, 0x3c, 0x19, 0x3c,
    0x20, 0x03, 0x3c, 0x26, 0x37, 0x2c, 0x30, 0x2c, 0x03, 0x2a, 0x2c, 0x24,
    0x27, 0x24, 0x20, 0x03, 0x24, 0x1a, 0x29, 0x14, 0x30, 0x14, 0x00,
};
const cursor_none_tvg = @embedFile("assets/cursor_none.tvg");

const seizer = @import("seizer");
const std = @import("std");
const ImageLinear = seizer.image.Linear(seizer.color.argbf32_premultiplied);
