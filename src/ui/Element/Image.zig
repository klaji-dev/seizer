stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,

image: seizer.image.Image(seizer.color.argbf32_premultiplied),

pub fn create(stage: *ui.Stage, image: seizer.image.Image(seizer.color.argbf32_premultiplied)) !*@This() {
    const this = try stage.gpa.create(@This());
    errdefer stage.gpa.destroy(this);

    this.* = .{
        .stage = stage,
        .image = image,
    };
    return this;
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

    .process_event_fn = processEvent,
    .get_min_size_fn = getMinSize,
    .render_fn = render,
});

fn acquire(this: *@This()) void {
    this.reference_count += 1;
}

fn release(this: *@This()) void {
    this.reference_count -= 1;
    if (this.reference_count == 0) {
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
    _ = this;
    _ = event;
    return null;
}

fn getMinSize(this: *@This()) [2]f64 {
    return .{
        @floatFromInt(this.image.size[0]),
        @floatFromInt(this.image.size[1]),
    };
}

fn render(this: *@This(), canvas: Canvas, rect: Rect) void {
    // consr source_rect = .{
    //     .pos = .{ 0, 0 },
    //     .size = .{ @floatFromInt(image.size[0]), @floatFromInt(image.size[1]) },
    // };

    canvas.textureRect(rect.pos, rect.size, this.image, .{});
}

const seizer = @import("../../seizer.zig");
const ui = seizer.ui;
const Element = ui.Element;
const Rect = seizer.geometry.Rect(f64);
const Canvas = seizer.Canvas;
const std = @import("std");
