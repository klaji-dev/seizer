pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var font: seizer.Canvas.Font = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer font.deinit();

    seizer.setDeinit(deinit);
}

/// This is a global deinit, not window specific. This is important because windows can hold onto Graphics resources.
fn deinit() void {
    font.deinit();
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    var framebuffer = try surface.getBuffer();
    framebuffer.clear(.{ 0.5, 0.5, 0.7, 1.0 });

    var pos = [2]f64{ 50, 50 };
    pos[1] += framebuffer.canvas().writeText(&font, pos, "Hello, world!", .{})[1];
    pos[1] += framebuffer.canvas().writeText(&font, pos, "Hello, world!", .{ .color = .{ 0, 0, 0, 1 } })[1];
    pos[1] += framebuffer.canvas().printText(&font, pos, "pos = <{}, {}>", .{ pos[0], pos[1] }, .{})[1];

    try surface.present(framebuffer);
}

const seizer = @import("seizer");
const std = @import("std");
