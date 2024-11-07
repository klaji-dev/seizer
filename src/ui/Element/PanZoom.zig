stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,

/// The size of the Canvas before zooming and panning
size: [2]f64 = .{ 1, 1 },
/// The size of the Canvas after zooming and panning
output_size: [2]f64 = .{ 1, 1 },

/// Value is log-scale, meaning that to get the actual scaling you need to do @exp(zoom)
zoom: f64 = 0,
pan: [2]f64 = .{ 0, 0 },

pan_start: ?[2]f64 = null,
cursor_pos: [2]f64 = .{ 0, 0 },

bg_color: seizer.color.argbf32_premultiplied = seizer.color.fromSRGB(0x40, 0x40, 0x40, 0xFF),

children: std.AutoArrayHashMapUnmanaged(Element, void) = .{},
systems: std.AutoArrayHashMapUnmanaged(?*anyopaque, System) = .{},

const PanZoom = @This();

const System = struct {
    userdata: ?*anyopaque,
    render_fn: RenderFn,

    const RenderFn = *const fn (userdata: ?*anyopaque, pan_zoom: *PanZoom, canvas: Canvas) void;
};

pub fn create(stage: *ui.Stage) !*@This() {
    const this = try stage.gpa.create(@This());
    this.* = .{
        .stage = stage,
    };
    return this;
}

pub fn appendChild(this: *@This(), child: Element) !void {
    try this.children.put(this.stage.gpa, child, {});
    child.acquire();
    child.setParent(this.element());
}

pub fn element(this: *@This()) Element {
    return .{
        .ptr = this,
        .interface = &INTERFACE,
    };
}

const INTERFACE = Element.Interface.getTypeErasedFunctions(@This(), .{
    .acquire_fn = acquire,
    .release_fn = release,
    .set_parent_fn = setParent,
    .get_parent_fn = getParent,
    .get_child_rect_fn = element_getChildRect,

    .process_event_fn = processEvent,
    .get_min_size_fn = getMinSize,
    .layout_fn = layout,
    .render_fn = render,
});

fn acquire(this: *@This()) void {
    this.reference_count += 1;
}

fn release(this: *@This()) void {
    this.reference_count -= 1;
    if (this.reference_count == 0) {
        for (this.children.keys()) |child| {
            child.release();
        }
        this.children.deinit(this.stage.gpa);
        this.systems.deinit(this.stage.gpa);
        this.stage.gpa.destroy(this);
    }
}

fn setParent(this: *@This(), new_parent: ?Element) void {
    this.parent = new_parent;
}

fn getParent(this: *@This()) ?Element {
    return this.parent;
}

fn processEvent(this: *@This(), event: seizer.input.Event) ?Element {
    const inverse = panZoomInverse(
        this.output_size,
        this.size,
        this.zoom,
        this.pan,
    );
    const transformed_event = event.transform(inverse);

    if (this.stage.pointer_capture_element == null or this.stage.pointer_capture_element.?.ptr != this.element().ptr) {
        for (this.children.keys()) |child| {
            if (child.processEvent(transformed_event)) |element_that_handled_event| {
                return element_that_handled_event;
            }
        }
    }

    switch (event) {
        .hover => |hover| {
            this.cursor_pos = hover.pos;
            if (this.pan_start) |pan_start| {
                this.stage.cursor_shape = .move;
                const pan_start_inverse = panZoomInverse(
                    this.output_size,
                    this.size,
                    this.zoom,
                    pan_start,
                );

                this.pan = seizer.geometry.mat4.mulVec(f64, pan_start_inverse, .{
                    hover.pos[0],
                    hover.pos[1],
                    0,
                    1,
                })[0..2].*;
                return this.element();
            }
        },
        .click => |click| {
            if (click.button == .middle) {
                if (!click.pressed) {
                    this.stage.releasePointer(this.element());
                    this.pan_start = null;
                    return this.element();
                }

                this.stage.capturePointer(this.element());
                this.pan_start = transformed_event.click.pos;
                return this.element();
            }
        },
        .scroll => |scroll| {
            const new_zoom = this.zoom - scroll.offset[1] / 128;

            const new_inverse = panZoomInverse(
                this.output_size,
                this.size,
                new_zoom,
                this.pan,
            );

            const cursor_before = seizer.geometry.mat4.mulVec(f64, inverse, this.cursor_pos ++ [2]f64{ 0, 1 });
            const cursor_after = seizer.geometry.mat4.mulVec(f64, new_inverse, this.cursor_pos ++ [2]f64{ 0, 1 });

            this.zoom = new_zoom;
            this.pan = .{
                this.pan[0] + (cursor_after[0] - cursor_before[0]),
                this.pan[1] + (cursor_after[1] - cursor_before[1]),
            };
        },
        else => {},
    }

    return this.element();
}

fn getMinSize(this: *@This()) [2]f64 {
    _ = this;
    return .{ 1, 1 };
}

