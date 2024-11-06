pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var input_listener: seizer.Display.ToplevelSurface.OnInputListener = undefined;

var font: seizer.Canvas.Font = undefined;
var stack_cutscene: []align(16) u8 = undefined;
var frame_cutscene: seizer.libcoro.Frame = undefined;
var message: []const u8 = "";
var clear_color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.BLACK;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);
    toplevel_surface.setOnInput(&input_listener, onInput, null);

    font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer font.deinit();

    stack_cutscene = try seizer.libcoro.stackAlloc(gpa.allocator(), null);
    errdefer gpa.allocator().free(stack_cutscene);
    const coro = try seizer.libcoro.xasync(cutsceneCoro, .{}, stack_cutscene);
    frame_cutscene = coro.frame();
    errdefer frame_cutscene.deinit();

    seizer.setDeinit(deinit);
}

fn deinit() void {
    frame_cutscene.deinit();
    gpa.allocator().free(stack_cutscene);
    font.deinit();
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onInput(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    if (event == .click) {
        if (event.click.pressed) {
            if (frame_cutscene.status != .Done) {
                seizer.libcoro.xresume(frame_cutscene);
                try surface.requestAnimationFrame();
            }
            if (frame_cutscene.status == .Done) {
                surface.hide();
            }
        }
    }
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(clear_color);
    _ = canvas.writeText(&font, .{ 32, 32 }, message, .{});
    try surface.present();
}

fn cutsceneCoro() void {
    message = "Hello World! Click to continue.";
    seizer.libcoro.xsuspend();
    message = "This is a scene scripted using libcoro.";
    clear_color = .{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 };
    seizer.libcoro.xsuspend();
    message = "It means we can write linear code that pauses execution\nuntil we tell it to resume.";
    clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.6, .a = 1.0 };
    seizer.libcoro.xsuspend();
    message = "It's very useful for cutscenes!";
    seizer.libcoro.xsuspend();
    message = "Bye!";
    seizer.libcoro.xsuspend();
    message = "";
}

const seizer = @import("seizer");
const std = @import("std");
