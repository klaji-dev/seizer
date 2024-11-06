pub fn Linear(Pixel: type) type {
    // std.debug.assert(@hasDecl(Pixel, "fromArgb8888"));
    // std.debug.assert(@hasDecl(Pixel, "toArgb8888"));
    // std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
    return struct {
        pixels: [*]Pixel,
        size: [2]u32,
        stride: u32,

        pub fn alloc(allocator: std.mem.Allocator, size: [2]u32) !@This() {
            const pixels = try allocator.alloc(Pixel, size[0] * size[1]);
            errdefer allocator.free(pixels);

            return .{
                .size = size,
                .stride = size[0],
                .pixels = pixels.ptr,
            };
        }

        pub fn clear(this: @This(), pixel: Pixel) void {
            std.debug.assert(this.size[0] == this.stride);
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
                for (dst_row, src_row) |*dst_argb, src_argb| {
                    dst_argb.* = Pixel.compositeSrcOver(dst_argb.*, src_argb);
                }
            }
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
        fn capsuleSDF(p: [2]f32, a: [2]f32, b: [2]f32, r: f32) f32 {
            const pax = p[0] - a[0];
            const pay = p[1] - a[1];
            const bax = b[0] - a[0];
            const bay = b[1] - a[1];
            const h = std.math.clamp((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1);
            const dx = pax - bax * h;
            const dy = pay - bay * h;
            return @sqrt(dx * dx + dy * dy) - r;
        }

        fn lineProgress(p: [2]f32, a: [2]f32, b: [2]f32) f32 {
            const pax = p[0] - a[0];
            const pay = p[1] - a[1];
            const bax = b[0] - a[0];
            const bay = b[1] - a[1];
            const h = std.math.clamp((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1);
            return h;
        }

        pub fn drawLine(this: @This(), a: [2]f32, b: [2]f32, r: f32, colors: [2]Pixel) void {
            const px0: usize = @intFromFloat(@floor(@min(a[0], b[0]) - r));
            const px1: usize = @intFromFloat(@ceil(@max(a[0], b[0]) + r));
            const py0: usize = @intFromFloat(@floor(@min(a[1], b[1]) - r));
            const py1: usize = @intFromFloat(@ceil(@max(a[1], b[1]) + r));
            std.debug.assert(px1 - px0 > 0 and py1 - py0 > 0);
            std.debug.assert(px1 != px0 and py1 != py0);
            for (py0..py1) |y| {
                for (px0..px1) |x| {
                    const h = lineProgress(.{ @floatFromInt(x), @floatFromInt(y) }, a, b);
                    const color = colors[0].blend(colors[1], h);
                    const bg = this.getPixel(.{ @intCast(x), @intCast(y) });
                    const capsule = capsuleSDF(.{ @floatFromInt(x), @floatFromInt(y) }, a, b, r);
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

pub fn Tiled(comptime tile_size: [2]u8, Pixel: type) type {
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
    return struct {
        tiles: [*]Tile,
        /// The size of the Tiled image, in pixels.
        size_px: [2]u32,
        /// The offset into the Tiled image this slice starts at
        start_px: [2]u32,
        /// The offset into the Tiled image this slice ends at. Must be > start_px
        end_px: [2]u32,

        pub const Tile = [tile_size[1]][tile_size[0]]Pixel;

        pub const TILE_SIZE = tile_size;

        pub fn alloc(allocator: std.mem.Allocator, size_px: [2]u32) !@This() {
            const size_in_tiles = sizeInTiles(size_px);

            const tiles = try allocator.alloc(Tile, size_in_tiles[0] * size_in_tiles[1]);
            errdefer allocator.free(tiles);

            return .{
                .tiles = tiles.ptr,
                .size_px = size_px,
                .start_px = .{ 0, 0 },
                .end_px = size_px,
            };
        }

        pub fn ensureSize(this: *@This(), allocator: std.mem.Allocator, new_size_px: [2]u32) !void {
            const new_size_tiles = sizeInTiles(new_size_px);

            if (this.size_px[0] == 0 and this.size_px[1] == 0) {
                const new_tiles = try allocator.alloc(Tile, new_size_tiles[0] * new_size_tiles[1]);
                this.tiles = new_tiles.ptr;
                this.size_px = new_size_px;
                this.start_px = .{ 0, 0 };
                this.end_px = new_size_px;
                this.clear(Pixel.BLACK);
                return;
            }

            if (new_size_px[0] <= this.size_px[0] and new_size_px[1] <= this.size_px[1]) return;
            const size_tiles = sizeInTiles(this.size_px);

            const tiles = this.tiles[0 .. size_tiles[0] * size_tiles[1]];
            const new_tiles = try allocator.realloc(tiles, new_size_tiles[0] * new_size_tiles[1]);

            this.tiles = new_tiles.ptr;
            this.size_px = new_size_px;
            this.start_px = .{ 0, 0 };
            this.end_px = new_size_px;
            this.clear(Pixel.BLACK);
        }

        pub fn free(this: @This(), allocator: std.mem.Allocator) void {
            if (this.size_px[0] == 0 and this.size_px[1] == 0) return;
            const size_in_tiles = sizeInTiles(this.size_px);
            allocator.free(this.tiles[0 .. size_in_tiles[0] * size_in_tiles[1]]);
        }

        pub fn clear(this: @This(), pixel: Pixel) void {
            std.debug.assert(this.size_px[0] == this.end_px[0] and this.size_px[1] == this.end_px[1]);
            const size_in_tiles = sizeInTiles(this.size_px);
            for (this.tiles[0 .. size_in_tiles[0] * size_in_tiles[1]]) |*tile| {
                for (tile) |*row| {
                    @memset(row, pixel);
                }
            }
        }

        pub fn sizeInTiles(size_px: [2]u32) [2]u32 {
            return .{
                (size_px[0] + (tile_size[0] + 1)) / tile_size[0],
                (size_px[1] + (tile_size[1] + 1)) / tile_size[1],
            };
        }

        pub fn slice(this: @This(), offset: [2]u32, size: [2]u32) @This() {
            const new_start = [2]u32{
                this.start_px[0] + offset[0],
                this.start_px[1] + offset[1],
            };
            const new_end = [2]u32{
                new_start[0] + size[0],
                new_start[1] + size[1],
            };
            std.debug.assert(new_start[0] <= this.size_px[0] and new_start[1] <= this.size_px[1]);
            std.debug.assert(new_end[0] <= this.size_px[0] and new_end[1] <= this.size_px[1]);

            return .{
                .tiles = this.tiles,
                .size_px = this.size_px,
                .start_px = new_start,
                .end_px = new_end,
            };
        }

        pub fn compositeLinear(dst: @This(), src: Linear(Pixel)) void {
            const dst_size = [2]u32{
                dst.end_px[0] - dst.start_px[0],
                dst.end_px[1] - dst.start_px[1],
            };
            std.debug.assert(dst_size[0] == src.size[0] and dst_size[1] == src.size[1]);

            const min_tile_pos = [2]u32{
                dst.start_px[0] / tile_size[0],
                dst.start_px[1] / tile_size[1],
            };
            const max_tile_pos = [2]u32{
                (dst.end_px[0] + (tile_size[0] - 1)) / tile_size[0],
                (dst.end_px[1] + (tile_size[1] - 1)) / tile_size[1],
            };

            const size_in_tiles = sizeInTiles(dst.size_px);

            for (min_tile_pos[1]..max_tile_pos[1]) |tile_y| {
                for (min_tile_pos[0]..max_tile_pos[0]) |tile_x| {
                    const tile_index = tile_y * size_in_tiles[0] + tile_x;
                    const tile = &dst.tiles[tile_index];

                    const tile_pos_in_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };

                    const min_in_tile = [2]u32{
                        dst.start_px[0] -| tile_pos_in_px[0],
                        dst.start_px[1] -| tile_pos_in_px[1],
                    };
                    const max_in_tile = [2]u32{
                        @min(tile_size[0], (dst.end_px[0] -| tile_pos_in_px[0])),
                        @min(tile_size[1], (dst.end_px[1] -| tile_pos_in_px[1])),
                    };

                    for (min_in_tile[1]..max_in_tile[1]) |y| {
                        for (min_in_tile[0]..max_in_tile[0]) |x| {
                            const src_pos: [2]u32 = .{
                                @intCast(tile_pos_in_px[0] + x - dst.start_px[0]),
                                @intCast(tile_pos_in_px[1] + y - dst.start_px[1]),
                            };
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], src.getPixel(src_pos));
                        }
                    }
                }
            }
        }

        pub fn compositeSampler(
            dst: @This(),
            comptime SamplerContext: type,
            comptime sample_fn: fn (SamplerContext, pos: [2]u32, sample_rect: Linear(Pixel)) void,
            sampler_context: SamplerContext,
        ) void {
            const min_tile_pos = [2]u32{
                dst.start_px[0] / tile_size[0],
                dst.start_px[1] / tile_size[1],
            };
            const max_tile_pos = [2]u32{
                (dst.end_px[0] + (tile_size[0] - 1)) / tile_size[0],
                (dst.end_px[1] + (tile_size[1] - 1)) / tile_size[1],
            };

            const size_in_tiles = sizeInTiles(dst.size_px);

            var sample_rect_pixel_buffer: [@as(u32, tile_size[0]) * tile_size[1]]Pixel = undefined;

            for (min_tile_pos[1]..max_tile_pos[1]) |tile_y| {
                for (min_tile_pos[0]..max_tile_pos[0]) |tile_x| {
                    const tile_index = tile_y * size_in_tiles[0] + tile_x;
                    const tile = &dst.tiles[tile_index];

                    const tile_pos_in_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };

                    const min_in_tile = [2]u32{
                        dst.start_px[0] -| tile_pos_in_px[0],
                        dst.start_px[1] -| tile_pos_in_px[1],
                    };
                    const max_in_tile = [2]u32{
                        @min(tile_size[0], (dst.end_px[0] -| tile_pos_in_px[0])),
                        @min(tile_size[1], (dst.end_px[1] -| tile_pos_in_px[1])),
                    };

                    const sample_size = .{
                        max_in_tile[0] - min_in_tile[0],
                        max_in_tile[1] - min_in_tile[1],
                    };

                    const sample_rect = Linear(Pixel){
                        .pixels = &sample_rect_pixel_buffer,
                        .size = sample_size,
                        // TODO: contiguous image type?
                        .stride = sample_size[0],
                    };

                    // get the pixels we'll need to render
                    sample_fn(
                        sampler_context,
                        .{
                            tile_pos_in_px[0] + min_in_tile[0] - dst.start_px[0],
                            tile_pos_in_px[1] + min_in_tile[1] - dst.start_px[1],
                        },
                        sample_rect,
                    );

                    for (min_in_tile[1]..max_in_tile[1], 0..) |y, sample_y| {
                        for (min_in_tile[0]..max_in_tile[0], 0..) |x, sample_x| {
                            tile[y][x] = Pixel.compositeSrcOver(
                                tile[y][x],
                                sample_rect.getPixel(.{ @intCast(sample_x), @intCast(sample_y) }),
                            );
                        }
                    }
                }
            }
        }

        pub fn drawFillRect(this: @This(), a: [2]i32, b: [2]i32, color: Pixel) void {
            const this_size = [2]u32{
                this.end_px[0] - this.start_px[0],
                this.end_px[1] - this.start_px[1],
            };

            const size_i = [2]i32{ @intCast(this_size[0]), @intCast(this_size[1]) };
            const min_offset = [2]u32{
                @intCast(std.math.clamp(@min(a[0], b[0]), 0, size_i[0])),
                @intCast(std.math.clamp(@min(a[1], b[1]), 0, size_i[1])),
            };
            const max_offset = [2]u32{
                @intCast(std.math.clamp(@max(a[0], b[0]), 0, size_i[0])),
                @intCast(std.math.clamp(@max(a[1], b[1]), 0, size_i[1])),
            };

            const min_tile_pos = this.tilePosFromOffset(min_offset);
            const max_tile_pos = this.tilePosFromOffset(max_offset);

            const size_in_tiles = sizeInTiles(this.size_px);

            for (min_tile_pos.tile_pos[1]..max_tile_pos.tile_pos[1] + 1) |tile_y| {
                for (min_tile_pos.tile_pos[0]..max_tile_pos.tile_pos[0] + 1) |tile_x| {
                    const tile_index: u32 = @intCast(tile_y * size_in_tiles[0] + tile_x);
                    const tile = &this.tiles[tile_index];

                    const tile_pos_in_px = [2]u32{
                        @intCast(tile_x * tile_size[0]),
                        @intCast(tile_y * tile_size[1]),
                    };

                    const min_in_tile = [2]u32{
                        min_offset[0] -| tile_pos_in_px[0],
                        min_offset[1] -| tile_pos_in_px[1],
                    };
                    const max_in_tile = [2]u32{
                        @min((max_offset[0] -| tile_pos_in_px[0]), tile_size[0]),
                        @min((max_offset[1] -| tile_pos_in_px[1]), tile_size[1]),
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

        pub fn drawLine(this: @This(), a: [2]f32, b: [2]f32, r: [2]f32, colors: [2]Pixel) void {
            const rmax = @max(r[0], r[1]);

            const sizef: [2]f32 = .{
                @floatFromInt(this.size_px[0]),
                @floatFromInt(this.size_px[1]),
            };

            const px0: usize = @intFromFloat(std.math.clamp(@floor(@min(a[0], b[0]) - rmax), 0, sizef[0]));
            const px1: usize = @intFromFloat(std.math.clamp(@ceil(@max(a[0], b[0]) + rmax), 0, sizef[0]));
            const py0: usize = @intFromFloat(std.math.clamp(@floor(@min(a[1], b[1]) - rmax), 0, sizef[1]));
            const py1: usize = @intFromFloat(std.math.clamp(@ceil(@max(a[1], b[1]) + rmax), 0, sizef[1]));

            for (py0..py1) |y| {
                for (px0..px1) |x| {
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
            std.debug.assert(offset[0] >= 0 and offset[1] >= 0);
            std.debug.assert(offset[0] <= this.end_px[0] - this.start_px[0] and offset[1] <= this.end_px[1] - this.start_px[1]);
            const pos = [2]u32{
                @intCast(this.start_px[0] + offset[0]),
                @intCast(this.start_px[1] + offset[1]),
            };

            const tile_pos = [2]u32{
                pos[0] / tile_size[0],
                pos[1] / tile_size[1],
            };
            const size_in_tiles = sizeInTiles(this.size_px);

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

test "Tiled ops == Linear ops" {
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

        const linear = try Linear(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer linear.free(std.testing.allocator);
        const tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer tiled.free(std.testing.allocator);

        const clear_color = seizer.color.argbf32_premultiplied.init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);

        linear.clear(clear_color);
        tiled.clear(clear_color);

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
            linear.slice(pos, src_size).composite(src_linear);
            tiled.slice(pos, src_size).compositeLinear(src_linear);
        }

        for (0..size[1]) |y| {
            for (0..size[0]) |x| {
                const pos = [2]u32{ @intCast(x), @intCast(y) };
                try std.testing.expectEqual(linear.getPixel(pos), tiled.getPixel(pos));
            }
        }
    }
}

const probes = @import("probes");
const std = @import("std");
const seizer = @import("./seizer.zig");
const zigimg = @import("zigimg");
