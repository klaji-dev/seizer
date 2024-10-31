size: [2]u32,
stride: u32,
pixels: [*]Pixel,

pub const Pixel = [4]u8;

pub fn fromMemory(allocator: std.mem.Allocator, file_contents: []const u8) !@This() {
    var img = try zigimg.Image.fromMemory(allocator, file_contents);
    defer img.deinit();

    try img.convert(.rgba32);
    const pixels = try allocator.dupe([4]u8, @ptrCast(img.pixels.rgba32));

    return .{
        .size = .{ @intCast(img.width), @intCast(img.height) },
        .stride = @intCast(img.width),
        .pixels = pixels.ptr,
    };
}

pub fn free(this: @This(), allocator: std.mem.Allocator) void {
    allocator.free(this.pixels[0 .. this.size[0] * this.size[1]]);
}

pub fn fromRawPixels(pixels: []Pixel, size: [2]u32) @This() {
    std.debug.assert(pixels.len == size[0] * size[1]);
    return .{
        .size = size,
        .stride = size[0],
        .pixels = pixels.ptr,
    };
}

pub fn slice(this: @This(), offset: [2]u32, size: [2]u32) @This() {
    std.debug.assert(offset[0] <= this.size[0] and offset[1] <= this.size[1]);
    std.debug.assert(offset[0] + size[0] <= this.size[0] and offset[1] + size[1] <= this.size[1]);

    const raw_pixels = this.pixels[0 .. this.stride * this.size[1]];
    const sub_pixels = raw_pixels[offset[1] * this.stride + offset[0] ..];

    return .{
        .size = size,
        .stride = this.stride,
        .pixels = sub_pixels.ptr,
    };
}

pub fn copy(dest: @This(), src: @This()) void {
    std.debug.assert(dest.size[0] == src.size[0] and dest.size[1] == src.size[1]);

    for (0..dest.size[1]) |y| {
        const dest_row = dest.pixels[y * dest.stride ..][0..dest.size[0]];
        const src_row = src.pixels[y * src.stride ..][0..src.size[0]];
        @memcpy(dest_row, src_row);
    }
}

pub fn composite(dst: @This(), src: @This()) void {
    std.debug.assert(dst.size[0] == src.size[0] and dst.size[1] == src.size[1]);

    for (0..dst.size[1]) |y| {
        const dst_row = dst.pixels[y * dst.stride ..][0..dst.size[0]];
        const src_row = src.pixels[y * src.stride ..][0..src.size[0]];
        for (dst_row, src_row) |*dst_pixel, src_pixel| {
            dst_pixel.* = seizer.color.compositeAOverB(
                src_pixel,
                dst_pixel.*,
            );
        }
    }
}

pub fn drawFillRect(this: @This(), a: [2]i32, b: [2]i32, color: [4]u8) void {
    const size_i = [2]i32{ @intCast(this.size[0]), @intCast(this.size[1]) };
    const min = [2]u32{
        @intCast(std.math.clamp(@min(a[0], b[0]), 0, size_i[0])),
        @intCast(std.math.clamp(@min(a[1], b[1]), 0, size_i[1])),
    };
    const max = [2]u32{
        @intCast(std.math.clamp(@max(a[0], b[0]), 0, size_i[0])),
        @intCast(std.math.clamp(@max(a[1], b[1]), 0, size_i[1])),
    };

    var row: u32 = @intCast(min[1]);
    while (row < max[1]) : (row += 1) {
        const start_of_row: u32 = @intCast(row * this.stride);
        const row_buffer = this.pixels[start_of_row..][min[0]..max[0]];
        @memset(row_buffer, color);
    }
}

pub fn drawLine(this: @This(), a: [2]i32, b: [2]i32, color: [4]u8) void {
    if (a[0] == b[0]) {
        var y = @min(a[1], b[1]);
        const end_y = @max(a[1], b[1]);
        while (y <= end_y) : (y += 1) {
            this.setPixel(.{ a[0], y }, color);
        }
        return;
    } else if (a[1] == b[1]) {
        if (a[1] < 0 or a[1] >= this.size[1]) {
            return;
        }
        const size_i = [2]i32{ @intCast(this.size[0]), @intCast(this.size[1]) };
        const x_min: u32 = @intCast(std.math.clamp(@min(a[0], b[0]), 0, size_i[0]));
        const x_max: u32 = @intCast(std.math.clamp(@max(a[0], b[0]) + 1, 0, size_i[0]));
        const y: u32 = @intCast(a[1]);

        const start_of_row: u32 = @intCast(y * this.stride);
        const row_buffer = this.pixels[start_of_row..][x_min..x_max];
        @memset(row_buffer, color);

        return;
    }

    const delta = [2]i32{
        @intCast(@abs(b[0] - a[0])),
        -@as(i32, @intCast(@abs(b[1] - a[1]))),
    };
    const sign = [2]i32{
        std.math.sign(b[0] - a[0]),
        std.math.sign(b[1] - a[1]),
    };

    var err = delta[0] + delta[1];
    var pos = a;
    while (true) {
        this.setPixel(pos, color);
        if (pos[0] == b[0] and pos[1] == b[1]) break;
        const err2 = 2 * err;
        if (err2 >= delta[1]) {
            err += delta[1];
            pos[0] += sign[0];
        }
        if (err2 <= delta[0]) {
            err += delta[0];
            pos[1] += sign[1];
        }
    }
}

pub fn setPixel(this: @This(), pos: [2]i32, color: Pixel) void {
    if (pos[0] < 0 or pos[0] >= this.size[0]) return;
    if (pos[1] < 0 or pos[1] >= this.size[1]) return;
    const posu = [2]u32{ @intCast(pos[0]), @intCast(pos[1]) };
    this.pixels[@intCast(posu[1] * this.stride + posu[0])] = color;
}

pub fn getPixel(this: @This(), pos: [2]i32) Pixel {
    std.debug.assert(pos[0] >= 0 or pos[0] < this.size[0]);
    std.debug.assert(pos[1] >= 0 or pos[1] < this.size[1]);
    const posu = [2]u32{ @intCast(pos[0]), @intCast(pos[1]) };
    return this.pixels[@intCast(posu[1] * this.stride + posu[0])];
}

const std = @import("std");
const seizer = @import("./seizer.zig");
const zigimg = @import("zigimg");
