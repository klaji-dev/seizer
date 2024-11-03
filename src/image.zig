pub fn Image(Pixel: type) type {
    std.debug.assert(@hasDecl(Pixel, "fromArgb8888"));
    std.debug.assert(@hasDecl(Pixel, "toArgb8888"));
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
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

        pub fn fromMemory(allocator: std.mem.Allocator, file_contents: []const u8) !@This() {
            var img = try zigimg.Image.fromMemory(allocator, file_contents);
            defer img.deinit();

            try img.convert(.rgba32);

            const pixels = try allocator.alloc(Pixel, img.pixels.rgba32.len);

            // pre-multiply the image
            for (pixels, img.pixels.rgba32) |*out, in| {
                out.* = Pixel.fromArgb8888(.{
                    .b = @enumFromInt(@as(u8, @intCast((@as(u16, in.b) * @as(u16, in.a)) >> 8))),
                    .g = @enumFromInt(@as(u8, @intCast((@as(u16, in.g) * @as(u16, in.a)) >> 8))),
                    .r = @enumFromInt(@as(u8, @intCast((@as(u16, in.r) * @as(u16, in.a)) >> 8))),
                    .a = in.a,
                });
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

        pub fn drawLine(this: @This(), a: [2]i32, b: [2]i32, color: Pixel) void {
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
            std.debug.assert(pos[0] >= 0 and pos[0] < this.size[0]);
            std.debug.assert(pos[1] >= 0 and pos[1] < this.size[1]);
            const posu = [2]u32{ @intCast(pos[0]), @intCast(pos[1]) };
            this.pixels[@intCast(posu[1] * this.stride + posu[0])] = color;
        }

        pub fn getPixel(this: @This(), pos: [2]i32) Pixel {
            std.debug.assert(pos[0] >= 0 and pos[0] < this.size[0]);
            std.debug.assert(pos[1] >= 0 and pos[1] < this.size[1]);
            const posu = [2]u32{ @intCast(pos[0]), @intCast(pos[1]) };
            return this.pixels[@intCast(posu[1] * this.stride + posu[0])];
        }

        pub fn resize(dst: @This(), src: @This()) void {
            const dst_size = [2]f64{
                @floatFromInt(dst.size[0]),
                @floatFromInt(dst.size[1]),
            };

            const src_size = [2]f64{
                @floatFromInt(src.size[0]),
                @floatFromInt(src.size[1]),
            };

            for (0..dst.size[1]) |dst_y| {
                for (0..dst.size[0]) |dst_x| {
                    const uv = [2]f64{
                        @as(f64, @floatFromInt(dst_x)) / dst_size[0],
                        @as(f64, @floatFromInt(dst_y)) / dst_size[1],
                    };
                    const src_pos = [2]f64{
                        uv[0] * src_size[0] - 0.5,
                        uv[1] * src_size[1] - 0.5,
                    };
                    const src_columnf = @floor(src_pos[0]);
                    const col_indices = [4]f64{
                        @floor(src_columnf - 1),
                        @floor(src_columnf - 0),
                        @floor(src_columnf + 1),
                        @floor(src_columnf + 2),
                    };
                    const src_rowf = @floor(src_pos[1]);
                    const row_indices = [4]f64{
                        @floor(src_rowf - 1),
                        @floor(src_rowf - 0),
                        @floor(src_rowf + 1),
                        @floor(src_rowf + 2),
                    };

                    const kernel_x: @Vector(4, f64) = .{
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[0] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[1] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[2] - src_pos[0]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, col_indices[3] - src_pos[0]),
                    };
                    const kernel_y: @Vector(4, f64) = .{
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[0] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[1] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[2] - src_pos[1]),
                        cubicFilter(1.0 / 3.0, 1.0 / 3.0, row_indices[3] - src_pos[1]),
                    };

                    var row_interpolations: [4][4]f64 = undefined;
                    for (0..4, row_indices) |interpolation_idx, row_idxf| {
                        // TODO: set out of bounds pixels to transparent instead of repeating row
                        const row_idx: i32 = @intFromFloat(std.math.clamp(row_idxf, 0, src_size[1] - 1));
                        // transpose so we can multiply by each color channel separately
                        const src_row_pixels = seizer.geometry.mat.transpose(4, 4, f64, [4][4]f64{
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[0], 0, src_size[0] - 1)), row_idx }).toArgb().toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[1], 0, src_size[0] - 1)), row_idx }).toArgb().toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[2], 0, src_size[0] - 1)), row_idx }).toArgb().toArray(),
                            src.getPixel(.{ @intFromFloat(std.math.clamp(col_indices[3], 0, src_size[0] - 1)), row_idx }).toArgb().toArray(),
                        });

                        for (0..4, src_row_pixels[0..4]) |interpolation_channel, channel| {
                            const channel_v: @Vector(4, f64) = channel;
                            row_interpolations[interpolation_channel][interpolation_idx] = @reduce(.Add, kernel_x * channel_v);
                        }
                    }

                    var out_pixel: [4]f64 = undefined;

                    for (out_pixel[0..], row_interpolations[0..]) |*out_channel, channel| {
                        const channel_v: @Vector(4, f64) = channel;
                        out_channel.* = std.math.clamp(@reduce(.Add, kernel_y * channel_v), 0, 1);
                    }

                    dst.setPixel(.{ @intCast(dst_x), @intCast(dst_y) }, seizer.color.argb(f64).fromArray(out_pixel).toArgb8888());
                }
            }
        }

        // Returns the amount a sample should influence the output result
        pub fn cubicFilter(B: f64, C: f64, x: f64) f64 {
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

        pub fn alloc(allocator: std.mem.Allocator, size_px: [2]u32) !@This() {
            const size_in_tiles = [2]u32{
                size_px[0] / tile_size[0],
                size_px[1] / tile_size[1],
            };

            const tiles = try allocator.alloc(Tile, size_in_tiles[0] * size_in_tiles[1]);
            errdefer allocator.free(tiles);

            return .{
                .tiles = tiles.ptr,
                .size_px = size_px,
                .start_px = .{ 0, 0 },
                .end_px = size_px,
            };
        }

        pub fn free(this: @This(), allocator: std.mem.Allocator) void {
            const size_in_tiles = [2]u32{
                this.size_px[0] / tile_size[0],
                this.size_px[1] / tile_size[1],
            };

            allocator.free(this.tiles[0 .. size_in_tiles[0] * size_in_tiles[1]]);
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

        pub fn composite(dst: @This(), src: @This()) void {
            const dst_size = [2]u32{
                dst.end_px[0] - dst.start_px[0],
                dst.end_px[1] - dst.start_px[1],
            };
            const src_size = [2]u32{
                src.end_px[0] - src.start_px[0],
                src.end_px[1] - src.start_px[1],
            };
            std.debug.assert(dst_size[0] == src_size[0] and dst_size[1] == src_size[1]);

            const min_tile_pos = [2]u32{
                dst.start_px[0] / tile_size[0],
                dst.start_px[1] / tile_size[1],
            };
            const max_tile_pos = [2]u32{
                dst.end_px[0] / tile_size[0],
                dst.end_px[1] / tile_size[1],
            };

            const size_in_tiles = [2]u32{
                dst.size_px[0] / tile_size[0],
                dst.size_px[1] / tile_size[1],
            };

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
                        (dst.end_px[0] -| tile_pos_in_px[0]) % tile_size[0],
                        (dst.end_px[1] -| tile_pos_in_px[1]) % tile_size[1],
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

        pub fn compositeLinear(dst: @This(), src: Image(Pixel)) void {
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
                dst.end_px[0] / tile_size[0],
                dst.end_px[1] / tile_size[1],
            };

            const size_in_tiles = [2]u32{
                dst.size_px[0] / tile_size[0],
                dst.size_px[1] / tile_size[1],
            };

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
                        (dst.end_px[0] -| tile_pos_in_px[0]) % tile_size[0],
                        (dst.end_px[1] -| tile_pos_in_px[1]) % tile_size[1],
                    };

                    for (min_in_tile[1]..max_in_tile[1]) |y| {
                        for (min_in_tile[0]..max_in_tile[0]) |x| {
                            const src_pos: [2]i32 = .{
                                @intCast(tile_pos_in_px[0] + x - dst.start_px[0]),
                                @intCast(tile_pos_in_px[1] + y - dst.start_px[1]),
                            };
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], src.getPixel(src_pos));
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

            const size_in_tiles = [2]u32{
                this.size_px[0] / tile_size[0],
                this.size_px[1] / tile_size[1],
            };

            for (min_tile_pos.tile_pos[1]..max_tile_pos.tile_pos[1]) |tile_y| {
                for (min_tile_pos.tile_pos[0]..max_tile_pos.tile_pos[0]) |tile_x| {
                    const tile_index = tile_y * size_in_tiles + tile_x;
                    const tile = &this.tiles[tile_index];

                    const tile_pos_in_px = [2]u32{
                        tile_x * tile_size[0],
                        tile_y * tile_size[1],
                    };

                    const min_in_tile = [2]u32{
                        min_offset[0] -| tile_pos_in_px[0],
                        min_offset[1] -| tile_pos_in_px[1],
                    };
                    const max_in_tile = [2]u32{
                        (max_tile_pos[0] -| max_offset[0]) % tile_size[0],
                        (max_tile_pos[1] -| max_offset[1]) % tile_size[1],
                    };

                    for (min_in_tile[1]..max_in_tile[1]) |y| {
                        for (min_in_tile[0]..max_in_tile[0]) |x| {
                            tile[y][x] = Pixel.compositeSrcOver(tile[y][x], color);
                        }
                    }
                }
            }
        }

        pub fn drawLine(this: @This(), a: [2]i32, b: [2]i32, color: Pixel) void {
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
                this.setPixel(pos, Pixel.compositeSrcOver(this.getPixel(pos), color));
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

        fn tilePosFromOffset(this: @This(), offset: [2]u32) TilePos {
            std.debug.assert(offset[0] >= 0 and offset[1] >= 0);
            std.debug.assert(offset[0] < this.end_px[0] - this.start_px[0] and offset[1] < this.end_px[1] - this.start_px[1]);
            const pos = [2]u32{
                @intCast(this.start_px[0] + offset[0]),
                @intCast(this.start_px[1] + offset[1]),
            };

            const tile_pos = [2]u32{
                pos[0] / tile_size[0],
                pos[1] / tile_size[1],
            };
            const size_in_tiles = [2]u32{
                this.size_px[0] / tile_size[0],
                this.size_px[1] / tile_size[1],
            };

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

const probes = @import("probes");
const std = @import("std");
const seizer = @import("./seizer.zig");
const zigimg = @import("zigimg");
