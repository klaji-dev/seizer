pub const PLATFORM = seizer.Platform{
    .name = "linuxbsd",
    .main = main,
    .allocator = getAllocator,
    .loop = _getLoop,
    .setShouldExit = _setShouldExit,
    // .createWindow = createWindow,
    // .addButtonInput = addButtonInput,
    .writeFile = writeFile,
    .readFile = readFile,
    .setDeinitCallback = setDeinitFn,
    .setEventCallback = setEventCallback,
};

var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = builtin.mode == .Debug }){};
var loop: xev.Loop = undefined;
var evdev: EvDev = undefined;
var should_exit: bool = false;
var key_bindings: std.AutoHashMapUnmanaged(seizer.Platform.Binding, std.ArrayListUnmanaged(seizer.Platform.AddButtonInputOptions)) = .{};
var deinit_fn: ?seizer.Platform.DeinitFn = null;
var renderdoc: @import("renderdoc") = undefined;

pub fn main() anyerror!void {
    const root = @import("root");

    if (!@hasDecl(root, "init")) {
        @compileError("root module must contain init function");
    }

    defer _ = gpa.deinit();

    loop = try xev.Loop.init(.{});
    defer loop.deinit();

    defer {
        var iter = key_bindings.valueIterator();
        while (iter.next()) |actions| {
            actions.deinit(gpa.allocator());
        }
        key_bindings.deinit(gpa.allocator());
    }

    evdev = try EvDev.init(gpa.allocator(), &loop, &key_bindings);
    defer evdev.deinit();
    try evdev.scanForDevices();

    {
        var library_prefixes = @"dynamic-library-utils".getLibrarySearchPaths(gpa.allocator()) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.LibraryLoadFailed,
        };
        defer library_prefixes.arena.deinit();

        renderdoc = @import("renderdoc").loadUsingPrefixes(library_prefixes.paths.items);
    }

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
    while (!should_exit) {
        try loop.run(.once);
    }
}

pub fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

fn _getLoop() *xev.Loop {
    return &loop;
}

fn _setShouldExit(new_should_exit: bool) void {
    should_exit = new_should_exit;
}

// pub fn createGraphics(allocator: std.mem.Allocator, options: seizer.Platform.CreateGraphicsOptions) seizer.Platform.CreateGraphicsError!seizer.Graphics {
//     if (seizer.Graphics.impl.vulkan.create(allocator, options)) |graphics| {
//         return graphics;
//     } else |err| {
//         std.log.warn("Failed to create vulkan context: {}", .{err});
//         if (@errorReturnTrace()) |err_return_trace| {
//             std.debug.dumpStackTrace(err_return_trace.*);
//         }
//     }

//     // if (seizer.Graphics.impl.gles3v0.create(allocator, options)) |graphics| {
//     //     return graphics;
//     // } else |err| {
//     //     std.log.warn("Failed to create gles3v0 context: {}", .{err});
//     //     if (@errorReturnTrace()) |err_return_trace| {
//     //         std.debug.dumpStackTrace(err_return_trace.*);
//     //     }
//     // }

//     return error.InitializationFailed;
// }

pub fn addButtonInput(options: seizer.Platform.AddButtonInputOptions) anyerror!void {
    for (options.default_bindings) |button_code| {
        const gop = try key_bindings.getOrPut(gpa.allocator(), button_code);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(gpa.allocator(), options);
    }
}

pub fn writeFile(options: seizer.Platform.WriteFileOptions) void {
    linuxbsd_fs.writeFile(gpa.allocator(), options);
}

pub fn readFile(options: seizer.Platform.ReadFileOptions) void {
    linuxbsd_fs.readFile(gpa.allocator(), options);
}

fn setEventCallback(new_on_event_callback: ?*const fn (event: seizer.input.Event) anyerror!void) void {
    _ = new_on_event_callback;
    // window_manager.setEventCallback(new_on_event_callback);
}

fn setDeinitFn(new_deinit_fn: ?seizer.Platform.DeinitFn) void {
    deinit_fn = new_deinit_fn;
}

pub const EvDev = @import("./linuxbsd/evdev.zig");

const linuxbsd_fs = @import("./linuxbsd/fs.zig");

const @"dynamic-library-utils" = @import("dynamic-library-utils");
const xev = @import("xev");
const seizer = @import("../seizer.zig");
const builtin = @import("builtin");
const std = @import("std");
