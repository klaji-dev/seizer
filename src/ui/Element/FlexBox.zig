stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,

children: std.AutoArrayHashMapUnmanaged(Element, AABB) = .{},
direction: Direction = .column,
justification: Justification = .start,
cross_align: CrossAlign = .start,

pub const Direction = enum {
    row,
    column,
};

pub const Justification = enum {
    start,
    center,
    space_between,
    end,
};

pub const CrossAlign = enum {
    start,
    center,
    end,
};

pub fn create(stage: *ui.Stage) !*@This() {
    const this = try stage.gpa.create(@This());
    this.* = .{
        .stage = stage,
    };
    return this;
}

pub fn appendChild(this: *@This(), child: Element) !void {
    try this.children.putNoClobber(this.stage.gpa, child, .{ .min = .{ 0, 0 }, .max = .{ 0, 0 } });
    child.acquire();
    child.setParent(this.element());
    this.stage.needs_layout = true;
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
    const child_rect = this.children.get(child) orelse return null;

    if (this.parent) |parent| {
        if (parent.getChildRect(this.element())) |rect_transform| {
            return .{
                .rect = child_rect.translate(rect_transform.rect.min),
                .transform = rect_transform.transform,
            };
        }
    }
    return .{
        .rect = child_rect,
        .transform = seizer.geometry.mat4.identity(f64),
    };
}

fn processEvent(this: *@This(), event: seizer.input.Event) ?Element {
    switch (event) {
        .hover => |hover| {
            for (this.children.keys(), this.children.values()) |child_element, child_rect| {
                if (child_rect.contains(hover.pos)) {
                    const child_event = event.transform(seizer.geometry.mat4.translate(f64, .{
                        -child_rect.min[0],
                        -child_rect.min[1],
                        0,
                    }));

                    if (child_element.processEvent(child_event)) |hovered| {
                        return hovered;
                    }
                }
            }
        },
        .click => |click| {
            for (this.children.keys(), this.children.values()) |child_element, child_rect| {
                if (child_rect.contains(click.pos)) {
                    const child_event = event.transform(seizer.geometry.mat4.translate(f64, .{
                        -child_rect.min[0],
                        -child_rect.min[1],
                        0,
                    }));

                    if (child_element.processEvent(child_event)) |clicked| {
                        return clicked;
                    }
                }
            }
        },
        else => {},
    }
    return null;
}

pub fn getMinSize(this: *@This()) [2]f64 {
    const main_axis: usize = switch (this.direction) {
        .row => 0,
        .column => 1,
    };
    const cross_axis: usize = switch (this.direction) {
        .row => 1,
        .column => 0,
    };

    var min_size = [2]f64{ 0, 0 };
    for (this.children.keys()) |child_element| {
        const child_min = child_element.getMinSize();

        min_size[main_axis] += child_min[main_axis];
        min_size[cross_axis] = @max(min_size[cross_axis], child_min[cross_axis]);
    }
    return min_size;
}

