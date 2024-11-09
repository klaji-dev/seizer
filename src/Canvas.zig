pub const Font = @import("./Canvas/Font.zig");
pub const Transformed = @import("./Canvas/Transformed.zig");

const Canvas = @This();

ptr: ?*anyopaque,
interface: *const Interface,

pub const Interface = struct {
    /// The size of the renderable area
    size: *const fn (?*anyopaque) [2]f64,
    clear: *const fn (?*anyopaque, seizer.color.argbf32_premultiplied) void,
    blit: *const fn (?*anyopaque, pos: [2]f64, image: seizer.image.Slice(seizer.color.argbf32_premultiplied)) void,
    texture_rect: *const fn (?*anyopaque, dst_area: geometry.AABB(f64), image: seizer.image.Slice(seizer.color.argbf32_premultiplied), options: TextureRectOptions) void,
    fill_rect: *const fn (?*anyopaque, area: geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: FillRectOptions) void,
    line: *const fn (?*anyopaque, start: [2]f64, end: [2]f64, options: LineOptions) void,
};

pub fn size(this: @This()) [2]f64 {
    return this.interface.size(this.ptr);
}

pub fn clear(this: @This(), color: seizer.color.argbf32_premultiplied) void {
    return this.interface.clear(this.ptr, color);
}

pub fn blit(this: @This(), pos: [2]f64, image: seizer.image.Slice(seizer.color.argbf32_premultiplied)) void {
    return this.interface.blit(this.ptr, pos, image);
}

pub const TextureRectOptions = struct {
    depth: f64 = 0.5,
    color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
    src_area: ?geometry.AABB(f64) = null,
};

