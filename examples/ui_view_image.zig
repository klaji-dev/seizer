pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var input_listener: seizer.Display.ToplevelSurface.OnInputListener = undefined;

var font: seizer.Canvas.Font = undefined;
var ui_image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
var character_image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;
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

    ui_image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/ui.png"));
    errdefer ui_image.free(gpa.allocator());

    character_image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/wedge.png"));
    errdefer character_image.free(gpa.allocator());

    // initialize ui stage and elements
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

    const frame = try seizer.ui.Element.Frame.create(_stage);
    defer frame.element().release();

    const frame_flexbox = try seizer.ui.Element.FlexBox.create(_stage);
    defer frame_flexbox.element().release();
    frame_flexbox.cross_align = .center;

    const title_label = try seizer.ui.Element.Label.create(_stage, "Images in PanZoom");
    defer title_label.element().release();
    title_label.style = _stage.default_style.with(.{
        .text_color = seizer.color.argbf32_premultiplied.BLACK,
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 48, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
    });

    const pan_zoom = try seizer.ui.Element.PanZoom.create(_stage);
    defer pan_zoom.element().release();

    const pan_zoom_flexbox = try seizer.ui.Element.FlexBox.create(_stage);
    defer pan_zoom_flexbox.element().release();

    const character_image_element = try seizer.ui.Element.Image.create(_stage, character_image);
    defer character_image_element.element().release();

    const image_element = try seizer.ui.Element.Image.create(_stage, ui_image);
    defer image_element.element().release();

    const hello_button = try seizer.ui.Element.Button.create(_stage, "Hello");
    defer hello_button.element().release();

    const text_field = try seizer.ui.Element.TextField.create(_stage);
    defer text_field.element().release();

    // put elements into containers
    _stage.setRoot(flexbox.element());

    try flexbox.appendChild(frame.element());

    frame.setChild(frame_flexbox.element());

    try frame_flexbox.appendChild(title_label.element());
    try frame_flexbox.appendChild(pan_zoom.element());

    try pan_zoom.appendChild(pan_zoom_flexbox.element());

    try pan_zoom_flexbox.appendChild(character_image_element.element());
    try pan_zoom_flexbox.appendChild(image_element.element());
    try pan_zoom_flexbox.appendChild(hello_button.element());
    try pan_zoom_flexbox.appendChild(text_field.element());

    // setup global deinit callback
    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    _stage.destroy();

    font.deinit();
    character_image.free(gpa.allocator());
    ui_image.free(gpa.allocator());

    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onToplevelInputEvent(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    if (_stage.processEvent(event)) |_| {
        try surface.requestAnimationFrame();
    }
    try display.connection.sendRequest(@TypeOf(surface.wl_surface)._SPECIFIED_INTERFACE, surface.wl_surface, .commit, .{});
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
