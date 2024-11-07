pub const Font = @import("./Canvas/Font.zig");
pub const Transformed = @import("./Canvas/Transformed.zig");

const Canvas = @This();

ptr: ?*anyopaque,
interface: *const Interface,

pub const Interface = struct {
    /// The size of the renderable area
    size: *const fn (?*anyopaque) [2]f64,
    clear: *const fn (?*anyopaque, seizer.color.argbf32_premultiplied) void,
    blit: *const fn (?*anyopaque, pos: [2]f64, image: seizer.image.Linear(seizer.color.argbf32_premultiplied)) void,
    texture_rect: *const fn (?*anyopaque, dst_area: geometry.AABB(f64), image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: TextureRectOptions) void,
    fill_rect: *const fn (?*anyopaque, area: geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: FillRectOptions) void,
    line: *const fn (?*anyopaque, start: [2]f64, end: [2]f64, options: LineOptions) void,
};

pub fn size(this: @This()) [2]f64 {
    return this.interface.size(this.ptr);
}

pub fn clear(this: @This(), color: seizer.color.argbf32_premultiplied) void {
    return this.interface.clear(this.ptr, color);
}

pub fn blit(this: @This(), pos: [2]f64, image: seizer.image.Linear(seizer.color.argbf32_premultiplied)) void {
    return this.interface.blit(this.ptr, pos, image);
}

pub const TextureRectOptions = struct {
    depth: f64 = 0.5,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
    src_area: ?geometry.AABB(f64) = null,
};

pub fn textureRect(this: @This(), dst_rect: geometry.AABB(f64), image: seizer.image.Linear(seizer.color.argbf32_premultiplied), options: TextureRectOptions) void {
    return this.interface.texture_rect(this.ptr, dst_rect, image, options);
}

pub const FillRectOptions = struct {
    depth: f64 = 0.5,
};

