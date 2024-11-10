pub fn Linear(Pixel: type) type {
    return struct {
        pixels: [*]Pixel,
        size: [2]u32,

        pub fn alloc(allocator: std.mem.Allocator, size: [2]u32) !@This() {
            const pixels = try allocator.alloc(Pixel, size[0] * size[1]);
            errdefer allocator.free(pixels);

            return .{
                .size = size,
                .pixels = pixels.ptr,
            };
        }

        pub fn clear(this: @This(), pixel: Pixel) void {
            @memset(this.pixels[0 .. this.size[0] * this.size[1]], pixel);
        }

        pub fn fromMemory(allocator: std.mem.Allocator, file_contents: []const u8) !@This() {
            var img = try zigimg.Image.fromMemory(allocator, file_contents);
            defer img.deinit();

            // TODO: Unfuck this. We don't know what the color space is, as zigimg doesn't tell us. Changes will have to be made in zigimg to support this.
            try img.convert(.rgba32);

            const pixels = try allocator.alloc(Pixel, img.pixels.rgba32.len);

            // pre-multiply the image
            for (pixels, img.pixels.rgba32) |*out, in| {
                out.* = (seizer.color.argb(seizer.color.sRGB8, .straight, u8){
                    .b = @enumFromInt(in.b),
                    .g = @enumFromInt(in.g),
                    .r = @enumFromInt(in.r),
                    .a = in.a,
                }).convertColorTo(f32).convertAlphaTo(f32).convertAlphaModelTo(.premultiplied);
            }

            return .{
                .size = .{ @intCast(img.width), @intCast(img.height) },
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

        pub fn slice(this: @This(), offset: [2]u32, size: [2]u32) Slice(Pixel) {
            std.debug.assert(offset[0] <= this.size[0] and offset[1] <= this.size[1]);
            std.debug.assert(offset[0] + size[0] <= this.size[0] and offset[1] + size[1] <= this.size[1]);

            const raw_pixels = this.pixels[0 .. this.size[0] * this.size[1]];
            const sub_pixels = raw_pixels[offset[1] * this.size[0] + offset[0] ..];

            return .{
                .size = size,
                .stride = this.size[0],
                .pixels = sub_pixels.ptr,
            };
        }

        pub fn asSlice(this: @This()) Slice(Pixel) {
            return .{
                .pixels = this.pixels,
                .size = this.size,
                .stride = this.size[0],
            };
        }

        pub fn setPixel(this: @This(), pos: [2]u32, color: Pixel) void {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            this.pixels[pos[1] * this.size[0] + pos[0]] = color;
        }

        pub fn getPixel(this: @This(), pos: [2]u32) Pixel {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            return this.pixels[pos[1] * this.size[0] + pos[0]];
        }
    };
}

pub fn Slice(Pixel: type) type {
    return struct {
        pixels: [*]Pixel,
        size: [2]u32,
        stride: u32,

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
                for (dst_row, src_row) |*dst_argb, src_argb| {
                    dst_argb.* = Pixel.compositeSrcOver(dst_argb.*, src_argb);
                }
            }
        }

        pub fn compositeSampler(
            dst: @This(),
            F: type,
            src_area: seizer.geometry.AABB(F),
            comptime SamplerContext: type,
            comptime sample_fn: fn (SamplerContext, pos: [2]F) Pixel,
            sampler_context: SamplerContext,
        ) void {
            const sample_stride = [2]F{
                (src_area.size()[0]) / @as(F, @floatFromInt(dst.size[0] - 1)),
                (src_area.size()[1]) / @as(F, @floatFromInt(dst.size[1] - 1)),
            };
            var sample_pos: [2]F = src_area.min();
            for (0..dst.size[1]) |y| {
                sample_pos[0] = src_area.min()[0];

                const dst_row = dst.pixels[y * dst.stride ..][0..dst.size[0]];
                for (dst_row) |*dst_argb| {
                    dst_argb.* = Pixel.compositeSrcOver(dst_argb.*, sample_fn(sampler_context, sample_pos));

                    sample_pos[0] += sample_stride[0];
                }

                sample_pos[1] += sample_stride[1];
            }
        }

        test compositeSampler {
            var linear = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, .{ 5, 5 });
            defer linear.free(std.testing.allocator);
            const dst_slice = linear.slice(.{ 0, 0 }, linear.size);

            const RGGradientSampler = struct {
                pub fn sample(this: @This(), pos: [2]f64) seizer.color.argbf32_premultiplied {
                    _ = this;
                    return seizer.color.argbf32_premultiplied.init(
                        0,
                        @floatCast(pos[1]),
                        @floatCast(pos[0]),
                        1,
                    );
                }
            };
            dst_slice.compositeSampler(f64, geometry.AABB(f64).init(.{ 0, 0 }, .{ 1, 1 }), RGGradientSampler, RGGradientSampler.sample, .{});

            const ARGB = seizer.color.argbf32_premultiplied;
            var expected_buffer = [5][5]seizer.color.argbf32_premultiplied{
                .{ ARGB.init(0, 0.00, 0.00, 1), ARGB.init(0, 0.00, 0.25, 1), ARGB.init(0, 0.00, 0.50, 1), ARGB.init(0, 0.00, 0.75, 1), ARGB.init(0, 0.00, 1.00, 1) },
                .{ ARGB.init(0, 0.25, 0.00, 1), ARGB.init(0, 0.25, 0.25, 1), ARGB.init(0, 0.25, 0.50, 1), ARGB.init(0, 0.25, 0.75, 1), ARGB.init(0, 0.25, 1.00, 1) },
                .{ ARGB.init(0, 0.50, 0.00, 1), ARGB.init(0, 0.50, 0.25, 1), ARGB.init(0, 0.50, 0.50, 1), ARGB.init(0, 0.50, 0.75, 1), ARGB.init(0, 0.50, 1.00, 1) },
                .{ ARGB.init(0, 0.75, 0.00, 1), ARGB.init(0, 0.75, 0.25, 1), ARGB.init(0, 0.75, 0.50, 1), ARGB.init(0, 0.75, 0.75, 1), ARGB.init(0, 0.75, 1.00, 1) },
                .{ ARGB.init(0, 1.00, 0.00, 1), ARGB.init(0, 1.00, 0.25, 1), ARGB.init(0, 1.00, 0.50, 1), ARGB.init(0, 1.00, 0.75, 1), ARGB.init(0, 1.00, 1.00, 1) },
            };
            const expected_image = Linear(seizer.color.argbf32_premultiplied){
                .pixels = expected_buffer[0][0..],
                .size = .{ expected_buffer[0].len, expected_buffer.len },
            };

            try expectEqualImageSections(geometry.UAABB(u32).init(.{ 0, 0 }, .{ 4, 4 }), expected_image, linear);
        }

        pub fn drawFillRect(this: @This(), a: [2]i32, b: [2]i32, color: Pixel) void {
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
                for (row_buffer) |*pixel| {
                    pixel.* = pixel.*.compositeSrcOver(color);
                }
            }
        }

        /// Returns the signed distance to a line segment
        fn capsuleSDF(p: [2]f32, a: [2]f32, b: [2]f32, r: [2]f32) struct { f32, f32 } {
            const pax = p[0] - a[0];
            const pay = p[1] - a[1];
            const bax = b[0] - a[0];
            const bay = b[1] - a[1];
            const h = std.math.clamp((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1);
            const dx = pax - bax * h;
            const dy = pay - bay * h;
            const rh = std.math.lerp(r[0], r[1], h);
            return .{ @sqrt(dx * dx + dy * dy) - rh, h };
        }

        pub fn drawLine(this: @This(), clip: geometry.UAABB(u32), a: [2]f32, b: [2]f32, r: [2]f32, colors: [2]Pixel) void {
            const rmax = @max(r[0], r[1]);

            const area_line = seizer.geometry.AABB(f32).init(.{ .{
                @floor(@min(a[0], b[0]) - rmax),
                @floor(@min(a[1], b[1]) - rmax),
            }, .{
                @ceil(@max(a[0], b[0]) + rmax),
                @ceil(@max(a[1], b[1]) + rmax),
            } });

            const overlapf = area_line.clamp(clip.into(f32));
            const overlap = overlapf.into(u32);

            for (overlap.min[1]..overlap.max[1]) |y| {
                for (overlap.min[0]..overlap.max[0]) |x| {
                    const capsule, const h = capsuleSDF(.{ @floatFromInt(x), @floatFromInt(y) }, a, b, r);
                    const color = colors[0].blend(colors[1], h);
                    const bg = this.getPixel(.{ @intCast(x), @intCast(y) });
                    const dist = std.math.clamp(0.5 - capsule, 0, 1);
                    const blended = bg.blend(color, dist);
                    this.setPixel(.{ @intCast(x), @intCast(y) }, blended);
                }
            }
        }

        pub fn setPixel(this: @This(), pos: [2]u32, color: Pixel) void {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            this.pixels[pos[1] * this.stride + pos[0]] = color;
        }

        pub fn getPixel(this: @This(), pos: [2]u32) Pixel {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            return this.pixels[pos[1] * this.stride + pos[0]];
        }

        pub fn resize(dst: @This(), src: @This()) void {
            const dst_size = [2]f32{
                @floatFromInt(dst.size[0]),
                @floatFromInt(dst.size[1]),
            };

            const src_size = [2]f32{
                @floatFromInt(src.size[0]),
                @floatFromInt(src.size[1]),
            };

            for (0..dst.size[1]) |dst_y| {
                for (0..dst.size[0]) |dst_x| {
                    const uv = [2]f32{
                        @as(f32, @floatFromInt(dst_x)) / dst_size[0],
                        @as(f32, @floatFromInt(dst_y)) / dst_size[1],
                    };
                    const src_pos = [2]f32{
                        uv[0] * src_size[0] - 0.5,
                        uv[1] * src_size[1] - 0.5,
                    };
                    const src_columnf = @floor(src_pos[0]);
                    const col_indices = [4]f32{
                        @floor(src_columnf - 1),
                        @floor(src_columnf - 0),
                        @floor(src_columnf + 1),
                        @floor(src_columnf + 2),
                    };
                    const src_rowf = @floor(src_pos[1]);
                    const row_indices = [4]f32{
                        @floor(src_rowf - 1),
                        @floor(src_rowf - 0),
                        @floor(src_rowf + 1),
                        @floor(src_rowf + 2),
                    };

                    const kernel_x: @Vector(4, f32) = .{
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[0] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[1] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[2] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[3] - src_pos[0]),
                    };
                    const kernel_y: @Vector(4, f32) = .{
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[0] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[1] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[2] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[3] - src_pos[1]),
                    };

                    var row_interpolations: [4][4]f32 = undefined;
                    for (0..4, row_indices) |interpolation_idx, row_idxf| {
                        // TODO: set out of bounds pixels to transparent instead of repeating row
                        const row_idx: u32 = @intFromFloat(std.math.clamp(row_idxf, 0, src_size[1] - 1));
                        // transpose so we can multiply by each color channel separately
                        const src_row_pixels = seizer.geometry.mat.transpose(4, 4, f32, [4][4]f32{
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[0], 0, src_size[0] - 1)), row_idx }).toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[1], 0, src_size[0] - 1)), row_idx }).toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[2], 0, src_size[0] - 1)), row_idx }).toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[3], 0, src_size[0] - 1)), row_idx }).toArray(),
                        });

                        for (0..4, src_row_pixels[0..4]) |interpolation_channel, channel| {
                            const channel_v: @Vector(4, f32) = channel;
                            row_interpolations[interpolation_channel][interpolation_idx] = @reduce(.Add, kernel_x * channel_v);
                        }
                    }

                    var out_pixel: [4]f32 = undefined;

                    for (out_pixel[0..], row_interpolations[0..]) |*out_channel, channel| {
                        const channel_v: @Vector(4, f32) = channel;
                        out_channel.* = std.math.clamp(@reduce(.Add, kernel_y * channel_v), 0, 1);
                    }

                    dst.setPixel(.{ @intCast(dst_x), @intCast(dst_y) }, seizer.color.argbf32_premultiplied.fromArray(out_pixel));
                }
            }
        }

        // Returns the amount a sample should influence the output result
        pub fn cubicFilter(B: f32, C: f32, x: f32) f32 {
            const x1 = @abs(x);
            const x2 = @abs(x) * @abs(x);
            const x3 = @abs(x) * @abs(x) * @abs(x);

            if (x1 < 1.0) {
                return ((12.0 - 9.0 * B - 6.0 * C) * x3 + (-18.0 + 12.0 * B + 6.0 * C) * x2 + (6.0 - 2.0 * B)) / 6.0;
            } else if (x1 < 2.0) {
                return ((-B - 6.0 * C) * x3 + (6.0 * B + 30.0 * C) * x2 + (-12.0 * B - 48.0 * C) * x1 + (8.0 * B + 24.0 * C)) / 6.0;
            } else {
                return 0;
            }
        }
    };
}