pub fn layout(this: *@This(), min_size: [2]f64, max_size: [2]f64) [2]f64 {
    _ = min_size;

    this.size = .{ 0, 0 };
    for (this.children.keys()) |child| {
        const child_size = child.getMinSize();
        this.size = .{
            @max(this.size[0], child_size[0]),
            @max(this.size[1], child_size[1]),
        };
    }

    for (this.children.keys()) |child| {
        _ = child.layout(
            .{ 0, 0 },
            this.size,
        );
    }

    this.output_size = max_size;
    return this.output_size;
}

fn render(this: *@This(), parent_canvas: Canvas, rect: AABB) void {
    parent_canvas.fillRect(rect, this.bg_color, .{});

    var transformed_canvas = parent_canvas.transformed(.{
        .clip = rect,
        .transform = seizer.geometry.mat4.mul(
            f64,
            panZoomTransform(
                rect.size(),
                this.size,
                this.zoom,
                this.pan,
            ),
            seizer.geometry.mat4.translate(f64, .{ rect.min[0], rect.min[1], 0 }),
        ),
    });
    const canvas = transformed_canvas.canvas();

    for (this.children.keys()) |child| {
        child.render(canvas, .{ .min = .{ 0, 0 }, .max = this.size });
    }
    for (this.systems.values()) |system| {
        system.render_fn(system.userdata, this, canvas);
    }
}

fn element_getChildRect(this: *@This(), child: Element) ?Element.TransformedRect {
    _ = this.children.get(child) orelse return null;

    const transform = panZoomInverse(
        this.output_size,
        this.size,
        this.zoom,
        this.pan,
    );
    if (this.parent) |parent| {
        if (parent.getChildRect(this.element())) |rect_transform| {
            return .{
                .rect = .{ .min = .{ 0, 0 }, .max = this.size },
                .transform = seizer.geometry.mat4.mul(f64, transform, rect_transform.transformWithTranslation()),
            };
        }
    }
    return .{
        .rect = .{ .min = .{ 0, 0 }, .max = this.size },
        .transform = transform,
    };
}

pub fn panZoomTransform(out_size: [2]f64, child_size: [2]f64, zoom_ln: f64, pan: [2]f64) [4][4]f64 {
    const zoom = @exp(zoom_ln);

    const child_aspect = child_size[0] / child_size[1];

    const out_aspect = out_size[0] / out_size[1];

    const aspect = child_aspect / out_aspect;

    const size = if (aspect >= 1)
        [2]f64{
            out_size[0],
            out_size[1] / aspect,
        }
    else
        [2]f64{
            out_size[0] * aspect,
            out_size[1],
        };

    return seizer.geometry.mat4.mulAll(
        f64,
        &.{
            seizer.geometry.mat4.translate(f64, .{
                (out_size[0] - size[0]) / 2.0,
                (out_size[1] - size[1]) / 2.0,
                0,
            }),
            seizer.geometry.mat4.scale(f64, .{
                size[0] / child_size[0],
                size[1] / child_size[1],
                1,
            }),
            seizer.geometry.mat4.translate(f64, .{
                child_size[0] / 2.0,
                child_size[1] / 2.0,
                0,
            }),
            seizer.geometry.mat4.scale(f64, .{
                zoom,
                zoom,
                1,
            }),
            seizer.geometry.mat4.translate(f64, .{
                pan[0],
                pan[1],
                0,
            }),
            seizer.geometry.mat4.translate(f64, .{
                -child_size[0] / 2.0,
                -child_size[1] / 2.0,
                0,
            }),
        },
    );
}

pub fn panZoomInverse(out_size: [2]f64, child_size: [2]f64, zoom_ln: f64, pan: [2]f64) [4][4]f64 {
    const zoom = @exp(zoom_ln);

    const child_aspect = child_size[0] / child_size[1];

    const out_aspect = out_size[0] / out_size[1];

    const aspect = child_aspect / out_aspect;

    const size = if (aspect >= 1)
        [2]f64{
            out_size[0],
            out_size[1] / aspect,
        }
    else
        [2]f64{
            out_size[0] * aspect,
            out_size[1],
        };

    return seizer.geometry.mat4.mulAll(f64, &.{
        seizer.geometry.mat4.translate(f64, .{
            child_size[0] / 2.0,
            child_size[1] / 2.0,
            0,
        }),
        seizer.geometry.mat4.translate(f64, .{
            -pan[0],
            -pan[1],
            0,
        }),
        seizer.geometry.mat4.scale(f64, .{
            1.0 / zoom,
            1.0 / zoom,
            1,
        }),
        seizer.geometry.mat4.translate(f64, .{
            -child_size[0] / 2.0,
            -child_size[1] / 2.0,
            0,
        }),
        seizer.geometry.mat4.scale(f64, .{
            1.0 / (size[0] / child_size[0]),
            1.0 / (size[1] / child_size[1]),
            1,
        }),
        seizer.geometry.mat4.translate(f64, .{
            -(out_size[0] - size[0]) / 2.0,
            -(out_size[1] - size[1]) / 2.0,
            0,
        }),
    });
}

const seizer = @import("../../seizer.zig");
const ui = seizer.ui;
const Element = ui.Element;
const AABB = seizer.ui.AABB;
const Canvas = seizer.Canvas;
const std = @import("std");
