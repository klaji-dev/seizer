pub const Font = @import("./Canvas/Font.zig");
pub const Transformed = @import("./Canvas/Transformed.zig");

const Canvas = @This();

ptr: ?*anyopaque,
interface: *const Interface,

pub const Interface = struct {
    /// The size of the renderable area
    size: *const fn (?*anyopaque) [2]f64,
    clear: *const fn (?*anyopaque, seizer.color.argbf32_premultiplied) void,
    blit: *const fn (?*anyopaque, pos: [2]f64, image: seizer.image.Image(seizer.color.argbf32_premultiplied)) void,
    texture_rect: *const fn (?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, image: seizer.image.Image(seizer.color.argbf32_premultiplied), options: RectOptions) void,
    fill_rect: *const fn (?*anyopaque, pos: [2]f64, size: [2]f64, options: RectOptions) void,
    line: *const fn (?*anyopaque, start: [2]f64, end: [2]f64, options: LineOptions) void,
};

pub fn size(this: @This()) [2]f64 {
    return this.interface.size(this.ptr);
}

pub fn clear(this: @This(), color: seizer.color.argbf32_premultiplied) void {
    return this.interface.clear(this.ptr, color);
}

pub fn blit(this: @This(), pos: [2]f64, image: seizer.image.Image(seizer.color.argbf32_premultiplied)) void {
    return this.interface.blit(this.ptr, pos, image);
}

pub const RectOptions = struct {
    depth: f64 = 0.5,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
};

pub fn textureRect(this: @This(), dst_pos: [2]f64, dst_size: [2]f64, image: seizer.image.Image(seizer.color.argbf32_premultiplied), options: RectOptions) void {
    return this.interface.texture_rect(this.ptr, dst_pos, dst_size, image, options);
}

pub fn fillRect(this: @This(), pos: [2]f64, rect_size: [2]f64, options: RectOptions) void {
    return this.interface.fill_rect(this.ptr, pos, rect_size, options);
}

pub const LineOptions = struct {
    depth: f64 = 0.5,
    width: f64 = 1,
    end_width: ?f64 = null,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
    end_color: ?seizer.color.argbf32_premultiplied = null,
};

pub fn line(this: @This(), start_pos: [2]f64, end_pos: [2]f64, options: LineOptions) void {
    return this.interface.line(this.ptr, start_pos, end_pos, options);
}

// Stuff that is implemented on top of the base functions

pub const NinePatch = struct {
    image: seizer.image.Image(seizer.color.argbf32_premultiplied),
    inset: seizer.geometry.Inset(u32),

    pub const Options = struct {
        depth: f64 = 0.5,
        color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
        scale: f64 = 1,
    };

    pub fn init(image: seizer.image.Image(seizer.color.argbf32_premultiplied), inset: seizer.geometry.Inset(u32)) NinePatch {
        return .{ .image = image, .inset = inset };
    }

    pub fn images(this: @This()) [9]seizer.image.Image(seizer.color.argbf32_premultiplied) {
        const left = this.inset.min[0];
        const top = this.inset.min[1];
        const right = this.image.size[0] - this.inset.max[0];
        const bot = this.image.size[1] - this.inset.max[1];
        return [9]seizer.image.Image(seizer.color.argbf32_premultiplied){
            // Inside first
            this.image.slice(this.inset.min, .{ right - left, bot - top }),
            // Edges second
            this.image.slice(.{ left, 0 }, .{ right - left, top }), // top
            this.image.slice(.{ 0, top }, .{ left, bot - top }), // left
            this.image.slice(.{ right, top }, .{ this.inset.max[0], bot - top }), // right
            this.image.slice(.{ left, bot }, .{ right - left, this.inset.max[1] }), // bottom
            // Corners third
            this.image.slice(.{ 0, 0 }, this.inset.min), // top left
            this.image.slice(.{ right, 0 }, .{ this.inset.max[0], top }), // top right
            this.image.slice(.{ 0, bot }, .{ left, this.inset.max[1] }), // bottom left
            this.image.slice(.{ right, bot }, this.inset.max), // bottom right
        };
    }
};

