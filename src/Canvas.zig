pub const Font = @import("./Canvas/Font.zig");

const Canvas = @This();

ptr: ?*anyopaque,
interface: *const Interface,

pub const Interface = struct {
    /// The size of the renderable area
    size: *const fn (?*anyopaque) [2]f64,
    blit: *const fn (?*anyopaque, pos: [2]f64, image: seizer.Image) void,
    texture_rect: *const fn (?*anyopaque, dst_pos: [2]f64, dst_size: [2]f64, image: seizer.Image, options: RectOptions) void,
    // fill_rect: *const fn (?*anyopaque, pos: [2]f64, size: [2]f64, options: RectOptions) void,
    // line: *const fn (?*anyopaque, start: [2]f64, end: [2]f64, options: LineOptions) void,
};

pub const Texture = opaque {};

pub const RectOptions = struct {
    depth: f64 = 0.5,
    color: [4]f64 = .{ 1, 1, 1, 1 },
};

pub const LineOptions = struct {
    depth: f64 = 0.5,
    width: f64 = 1,
    color: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF },
};

// Stuff that is implemented on top of the base functions

pub const TextOptions = struct {
    depth: f32 = 0.5,
    color: [4]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF },
    scale: f32 = 1,
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

/// A transformed canvas
pub const Transformed = struct {
    canvas: *Canvas,
    transform: [4][4]f32,

    pub fn rect(this: @This(), pos: [2]f32, size: [2]f32, options: RectOptions) void {
        this.canvas.addVertices(this.pipeline, this.extra_uniforms, this.transform, options.texture orelse this.canvas.blank_texture, this.scissor, &.{
            // triangle 1
            .{
                .pos = pos ++ [1]f32{options.depth},
                .uv = options.uv.min,
                .color = options.color,
            },
            .{
                .pos = .{
                    pos[0] + size[0],
                    pos[1],
                    options.depth,
                },
                .uv = .{
                    options.uv.max[0],
                    options.uv.min[1],
                },
                .color = options.color,
            },
            .{
                .pos = .{
                    pos[0],
                    pos[1] + size[1],
                    options.depth,
                },
                .uv = .{
                    options.uv.min[0],
                    options.uv.max[1],
                },
                .color = options.color,
            },

            // triangle 2
            .{
                .pos = .{
                    pos[0] + size[0],
                    pos[1] + size[1],
                    options.depth,
                },
                .uv = options.uv.max,
                .color = options.color,
            },
            .{
                .pos = .{
                    pos[0],
                    pos[1] + size[1],
                    options.depth,
                },
                .uv = .{
                    options.uv.min[0],
                    options.uv.max[1],
                },
                .color = options.color,
            },
            .{
                .pos = .{
                    pos[0] + size[0],
                    pos[1],
                    options.depth,
                },
                .uv = .{
                    options.uv.max[0],
                    options.uv.min[1],
                },
                .color = options.color,
            },
        });
    }

    pub fn writeText(this: @This(), font: *const Font, pos: [2]f32, text: []const u8, options: TextOptions) [2]f32 {
        const text_size = font.textSize(text, options.scale);

        const x: f32 = switch (options.@"align") {
            .left => pos[0],
            .center => pos[0] - text_size[0] / 2,
            .right => pos[0] - text_size[0],
        };
        const y: f32 = switch (options.baseline) {
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

    pub fn printText(this: @This(), font: *const Font, pos: [2]f32, comptime fmt: []const u8, args: anytype, options: TextOptions) [2]f32 {
        const text_size = font.fmtTextSize(fmt, args, options.scale);

        const x: f32 = switch (options.@"align") {
            .left => pos[0],
            .center => pos[0] - text_size[0] / 2,
            .right => pos[0] - text_size[0],
        };
        const y: f32 = switch (options.baseline) {
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
        pos: [2]f32 = .{ 0, 0 },
        scale: f32 = 1,
        color: [4]u8,
    };
    pub fn textLayoutWriter(this: @This(), font: *const Font, options: TextLayoutOptions) TextLayoutWriter {
        return TextLayoutWriter{
            .context = .{
                .transformed = this,
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

    const WriteGlyphContext = struct {
        transformed: Transformed,
        font: *const Font,
        options: TextLayoutOptions,
    };

    fn writeGlyph(ctx: WriteGlyphContext, item: Font.TextLayout.Item) void {
        const font_page = ctx.font.pages.get(item.glyph.page);
        const texture = if (font_page) |page| page.texture else ctx.transformed.canvas.blank_texture;
        const texture_sizef: [2]f32 = if (font_page) |page| .{ @floatFromInt(page.size[0]), @floatFromInt(page.size[1]) } else .{ 1, 1 };
        ctx.transformed.rect(
            item.pos,
            item.size,
            .{
                .texture = texture,
                .uv = .{
                    .min = .{
                        item.glyph.pos[0] / texture_sizef[0],
                        item.glyph.pos[1] / texture_sizef[1],
                    },
                    .max = .{
                        (item.glyph.pos[0] + item.glyph.size[0]) / texture_sizef[0],
                        (item.glyph.pos[1] + item.glyph.size[1]) / texture_sizef[1],
                    },
                },
                .color = ctx.options.color,
            },
        );
    }

    pub fn line(this: @This(), pos1: [2]f32, pos2: [2]f32, options: LineOptions) void {
        const half_width = options.width / 2;
        const half_length = geometry.vec.magnitude(2, f32, .{
            pos2[0] - pos1[0],
            pos2[1] - pos1[1],
        }) / 2;

        const forward = geometry.vec.normalize(2, f32, .{
            pos2[0] - pos1[0],
            pos2[1] - pos1[1],
        });
        const right = geometry.vec.normalize(2, f32, .{
            forward[1],
            -forward[0],
        });
        const midpoint = [2]f32{
            (pos1[0] + pos2[0]) / 2,
            (pos1[1] + pos2[1]) / 2,
        };

        const back_left = [2]f32{
            midpoint[0] - half_length * forward[0] - half_width * right[0],
            midpoint[1] - half_length * forward[1] - half_width * right[1],
        };
        const back_right = [2]f32{
            midpoint[0] - half_length * forward[0] + half_width * right[0],
            midpoint[1] - half_length * forward[1] + half_width * right[1],
        };
        const fore_left = [2]f32{
            midpoint[0] + half_length * forward[0] - half_width * right[0],
            midpoint[1] + half_length * forward[1] - half_width * right[1],
        };
        const fore_right = [2]f32{
            midpoint[0] + half_length * forward[0] + half_width * right[0],
            midpoint[1] + half_length * forward[1] + half_width * right[1],
        };

        this.canvas.addVertices(this.pipeline, this.extra_uniforms, this.transform, this.canvas.blank_texture, this.scissor, &.{
            .{
                .pos = back_left ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },
            .{
                .pos = fore_left ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },
            .{
                .pos = back_right ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },

            .{
                .pos = back_right ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },
            .{
                .pos = fore_left ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },
            .{
                .pos = fore_right ++ [1]f32{options.depth},
                .uv = .{ 0, 0 },
                .color = options.color,
            },
        });
    }

    pub fn transformed(this: @This(), transform: [4][4]f32) Transformed {
        return Transformed{
            .render_buffer = this.render_buffer,
            .canvas = this.canvas,
            .transform = geometry.mat4.mul(f32, this.transform, transform),
            .scissor = this.scissor,
            .pipeline = this.pipeline,
            .extra_uniforms = this.extra_uniforms,
        };
    }
};

const log = std.log.scoped(.Canvas);
const std = @import("std");
const seizer = @import("seizer.zig");
const zigimg = @import("zigimg");
const geometry = @import("./geometry.zig");
