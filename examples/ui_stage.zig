pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var input_listener: seizer.Display.ToplevelSurface.OnInputListener = undefined;

var font: seizer.Canvas.Font = undefined;
var ui_image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
var stage: *seizer.ui.Stage = undefined;

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

    ui_image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/ui.png"));
    errdefer ui_image.free(gpa.allocator());

    stage = try seizer.ui.Stage.create(gpa.allocator(), .{
        .padding = .{
            .min = .{ 16, 16 },
            .max = .{ 16, 16 },
        },
        .text_font = &font,
        .text_scale = 1,
        .text_color = seizer.color.argbf32_premultiplied.BLACK,
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 0, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
        .background_color = seizer.color.argbf32_premultiplied.WHITE,
    });
    errdefer stage.destroy();

    var flexbox = try seizer.ui.Element.FlexBox.create(stage);
    defer flexbox.element().release();
    flexbox.justification = .center;
    flexbox.cross_align = .center;
    stage.setRoot(flexbox.element());

    const frame = try seizer.ui.Element.Frame.create(stage);
    defer frame.element().release();
    try flexbox.appendChild(frame.element());

    var frame_flexbox = try seizer.ui.Element.FlexBox.create(stage);
    defer frame_flexbox.element().release();
    frame_flexbox.justification = .center;
    frame_flexbox.cross_align = .center;
    frame.setChild(frame_flexbox.element());

    const hello_world_label = try seizer.ui.Element.Label.create(stage, "Hello, world!");
    defer hello_world_label.element().release();
    hello_world_label.style = stage.default_style.with(.{
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 48, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
    });
    try frame_flexbox.appendChild(hello_world_label.element());

    const hello_button = try seizer.ui.Element.Button.create(stage, "Hello");
    defer hello_button.element().release();

    hello_button.default_style.padding = .{
        .min = .{ 8, 7 },
        .max = .{ 8, 9 },
    };
    hello_button.default_style.text_color = seizer.color.argbf32_premultiplied.BLACK;
    hello_button.default_style.background_color = seizer.color.argbf32_premultiplied.WHITE;
    hello_button.default_style.background_ninepatch = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 120, 24 }, .{ 24, 24 }), seizer.geometry.Inset(u32).initXY(8, 8));

    hello_button.hovered_style.padding = .{
        .min = .{ 8, 8 },
        .max = .{ 8, 8 },
    };
    hello_button.hovered_style.text_color = seizer.color.argbf32_premultiplied.BLACK;
    hello_button.hovered_style.background_color = seizer.color.argbf32_premultiplied.WHITE;
    hello_button.hovered_style.background_ninepatch = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 96, 0 }, .{ 24, 24 }), seizer.geometry.Inset(u32).initXY(8, 8));

    hello_button.clicked_style.padding = .{
        .min = .{ 8, 9 },
        .max = .{ 8, 7 },
    };
    hello_button.clicked_style.text_color = seizer.color.argbf32_premultiplied.BLACK;
    hello_button.clicked_style.background_color = seizer.color.argbf32_premultiplied.WHITE;
    hello_button.clicked_style.background_ninepatch = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 120, 0 }, .{ 24, 24 }), seizer.geometry.Inset(u32).initXY(8, 8));

    try frame_flexbox.appendChild(hello_button.element());

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    stage.destroy();

    font.deinit();
    ui_image.free(gpa.allocator());

    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onToplevelInputEvent(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    if (stage.processEvent(event)) |_| {
        try surface.requestAnimationFrame();
        try display.connection.sendRequest(@TypeOf(surface.wl_surface)._SPECIFIED_INTERFACE, surface.wl_surface, .commit, .{});
    }
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    stage.needs_layout = true;
    stage.render(canvas, canvas.size());

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
