// seizer sub libraries
pub const color = @import("./color.zig");
pub const colormaps = @import("./colormaps.zig");
pub const geometry = @import("./geometry.zig");
pub const image = @import("./image.zig");
pub const input = @import("./input.zig");
pub const ui = @import("./ui.zig");

pub const Canvas = @import("./Canvas.zig");
pub const Display = @import("./Display.zig");

// re-exported libraries
pub const tvg = @import("tvg");
pub const xev = @import("xev");

/// Seizer version
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

//
const seizer = @This();

var loop: xev.Loop = undefined;
var deinit_fn: ?DeinitFn = null;

pub fn main() anyerror!void {
    const root = @import("root");

    if (!@hasDecl(root, "init")) {
        @compileError("root module must contain init function");
    }

    loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Call root module's `init()` function
    root.init() catch |err| {
        std.debug.print("{s}\n", .{@errorName(err)});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        return;
    };
    defer {
        if (deinit_fn) |deinit| {
            deinit();
        }
    }

    try loop.run(.until_done);
}

pub fn getLoop() *xev.Loop {
    return &loop;
}

pub const DeinitFn = *const fn () void;
pub fn setDeinit(new_deinit_fn: ?seizer.DeinitFn) void {
    deinit_fn = new_deinit_fn;
}

comptime {
    if (builtin.is_test) {
        _ = color;
        _ = image;
    }
}

const builtin = @import("builtin");
const std = @import("std");
