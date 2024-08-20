const seizer = @import("seizer.zig");
const gl = seizer.gl;

pointer: ?*anyopaque,
interface: *const Interface,

const Window = @This();

pub const Interface = struct {
    getSize: *const fn (?*anyopaque) [2]f32,
    getFramebufferSize: *const fn (?*anyopaque) [2]f32,
    setShouldClose: *const fn (?*anyopaque, should_close: bool) void,
    swapBuffers: *const fn (?*anyopaque) anyerror!void,
    setUserdata: *const fn (?*anyopaque, ?*anyopaque) void,
    getUserdata: *const fn (?*anyopaque) ?*anyopaque,
};

pub fn getSize(this: @This()) [2]f32 {
    return this.interface.getSize(this.pointer);
}

pub fn getFramebufferSize(this: @This()) [2]f32 {
    return this.interface.getFramebufferSize(this.pointer);
}

pub fn setShouldClose(this: @This(), should_close: bool) void {
    return this.interface.setShouldClose(this.pointer, should_close);
}

pub fn swapBuffers(this: @This()) anyerror!void {
    return this.interface.swapBuffers(this.pointer);
}

pub fn setUserdata(this: @This(), user_userdata: ?*anyopaque) void {
    return this.interface.setUserdata(this.pointer, user_userdata);
}

pub fn getUserdata(this: @This()) ?*anyopaque {
    return this.interface.getUserdata(this.pointer);
}
