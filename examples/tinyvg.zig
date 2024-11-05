pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var shield_image: seizer.image.Image(seizer.color.argb(f32)) = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    var shield_image_tvg = try seizer.tvg.rendering.renderBuffer(
        gpa.allocator(),
        gpa.allocator(),
        .inherit,
        null,
        &shield_icon_tvg,
    );
    defer shield_image_tvg.deinit(gpa.allocator());

    shield_image = try seizer.image.Image(seizer.color.argb(f32)).alloc(
        gpa.allocator(),
        .{ shield_image_tvg.width, shield_image_tvg.width },
    );
    errdefer shield_image.free(gpa.allocator());

    for (shield_image.pixels[0 .. shield_image.size[0] * shield_image.size[1]], shield_image_tvg.pixels) |*out, in| {
        const argb8888 = seizer.color.argb8888{
            .b = @enumFromInt(in.b),
            .r = @enumFromInt(in.r),
            .g = @enumFromInt(in.g),
            .a = in.a,
        };
        const argb = argb8888.toArgb(f32);
        out.* = seizer.color.argb(f32).fromRGBUnassociatedAlpha(argb.r, argb.g, argb.b, argb.a);
    }

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    shield_image.free(gpa.allocator());
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    canvas.blit(.{ 50, 50 }, shield_image);

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

const seizer = @import("seizer");
const std = @import("std");