pub const TVG = struct {
    header: seizer.tvg.parsing.Header,
    source: []const u8,
    scratch_buffer: []u8,

    pub fn size(this: @This()) [2]u32 {
        return .{ this.header.width, this.header.height };
    }

    pub fn fromMemory(allocator: std.mem.Allocator, source: []const u8) !TVG {
        var stream = std.io.fixedBufferStream(source);
        var parser = try seizer.tvg.parse(allocator, stream.reader());
        defer parser.deinit();

        var temp_buffer_size: usize = 0;

        while (try parser.next()) |cmd| {
            _ = cmd;
            temp_buffer_size = @max(parser.temp_buffer.capacity, temp_buffer_size);
        }

        std.log.debug("max buffer size {}", .{temp_buffer_size});
        const align_size = std.mem.alignAllocLen(std.math.maxInt(u32), temp_buffer_size, 16);
        const scratch_buffer = try allocator.alloc(u8, align_size);

        return .{
            .header = parser.header,
            .scratch_buffer = scratch_buffer,
            .source = source,
        };
    }

    pub fn deinit(tvg: *const TVG, allocator: std.mem.Allocator) void {
        allocator.free(tvg.scratch_buffer);
    }

    pub const RasterizeOptions = struct {
        // TODO: Implement scaling
        // scaling: usize = 1,
        // TODO: Implement anti-aliasing
        // anti_aliasing: usize,
        /// Used for temporarily storing data while rendering
        temporary_allocator: ?std.mem.Allocator = null,
    };
    pub fn rasterize(tvg: *const TVG, destination: *Linear(seizer.color.argbf32_premultiplied), options: RasterizeOptions) !void {
        const framebuffer = Framebuffer.init(destination);

        var stream = std.io.fixedBufferStream(tvg.source);
        var fba = std.heap.FixedBufferAllocator.init(tvg.scratch_buffer);

        var parser = seizer.tvg.parse(fba.allocator(), stream.reader()) catch unreachable;
        defer parser.deinit();

        while (parser.next() catch unreachable) |cmd| {
            try seizer.tvg.rendering.renderCommand(&framebuffer, tvg.header, parser.color_table, cmd, options.temporary_allocator);
            fba.reset();
        }
    }

    /// Implements a type compatible with the TinyVG `Framebuffer` interface.
    pub const Framebuffer = struct {
        image: *Linear(seizer.color.argbf32_premultiplied),

        // Fields expected by TVG renderer
        width: usize,
        height: usize,

        pub fn init(framebuffer: *Linear(seizer.color.argbf32_premultiplied)) Framebuffer {
            return .{
                .image = framebuffer,
                .width = framebuffer.size[0],
                .height = framebuffer.size[1],
            };
        }

        pub fn setPixel(self: *const @This(), x: isize, y: isize, src_color: seizer.tvg.Color) void {
            if (x < 0 or y < 0 or x > self.width or y > self.height) return;
            const argb = seizer.color.argb(f32, .straight, f32);
            const color = argb.fromArray(.{ src_color.b, src_color.g, src_color.r, src_color.a });
            const dest_color = color.convertAlphaModelTo(.premultiplied);
            self.image.setPixel(.{ @intCast(x), @intCast(y) }, dest_color);
        }
    };
};

