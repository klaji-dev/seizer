pub const wasm = @import("backend/wasm.zig");
pub const wayland = @import("backend/wayland.zig");
pub const linux = @import("backend/linux.zig");

pub const gl = if (builtin.target.cpu.arch.isWasm())
    wasm.gl
else
    @import("gl");

pub const Backend = struct {
    name: []const u8,
    /// should return true if the next backend should be tried
    main: *const fn () anyerror!void,
    createWindow: *const fn (this: *seizer.Context, options: seizer.Context.CreateWindowOptions) anyerror!seizer.Window,
    addButtonInput: *const fn (this: *seizer.Context, options: seizer.Context.AddButtonInputOptions) anyerror!void,
    write_file_fn: *const fn (this: *seizer.Context, options: seizer.Context.WriteFileOptions) void,
    read_file_fn: *const fn (this: *seizer.Context, options: seizer.Context.ReadFileOptions) void,
};

pub fn main() !void {
    if (builtin.target.os.tag == .linux) {
        if (wayland.BACKEND.main()) {
            //
        } else |wayland_err| if (linux.BACKEND.main()) {
            std.debug.print("{s}\n", .{@errorName(wayland_err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            //
        } else |err| {
            std.debug.print("{s}\n", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            //
        }
    } else if (builtin.target.cpu.arch.isWasm()) {
        if (wasm.BACKEND.main()) {
            //
        } else |err| {
            std.log.err("{s}", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
    }
}

const LibraryPaths = struct {
    arena: std.heap.ArenaAllocator,
    paths: std.ArrayListUnmanaged([]const u8),
};
/// This function will pre-emptively load libraries so GLFW will detect Wayland on NixOS.
pub fn getLibrarySearchPaths(gpa: std.mem.Allocator) !LibraryPaths {
    var path_arena_allocator = std.heap.ArenaAllocator.init(gpa);
    errdefer path_arena_allocator.deinit();
    const arena = path_arena_allocator.allocator();

    var prefixes_to_try = std.ArrayList([]const u8).init(arena);

    try prefixes_to_try.append(try arena.dupe(u8, "."));
    try prefixes_to_try.append(try arena.dupe(u8, ""));
    try prefixes_to_try.append(try arena.dupe(u8, "/usr/lib/"));
    if (std.process.getEnvVarOwned(arena, "NIX_LD_LIBRARY_PATH")) |path_list| {
        var path_list_iter = std.mem.tokenize(u8, path_list, ":");
        while (path_list_iter.next()) |path| {
            try prefixes_to_try.append(path);
        }
    } else |_| {}

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const exe_dir_path = try std.fs.selfExeDirPath(&path_buf);
    var dir_to_search_opt: ?[]const u8 = exe_dir_path;
    while (dir_to_search_opt) |dir_to_search| : (dir_to_search_opt = std.fs.path.dirname(dir_to_search)) {
        try prefixes_to_try.append(try std.fs.path.join(arena, &.{ dir_to_search, "lib" }));
    }

    return LibraryPaths{
        .arena = path_arena_allocator,
        .paths = prefixes_to_try.moveToUnmanaged(),
    };
}

pub fn tryLoadDynamicLibraryFromPrefixes(prefixes: []const []const u8, library_name: []const u8) !std.DynLib {
    for (prefixes) |prefix| {
        var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        @memcpy(path_buffer[0..prefix.len], prefix);
        path_buffer[prefix.len] = '/';
        @memcpy(path_buffer[prefix.len + 1 ..][0..library_name.len], library_name);
        const path = path_buffer[0 .. prefix.len + 1 + library_name.len];

        std.log.debug("trying to load library at \"{}\"", .{std.zig.fmtEscapes(path)});
        const lib = std.DynLib.open(path) catch |err| switch (err) {
            error.FileNotFound => {
                continue;
            },
            else => |e| return e,
        };
        return lib;
    }
    return error.FileNotFound;
}

const seizer = @import("./seizer.zig");
const std = @import("std");
const builtin = @import("builtin");