pub fn textureRect(this: @This(), dst_rect: geometry.AABB(f64), image: seizer.image.Slice(seizer.color.argbf32_premultiplied), options: TextureRectOptions) void {
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
    image: seizer.image.Slice(seizer.color.argbf32_premultiplied),
    inset: seizer.geometry.Inset(f64),

    pub const Options = struct {
        depth: f64 = 0.5,
        color: seizer.color.argbf32_premultiplied = seizer.color.argbf32_premultiplied.WHITE,
        scale: f64 = 1,
    };

    pub fn init(image: seizer.image.Slice(seizer.color.argbf32_premultiplied), inset: seizer.geometry.Inset(f64)) NinePatch {
        return .{ .image = image, .inset = inset };
    }

    pub fn images(this: @This()) [9]seizer.image.Slice(seizer.color.argbf32_premultiplied) {
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

pub fn ninePatch(this: @This(), area: geometry.AABB(f64), image: seizer.image.Slice(seizer.color.argbf32_premultiplied), inset: geometry.Inset(f64), options: NinePatch.Options) void {
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
        image.slice(.{ 0, 0 }, image.size),
        .{
            .src_area = seizer.geometry.AABB(f64).fromRect(.{ .pos = item.glyph.pos, .size = item.glyph.size }),
            .color = ctx.options.color,
        },
    );
}

pub const RenderCache = struct {
    // Cached software rendering
    command: std.MultiArrayList(Command),
    command_hash: std.ArrayListUnmanaged(std.hash.Fnv1a_32),
    command_hash_prev: std.ArrayListUnmanaged(std.hash.Fnv1a_32),

    pub fn init(allocator: std.mem.Allocator) @This() {
        var this = @This(){
            .command = .{},
            .command_hash = .{},
            .command_hash_prev = .{},
        };
        try this.command.ensureTotalCapacity(allocator, 1024);
        try this.command_hash.ensureTotalCapacity(allocator, 2048); // enough room for 4k stuff
        try this.command_hash_prev.ensureTotalCapacity(allocator, 2048); // enough room for 4k stuff
        return this;
    }

    const CANVAS_INTERFACE: *const seizer.Canvas.Interface = &.{
        .size = canvas_size,
        .clear = canvas_clear,
        .blit = canvas_blit,
        .texture_rect = canvas_textureRect,
        .fill_rect = canvas_fillRect,
        .line = canvas_line,
    };

    const Command = struct {
        tag: Tag,
        renderRect: seizer.geometry.AABB(u32),
        renderData: Data,

        const Tag = enum {
            blit,
            line,
            rect_texture,
            rect_fill,
            rect_clear,

            // TODO: Implement these commands
            rect_stroke,
            rect_fill_stroke,
        };

        const Data = union {
            blit: struct {
                pos: [2]f64,
                src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied),
            },
            line: struct {
                point: [2][2]f32,
                color: [2]seizer.color.argbf32_premultiplied,
                radii: [2]f32,
            },
            rect_texture: struct {
                dst_area: seizer.geometry.AABB(f64),
                src_area: seizer.geometry.AABB(f64),
                src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied),
                color: seizer.color.argbf32_premultiplied,
            },
            rect_fill: struct {
                area: seizer.geometry.AABB(f64),
                color: seizer.color.argbf32_premultiplied,
            },
            rect_clear: struct {
                area: seizer.geometry.AABB(u32),
                color: seizer.color.argbf32_premultiplied,
            },

            // TODO: Implement these commands
            // rect_stroke,
            // rect_fill_stroke,

            pub fn asBytes(this: *const @This(), tag: Tag) []const u8 {
                return switch (tag) {
                    .blit => std.mem.asBytes(&this.blit),
                    .line => std.mem.asBytes(&this.line),
                    .rect_texture => std.mem.asBytes(&this.rect_texture),
                    .rect_fill => std.mem.asBytes(&this.rect_fill),
                    .rect_clear => std.mem.asBytes(&this.rect_clear),

                    // TODO: Implement these commands
                    .rect_stroke,
                    .rect_fill_stroke,
                    => unreachable,
                };
            }
        };
    };

    pub fn canvas_size(this_opaque: ?*anyopaque) [2]f64 {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));
        return .{ @floatFromInt(this.current_configuration.window_size[0]), @floatFromInt(this.current_configuration.window_size[1]) };
    }

    pub fn canvas_clear(this_opaque: ?*anyopaque, color: seizer.color.argbf32_premultiplied) void {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));
        const area = seizer.geometry.AABB(u32){ .min = .{ 0, 0 }, .max = this.current_configuration.window_size };

        const index = this.command.addOneAssumeCapacity();

        const slice = this.command.slice();
        slice.items(.tag)[index] = .rect_clear;
        slice.items(.renderRect)[index] = area;

        slice.items(.renderData)[index] = .{ .rect_clear = .{ .area = area, .color = color } };
    }

    pub fn canvas_blit(this_opaque: ?*anyopaque, pos: [2]f64, src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied)) void {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));
        var rect = seizer.geometry.Rect(f64){ .pos = pos, .size = seizer.geometry.vec.into(f64, src_image.size) };
        rect = rect.translate(pos);
        this.command.appendAssumeCapacity(.{
            .tag = .blit,
            .renderRect = rect.toAABB().into(u32),
            .renderData = .{ .blit = .{ .pos = pos, .src_image = src_image } },
        });
    }

    pub fn canvas_fillRect(this_opaque: ?*anyopaque, area: seizer.geometry.AABB(f64), color: seizer.color.argbf32_premultiplied, options: seizer.Canvas.FillRectOptions) void {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));
        _ = options;

        std.debug.assert(area.min[0] < area.max[0]);
        std.debug.assert(area.min[1] < area.max[1]);

        const canvas_clip = seizer.geometry.AABB(f64){ .min = .{ 0, 0 }, .max = .{
            @floatFromInt(this.current_configuration.window_size[0] - 1),
            @floatFromInt(this.current_configuration.window_size[1] - 1),
        } };

        this.command.appendAssumeCapacity(.{
            .tag = .rect_fill,
            .renderRect = area.clamp(canvas_clip).into(u32),
            .renderData = .{ .rect_fill = .{
                .area = area.clamp(canvas_clip),
                .color = color,
            } },
        });
    }

    pub fn canvas_textureRect(this_opaque: ?*anyopaque, dst_area: seizer.geometry.AABB(f64), src_image: seizer.image.Slice(seizer.color.argbf32_premultiplied), options: seizer.Canvas.TextureRectOptions) void {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));

        const canvas_clip = seizer.geometry.AABB(f64){ .min = .{ 0, 0 }, .max = .{
            @floatFromInt(this.current_configuration.window_size[0] - 1),
            @floatFromInt(this.current_configuration.window_size[1] - 1),
        } };

        var render_rect = dst_area.clamp(canvas_clip).into(u32);
        render_rect.min[0] -|= 1;
        render_rect.min[1] -|= 1;
        render_rect.max[0] +|= 1;
        render_rect.max[1] +|= 1;

        this.command.appendAssumeCapacity(.{
            .tag = .rect_texture,
            .renderRect = render_rect,
            .renderData = .{ .rect_texture = .{
                .dst_area = dst_area,
                .src_area = options.src_area orelse .{
                    .min = .{ 0, 0 },
                    .max = .{ @floatFromInt(src_image.size[0] - 1), @floatFromInt(src_image.size[1] - 1) },
                },
                .src_image = src_image,
                .color = options.color,
            } },
        });
    }

    pub fn canvas_line(this_opaque: ?*anyopaque, start: [2]f64, end: [2]f64, options: seizer.Canvas.LineOptions) void {
        const this: *@This() = @ptrCast(@alignCast(this_opaque));

        const start_f = seizer.geometry.vec.into(f32, start);
        const end_f = seizer.geometry.vec.into(f32, end);
        const end_color = options.end_color orelse options.color;
        const width: f32 = @floatCast(options.width);
        const end_width: f32 = @floatCast(options.end_width orelse width);

        const canvas_clip = seizer.geometry.AABB(u32){ .min = .{ 0, 0 }, .max = .{
            this.current_configuration.window_size[0] - 1,
            this.current_configuration.window_size[1] - 1,
        } };
        const rmax = @max(width, end_width);
        const area_line = seizer.geometry.AABB(f32).init(.{ .{
            @floor(@min(start_f[0], end_f[0]) - rmax),
            @floor(@min(start_f[1], end_f[1]) - rmax),
        }, .{
            @ceil(@max(start_f[0], end_f[0]) + rmax),
            @ceil(@max(start_f[1], end_f[1]) + rmax),
        } });
        const clipped = area_line.clamp(canvas_clip.into(f32)).into(u32);

        this.command.appendAssumeCapacity(.{
            .tag = .line,
            .renderRect = clipped,
            .renderData = .{
                .line = .{
                    .point = .{ start_f, end_f },
                    .color = .{ options.color, end_color },
                    .radii = .{ width, end_width },
                },
            },
        });
    }

    const binning_size = 64;
    const bin_aabb = seizer.geometry.AABB(u32).init(.{ .{ 0, 0 }, .{ binning_size - 1, binning_size - 1 } });

    fn executeCanvasCommands(this: *@This()) !void {
        const allocator = this.display.allocator;
        const window_size = this.current_configuration.window_size;
        const bin_count = .{
            @divFloor(window_size[0], binning_size) + 1,
            @divFloor(window_size[1], binning_size) + 1,
        };
        try this.command_hash.resize(allocator, bin_count[0] * bin_count[1]);

        for (this.command_hash.items) |*h| {
            h.* = std.hash.Fnv1a_32.init();
        }

        const command = this.command.slice();

        for (command.items(.tag), command.items(.renderRect), command.items(.renderData)) |tag, rect, data| {
            // Compute hash of the render command
            var hash = std.hash.Fnv1a_32.init();
            hash.update(std.mem.asBytes(&tag));
            hash.update(data.asBytes(tag));
            const h = hash.final();

            const update_x_start: usize = rect.min[0] / binning_size;
            const update_y_start: usize = rect.min[1] / binning_size;
            const update_x_end: usize = @min(bin_count[0], (rect.max[0] / binning_size) + 1);
            const update_y_end: usize = @min(bin_count[1], (rect.max[1] / binning_size) + 1);

            for (update_y_start..update_y_end) |y| {
                for (update_x_start..update_x_end) |x| {
                    this.command_hash.items[x + y * bin_count[0]].update(std.mem.asBytes(&h));
                }
            }
        }

        const canvas_clip = seizer.geometry.AABB(u32){
            .min = .{ 0, 0 },
            .max = .{ this.current_configuration.window_size[0] - 1, this.current_configuration.window_size[1] - 1 },
        };
        if (this.command_hash.items.len == this.command_hash_prev.items.len) {
            // See if the we can skip rendering
            for (this.command_hash.items, this.command_hash_prev.items, 0..) |*h, *hp, i| {
                if (h.final() != hp.final()) {
                    const bin_x = i % bin_count[0];
                    const bin_y = i / bin_count[0];
                    const px_pos = [2]u32{
                        @intCast(bin_x * binning_size),
                        @intCast(bin_y * binning_size),
                    };

                    const clip = bin_aabb.translate(px_pos).clamp(canvas_clip);
                    // Hash mismatch! This bin needs to be updated
                    for (command.items(.tag), command.items(.renderData)) |tag, data| {
                        this.executeCanvasCommand(tag, data, clip);
                    }
                }
            }
        } else {
            for (command.items(.tag), command.items(.renderData)) |tag, data| {
                this.executeCanvasCommand(tag, data, canvas_clip);
            }
        }

        // Swap the memory used for current and previous hash lists
        std.mem.swap(std.ArrayListUnmanaged(std.hash.Fnv1a_32), &this.command_hash_prev, &this.command_hash);

        this.command.shrinkRetainingCapacity(0);
    }

    fn executeCanvasCommand(this: *@This(), tag: Command.Tag, data: Command.Data, clip: seizer.geometry.AABB(u32)) void {
        switch (tag) {
            .blit => {
                const pos = data.blit.pos;
                const src_image = data.blit.src_image;
                const pos_i = [2]i32{
                    @intFromFloat(@floor(pos[0])),
                    @intFromFloat(@floor(pos[1])),
                };
                const size_i = [2]i32{
                    @intCast(this.current_configuration.window_size[0]),
                    @intCast(this.current_configuration.window_size[1]),
                };

                if (pos_i[0] + size_i[0] <= 0 or pos_i[1] + size_i[1] <= 0) return;
                if (pos_i[0] >= size_i[0] or pos_i[1] >= size_i[1]) return;

                const src_size = [2]u32{
                    @min(src_image.size[0], @as(u32, @intCast(size_i[0] - pos_i[0]))),
                    @min(src_image.size[1], @as(u32, @intCast(size_i[1] - pos_i[1]))),
                };

                const src_offset = [2]u32{
                    if (pos_i[0] < 0) @intCast(-pos_i[0]) else 0,
                    if (pos_i[1] < 0) @intCast(-pos_i[1]) else 0,
                };
                const dest_offset = [2]u32{
                    @intCast(@max(pos_i[0], 0)),
                    @intCast(@max(pos_i[1], 0)),
                };
                const dest_end = [2]u32{
                    dest_offset[0] + src_size[0] - 1,
                    dest_offset[1] + src_size[1] - 1,
                };

                const src = src_image.slice(src_offset, src_size);

                this.framebuffer.compositeLinear(.{ .min = dest_offset, .max = dest_end }, src);
            },
            .line => {
                const start = data.line.point[0];
                const end = data.line.point[1];
                const radii = data.line.radii;
                const color = data.line.color;

                this.framebuffer.drawLine(clip, start, end, radii, color);
            },
            .rect_texture => {
                const dst_area = data.rect_texture.dst_area;
                const src_area = data.rect_texture.src_area;
                const src_image = data.rect_texture.src_image;
                const color = data.rect_texture.color;

                std.debug.assert(dst_area.sizePlusEpsilon()[0] >= 0 and dst_area.sizePlusEpsilon()[1] >= 0);

                const dst_area_clamped = dst_area.clamp(clip.into(f64));

                const Sampler = struct {
                    texture: seizer.image.Slice(seizer.color.argbf32_premultiplied),
                    tint: seizer.color.argbf32_premultiplied,

                    pub fn sample(sampler: *const @This(), pos: [2]f64) seizer.color.argbf32_premultiplied {
                        const src_pixel = sampler.texture.getPixel(.{
                            @min(@as(u32, @intFromFloat(@max(pos[0], 0))), sampler.texture.size[0] - 1),
                            @min(@as(u32, @intFromFloat(@max(pos[1], 0))), sampler.texture.size[1] - 1),
                        });
                        return src_pixel.tint(sampler.tint);
                    }
                };

                this.framebuffer.compositeSampler(
                    dst_area_clamped.into(u32),
                    f64,
                    src_area.inset(.{
                        .min = .{
                            ((dst_area_clamped.min[0] - dst_area.min[0]) / dst_area.size()[0]) * src_area.size()[0],
                            ((dst_area_clamped.min[1] - dst_area.min[1]) / dst_area.size()[1]) * src_area.size()[1],
                        },
                        .max = .{
                            ((dst_area.max[0] - dst_area_clamped.max[0]) / dst_area.size()[0]) * src_area.size()[0],
                            ((dst_area.max[1] - dst_area_clamped.max[1]) / dst_area.size()[1]) * src_area.size()[1],
                        },
                    }),
                    *const Sampler,
                    Sampler.sample,
                    &.{
                        .texture = src_image,
                        .tint = color,
                    },
                );
            },
            .rect_fill => {
                const area = data.rect_fill.area;
                const color = data.rect_fill.color;

                this.framebuffer.drawFillRect(area.into(u32), color);
            },
            .rect_clear => {
                const d = data.rect_clear;
                this.framebuffer.set(d.area.clamp(clip), d.color);
            },
            .rect_stroke => {
                // TODO
            },
            .rect_fill_stroke => {
                // TODO
            },
        }
    }
};

const log = std.log.scoped(.Canvas);
const std = @import("std");
const seizer = @import("seizer.zig");
const zigimg = @import("zigimg");
const geometry = @import("./geometry.zig");
