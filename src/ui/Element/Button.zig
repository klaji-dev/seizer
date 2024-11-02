stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,

text: std.ArrayListUnmanaged(u8),

default_style: Style,
hovered_style: Style,
clicked_style: Style,

on_click: ?ui.Callable(fn (*@This()) void) = null,

const RECT_COLOR_DEFAULT = seizer.color.argb(f64).fromArray(.{ 0x30.0 / 0xFF.0, 0x30.0 / 0xFF.0, 0x30.0 / 0xFF.0, 1 });
const RECT_COLOR_HOVERED = seizer.color.argb(f64).fromArray(.{ 0x50.0 / 0xFF.0, 0x50.0 / 0xFF.0, 0x50.0 / 0xFF.0, 1 });
const RECT_COLOR_CLICKED = seizer.color.argb(f64).fromArray(.{ 0x70.0 / 0xFF.0, 0x70.0 / 0xFF.0, 0x70.0 / 0xFF.0, 1 });

const TEXT_COLOR_DEFAULT = seizer.color.argb(f64).fromArray(.{ 1, 1, 1, 1 });
const TEXT_COLOR_HOVERED = seizer.color.argb(f64).fromArray(.{ 1, 1, 0.5, 1 });
const TEXT_COLOR_CLICKED = seizer.color.argb(f64).fromArray(.{ 1, 1, 0, 1 });

pub const Style = struct {
    padding: seizer.geometry.Inset(f64),
    text_font: *const seizer.Canvas.Font,
    text_scale: f64,
    text_color: seizer.color.argb(f64),
    background_ninepatch: ?seizer.Canvas.NinePatch = null,
    background_color: seizer.color.argb(f64),
};

pub fn create(stage: *ui.Stage, text: []const u8) !*@This() {
    const this = try stage.gpa.create(@This());

    const pad = stage.default_style.text_font.line_height / 2;
    const default_style = Style{
        .padding = .{
            .min = .{ pad, pad },
            .max = .{ pad, pad },
        },
        .text_font = stage.default_style.text_font,
        .text_scale = stage.default_style.text_scale,
        .text_color = TEXT_COLOR_DEFAULT,
        .background_ninepatch = null,
        .background_color = RECT_COLOR_DEFAULT,
    };

    const hovered_style = Style{
        .padding = .{
            .min = .{ pad, pad },
            .max = .{ pad, pad },
        },
        .text_font = stage.default_style.text_font,
        .text_scale = stage.default_style.text_scale,
        .text_color = TEXT_COLOR_HOVERED,
        .background_ninepatch = null,
        .background_color = RECT_COLOR_HOVERED,
    };

    const clicked_style = Style{
        .padding = .{
            .min = .{ pad, pad },
            .max = .{ pad, pad },
        },
        .text_font = stage.default_style.text_font,
        .text_scale = stage.default_style.text_scale,
        .text_color = TEXT_COLOR_CLICKED,
        .background_ninepatch = null,
        .background_color = RECT_COLOR_CLICKED,
    };

    var text_owned = std.ArrayListUnmanaged(u8){};
    errdefer text_owned.deinit(stage.gpa);
    try text_owned.appendSlice(stage.gpa, text);

    this.* = .{
        .stage = stage,
        .text = text_owned,
        .default_style = default_style,
        .hovered_style = hovered_style,
        .clicked_style = clicked_style,
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
        this.text.deinit(this.stage.gpa);
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
    switch (event) {
        .hover => return this.element(),
        .click => |click| {
            if (click.button == .left) {
                if (click.pressed) {
                    this.stage.capturePointer(this.element());

                    if (this.on_click) |on_click| {
                        on_click.call(.{this});
                    }
                } else {
                    this.stage.releasePointer(this.element());
                }
                return this.element();
            }
        },
        .key => |key| {
            switch (key.key) {
                .unicode => |c| if ((c == ' ' or c == '\n') and key.action == .press) {
                    this.stage.capturePointer(this.element());
                    if (this.on_click) |on_click| {
                        on_click.call(.{this});
                    }
                    return this.element();
                } else {
                    this.stage.releasePointer(this.element());
                },
                else => {},
            }
        },
        else => {},
    }

    return null;
}

pub fn getMinSize(this: *@This()) [2]f64 {
    const is_pressed = if (this.stage.pointer_capture_element) |pce| pce.ptr == this.element().ptr else false;
    const is_hovered = if (this.stage.hovered_element) |hovered| hovered.ptr == this.element().ptr else false;
    const style = if (is_pressed) this.clicked_style else if (is_hovered) this.hovered_style else this.default_style;

    const text_size = style.text_font.textSize(this.text.items, style.text_scale);
    return .{
        text_size[0] + style.padding.size()[0],
        text_size[1] + style.padding.size()[1],
    };
}

fn render(this: *@This(), canvas: Canvas, rect: Rect) void {
    const is_pressed = if (this.stage.pointer_capture_element) |pce| pce.ptr == this.element().ptr else false;
    const is_hovered = if (this.stage.hovered_element) |hovered| hovered.ptr == this.element().ptr else false;
    const style = if (is_pressed) this.clicked_style else if (is_hovered) this.hovered_style else this.default_style;

    if (style.background_ninepatch) |ninepatch| {
        canvas.ninePatch(rect.pos, rect.size, ninepatch.image, ninepatch.inset, .{
            .color = style.background_color,
        });
    } else {
        canvas.fillRect(rect.pos, rect.size, .{
            .color = style.background_color,
        });
    }

    _ = canvas.writeText(style.text_font, .{
        rect.pos[0] + style.padding.min[0],
        rect.pos[1] + style.padding.min[1],
    }, this.text.items, .{
        .scale = style.text_scale,
        .color = style.text_color,
    });
}

const seizer = @import("../../seizer.zig");
const ui = seizer.ui;
const Element = ui.Element;
const Rect = seizer.geometry.Rect(f64);
const Canvas = seizer.Canvas;
const std = @import("std");
