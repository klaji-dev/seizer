stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,
style: ui.Style,

child: ?Element = null,
child_rect: AABB = AABB.init(.{ 0, 0 }, .{ 0, 0 }),

pub fn create(stage: *ui.Stage) !*@This() {
    const this = try stage.gpa.create(@This());
    this.* = .{
        .stage = stage,
        .style = stage.default_style,
    };
    return this;
}

pub fn setChild(this: *@This(), new_child_opt: ?Element) void {
    if (new_child_opt) |new_child| {
        new_child.acquire();
    }
    if (this.child) |r| {
        r.release();
    }
    if (new_child_opt) |new_child| {
        new_child.setParent(this.element());
    }
    this.child = new_child_opt;
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
        if (this.child) |child| {
            child.release();
        }
        this.stage.gpa.destroy(this);
    }
}

fn setParent(this: *@This(), new_parent: ?Element) void {
    this.parent = new_parent;
}

fn getParent(this: *@This()) ?Element {
    return this.parent;
}

fn element_getChildRect(this: *@This(), child: Element) ?Element.TransformedRect {
    if (!std.meta.eql(this.child, child)) return null;

    if (this.parent) |parent| {
        if (parent.getChildRect(this.element())) |parent_rect_transform| {
            return .{
                .rect = AABB.init(
                    .{
                        parent_rect_transform.rect.min()[0] + this.child_rect.min()[0],
                        parent_rect_transform.rect.min()[1] + this.child_rect.min()[1],
                    },
                    .{
                        parent_rect_transform.rect.min()[0] + this.child_rect.max()[0],
                        parent_rect_transform.rect.min()[1] + this.child_rect.max()[1],
                    },
                ),
                .transform = parent_rect_transform.transform,
            };
        }
    }
    return .{
        .rect = this.child_rect,
        .transform = seizer.geometry.mat4.identity(f64),
    };
}

fn processEvent(this: *@This(), event: seizer.input.Event) ?Element {
    if (this.child == null) return null;

    const child_event = event.transform(seizer.geometry.mat4.translate(f64, .{
        -this.child_rect.min()[0],
        -this.child_rect.min()[1],
        0,
    }));

    switch (event) {
        .hover => |hover| {
            if (this.child_rect.contains(hover.pos)) {
                return this.child.?.processEvent(child_event);
            }
        },
        .click => |click| {
            if (this.child_rect.contains(click.pos)) {
                return this.child.?.processEvent(child_event);
            }
        },
        else => {},
    }
    return null;
}

fn getMinSize(this: *@This()) [2]f64 {
    const padding_size = this.style.padding.size();

    if (this.child) |child| {
        const child_size = child.getMinSize();
        return .{
            child_size[0] + padding_size[0],
            child_size[1] + padding_size[1],
        };
    }

    return padding_size;
}

pub fn layout(this: *@This(), min_size: [2]f64, max_size: [2]f64) [2]f64 {
    const padding_size = this.style.padding.size();

    if (this.child) |child| {
        const child_size = child.layout(min_size, .{
            max_size[0] - padding_size[0],
            max_size[1] - padding_size[1],
        });
        this.child_rect = AABB.init(
            this.style.padding.min,
            .{
                this.style.padding.min[0] + child_size[0],
                this.style.padding.min[1] + child_size[1],
            },
        );
        return .{
            child_size[0] + padding_size[0],
            child_size[1] + padding_size[1],
        };
    }

    return padding_size;
}

fn render(this: *@This(), canvas: Canvas, rect: AABB) void {
    canvas.ninePatch(rect, this.style.background_image.image, this.style.background_image.inset, .{
        .color = this.style.background_color,
    });

    if (this.child) |child| {
        child.render(canvas, this.child_rect.translate(rect.min));
    }
}

const seizer = @import("../../seizer.zig");
const ui = seizer.ui;
const Element = ui.Element;
const AABB = seizer.geometry.AABB(f64);
const Canvas = seizer.Canvas;
const std = @import("std");
