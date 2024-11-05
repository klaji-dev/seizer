pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    seizer.setDeinit(deinit);
}

fn deinit() void {
    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });
    const BLUE =
        seizer.color.argb(f64){
        .r = (91.0 / 255.0),
        .g = (206.0 / 255.0),
        .b = (250.0 / 255.0),
        .a = 1.0,
    };
    const PINK = seizer.color.argb(f64){
        .r = (245.0 / 255.0),
        .g = (169.0 / 255.0),
        .b = (184.0 / 255.0),
        .a = 1.0,
    };
    //const WHITE = seizer.color.argb(f64).WHITE;

    canvas.line(.{ 5, 5 }, .{ 200, 200 }, .{
        .width = 5,
        .color = BLUE,
        .end_color = PINK,
        // .gradient = .{
        //     // .start = .{ 5, 5 },
        //     // .end = .{ 200, 200 },
        //     .end_color = PINK,
        //     .type = .linear,
        //     // .stops = &.{
        //     //     .{ .offset = 0.25, .color = PINK },
        //     //     .{ .offset = 0.5, .color = WHITE },
        //     //     .{ .offset = 0.75, .color = PINK },
        //     //     .{ .offset = 1.0, .color = BLUE },
        //     // },
        // },
    });
    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