pub fn Tiled(comptime tile_size: [2]u8, Pixel: type) type {
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
    return struct {
        tiles: [*]Tile,
        /// The size of the Tiled image, in pixels.
        size_px: [2]u32,

        pub const Tile = [tile_size[1]][tile_size[0]]Pixel;

        pub const TILE_SIZE = tile_size;

        pub fn alloc(allocator: std.mem.Allocator, size_px: [2]u32) !@This() {
            const size_in_tiles = .{
                (size_px[0] + (tile_size[0] - 1)) / tile_size[0],
                (size_px[1] + (tile_size[1] - 1)) / tile_size[1],
            };

            const tiles = try allocator.alloc(Tile, size_in_tiles[0] * size_in_tiles[1]);
            errdefer allocator.free(tiles);

            return .{
                .tiles = tiles.ptr,
                .size_px = size_px,
            };
        }

        pub fn ensureSize(this: *@This(), allocator: std.mem.Allocator, new_size_px: [2]u32) !void {
            const new_size_tiles = .{
                (new_size_px[0] + (tile_size[0] - 1)) / tile_size[0],
                (new_size_px[1] + (tile_size[1] - 1)) / tile_size[1],
            };

            if (this.size_px[0] == 0 and this.size_px[1] == 0) {
                const new_tiles = try allocator.alloc(Tile, new_size_tiles[0] * new_size_tiles[1]);
                this.tiles = new_tiles.ptr;
                this.size_px = new_size_px;
                return;
            }

            if (new_size_px[0] <= this.size_px[0] and new_size_px[1] <= this.size_px[1]) return;
            const size_tiles = this.sizeInTiles();

            const tiles = this.tiles[0 .. size_tiles[0] * size_tiles[1]];
            const new_tiles = try allocator.realloc(tiles, new_size_tiles[0] * new_size_tiles[1]);

            this.tiles = new_tiles.ptr;
            this.size_px = new_size_px;
        }

        pub fn free(this: @This(), allocator: std.mem.Allocator) void {
            if (this.size_px[0] == 0 and this.size_px[1] == 0) return;
            const size_in_tiles = this.sizeInTiles();
            allocator.free(this.tiles[0 .. size_in_tiles[0] * size_in_tiles[1]]);
        }

        pub fn set(this: @This(), area: geometry.UAABB(u32), pixel: Pixel) void {
            std.debug.assert(area.max()[0] < this.size_px[0]);
            std.debug.assert(area.max()[1] < this.size_px[1]);

            const min_tile_pos = this.tilePosFromOffset(area.min());
            const max_tile_pos = this.tilePosFromOffset(area.max());

            const size_in_tiles = this.sizeInTiles();
            for (min_tile_pos.tile_pos[1]..max_tile_pos.tile_pos[1] + 1) |tile_y| {
                for (min_tile_pos.tile_pos[0]..max_tile_pos.tile_pos[0] + 1) |tile_x| {
                    const tile_index = tile_y * size_in_tiles[0] + tile_x;
                    const tile = &this.tiles[tile_index];
                    if (tile_y != min_tile_pos.tile_pos[1] and
                        tile_y != max_tile_pos.tile_pos[1] and
                        tile_x != min_tile_pos.tile_pos[0] and
                        tile_x != max_tile_pos.tile_pos[0])
                    {
                        for (tile) |*row| {
                            @memset(row, pixel);
                        }
                        continue;
                    }

                    const tile_pos_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };
                    const tile_bounds_px = seizer.geometry.UAABB(u32).init(
                        tile_pos_px,
                        .{
                            tile_pos_px[0] + tile_size[0] - 1,
                            tile_pos_px[1] + tile_size[1] - 1,
                        },
                    );

                    const min_pos = tile_bounds_px.constrain(area.min());
                    const max_pos = tile_bounds_px.constrain(area.max());

                    const min_in_tile = [2]u32{
                        min_pos[0] - tile_bounds_px.min()[0],
                        min_pos[1] - tile_bounds_px.min()[1],
                    };
                    const max_in_tile = [2]u32{
                        max_pos[0] - tile_bounds_px.min()[0],
                        max_pos[1] - tile_bounds_px.min()[1],
                    };

                    for (min_in_tile[1]..max_in_tile[1] + 1) |y| {
                        for (min_in_tile[0]..max_in_tile[0] + 1) |x| {
                            tile[y][x] = pixel;
                        }
                    }
                }
            }
        }

        pub fn sizeInTiles(this: @This()) [2]u32 {
            return .{
                (this.size_px[0] + (tile_size[0] - 1)) / tile_size[0],
                (this.size_px[1] + (tile_size[1] - 1)) / tile_size[1],
            };
        }

        test sizeInTiles {
            try std.testing.expectEqual([_]u32{ 1, 1 }, (@This(){ .tiles = undefined, .size_px = .{ 1, 1 } }).sizeInTiles());
            try std.testing.expectEqual([_]u32{ 1, 1 }, (@This(){ .tiles = undefined, .size_px = .{ 16, 16 } }).sizeInTiles());
            try std.testing.expectEqual([_]u32{ 4, 4 }, (@This(){ .tiles = undefined, .size_px = .{ 64, 64 } }).sizeInTiles());
            try std.testing.expectEqual([_]u32{ 3, 3 }, (@This(){ .tiles = undefined, .size_px = .{ 48, 48 } }).sizeInTiles());
            try std.testing.expectEqual([_]u32{ 3, 3 }, (@This(){ .tiles = undefined, .size_px = .{ 47, 47 } }).sizeInTiles());
            try std.testing.expectEqual([_]u32{ 3, 3 }, (@This(){ .tiles = undefined, .size_px = .{ 33, 33 } }).sizeInTiles());
        }

        pub fn compositeLinear(this: @This(), dst: seizer.geometry.UAABB(u32), src: Slice(Pixel)) void {
            std.debug.assert(dst.sizePlusEpsilon()[0] == src.size[0] and dst.sizePlusEpsilon()[1] == src.size[1]);

            const min_tile_pos = [2]u32{
                dst.min()[0] / tile_size[0],
                dst.min()[1] / tile_size[1],
            };
            const max_tile_pos = [2]u32{
                dst.max()[0] / tile_size[0],
                dst.max()[1] / tile_size[1],
            };

            const size_in_tiles = this.sizeInTiles();

            for (min_tile_pos[1]..max_tile_pos[1] + 1) |tile_y| {
                for (min_tile_pos[0]..max_tile_pos[0] + 1) |tile_x| {
                    const tile_index = tile_y * size_in_tiles[0] + tile_x;
                    const tile = &this.tiles[tile_index];

                    const tile_pos_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };
                    const tile_bounds_px = seizer.geometry.UAABB(u32).init(
                        tile_pos_px,
                        .{
                            tile_pos_px[0] + tile_size[0] - 1,
                            tile_pos_px[1] + tile_size[1] - 1,
                        },
                    );

                    const min_pos = tile_bounds_px.constrain(dst.min());
                    const max_pos = tile_bounds_px.constrain(dst.max());

                    const min_in_tile = [2]u32{
                        min_pos[0] - tile_bounds_px.min()[0],
                        min_pos[1] - tile_bounds_px.min()[1],
                    };
                    const max_in_tile = [2]u32{
                        max_pos[0] - tile_bounds_px.min()[0],
                        max_pos[1] - tile_bounds_px.min()[1],
                    };

                    for (min_in_tile[1]..max_in_tile[1] + 1) |y| {
                        for (min_in_tile[0]..max_in_tile[0] + 1) |x| {
                            const src_pos: [2]u32 = .{
                                @intCast(tile_pos_px[0] + x - dst.min()[0]),
                                @intCast(tile_pos_px[1] + y - dst.min()[1]),
                            };
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], src.getPixel(src_pos));
                        }
                    }
                }
            }
        }

        pub fn compositeSampler(
            dst: @This(),
            dst_area: seizer.geometry.UAABB(u32),
            comptime F: type,
            src_area: seizer.geometry.AABB(F),
            comptime SamplerContext: type,
            comptime sample_fn: fn (SamplerContext, pos: [2]F) Pixel,
            sampler_context: SamplerContext,
        ) void {
            const min_tile_pos = [2]u32{
                dst_area.min()[0] / tile_size[0],
                dst_area.min()[1] / tile_size[1],
            };
            const max_tile_pos = [2]u32{
                dst_area.max()[0] / tile_size[0],
                dst_area.max()[1] / tile_size[1],
            };

            const size_in_tiles = dst.sizeInTiles();

            const sample_stride = [2]F{
                (src_area.size()[0]) / @as(F, @floatFromInt(dst_area.size()[0])),
                (src_area.size()[1]) / @as(F, @floatFromInt(dst_area.size()[1])),
            };

            var sample_buffer: Tile = undefined;

            for (min_tile_pos[1]..max_tile_pos[1] + 1) |tile_y| {
                for (min_tile_pos[0]..max_tile_pos[0] + 1) |tile_x| {
                    const tile_index = tile_y * size_in_tiles[0] + tile_x;
                    const tile = &dst.tiles[tile_index];

                    const tile_pos_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };
                    const tile_bounds_px = seizer.geometry.UAABB(u32).init(
                        tile_pos_px,
                        .{
                            tile_pos_px[0] + tile_size[0] - 1,
                            tile_pos_px[1] + tile_size[1] - 1,
                        },
                    );

                    const min_pos = tile_bounds_px.constrain(dst_area.min());
                    const max_pos = tile_bounds_px.constrain(dst_area.max());

                    // Calculate offset using
                    // min_pos - tile_bounds_px.min()
                    const min_in_tile = [2]u32{
                        min_pos[0] - tile_bounds_px.min()[0],
                        min_pos[1] - tile_bounds_px.min()[1],
                    };
                    const max_in_tile = [2]u32{
                        max_pos[0] - tile_bounds_px.min()[0],
                        max_pos[1] - tile_bounds_px.min()[1],
                    };

                    // clear the pixels in the sample buffer
                    for (sample_buffer[0..]) |*sample_row| {
                        for (sample_row[0..]) |*sample| {
                            sample.* = Pixel.TRANSPARENT;
                        }
                    }

                    // get the samples we'll need to render
                    const sample_start_pos = [2]F{
                        src_area.min()[0] + @as(F, @floatFromInt(min_pos[0] - dst_area.min()[0])) * sample_stride[0],
                        src_area.min()[1] + @as(F, @floatFromInt(min_pos[1] - dst_area.min()[1])) * sample_stride[1],
                    };

                    var sample_pos: [2]F = sample_start_pos;
                    for (min_in_tile[1]..max_in_tile[1] + 1) |y| {
                        sample_pos[0] = sample_start_pos[0];
                        for (sample_buffer[y][min_in_tile[0] .. max_in_tile[0] + 1]) |*sample_pixel| {
                            sample_pixel.* = sample_fn(sampler_context, sample_pos);

                            sample_pos[0] += sample_stride[0];
                        }

                        sample_pos[1] += sample_stride[1];
                    }

                    // composite the samples with the current pixels
                    for (min_in_tile[1]..max_in_tile[1] + 1) |y| {
                        for (min_in_tile[0]..max_in_tile[0] + 1) |x| {
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], sample_buffer[y][x]);
                        }
                    }
                }
            }
        }

        pub fn drawFillRect(this: @This(), area: geometry.UAABB(u32), color: Pixel) void {
            const min_tile_pos = this.tilePosFromOffset(area.min());
            const max_tile_pos = this.tilePosFromOffset(area.max());

            const size_in_tiles = this.sizeInTiles();

            for (min_tile_pos.tile_pos[1]..max_tile_pos.tile_pos[1] + 1) |tile_y| {
                for (min_tile_pos.tile_pos[0]..max_tile_pos.tile_pos[0] + 1) |tile_x| {
                    const tile_index: u32 = @intCast(tile_y * size_in_tiles[0] + tile_x);
                    const tile = &this.tiles[tile_index];

                    const tile_pos_in_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };

                    const min_in_tile = [2]u32{
                        area.min()[0] -| tile_pos_in_px[0],
                        area.min()[1] -| tile_pos_in_px[1],
                    };
                    const max_in_tile = [2]u32{
                        @min((area.max()[0] -| tile_pos_in_px[0]), tile_size[0]),
                        @min((area.max()[1] -| tile_pos_in_px[1]), tile_size[1]),
                    };

                    for (min_in_tile[1]..max_in_tile[1]) |y| {
                        for (min_in_tile[0]..max_in_tile[0]) |x| {
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], color);
                        }
                    }
                }
            }
        }

        /// Returns the signed distance to a line segment
        fn capsuleSDF(p: [2]f32, a: [2]f32, b: [2]f32, r: [2]f32) struct { f32, f32 } {
            const pax = p[0] - a[0];
            const pay = p[1] - a[1];
            const bax = b[0] - a[0];
            const bay = b[1] - a[1];
            const h = std.math.clamp((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1);
            const dx = pax - bax * h;
            const dy = pay - bay * h;
            const rh = std.math.lerp(r[0], r[1], h);
            return .{ @sqrt(dx * dx + dy * dy) - rh, h };
        }

        pub fn drawLine(this: @This(), clip: geometry.UAABB(u32), a: [2]f32, b: [2]f32, r: [2]f32, colors: [2]Pixel) void {
            const rmax = @max(r[0], r[1]);

            const area_line = seizer.geometry.AABB(f32).init(.{
                @floor(@min(a[0], b[0]) - rmax),
                @floor(@min(a[1], b[1]) - rmax),
            }, .{
                @ceil(@max(a[0], b[0]) + rmax),
                @ceil(@max(a[1], b[1]) + rmax),
            });

            const overlapf = area_line.intersection(clip.intoAABB(f32));
            const overlap = overlapf.intoUAABB(u32);

            for (overlap.min()[1]..overlap.max()[1] + 1) |y| {
                for (overlap.min()[0]..overlap.max()[0] + 1) |x| {
                    const capsule, const h = capsuleSDF(.{ @floatFromInt(x), @floatFromInt(y) }, a, b, r);
                    const color = colors[0].blend(colors[1], h);
                    const bg = this.getPixel(.{ @intCast(x), @intCast(y) });
                    const dist = std.math.clamp(0.5 - capsule, 0, 1);
                    const blended = bg.blend(color, dist);
                    this.setPixel(.{ @intCast(x), @intCast(y) }, blended);
                }
            }
        }

        pub fn setPixel(this: @This(), offset: [2]u32, color: Pixel) void {
            const tile_pos = this.tilePosFromOffset(offset);

            const tile = &this.tiles[tile_pos.index];

            tile[tile_pos.pos_in_tile[1]][tile_pos.pos_in_tile[0]] = color;
        }

        pub fn getPixel(this: @This(), offset: [2]u32) Pixel {
            const tile_pos = this.tilePosFromOffset(offset);

            const tile = &this.tiles[tile_pos.index];

            return tile[tile_pos.pos_in_tile[1]][tile_pos.pos_in_tile[0]];
        }

        const TilePos = struct {
            tile_pos: [2]u32,
            index: u32,
            pos_in_tile: [2]u8,
        };

        pub fn tilePosFromOffset(this: @This(), offset: [2]u32) TilePos {
            const bounds = seizer.geometry.UAABB(u32).init(.{ 0, 0 }, .{ this.size_px[0] - 1, this.size_px[1] - 1 });
            std.debug.assert(bounds.contains(offset));

            const pos = [2]u32{
                @intCast(offset[0]),
                @intCast(offset[1]),
            };

            const tile_pos = [2]u32{
                pos[0] / tile_size[0],
                pos[1] / tile_size[1],
            };
            const size_in_tiles = this.sizeInTiles();

            const tile_index = tile_pos[1] * size_in_tiles[0] + tile_pos[0];

            const pos_in_tile = [2]u8{
                @intCast(pos[0] % tile_size[0]),
                @intCast(pos[1] % tile_size[1]),
            };

            return TilePos{
                .tile_pos = tile_pos,
                .index = tile_index,
                .pos_in_tile = pos_in_tile,
            };
        }
    };
}

