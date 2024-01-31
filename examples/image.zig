pub fn init(stage: *seizer.Stage) !void {
    stage.handler = .{
        .ptr = undefined,
        .interface = .{
            .respond = index,
        },
    };
    log.debug("app initialized", .{});
}

pub fn index(ptr: *anyopaque, stage: *seizer.Stage, request: seizer.Request) anyerror!seizer.Response {
    _ = ptr;
    _ = stage;
    if (std.mem.eql(u8, request.path, "assets/wedge.png")) {
        return seizer.Response{
            .image_data = @embedFile("assets/wedge.png"),
        };
    } else {
        return seizer.Response{
            .screen = &.{
                .{ .image = .{ .source = "assets/wedge.png" } },
            },
        };
    }
}

const log = std.log.scoped(.example_image);

const seizer = @import("seizer");
const gl = seizer.gl;
const std = @import("std");
