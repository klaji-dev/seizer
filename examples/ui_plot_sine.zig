pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var input_listener: seizer.Display.ToplevelSurface.OnInputListener = undefined;

var font: seizer.Canvas.Font = undefined;
var ui_image: seizer.image.Image(seizer.color.argbf32_premultiplied) = undefined;
var _stage: *seizer.ui.Stage = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnInput(&input_listener, onToplevelInputEvent, null);
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer font.deinit();

    ui_image = try seizer.image.Image(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/ui.png"));
    errdefer ui_image.free(gpa.allocator());

    _stage = try seizer.ui.Stage.create(gpa.allocator(), .{
        .padding = .{
            .min = .{ 16, 16 },
            .max = .{ 16, 16 },
        },
        .text_font = &font,
        .text_scale = 1,
        .text_color = seizer.color.argbf32_premultiplied.WHITE,
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 0, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
        .background_color = seizer.color.argbf32_premultiplied.WHITE,
    });
    errdefer _stage.destroy();

    var flexbox = try seizer.ui.Element.FlexBox.create(_stage);
    defer flexbox.element().release();
    flexbox.justification = .center;
    flexbox.cross_align = .center;
    _stage.setRoot(flexbox.element());

    const frame = try seizer.ui.Element.Frame.create(_stage);
    defer frame.element().release();
    try flexbox.appendChild(frame.element());

    var frame_flexbox = try seizer.ui.Element.FlexBox.create(_stage);
    defer frame_flexbox.element().release();
    frame_flexbox.justification = .center;
    frame_flexbox.cross_align = .center;
    frame.setChild(frame_flexbox.element());

    const hello_world_label = try seizer.ui.Element.Label.create(_stage, "y = sin(x)");
    defer hello_world_label.element().release();
    hello_world_label.style = _stage.default_style.with(.{
        .text_color = seizer.color.argbf32_premultiplied.BLACK,
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 48, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
    });
    try frame_flexbox.appendChild(hello_world_label.element());

    const sine_plot = try seizer.ui.Element.Plot.create(_stage);
    defer sine_plot.element().release();
    try sine_plot.lines.put(_stage.gpa, try _stage.gpa.dupe(u8, "y = sin(x)"), .{});
    sine_plot.x_range = .{ 0, std.math.tau };
    sine_plot.y_range = .{ -1, 1 };
    try frame_flexbox.appendChild(sine_plot.element());

    try sine_plot.lines.getPtr("y = sin(x)").?.x.ensureTotalCapacity(_stage.gpa, 360);
    try sine_plot.lines.getPtr("y = sin(x)").?.y.ensureTotalCapacity(_stage.gpa, 360);

    sine_plot.lines.getPtr("y = sin(x)").?.x.items.len = 360;
    sine_plot.lines.getPtr("y = sin(x)").?.y.items.len = 360;

    const x_array = sine_plot.lines.getPtr("y = sin(x)").?.x.items;
    const y_array = sine_plot.lines.getPtr("y = sin(x)").?.y.items;
    for (x_array, y_array, 0..) |*x, *y, i| {
        x.* = std.math.tau * @as(f32, @floatFromInt(i)) / 360;
        y.* = @sin(x.*);
    }

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    _stage.destroy();

    font.deinit();
    ui_image.free(gpa.allocator());

    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onToplevelInputEvent(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    if (_stage.processEvent(event)) |_| {
        try surface.requestAnimationFrame();
        try display.connection.sendRequest(@TypeOf(surface.wl_surface)._SPECIFIED_INTERFACE, surface.wl_surface, .commit, .{});
    }
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0, .g = 0, .b = 0, .a = 1.0 });

    _stage.needs_layout = true;
    _stage.render(canvas, canvas.size());

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