/// Accepts any type that has a getPixel function
pub fn expectEqualImageSections(section: seizer.geometry.UAABB(u32), expected: anytype, actual: anytype) !void {
    const failed = comp_pixels: {
        for (section.min()[1]..section.max()[1] + 1) |y| {
            for (section.min()[0]..section.max()[0] + 1) |x| {
                const pos = [2]u32{ @intCast(x), @intCast(y) };

                const expected_pixel = expected.getPixel(pos);
                const actual_pixel = actual.getPixel(pos);

                const distance_each = [4]f64{
                    actual_pixel.b - expected_pixel.b,
                    actual_pixel.g - expected_pixel.g,
                    actual_pixel.r - expected_pixel.r,
                    actual_pixel.a - expected_pixel.a,
                };
                const distance = @sqrt(distance_each[0] * distance_each[0] +
                    distance_each[1] * distance_each[1] +
                    distance_each[2] * distance_each[2] +
                    distance_each[3] * distance_each[3]);

                if (distance > 0.001) {
                    std.debug.print("expected pixel to equal {}, found {} (distance = {})\n", .{ expected_pixel, actual_pixel, distance });
                    break :comp_pixels true;
                }
            }
        }
        break :comp_pixels false;
    };
    if (failed) {
        try writeTestImagesToTmpDir(section, expected, actual);
        return error.TestExpectedEqual;
    }
}

