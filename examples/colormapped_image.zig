pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var image: seizer.image.Linear(seizer.color.argbf32_premultiplied) = undefined;

pub const COLORMAP_SHADER_VULKAN = align_source_words: {
    const words_align1 = std.mem.bytesAsSlice(u32, @embedFile("./assets/colormap.frag.spv"));
    const aligned_words: [words_align1.len]u32 = words_align1[0..words_align1.len].*;
    break :align_source_words aligned_words;
};

pub const ColormapUniformData = extern struct {
    colormap_texture_id: u32,
    min_value: f32,
    max_value: f32,
};

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    // const zigimg_image = try seizer.zigimg.Image.fromMemory(seizer.platform.allocator(), @embedFile("assets/monochrome.png"));
    // defer zigimg_image.deinit();
    image = try seizer.image.Linear(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/monochrome.png"));
    errdefer image.free(gpa.allocator());

    // setup global deinit callback
    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    image.free(gpa.allocator());

    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.7, .g = 0.2, .b = 0.2, .a = 1.0 });

    // // split our canvas into two different modes of rendering
    // const regular_canvas_rendering = canvas.begin(render_buffer, .{
    //     .window_size = window_size,
    //     .window_scale = window_scale,
    //     .clear_color = .{ 0.7, 0.5, 0.5, 1.0 },
    // });

    // const colormap_texture_id = canvas.addTexture(colormap_texture);
    // const colormap_canvas_rendering = regular_canvas_rendering.withPipeline(colormap_pipeline, &.{
    //     .{
    //         .binding = 2,
    //         .data = std.mem.asBytes(&ColormapUniformData{
    //             .min_value = 1.0 / @as(f32, @floatFromInt(std.math.maxInt(u16))),
    //             .max_value = 1,
    //             .colormap_texture_id = colormap_texture_id,
    //         }),
    //     },
    // });

    // // render the image twice, once with the regular shader and one with our colormapping shader
    // regular_canvas_rendering.rect(.{ 0, 0 }, .{ 480, 480 }, .{ .texture = texture });
    canvas.textureRect(.{ .min = .{ 0, 0 }, .max = .{ 480, 480 } }, image.asSlice(), .{});
    // colormap_canvas_rendering.rect(.{ 480, 0 }, .{ 480, 480 }, .{ .texture = texture });

    try surface.present();
}

const seizer = @import("seizer");
const std = @import("std");
