pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;

var font: seizer.Canvas.Font = undefined;
var player_image: seizer.Image = undefined;
var sprites: std.MultiArrayList(Sprite) = .{};

var spawn_timer_duration: u32 = 10;
var spawn_timer: u32 = 0;
var prng: std.rand.DefaultPrng = undefined;

var frametimes: [256]u64 = [_]u64{0} ** 256;
var frametime_index: usize = 0;
var between_frame_timer: std.time.Timer = undefined;
var time_between_frames: [256]u64 = [_]u64{0} ** 256;

const Sprite = struct {
    pos: [2]f64,
    vel: [2]f64,
    size: [2]f64,
};
const WorldBounds = struct { min: [2]f64, max: [2]f64 };

pub fn move(positions: [][2]f64, velocities: []const [2]f64) void {
    for (positions, velocities) |*pos, vel| {
        pos[0] += vel[0];
        pos[1] += vel[1];
    }
}

pub fn keepInBounds(positions: []const [2]f64, velocities: [][2]f64, sizes: []const [2]f64, world_bounds: WorldBounds) void {
    for (positions, velocities, sizes) |pos, *vel, size| {
        if (pos[0] < world_bounds.min[0] and vel[0] < 0) vel[0] = -vel[0];
        if (pos[1] < world_bounds.min[1] and vel[1] < 0) vel[1] = -vel[1];
        if (pos[0] + size[0] > world_bounds.max[0] and vel[0] > 0) vel[0] = -vel[0];
        if (pos[1] + size[1] > world_bounds.max[1] and vel[1] > 0) vel[1] = -vel[1];
    }
}

pub fn init() !void {
    prng = std.Random.DefaultPrng.init(1337);

    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer font.deinit();

    player_image = try seizer.Image.fromMemory(gpa.allocator(), @embedFile("assets/wedge.png"));
    errdefer player_image.free(gpa.allocator());

    between_frame_timer = try std.time.Timer.start();

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    font.deinit();
    player_image.free(gpa.allocator());
    sprites.deinit(gpa.allocator());
    display.deinit();
    _ = gpa.deinit();
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;
    const window_size = surface.current_configuration.window_size;

    time_between_frames[frametime_index] = between_frame_timer.lap();

    const frame_start = std.time.nanoTimestamp();
    defer {
        const frame_end = std.time.nanoTimestamp();
        const duration: u64 = @intCast(frame_end - frame_start);
        frametimes[frametime_index] = duration;
        frametime_index += 1;
        frametime_index %= frametimes.len;
    }
    const world_bounds = WorldBounds{
        .min = .{ 0, 0 },
        .max = .{ @floatFromInt(window_size[0]), @floatFromInt(window_size[1]) },
    };

    // update sprites
    {
        const sprites_slice = sprites.slice();
        keepInBounds(sprites_slice.items(.pos), sprites_slice.items(.vel), sprites_slice.items(.size), world_bounds);
        move(sprites_slice.items(.pos), sprites_slice.items(.vel));
    }

    spawn_timer -|= 1;
    if (spawn_timer <= 1) {
        spawn_timer = spawn_timer_duration;

        const world_size = [2]f64{
            world_bounds.max[0] - world_bounds.min[0],
            world_bounds.max[1] - world_bounds.min[1],
        };

        const scale = prng.random().float(f64) * 3;
        const size = [2]f64{
            @as(f64, @floatFromInt(player_image.size[0])) * scale,
            @as(f64, @floatFromInt(player_image.size[1])) * scale,
        };
        try sprites.append(gpa.allocator(), .{
            .pos = .{
                prng.random().float(f64) * (world_size[0] - size[0]) + world_bounds.min[0],
                prng.random().float(f64) * (world_size[1] - size[1]) + world_bounds.min[1],
            },
            .vel = .{
                prng.random().float(f64) * 10 - 5,
                prng.random().float(f64) * 10 - 5,
            },
            .size = size,
        });
    }

    // begin rendering

    var framebuffer = try surface.getBuffer();
    framebuffer.clear(.{ 0.5, 0.5, 0.7, 1.0 });

    for (sprites.items(.pos), sprites.items(.size)) |pos, size| {
        framebuffer.canvas().textureRect(pos, size, player_image, .{});
    }

    var text_pos = [2]f64{ 50, 50 };
    text_pos[1] += framebuffer.canvas().printText(&font, text_pos, "sprite count = {}", .{sprites.len}, .{})[1];

    var frametime_total: f64 = 0;
    for (frametimes) |f| {
        frametime_total += @floatFromInt(f);
    }
    text_pos[1] += framebuffer.canvas().printText(&font, text_pos, "avg. frametime = {d:0.2} ms", .{frametime_total / @as(f64, @floatFromInt(frametimes.len)) / std.time.ns_per_ms}, .{})[1];

    var between_frame_total: f64 = 0;
    for (time_between_frames) |f| {
        between_frame_total += @floatFromInt(f);
    }
    text_pos[1] += framebuffer.canvas().printText(&font, text_pos, "avg. time between frames = {d:0.2} ms", .{between_frame_total / @as(f64, @floatFromInt(frametimes.len)) / std.time.ns_per_ms}, .{})[1];

    try surface.requestAnimationFrame();
    try surface.present(framebuffer);
}

const seizer = @import("seizer");
const std = @import("std");