/// Accepts any type that has a getPixel function
pub fn writeTestImagesToTmpDir(section: seizer.geometry.UAABB(u32), expected: anytype, actual: anytype) !void {
    const tmp_dir = std.testing.tmpDir(.{});

    try writeImageToTmpDir(tmp_dir, "actual", section, actual);
    try writeImageToTmpDir(tmp_dir, "expected", section, expected);

    var diff = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, .{ section.max()[0] + 1, section.max()[1] + 1 });
    defer diff.free(std.testing.allocator);

    for (section.min()[1]..section.max()[1] + 1) |y| {
        for (section.min()[0]..section.max()[0] + 1) |x| {
            const pos = [2]u32{ @intCast(x), @intCast(y) };

            const expected_pixel = expected.getPixel(pos);
            const actual_pixel = actual.getPixel(pos);

            const diff_pixel: seizer.color.argbf32_premultiplied = .{
                .b = actual_pixel.b - expected_pixel.b,
                .g = actual_pixel.g - expected_pixel.g,
                .r = actual_pixel.r - expected_pixel.r,
                .a = actual_pixel.a - expected_pixel.a,
            };
            const diff_pixel_sq: seizer.color.argbf32_premultiplied = .{
                .b = diff_pixel.b * diff_pixel.b,
                .g = diff_pixel.g * diff_pixel.g,
                .r = diff_pixel.r * diff_pixel.r,
                .a = diff_pixel.a * diff_pixel.a,
            };

            diff.setPixel(pos, diff_pixel_sq);
        }
    }

    try writeImageToTmpDir(tmp_dir, "diff", section, diff);
}

