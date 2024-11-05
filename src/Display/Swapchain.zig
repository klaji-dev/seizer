//! An ARGB framebuffer
size: [2]u32 = .{ 0, 0 },
memory: []align(std.mem.page_size) u8 = &.{},

wl_shm_pool: shimizu.Proxy(shimizu.core.wl_shm_pool) = .{ .connection = undefined, .id = @enumFromInt(0) },
buffers: std.BoundedArray(Buffer, 6) = .{},
free: std.BoundedArray(u32, 6) = .{},

wl_buffer_event_listener: shimizu.Listener = undefined,

pub fn allocate(this: *@This(), wl_shm: shimizu.Proxy(shimizu.core.wl_shm), size: [2]u32, count: u32) !void {
    std.debug.assert(count <= 6);
    const fd = try std.posix.memfd_create("swapchain", 0);
    defer std.posix.close(fd);

    const frame_size = size[0] * size[1] * @sizeOf(seizer.color.argb8);
    const total_size = frame_size * count;
    try std.posix.ftruncate(fd, total_size);

    const memory = try std.posix.mmap(null, total_size, std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);

    const wl_shm_pool = try wl_shm.sendRequest(.create_pool, .{
        .fd = @enumFromInt(fd),
        .size = @intCast(total_size),
    });

    var buffers = std.BoundedArray(Buffer, 6){};
    var free = std.BoundedArray(u32, 6){};
    var offset: u32 = 0;
    for (0..count) |index| {
        const wl_buffer = try wl_shm_pool.sendRequest(.create_buffer, .{
            .offset = @intCast(offset),
            .width = @intCast(size[0]),
            .height = @intCast(size[1]),
            .stride = @intCast(size[0] * @sizeOf(seizer.color.argb8)),
            .format = .argb8888,
        });
        buffers.appendAssumeCapacity(.{
            .wl_buffer = wl_buffer,
            .size = size,
            .pixels = @ptrCast(@alignCast(memory[offset..][0..frame_size].ptr)),
        });
        free.appendAssumeCapacity(@intCast(index));
        offset += frame_size;
    }

    this.* = .{
        .size = size,
        .memory = memory,
        .wl_shm_pool = wl_shm_pool,
        .buffers = buffers,
        .free = free,
        .wl_buffer_event_listener = undefined,
    };
    for (this.buffers.slice()) |buffer| {
        buffer.wl_buffer.setEventListener(&this.wl_buffer_event_listener, onWlBufferEvent, this);
    }
}

pub fn deinit(this: *@This()) void {
    if (@intFromEnum(this.wl_shm_pool.id) != 0) this.wl_shm_pool.sendRequest(.destroy, .{}) catch {};
    if (this.memory.len > 0) std.posix.munmap(this.memory);
    this.* = undefined;
}

pub fn getBuffer(this: *@This()) !Buffer {
    const buffer_index = this.free.popOrNull() orelse return error.OutOfFramebuffers;
    return this.buffers.slice()[buffer_index];
}

fn onWlBufferEvent(listener: *shimizu.Listener, wl_buffer: shimizu.Proxy(shimizu.core.wl_buffer), event: shimizu.core.wl_buffer.Event) !void {
    const this: *@This() = @fieldParentPtr("wl_buffer_event_listener", listener);
    switch (event) {
        .release => {
            const index = for (this.buffers.slice(), 0..) |buffer, i| {
                if (buffer.wl_buffer.id == wl_buffer.id) break i;
            } else return;
            this.free.appendAssumeCapacity(@intCast(index));
        },
    }
}

const Image = seizer.image.Image(seizer.color.argb8);
const Buffer = @import("./Buffer.zig");

const seizer = @import("../seizer.zig");
const shimizu = @import("shimizu");
const std = @import("std");