pub fn ninePatch(this: @This(), pos: [2]f64, ninepatch_size: [2]f64, image: seizer.image.Image(seizer.color.argbf32_premultiplied), inset: geometry.Inset(u32), options: NinePatch.Options) void {
    const images = NinePatch.images(.{ .image = image, .inset = inset });
    const scaled_inset = inset.intToFloat(f64).scale(options.scale);

    const x: [4]f64 = .{ pos[0], pos[0] + scaled_inset.min[0], pos[0] + ninepatch_size[0] - scaled_inset.min[0], pos[0] + ninepatch_size[0] };
    const y: [4]f64 = .{ pos[1], pos[1] + scaled_inset.min[1], pos[1] + ninepatch_size[1] - scaled_inset.min[1], pos[1] + ninepatch_size[1] };
    const w: [3]f64 = .{ x[1] - x[0], x[2] - x[1], x[3] - x[2] };
    const h: [3]f64 = .{ y[1] - y[0], y[2] - y[1], y[3] - y[2] };

    // Inside first
    this.textureRect(.{ x[1], y[1] }, .{ w[1], h[1] }, images[0], .{ .depth = options.depth, .color = options.color });
    // Edges second
    this.textureRect(.{ x[1], y[0] }, .{ w[1], h[0] }, images[1], .{ .depth = options.depth, .color = options.color }); // top
    this.textureRect(.{ x[0], y[1] }, .{ w[0], h[1] }, images[2], .{ .depth = options.depth, .color = options.color }); // left
    this.textureRect(.{ x[2], y[1] }, .{ w[2], h[1] }, images[3], .{ .depth = options.depth, .color = options.color }); // right
    this.textureRect(.{ x[1], y[2] }, .{ w[1], h[2] }, images[4], .{ .depth = options.depth, .color = options.color }); // bottom
    // Corners third
    this.textureRect(.{ x[0], y[0] }, .{ w[0], h[0] }, images[5], .{ .depth = options.depth, .color = options.color }); // top left
    this.textureRect(.{ x[2], y[0] }, .{ w[2], h[0] }, images[6], .{ .depth = options.depth, .color = options.color }); // top right
    this.textureRect(.{ x[0], y[2] }, .{ w[0], h[2] }, images[7], .{ .depth = options.depth, .color = options.color }); // bottom left
    this.textureRect(.{ x[2], y[2] }, .{ w[2], h[2] }, images[8], .{ .depth = options.depth, .color = options.color }); // bottom right
}

pub const TextOptions = struct {
    depth: f64 = 0.5,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
    scale: f64 = 1,
    @"align": Align = .left,
    baseline: Baseline = .top,

    const Align = enum {
        left,
        center,
        right,
    };

    const Baseline = enum {
        top,
        middle,
        bottom,
    };
};

pub fn writeText(this: @This(), font: *const Font, pos: [2]f64, text: []const u8, options: TextOptions) [2]f64 {
    const text_size = font.textSize(text, options.scale);

    const x: f64 = switch (options.@"align") {
        .left => pos[0],
        .center => pos[0] - text_size[0] / 2,
        .right => pos[0] - text_size[0],
    };
    const y: f64 = switch (options.baseline) {
        .top => pos[1],
        .middle => pos[1] - text_size[1] / 2,
        .bottom => pos[1] - text_size[1],
    };
    var text_writer = this.textLayoutWriter(font, .{
        .pos = .{ x, y },
        .scale = options.scale,
        .color = options.color,
    });
    text_writer.writer().writeAll(text) catch {};
    return text_writer.text_layout.size;
}

pub fn printText(this: @This(), font: *const Font, pos: [2]f64, comptime fmt: []const u8, args: anytype, options: TextOptions) [2]f64 {
    const text_size = font.fmtTextSize(fmt, args, options.scale);

    const x: f64 = switch (options.@"align") {
        .left => pos[0],
        .center => pos[0] - text_size[0] / 2,
        .right => pos[0] - text_size[0],
    };
    const y: f64 = switch (options.baseline) {
        .top => pos[1],
        .middle => pos[1] - text_size[1] / 2,
        .bottom => pos[1] - text_size[1],
    };

    var text_writer = this.textLayoutWriter(font, .{
        .pos = .{ x, y },
        .scale = options.scale,
        .color = options.color,
    });
    text_writer.writer().print(fmt, args) catch {};

    return text_writer.text_layout.size;
}

pub const TextLayoutWriter = Font.TextLayoutWriter(WriteGlyphContext, writeGlyph);
pub const TextLayoutOptions = struct {
    pos: [2]f64 = .{ 0, 0 },
    scale: f64 = 1,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
};

pub fn textLayoutWriter(this: @This(), font: *const Font, options: TextLayoutOptions) TextLayoutWriter {
    return TextLayoutWriter{
        .context = .{
            .canvas = this,
            .font = font,
            .options = options,
        },
        .text_layout = .{
            .glyphs = &font.glyphs,
            .text = "",
            .line_height = font.line_height,
            .current_offset = options.pos,
            .options = .{ .pos = options.pos, .scale = options.scale },
        },
    };
}

pub fn clipped(this: @This(), clip_rect: seizer.geometry.Rect(f64)) Transformed {
    return Transformed{
        .parent = this,
        .clip_area = clip_rect.toAABB(),
    };
}

const WriteGlyphContext = struct {
    canvas: Canvas,
    font: *const Font,
    options: TextLayoutOptions,
};

fn writeGlyph(ctx: WriteGlyphContext, item: Font.TextLayout.Item) void {
    const image = ctx.font.pages.get(item.glyph.page) orelse return;
    const glyph_image = image.slice(
        .{ @intFromFloat(item.glyph.pos[0]), @intFromFloat(item.glyph.pos[1]) },
        .{ @intFromFloat(item.glyph.size[0]), @intFromFloat(item.glyph.size[1]) },
    );
    ctx.canvas.interface.texture_rect(
        ctx.canvas.ptr,
        item.pos,
        item.size,
        glyph_image,
        .{
            .color = ctx.options.color,
        },
    );
}

const log = std.log.scoped(.Canvas);
const std = @import("std");
const seizer = @import("seizer.zig");
const zigimg = @import("zigimg");
const geometry = @import("./geometry.zig");