/// Accepts any type that has a getPixel function
pub fn writeImageToTmpDir(tmp_dir: std.testing.TmpDir, comptime name: []const u8, section: seizer.geometry.UAABB(u32), image: anytype) !void {
    var zigimg_image = try zigimg.Image.create(std.testing.allocator, section.size()[0] + 1, section.size()[1] + 1, .rgba32);
    defer zigimg_image.deinit();

    for (section.min()[1]..section.max()[1] + 1) |y| {
        for (section.min()[0]..section.max()[0] + 1) |x| {
            const pos = [2]u32{ @intCast(x), @intCast(y) };
            const index = y * zigimg_image.width + x;

            const actual_pixel = image.getPixel(pos)
                .convertAlphaModelTo(.straight)
                .convertColorTo(seizer.color.sRGB8)
                .convertAlphaTo(u8);

            zigimg_image.pixels.rgba32[index] = .{
                .r = @intFromEnum(actual_pixel.r),
                .g = @intFromEnum(actual_pixel.g),
                .b = @intFromEnum(actual_pixel.b),
                .a = actual_pixel.a,
            };
        }
    }

    var pathname_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    const file = try tmp_dir.dir.createFile(name ++ ".png", .{});
    zigimg_image.writeToFile(file, .{ .png = .{} }) catch |err| {
        std.debug.print("Failed to write \"" ++ name ++ ".png\": {}\n", .{err});
        return;
    };
    if (tmp_dir.dir.realpath(name ++ ".png", &pathname_buffer)) |pathname| {
        std.debug.print("Wrote \"" ++ name ++ ".png\" to \"{}\"\n", .{std.zig.fmtEscapes(pathname)});
    } else |err| {
        std.debug.print("Wrote \"" ++ name ++ ".png\" to tmp directory (could not get realpath: {})\n", .{err});
    }
}

