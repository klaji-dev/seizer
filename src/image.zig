pub fn Image(Pixel: type) type {
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

        fn sizeInTiles(size_px: [2]u32) [2]u32 {
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

        pub fn composite(dst: @This(), src: @This()) void {
            // And example of the problem we need to solve:
            //
            // ```zig
            // Tiled(.{7,3}, Pixel).composite(
            //     .{ // dst
            //         .start_px = .{ 4, 1 },
            //         .end_px = .{ 11, 5 },
            //     },
            //     .{ // src
            //         .start_px = .{ 1, 0 },
            //         .end_px = .{ 8, 4 },
            //     },
            // )
            // ```
            //
            // `dst`:
            //
            // ```ascii-art
            // tile x   0       1
            //    y +-------+-------+
            //      |       |       |
            //    0 |    +------+   |
            //      |    |      |   |
            //      +----|  dst |---+
            //      |    |      |   |
            //    1 |    +------+   |
            //      |       |       |
            //      +-------+-------+
            // ```
            //
            // `src`:
            //
            // ```ascii-art
            // tile x   0       1
            //    y +-------+-------+
            //      | +------+      |
            //    0 | |      |      |
            //      | |  src |      |
            //      +-|      |------+
            //      | +------+      |
            //    1 |       |       |
            //      |       |       |
            //      +-------+-------+
            // ```
            const dst_size = [2]u32{
                dst.end_px[0] - dst.start_px[0],
                dst.end_px[1] - dst.start_px[1],
            };
            const src_size = [2]u32{
                src.end_px[0] - src.start_px[0],
                src.end_px[1] - src.start_px[1],
            };
            std.debug.assert(dst_size[0] == src_size[0] and dst_size[1] == src_size[1]);

            const dst_min_tile_pos = [2]u32{
                dst.start_px[0] / tile_size[0],
                dst.start_px[1] / tile_size[1],
            };
            const dst_max_tile_pos = [2]u32{
                dst.end_px[0] / tile_size[0] + 1,
                dst.end_px[1] / tile_size[1] + 1,
            };

            const dst_size_in_tiles = sizeInTiles(dst.size_px);
            const src_size_in_tiles = sizeInTiles(src.size_px);

            for (dst_min_tile_pos[1]..dst_max_tile_pos[1]) |dst_tile_y| {
                for (dst_min_tile_pos[0]..dst_max_tile_pos[0]) |dst_tile_x| {
                    // Following on from the earlier example:
                    //
                    // `dst` tile `<0, 0>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |.......|       |
                    //    0 |....+------+   |
                    //      |....|###   |   |
                    //      +----|###   |---+
                    //      |    |      |   |
                    //    1 |    +------+   |
                    //      |       |       |
                    //      +-------+-------+
                    //
                    // tile_pos_px = <0, 0>
                    //
                    // dst_min_in_tile_px = `<4, 1>`
                    // dst_max_in_tile_px = `<7, 3>`
                    //
                    // dst_min_offset_in_tile = `<0, 0>`
                    // dst_max_offset_in_tile = `<3, 2>`
                    // ```

                    // `dst` tile `<1, 0>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |       |.......|
                    //    0 |    +------+...|
                    //      |    |  ####|...|
                    //      +----|  ####|---+
                    //      |    |      |   |
                    //    1 |    +------+   |
                    //      |       |       |
                    //      +-------+-------+
                    //
                    // tile_pos_px = <7, 0>
                    //
                    // dst_min_in_tile_px = `<0, 1>`
                    // dst_max_in_tile_px = `<4, 3>`
                    //
                    // dst_min_offset_in_tile = `<3, 0>`
                    // dst_max_offset_in_tile = `<7, 2>`
                    // ```

                    // `dst` tile `<0, 1>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |       |       |
                    //    0 |    +------+   |
                    //      |    |      |   |
                    //      +----|###   |---+
                    //      |....|###   |   |
                    //    1 |....+------+   |
                    //      |.......|       |
                    //      +-------+-------+
                    //
                    // tile_pos_px = <0, 3>
                    //
                    // dst_min_in_tile_px = `<4, 0>`
                    // dst_max_in_tile_px = `<7, 2>`
                    //
                    // dst_min_offset_in_tile = `<0, 2>`
                    // dst_max_offset_in_tile = `<3, 4>`
                    // ```

                    // `dst` tile `<0, 1>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |       |       |
                    //    0 |    +------+   |
                    //      |    |      |   |
                    //      +----|  ####|---+
                    //      |    |  ####|...|
                    //    1 |    +------+...|
                    //      |       |.......|
                    //      +-------+-------+
                    //
                    // tile_pos_px = <7, 3>
                    //
                    // dst_min_in_tile_px = `<0, 0>`
                    // dst_max_in_tile_px = `<4, 2>`
                    //
                    // dst_min_offset_in_tile = `<3, 2>`
                    // dst_max_offset_in_tile = `<7, 4>`
                    // ```
                    const dst_tile_index = dst_tile_y * dst_size_in_tiles[0] + dst_tile_x;
                    const dst_tile = &dst.tiles[dst_tile_index];

                    const dst_tile_pos_in_px = [2]u32{
                        @intCast(dst_tile_x * tile_size[0]),
                        @intCast(dst_tile_y * tile_size[1]),
                    };

                    const dst_min_in_tile_px = [2]u32{
                        dst.start_px[0] -| dst_tile_pos_in_px[0],
                        dst.start_px[1] -| dst_tile_pos_in_px[1],
                    };
                    const dst_max_in_tile_px = [2]u32{
                        @min(tile_size[0], (dst.end_px[0] -| dst_tile_pos_in_px[0])),
                        @min(tile_size[1], (dst.end_px[1] -| dst_tile_pos_in_px[1])),
                    };

                    // For `dst` tile `<0,0>`, we will need to get the `src` tiles
                    // for offsets starting `<0,0>` and ending at `<3,2>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      | +------+      |
                    //    0 | |##    |      |
                    //      | |      |      |
                    //      +-|      |------+
                    //      | +------+      |
                    //    1 |       |       |
                    //      |       |       |
                    //      +-------+-------+
                    // ```
                    //
                    // In this example, that would mean just `src` tile `<0,0>`.

                    // For `dst` tile `<1,0>`, we will need to get the `src` tiles
                    // for offsets starting `<3,0>` and ending at `<7,2>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |.+------+......|
                    //    0 |.|  ####|......|
                    //      |.|      |......|
                    //      +-|      |------+
                    //      | +------+      |
                    //    1 |       |       |
                    //      |       |       |
                    //      +-------+-------+
                    // ```
                    //
                    // In this example, that would mean `src` tiles `<0,0>` and `<1,0>`.

                    // For `dst` tile `<0,1>`, we will need to get the `src` tiles
                    // for offsets starting `<0,2>` and ending at `<3,4>`:
                    //
                    // ```ascii-art
                    // tile x   0       1
                    //    y +-------+-------+
                    //      |.+------+      |
                    //    0 |.|      |      |
                    //      |.|###   |      |
                    //      +-|###   |------+
                    //      |.+------+      |
                    //    1 |.......|       |
                    //      |.......|       |
                    //      +-------+-------+
                    // ```
                    //
                    // In this example, that would mean `src` tiles `<0,0>` and `<0,1>`.

                    // The offset into the compositing region, which starts at `dst.start_px` in `dst` and `src.start_px` in `src`
                    const min_offset_px = .{
                        dst_tile_pos_in_px[0] + dst_min_in_tile_px[0] - dst.start_px[0],
                        dst_tile_pos_in_px[1] + dst_min_in_tile_px[1] - dst.start_px[1],
                    };
                    const max_offset_px = .{
                        dst_tile_pos_in_px[0] + dst_max_in_tile_px[0] - dst.start_px[0],
                        dst_tile_pos_in_px[1] + dst_max_in_tile_px[1] - dst.start_px[1],
                    };

                    const src_start_tile = .{
                        (src.start_px[0] + min_offset_px[0]) / tile_size[0],
                        (src.start_px[1] + min_offset_px[1]) / tile_size[1],
                    };
                    const src_end_tile = .{
                        (src.start_px[0] + max_offset_px[0]) / tile_size[0] + 1,
                        (src.start_px[1] + max_offset_px[1]) / tile_size[1] + 1,
                    };

                    for (src_start_tile[1]..src_end_tile[1]) |src_tile_y| {
                        for (src_start_tile[0]..src_end_tile[0]) |src_tile_x| {
                            const src_tile_index = src_tile_y * src_size_in_tiles[0] + src_tile_x;
                            const src_tile = &src.tiles[src_tile_index];

                            // top left corner of the src tile
                            const src_tile_pos_px = [2]u32{
                                @intCast(src_tile_x * tile_size[0]),
                                @intCast(src_tile_y * tile_size[1]),
                            };

                            // We need to find the 4 values of tile relative positions that constrain the composite region for both `src` and `dst`:
                            //
                            // 1. `min[0]`, AKA the left pos:
                            //     ```ascii-art
                            //      +--|--+
                            //      |..|##|
                            //      |..|##|
                            //      +--|--+
                            //     ```
                            //
                            // 2. `min[1]`, AKA the top pos:
                            //     ```ascii-art
                            //      +----+
                            //      |....|
                            //      ------
                            //      |####|
                            //      +----+
                            //     ```
                            const src_min_in_tile_px = [2]u32{
                                // A saturating subtraction here means the src_min will either be 0 or an offset into the tile
                                (src.start_px[0] + min_offset_px[0]) -| src_tile_pos_px[0],
                                (src.start_px[1] + min_offset_px[1]) -| src_tile_pos_px[1],
                            };

                            // We already know the `dst_min_in_tile` in terms of the overall compositing region, but we need to find it in
                            // terms of this `src` tile.
                            const src_min_offset_px = [2]u32{
                                (src_tile_pos_px[0] + src_min_in_tile_px[0]) - src.start_px[0],
                                (src_tile_pos_px[1] + src_min_in_tile_px[1]) - src.start_px[1],
                            };

                            const dst_min_in_src_tile_px = [2]u32{
                                @max(dst_min_in_tile_px[0], (dst.start_px[0] + src_min_offset_px[0]) - dst_tile_pos_in_px[0]),
                                @max(dst_min_in_tile_px[1], (dst.start_px[1] + src_min_offset_px[1]) - dst_tile_pos_in_px[1]),
                            };

                            // 3. `max[0]`, AKA the right pos:
                            //     ```ascii-art
                            //      +--|--+
                            //      |##|..|
                            //      |##|..|
                            //      +--|--+
                            //     ```
                            //
                            // 4. `max[1]`, AKA the bottom pos:
                            //     ```ascii-art
                            //      +----+
                            //      |####|
                            //      ------
                            //      |....|
                            //      +----+
                            //     ```

                            const src_max_in_tile_px = [2]u32{
                                @min((src.start_px[0] + max_offset_px[0]) - src_tile_pos_px[0], tile_size[0]),
                                @min((src.start_px[1] + max_offset_px[1]) - src_tile_pos_px[1], tile_size[1]),
                            };

                            // We already know the `dst_max_in_tile` in terms of the overall compositing region, but we need to find it in
                            // terms of this `src` tile.
                            const src_max_offset_px = [2]u32{
                                (src_tile_pos_px[0] + src_max_in_tile_px[0]) - src.start_px[0],
                                (src_tile_pos_px[1] + src_max_in_tile_px[1]) - src.start_px[1],
                            };

                            const dst_max_in_src_tile_px = [2]u32{
                                @min(dst_max_in_tile_px[0], (dst.start_px[0] + src_max_offset_px[0]) - dst_tile_pos_in_px[0]),
                                @min(dst_max_in_tile_px[1], (dst.start_px[1] + src_max_offset_px[1]) - dst_tile_pos_in_px[1]),
                            };

                            // Finally, go through each pixel and perform the compositing operation
                            for (dst_tile[dst_min_in_src_tile_px[1]..dst_max_in_src_tile_px[1]], src_tile[src_min_in_tile_px[1]..src_max_in_tile_px[1]]) |*dst_row, src_row| {
                                for (dst_row[dst_min_in_src_tile_px[0]..dst_max_in_src_tile_px[0]], src_row[src_min_in_tile_px[0]..src_max_in_tile_px[0]]) |*dst_pixel, src_pixel| {
                                    dst_pixel.* = Pixel.compositeSrcOver(dst_pixel.*, src_pixel);
                                }
                            }
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

        pub fn compositeZOrder(dst: @This(), src: ZOrdered(Pixel)) void {
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
            const px0: usize = @intFromFloat(@max(0, @floor(@min(a[0], b[0]) - rmax)));
            const px1: usize = @intFromFloat(@max(0, @ceil(@max(a[0], b[0]) + rmax)));
            const py0: usize = @intFromFloat(@max(0, @floor(@min(a[1], b[1]) - rmax)));
            const py1: usize = @intFromFloat(@max(0, @ceil(@max(a[1], b[1]) + rmax)));
            std.debug.assert(px1 - px0 > 0 and py1 - py0 > 0);
            std.debug.assert(px1 != px0 and py1 != py0);
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

        fn tilePosFromOffset(this: @This(), offset: [2]u32) TilePos {
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

        const linear = try Image(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
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

        const src_linear = try Image(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, src_size);
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

test "Tiled composite == compositeLinear" {
    // TODO: replace with fuzz testing in zig 0.14
    var prng = std.Random.DefaultPrng.init(1392207985905151498);

    const ITERATIONS = 100;
    for (0..ITERATIONS) |iteration| {
        errdefer std.debug.print("iteration = {}\n", .{iteration});

        const src_size = [2]u32{
            prng.random().uintAtMost(u32, 32) + 1,
            prng.random().uintAtMost(u32, 32) + 1,
        };
        const size = [2]u32{
            prng.random().uintLessThan(u32, 128) + src_size[0],
            prng.random().uintLessThan(u32, 128) + src_size[1],
        };

        const dst_composite_linear = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer dst_composite_linear.free(std.testing.allocator);
        const dst_composite_tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, size);
        defer dst_composite_tiled.free(std.testing.allocator);

        const clear_color = seizer.color.argb(f32, .straight, f32).init(
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
            prng.random().float(f32),
        ).convertAlphaModelTo(.premultiplied);
        errdefer std.debug.print("clear color = ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n", .{
            clear_color.b,
            clear_color.g,
            clear_color.r,
            clear_color.a,
        });

        dst_composite_linear.clear(clear_color);
        dst_composite_tiled.clear(clear_color);

        const src_linear = try Image(seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, src_size);
        defer src_linear.free(std.testing.allocator);
        const src_tiled = try Tiled(.{ 16, 16 }, seizer.color.argbf32_premultiplied).alloc(std.testing.allocator, src_size);
        defer src_tiled.free(std.testing.allocator);
        for (0..src_size[1]) |y| {
            for (0..src_size[0]) |x| {
                const pixel = seizer.color.argb(f32, .straight, f32).init(
                    prng.random().float(f32),
                    prng.random().float(f32),
                    prng.random().float(f32),
                    prng.random().float(f32),
                ).convertAlphaModelTo(.premultiplied);
                const pos = [2]u32{ @intCast(x), @intCast(y) };
                src_linear.setPixel(pos, pixel);
                src_tiled.setPixel(pos, pixel);
                try std.testing.expectEqual(src_linear.getPixel(pos), src_tiled.getPixel(pos));
            }
        }

        for (0..10) |composite_idx| {
            const pos = [2]u32{
                prng.random().uintAtMost(u32, size[0] - src_size[0]),
                prng.random().uintAtMost(u32, size[1] - src_size[1]),
            };
            errdefer std.debug.print("composite {} pos = <{}, {}>, size = {}x{}\n", .{ composite_idx, pos[0], pos[1], src_size[0], src_size[1] });
            dst_composite_linear.slice(pos, src_size).compositeLinear(src_linear);
            dst_composite_tiled.slice(pos, src_size).composite(src_tiled);

            for (0..size[1]) |y| {
                for (0..size[0]) |x| {
                    const check_pos = [2]u32{ @intCast(x), @intCast(y) };
                    const px_linear = dst_composite_linear.getPixel(check_pos);
                    const px_tiled = dst_composite_tiled.getPixel(check_pos);

                    errdefer std.debug.print("check_pos = <{}, {}>; linear = ({d:.2}, {d:.2}, {d:.2}, {d:.2}); tiled = ({d:.2}, {d:.2}, {d:.2}, {d:.2})\n", .{
                        check_pos[0],
                        check_pos[1],
                        px_linear.b,
                        px_linear.g,
                        px_linear.r,
                        px_linear.a,
                        px_tiled.b,
                        px_tiled.g,
                        px_tiled.r,
                        px_tiled.a,
                    });

                    try std.testing.expectEqual(px_linear, px_tiled);
                }
            }
        }
    }
}

/// Pixels are stored in a Z-Order curve pattern to increase pixel locality.
pub fn ZOrdered(Pixel: type) type {
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
    return struct {
        pixels: [*]Pixel,
        size: [2]u32,
        start_px: [2]u32,
        end_px: [2]u32,

        pub fn alloc(allocator: std.mem.Allocator, size: [2]u32) !@This() {
            const max_dimension = @max(size[0], size[1]);
            const pixels = try allocator.alloc(Pixel, max_dimension * max_dimension);
            errdefer allocator.free(pixels);

            return .{
                .pixels = pixels.ptr,
                .size = size,
                .start_px = .{ 0, 0 },
                .end_px = size,
            };
        }

        pub fn clear(this: @This(), pixel: Pixel) void {
            const max_dimension = @max(this.size[0], this.size[1]);
            @memset(this.pixels[0 .. max_dimension * max_dimension], pixel);
        }

        pub fn free(this: @This(), allocator: std.mem.Allocator) void {
            const max_dimension = @max(this.size[0], this.size[1]);
            allocator.free(this.pixels[0 .. max_dimension * max_dimension]);
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
            std.debug.assert(new_start[0] <= this.size[0] and new_start[1] <= this.size[1]);
            std.debug.assert(new_end[0] <= this.size[0] and new_end[1] <= this.size[1]);

            return .{
                .pixels = this.pixels,
                .size = this.size,
                .start_px = new_start,
                .end_px = new_end,
            };
        }

        fn pixelIndex(pos: [2]u32) usize {
            var index: u32 = 0;
            for (0..16) |i_usize| {
                const i: u5 = @intCast(i_usize);
                index |= ((1 & (pos[0] >> i)) << (2 * i + 0));
                index |= ((1 & (pos[1] >> i)) << (2 * i + 1));
            }
            return index;
        }

        pub fn setPixel(this: @This(), pos: [2]u32, color: Pixel) void {
            std.debug.assert(this.start_px[0] + pos[0] < this.size[0] and this.start_px[1] + pos[1] < this.size[1]);
            const index = pixelIndex(.{ @intCast(pos[0]), @intCast(pos[1]) });
            this.pixels[index] = color;
        }

        pub fn getPixel(this: @This(), pos: [2]u32) Pixel {
            std.debug.assert(this.start_px[0] + pos[0] < this.size[0] and this.start_px[1] + pos[1] < this.size[1]);
            const index = pixelIndex(.{ @intCast(pos[0]), @intCast(pos[1]) });
            return this.pixels[index];
        }
    };
}

/// Pixel components are stored in separate arrays
pub fn Planar(Pixel: type) type {
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOver"));
    std.debug.assert(@hasDecl(Pixel, "compositeSrcOverVecPlanar"));
    std.debug.assert(@hasDecl(Pixel, "SUGGESTED_VECTOR_LEN"));

    const Components = @typeInfo(Pixel).Struct.fields;
    const N = Components.len;
    const component_pointer_fields = blk: {
        var pointer_fields: [N]std.builtin.Type.StructField = undefined;
        for (&pointer_fields, Components) |*ptr_field, component| {
            ptr_field.* = .{
                .name = component.name,
                .type = [*]component.type,
                .default_value = null,
                .is_comptime = component.is_comptime,
                .alignment = @alignOf([*]component.type),
            };
        }
        break :blk pointer_fields;
    };
    const COMPONENT_SIZES = blk: {
        var sizes: [N]usize = undefined;
        for (&sizes, Components) |*s, component| {
            s.* = @sizeOf(component.type);
        }
        break :blk sizes;
    };
    const COMPONENT_SIZE_TOTAL = blk: {
        var total: usize = 0;
        for (COMPONENT_SIZES) |size| {
            total += size;
        }
        break :blk total;
    };

    return struct {
        pixels: [*]u8,
        size: [2]u32,
        start_px: [2]u32,
        end_px: [2]u32,

        pub const ComponentPointers = @Type(.{ .Struct = .{
            .layout = .auto,
            .backing_integer = null,
            .decls = &.{},
            .is_tuple = false,
            .fields = &component_pointer_fields,
        } });

        pub fn alloc(allocator: std.mem.Allocator, size: [2]u32) !@This() {
            const pixels = try allocator.alloc(u8, size[0] * size[1] * COMPONENT_SIZE_TOTAL);
            errdefer allocator.free(pixels);

            return .{
                .pixels = pixels.ptr,
                .size = size,
                .start_px = .{ 0, 0 },
                .end_px = size,
            };
        }

        pub fn clear(this: @This(), pixel: Pixel) void {
            std.debug.assert(this.start_px[0] == 0 and this.start_px[1] == 0);
            std.debug.assert(this.end_px[0] == this.size[0] and this.end_px[1] == this.size[1]);

            const planes = this.componentPointers();

            const plane_len = this.size[0] * this.size[1];
            inline for (Components) |component| {
                @memset(@field(planes, component.name)[0..plane_len], @field(pixel, component.name));
            }
        }

        pub fn free(this: @This(), allocator: std.mem.Allocator) void {
            std.debug.assert(this.start_px[0] == 0 and this.start_px[1] == 0);
            std.debug.assert(this.end_px[0] == this.size[0] and this.end_px[1] == this.size[1]);
            allocator.free(this.pixels[0 .. this.size[0] * this.size[1]]);
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
            std.debug.assert(new_start[0] <= this.size[0] and new_start[1] <= this.size[1]);
            std.debug.assert(new_end[0] <= this.size[0] and new_end[1] <= this.size[1]);

            return .{
                .pixels = this.pixels,
                .size = this.size,
                .start_px = new_start,
                .end_px = new_end,
            };
        }

        fn pixelIndex(this: @This(), pos: [2]u32) usize {
            std.debug.assert(pos[0] < this.size[0] and pos[1] < this.size[1]);
            return pos[1] * this.size[0] + pos[0];
        }

        fn componentPointers(this: @This()) ComponentPointers {
            const plane_len = this.size[0] * this.size[1];

            var offset: usize = 0;
            var result: ComponentPointers = undefined;
            inline for (component_pointer_fields, COMPONENT_SIZES) |ptr_field_info, size| {
                @field(result, ptr_field_info.name) = @ptrCast(@alignCast(this.pixels[offset..]));
                offset += plane_len * size;
            }

            return result;
        }

        pub fn setPixel(this: @This(), offset: [2]u32, color: Pixel) void {
            const pos = [2]u32{ this.start_px[0] + offset[0], this.start_px[1] + offset[1] };
            const index = this.pixelIndex(pos);

            const planes = this.componentPointers();

            inline for (Components) |component| {
                @field(planes, component.name)[index] = @field(color, component.name);
            }
        }

        pub fn getPixel(this: @This(), offset: [2]u32) Pixel {
            const pos = [2]u32{ this.start_px[0] + offset[0], this.start_px[1] + offset[1] };
            const index = this.pixelIndex(pos);

            const planes = this.componentPointers();

            var result: Pixel = undefined;
            inline for (Components) |component| {
                @field(result, component.name) = @field(planes, component.name)[index];
            }
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

            const dst_planes = dst.componentPointers();
            const src_planes = src.componentPointers();

            for (dst.start_px[1]..dst.end_px[1], src.start_px[1]..src.end_px[1]) |dst_y, src_y| {
                var offset_x: u32 = 0;
                while (offset_x + Pixel.SUGGESTED_VECTOR_LEN < dst_size[0]) : (offset_x += Pixel.SUGGESTED_VECTOR_LEN) {
                    const dst_index = dst.pixelIndex(.{ @intCast(dst.start_px[0] + offset_x), @intCast(dst_y) });
                    const src_index = src.pixelIndex(.{ @intCast(src.start_px[0] + offset_x), @intCast(src_y) });

                    var dst_vec: Pixel.Vectorized(Pixel.SUGGESTED_VECTOR_LEN) = undefined;
                    inline for (Components) |component| {
                        @field(dst_vec, component.name) = @field(dst_planes, component.name)[dst_index .. dst_index + Pixel.SUGGESTED_VECTOR_LEN][0..Pixel.SUGGESTED_VECTOR_LEN].*;
                    }

                    var src_vec: Pixel.Vectorized(Pixel.SUGGESTED_VECTOR_LEN) = undefined;
                    inline for (Components) |component| {
                        @field(src_vec, component.name) = @field(src_planes, component.name)[src_index .. src_index + Pixel.SUGGESTED_VECTOR_LEN][0..Pixel.SUGGESTED_VECTOR_LEN].*;
                    }

                    const result_vec = Pixel.compositeSrcOverVecPlanar(
                        Pixel.SUGGESTED_VECTOR_LEN,
                        dst_vec,
                        src_vec,
                    );

                    inline for (Components) |component| {
                        @field(dst_planes, component.name)[dst_index .. dst_index + Pixel.SUGGESTED_VECTOR_LEN][0..Pixel.SUGGESTED_VECTOR_LEN].* = @field(result_vec, component.name);
                    }
                }

                for (dst.start_px[0] + offset_x..dst.end_px[0], src.start_px[0] + offset_x..src.end_px[0]) |dst_x, src_x| {
                    const dst_index = dst.pixelIndex(.{ @intCast(dst_x), @intCast(dst_y) });
                    const src_index = src.pixelIndex(.{ @intCast(src_x), @intCast(src_y) });

                    var dst_px: Pixel = undefined;
                    inline for (Components) |component| {
                        @field(dst_px, component.name) = @field(dst_planes, component.name)[dst_index];
                    }

                    var src_px: Pixel = undefined;
                    inline for (Components) |component| {
                        @field(src_px, component.name) = @field(src_planes, component.name)[src_index];
                    }

                    const result_px = Pixel.compositeSrcOver(dst_px, src_px);

                    inline for (Components) |component| {
                        @field(dst_planes, component.name)[dst_index] = @field(result_px, component.name);
                    }
                }
            }
        }
    };
}

const probes = @import("probes");
const std = @import("std");
const seizer = @import("./seizer.zig");
const zigimg = @import("zigimg");