pub fn fillRect(this: @This(), area: geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: FillRectOptions) void {
    return this.interface.fill_rect(this.ptr, area, color, options);
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
    image: seizer.image.Linear(seizer.color.argbf32_premultiplied),
    inset: seizer.geometry.Inset(f64),

    pub const Options = struct {
        depth: f64 = 0.5,
        color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
        scale: f64 = 1,
    };

    pub fn init(image: seizer.image.Linear(seizer.color.argbf32_premultiplied), inset: seizer.geometry.Inset(f64)) NinePatch {
        return .{ .image = image, .inset = inset };
    }

    pub fn images(this: @This()) [9]seizer.image.Linear(seizer.color.argbf32_premultiplied) {
        const left = this.inset.min[0];
        const top = this.inset.min[1];
        const right = this.image.size[0] - this.inset.max[0];
        const bot = this.image.size[1] - this.inset.max[1];
        return [9]seizer.image.Linear(seizer.color.argbf32_premultiplied){
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

    pub fn imageAreas(this: @This()) [9]seizer.geometry.AABB(f64) {
        const image_sizef = [2]f64{ @floatFromInt(this.image.size[0]), @floatFromInt(this.image.size[1]) };
        const left = this.inset.min[0];
        const top = this.inset.min[1];
        const right = image_sizef[0] - this.inset.max[0];
        const bot = image_sizef[1] - this.inset.max[1];
        return [9]seizer.geometry.AABB(f64){
            // Inside first
            .{ .min = this.inset.min, .max = .{ right, bot } },
            // Edges second
            .{ .min = .{ left, 0 }, .max = .{ right, top } }, // top
            .{ .min = .{ 0, top }, .max = .{ left, bot } }, // left
            .{ .min = .{ right, top }, .max = .{ image_sizef[0], bot } }, // right
            .{ .min = .{ left, bot }, .max = .{ right, image_sizef[1] } }, // bottom
            // Corners third
            .{ .min = .{ 0, 0 }, .max = .{ left, top } }, // top left
            .{ .min = .{ right, 0 }, .max = .{ image_sizef[0], top } }, // top right
            .{ .min = .{ 0, bot }, .max = .{ left, image_sizef[1] } }, // bottom left
            .{ .min = .{ right, bot }, .max = image_sizef }, // bottom right
        };
    }
};

pub fn ninePatch(this: @This(), area: geometry.AABB(f64), image: seizer.image.Linear(seizer.color.argbf32_premultiplied), inset: geometry.Inset(f64), options: NinePatch.Options) void {
    const image_areas = NinePatch.imageAreas(.{ .image = image, .inset = inset });
    const scaled_inset = inset.scale(options.scale);

    const x: [4]f64 = .{ area.min[0], area.min[0] + scaled_inset.min[0], area.max[0] - scaled_inset.min[0], area.max[0] };
    const y: [4]f64 = .{ area.min[1], area.min[1] + scaled_inset.min[1], area.max[1] - scaled_inset.min[1], area.max[1] };

    // Inside first
    this.textureRect(.{ .min = .{ x[1], y[1] }, .max = .{ x[2], y[2] } }, image, .{ .src_area = image_areas[0], .depth = options.depth, .color = options.color });
    // Edges second
    this.textureRect(.{ .min = .{ x[1], y[0] }, .max = .{ x[2], y[1] } }, image, .{ .src_area = image_areas[1], .depth = options.depth, .color = options.color }); // top
    this.textureRect(.{ .min = .{ x[0], y[1] }, .max = .{ x[1], y[2] } }, image, .{ .src_area = image_areas[2], .depth = options.depth, .color = options.color }); // left
    this.textureRect(.{ .min = .{ x[2], y[1] }, .max = .{ x[3], y[2] } }, image, .{ .src_area = image_areas[3], .depth = options.depth, .color = options.color }); // right
    this.textureRect(.{ .min = .{ x[1], y[2] }, .max = .{ x[2], y[3] } }, image, .{ .src_area = image_areas[4], .depth = options.depth, .color = options.color }); // bottom
    // Corners third
    this.textureRect(.{ .min = .{ x[0], y[0] }, .max = .{ x[1], y[1] } }, image, .{ .src_area = image_areas[5], .depth = options.depth, .color = options.color }); // top left
    this.textureRect(.{ .min = .{ x[2], y[0] }, .max = .{ x[3], y[0] } }, image, .{ .src_area = image_areas[6], .depth = options.depth, .color = options.color }); // top right
    this.textureRect(.{ .min = .{ x[0], y[2] }, .max = .{ x[1], y[3] } }, image, .{ .src_area = image_areas[7], .depth = options.depth, .color = options.color }); // bottom left
    this.textureRect(.{ .min = .{ x[2], y[2] }, .max = .{ x[3], y[3] } }, image, .{ .src_area = image_areas[8], .depth = options.depth, .color = options.color }); // bottom right
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

pub fn transformed(this: @This(), options: Transformed.InitOptions) Transformed {
    return Transformed.init(this, options);
}

const WriteGlyphContext = struct {
    canvas: Canvas,
    font: *const Font,
    options: TextLayoutOptions,
};

fn writeGlyph(ctx: WriteGlyphContext, item: Font.TextLayout.Item) void {
    const image = ctx.font.pages.get(item.glyph.page) orelse return;
    ctx.canvas.textureRect(
        .{
            .min = item.pos,
            .max = .{
                item.pos[0] + item.size[0],
                item.pos[1] + item.size[1],
            },
        },
        image,
        .{
            .src_area = seizer.geometry.AABB(f64).fromRect(.{ .pos = item.glyph.pos, .size = item.glyph.size }),
            .color = ctx.options.color,
        },
    );
}

const log = std.log.scoped(.Canvas);
const std = @import("std");
const seizer = @import("seizer.zig");
const zigimg = @import("zigimg");
const geometry = @import("./geometry.zig");