/// Accepts any type that has a getPixel function
pub fn expectAllPixelsEqual(comptime name: []const u8, section: seizer.geometry.UAABB(u32), expected_pixel: anytype, image: anytype) !void {
    for (section.min()[1]..section.max()[1] + 1) |y| {
        for (section.min()[0]..section.max()[0] + 1) |x| {
            const pos = [2]u32{ @intCast(x), @intCast(y) };
            const actual_pixel = image.getPixel(pos);
            if (!std.meta.eql(actual_pixel, expected_pixel)) {
                std.debug.print("Expected entire image to be {}, found {}\n", .{ expected_pixel, actual_pixel });

                const tmp_dir = std.testing.tmpDir(.{});
                try writeImageToTmpDir(tmp_dir, name, section, image);
                return error.TestExpectedEqual;
            }
        }
    }
}

test "Tiled.set(entire image)" {
    // TODO: use fuzz testing in zig 0.14
    const tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, .{ 52, 52 });
    defer tiled.free(std.testing.allocator);

    const image_aabb = seizer.geometry.UAABB(u32).init(
        .{ 0, 0 },
        .{ tiled.size_px[0] - 1, tiled.size_px[1] - 1 },
    );

    tiled.set(image_aabb, seizer.color.argbf32_premultiplied.TRANSPARENT);
    try expectAllPixelsEqual("TRANSPARENT", image_aabb, seizer.color.argbf32_premultiplied.TRANSPARENT, tiled);

    tiled.set(image_aabb, seizer.color.argbf32_premultiplied.BLACK);
    try expectAllPixelsEqual("BLACK", image_aabb, seizer.color.argbf32_premultiplied.BLACK, tiled);

    tiled.set(image_aabb, seizer.color.argbf32_premultiplied.WHITE);
    try expectAllPixelsEqual("WHITE", image_aabb, seizer.color.argbf32_premultiplied.WHITE, tiled);
}