pub fn layout(this: *@This(), min_size: [2]f64, max_size: [2]f64) [2]f64 {
    const content_min_size = this.getMinSize();

    const main_axis: usize = switch (this.direction) {
        .row => 0,
        .column => 1,
    };
    const cross_axis: usize = switch (this.direction) {
        .row => 1,
        .column => 0,
    };

    // Do a first pass where we divide the space equally between the children
    const main_equal_space_per_child = max_size[main_axis] / @as(f64, @floatFromInt(this.children.count()));

    var main_space_used: f64 = 0;
    var cross_min_width: f64 = min_size[cross_axis];
    var children_requesting_space: f64 = 0;
    for (this.children.keys(), this.children.values()) |child_element, *child_rect| {
        var constraint_min: [2]f64 = undefined;
        var constraint_max: [2]f64 = undefined;

        constraint_min[main_axis] = 0;
        constraint_min[cross_axis] = cross_min_width;

        constraint_max[main_axis] = main_equal_space_per_child;
        constraint_max[cross_axis] = max_size[cross_axis];

        const child_size = child_element.layout(constraint_min, constraint_max);
        child_rect.* = .{ .min = .{ 0, 0 }, .max = child_size };
        if (child_size[main_axis] >= main_equal_space_per_child) {
            children_requesting_space += 1;
        }

        main_space_used += child_size[main_axis];
        cross_min_width = @max(cross_min_width, child_size[cross_axis]);
    }

    // Do a second pass where we allocate more space to any children that used their full amount of space
    const MAX_ITERATIONS = 10;
    var iterations: usize = 0;
    while (main_space_used < max_size[main_axis] and children_requesting_space >= 0 and iterations < MAX_ITERATIONS) : (iterations += 1) {
        const main_space_per_grow = (max_size[main_axis] - main_space_used) / children_requesting_space;

        main_space_used = 0;
        cross_min_width = min_size[cross_axis];
        children_requesting_space = 0;
        for (this.children.keys(), this.children.values()) |child_element, *child_rect| {
            var constraint_min: [2]f64 = undefined;
            var constraint_max: [2]f64 = undefined;

            constraint_min[main_axis] = child_rect.max[main_axis];
            constraint_min[cross_axis] = child_rect.max[cross_axis];

            if (child_rect.max[main_axis] >= main_equal_space_per_child) {
                constraint_max[main_axis] = child_rect.max[main_axis] + main_space_per_grow;
            } else {
                constraint_max[main_axis] = child_rect.max[main_axis];
            }
            constraint_max[cross_axis] = max_size[cross_axis];

            child_rect.max = child_element.layout(constraint_min, constraint_max);
            if (child_rect.max[main_axis] >= main_equal_space_per_child) {
                children_requesting_space += 1;
            }

            main_space_used += child_rect.max[main_axis];
            cross_min_width = @max(cross_min_width, child_rect.max[cross_axis]);
        }
    }

    main_space_used = @max(content_min_size[main_axis], main_space_used);

    const num_items: f64 = @floatFromInt(this.children.count());

    const space_before: f64 = switch (this.justification) {
        .start, .space_between => 0,
        .center => (max_size[main_axis] - main_space_used) / 2,
        .end => max_size[main_axis] - main_space_used,
    };
    const space_between: f64 = switch (this.justification) {
        .start, .center, .end => 0,
        .space_between => (max_size[main_axis] - main_space_used) / @max(num_items - 1, 1),
    };
    const space_after: f64 = switch (this.justification) {
        .start => max_size[main_axis] - main_space_used,
        .center => (max_size[main_axis] - main_space_used) / 2,
        .space_between, .end => 0,
    };
    _ = space_after;

    const cross_axis_size = @min(max_size[cross_axis], cross_min_width);

    var main_pos: f64 = space_before;

    for (this.children.values()) |*child_rect| {
        var child_translate: [2]f64 = undefined;
        child_translate[main_axis] = main_pos;
        child_translate[cross_axis] = switch (this.cross_align) {
            .start => 0,
            .center => (cross_axis_size - child_rect.size()[cross_axis]) / 2,
            .end => cross_axis_size - child_rect.size()[cross_axis],
        };

        child_rect.* = child_rect.translate(child_translate);

        main_pos = child_rect.max[main_axis] + space_between;
    }

    var bounds = [2]f64{ 0, 0 };
    bounds[main_axis] = max_size[main_axis];
    bounds[cross_axis] = cross_axis_size;
    return bounds;
}

fn render(this: *@This(), canvas: Canvas, rect: AABB) void {
    for (this.children.keys(), this.children.values()) |child_element, child_rect| {
        child_element.render(canvas, child_rect.translate(rect.min));
    }
}

const seizer = @import("../../seizer.zig");
const ui = seizer.ui;
const Element = ui.Element;
const AABB = seizer.geometry.AABB(f64);
const Canvas = seizer.Canvas;
const std = @import("std");
