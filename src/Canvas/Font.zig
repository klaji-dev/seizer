allocator: std.mem.Allocator,
pages: std.AutoHashMapUnmanaged(u32, seizer.Image),
glyphs: GlyphMap,
line_height: f64,
base: f64,
scale: [2]f64,

const AngelCodeFont = @import("AngelCodeFont");
const Font = @This();

const GlyphMap = std.AutoHashMapUnmanaged(AngelCodeFont.Glyph.Id, AngelCodeFont.Glyph);

pub const ImageFile = struct {
    name: []const u8,
    contents: []const u8,
};

pub fn fromFileContents(allocator: std.mem.Allocator, font_contents: []const u8, image_list: []const ImageFile) !@This() {
    var font_data = try AngelCodeFont.parse(allocator, font_contents);
    defer font_data.deinit();

    var image_contents = std.StringHashMapUnmanaged([]const u8){};
    defer image_contents.deinit(allocator);
    for (image_list) |image| {
        try image_contents.putNoClobber(allocator, image.name, image.contents);
    }

    var missing_image = false;

    var pages = std.AutoHashMapUnmanaged(u32, seizer.Image){};
    defer pages.deinit(allocator);
    var page_name_iterator = font_data.pages.iterator();
    while (page_name_iterator.next()) |entry| {
        const image_content = image_contents.get(entry.value_ptr.*) orelse {
            log.warn("no matching image found for \"{}\"", .{std.zig.fmtEscapes(entry.value_ptr.*)});
            missing_image = true;
            continue;
        };
        try pages.ensureUnusedCapacity(allocator, 1);
        var image = try seizer.Image.fromMemory(allocator, image_content);
        errdefer image.free(allocator);

        pages.putAssumeCapacity(entry.key_ptr.*, image);
    }

    if (missing_image) return error.MissingImage;

    return @This(){
        .allocator = allocator,
        .pages = pages.move(),
        .glyphs = font_data.glyphs.move(),
        .line_height = font_data.lineHeight,
        .base = font_data.base,
        .scale = .{ font_data.scale[0], font_data.scale[1] },
    };
}

pub fn deinit(this: *@This()) void {
    var page_iter = this.pages.valueIterator();
    while (page_iter.next()) |page| {
        page.free(this.allocator);
    }
    this.pages.deinit(this.allocator);
    this.glyphs.deinit(this.allocator);
}

pub fn textSize(this: *const @This(), text: []const u8, scale: f64) [2]f64 {
    var layout = this.textLayout(text, .{ .pos = .{ 0, 0 }, .scale = scale });
    while (layout.next()) |_| {}
    return layout.size;
}

pub fn fmtTextSize(this: *const @This(), comptime format: []const u8, args: anytype, scale: f64) [2]f64 {
    return AngelCodeFont.fmtTextSize(
        &this.glyphs,
        this.line_height,
        format,
        args,
        scale,
    );
}

pub const TextLayout = AngelCodeFont.TextLayout;
pub fn textLayout(this: *const @This(), text: []const u8, options: TextLayout.Options) TextLayout {
    return AngelCodeFont.textLayout(
        &this.glyphs,
        this.line_height,
        text,
        options,
    );
}

pub const TextLayoutWriter = AngelCodeFont.TextLayoutWriter;

const log = std.log.scoped(.seizer);

const seizer = @import("../seizer.zig");
const std = @import("std");