test "Tiled.compositeLinear == Slice.composite" {
    // TODO: replace with fuzz testing in zig 0.14
    var prng = std.Random.DefaultPrng.init(4724468855559179511);

    const ITERATIONS = 100;
    for (0..ITERATIONS) |_| {
        const src_size = [2]u32{
            prng.random().uintAtMost(u32, 32) + 1,
            prng.random().uintAtMost(u32, 32) + 1,
        };
        const size = [2]u32{
            prng.random().uintLessThan(u32, 128) + src_size[0],
            prng.random().uintLessThan(u32, 128) + src_size[1],
        };

        const entire_image_area = seizer.geometry.UAABB(u32).init(
            .{ 0, 0 },
            .{
                size[0] - 1,
                size[1] - 1,
            },
        );

        const src_area = seizer.geometry.UAABB(u32).init(
            .{ 0, 0 },
            .{
                src_size[0] - 1,
                src_size[1] - 1,
            },
        );

        const linear = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer linear.free(std.testing.allocator);
        const tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer tiled.free(std.testing.allocator);

        const clear_color = seizer.color.argb(f32, .straight, f32).init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);

        linear.clear(clear_color);
        tiled.set(entire_image_area, clear_color);

        try expectEqualImageSections(geometry.UAABB(u32).init(.{ 0, 0 }, .{ size[0] - 1, size[1] - 1 }), linear, tiled);

        const src_linear = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, src_size);
        defer src_linear.free(std.testing.allocator);
        for (src_linear.pixels[0 .. src_linear.size[0] * src_linear.size[1]]) |*pixel| {
            pixel.* = seizer.color.argbf32_premultiplied.init(
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
                prng.random().float(f32),
            ).convertAlphaModelTo(.premultiplied);
        }

        for (0..10) |_| {
            const pos = [2]u32{
                prng.random().uintAtMost(u32, size[0] - src_size[0]),
                prng.random().uintAtMost(u32, size[1] - src_size[1]),
            };
            linear.slice(pos, src_size).composite(src_linear.slice(.{ 0, 0 }, src_size));
            tiled.compositeLinear(src_area.translate(pos), src_linear.slice(.{ 0, 0 }, src_size));
        }

        try expectEqualImageSections(geometry.UAABB(u32).init(.{ 0, 0 }, .{ size[0] - 1, size[1] - 1 }), linear, tiled);
    }
}

test "Tiled.compositeSampler == Slice.compositeSampler" {
    // TODO: replace with fuzz testing in zig 0.14
    var prng = std.Random.DefaultPrng.init(1854600890778579343);

    const ITERATIONS = 100;
    for (0..ITERATIONS) |_| {
        const src_size = [2]u32{
            prng.random().uintAtMost(u32, 32) + 1,
            prng.random().uintAtMost(u32, 32) + 1,
        };
        const size = [2]u32{
            prng.random().uintLessThan(u32, 128) + src_size[0],
            prng.random().uintLessThan(u32, 128) + src_size[1],
        };

        const entire_image_area = seizer.geometry.UAABB(u32).init(
            .{ 0, 0 },
            .{
                size[0] - 1,
                size[1] - 1,
            },
        );

        const dst_area = seizer.geometry.UAABB(u32).init(
            .{ 0, 0 },
            .{
                src_size[0] - 1,
                src_size[1] - 1,
            },
        );

        const src_gradient_size = [2]f32{
            prng.random().float(f32),
            prng.random().float(f32),
        };
        const src_gradient_start = [2]f32{
            prng.random().float(f32) * (1.0 - src_gradient_size[0]),
            prng.random().float(f32) * (1.0 - src_gradient_size[1]),
        };
        const src_gradient = seizer.geometry.AABB(f32).init(
            .{
                src_gradient_start[0],
                src_gradient_start[1],
            },
            .{
                src_gradient_start[0] + src_gradient_size[0],
                src_gradient_start[1] + src_gradient_size[1],
            },
        );

        const linear = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer linear.free(std.testing.allocator);
        const tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer tiled.free(std.testing.allocator);

        const clear_color = seizer.color.argb(f32, .straight, f32).init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);

        linear.clear(clear_color);
        tiled.set(entire_image_area, clear_color);

        try expectEqualImageSections(geometry.UAABB(u32).init(.{ 0, 0 }, .{ size[0] - 1, size[1] - 1 }), linear, tiled);

        const RGGradientSampler = struct {
            pub fn sample(this: @This(), pos: [2]f32) seizer.color.argbf32_premultiplied {
                _ = this;
                return seizer.color.argbf32_premultiplied.init(
                    0,
                    @floatCast(pos[1]),
                    @floatCast(pos[0]),
                    1,
                );
            }
        };

        for (0..10) |_| {
            const pos = [2]u32{
                prng.random().uintAtMost(u32, size[0] - src_size[0]),
                prng.random().uintAtMost(u32, size[1] - src_size[1]),
            };
            linear.slice(pos, src_size).compositeSampler(f32, src_gradient, RGGradientSampler, RGGradientSampler.sample, .{});
            tiled.compositeSampler(dst_area.translate(pos), f32, src_gradient, RGGradientSampler, RGGradientSampler.sample, .{});
        }

        try expectEqualImageSections(geometry.UAABB(u32).init(.{ 0, 0 }, .{ size[0] - 1, size[1] - 1 }), linear, tiled);
    }
}

comptime {
    _ = Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied);
    _ = Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).sizeInTiles;
    _ = Slice(seizer.color.argbf32_premultiplied);
}

const probes = @import("probes");
const std = @import("std");
const seizer = @import("./seizer.zig");
const geometry = seizer.geometry;
const zigimg = @import("zigimg");
