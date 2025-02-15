stage: *ui.Stage,
reference_count: usize = 1,
parent: ?Element = null,

text: std.ArrayListUnmanaged(u8) = .{},
/// Minimum width of the text area in ems.
width: f64 = 16,
cursor_pos: usize = 0,
selection_start: usize = 0,

default_style: ui.Style,
hovered_style: ui.Style,
focused_style: ui.Style,

on_enter: ?ui.Callable(fn (*@This()) void) = null,

const SELECTION_COLOR = seizer.color.fromSRGB(0xFF, 0xFF, 0xFF, 0xAA);

pub fn create(stage: *ui.Stage) !*@This() {
    const this = try stage.gpa.create(@This());
    this.* = .{
        .stage = stage,
        .default_style = stage.default_style,
        .hovered_style = stage.default_style,
        .focused_style = stage.default_style,
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
        this.cursor_pos = 0;
        this.selection_start = 0;
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
    const style = if (this.stage.isFocused(this.element()))
        this.focused_style
    else if (this.stage.isHovered(this.element()))
        this.hovered_style
    else
        this.default_style;

    const min_size = this.getMinSize();

    switch (event) {
        .hover => |hover| {
            if (this.stage.isPointerCaptureElement(this.element())) {
                const click_pos = [2]f64{
                    hover.pos[0] - MARGIN.min[0] - style.padding.min[0],
                    hover.pos[1] - MARGIN.min[1] - style.padding.min[1],
                };

                // check if the mouse is above or below the text field
                if (hover.pos[1] < 0) {
                    this.cursor_pos = 0;
                    return this.element();
                } else if (hover.pos[1] > min_size[1]) {
                    this.cursor_pos = this.text.items.len;
                    return this.element();
                }

                // check if the mouse is to the left or the right of the text field
                if (hover.pos[0] < 0) {
                    this.cursor_pos = 0;
                    return this.element();
                } else if (hover.pos[0] > min_size[0]) {
                    this.cursor_pos = this.text.items.len;
                    return this.element();
                }

                var text_layout = style.text_font.textLayout(this.text.items, .{ .pos = .{ 0, 0 }, .scale = style.text_scale });
                var prev_x: f64 = 0;
                var index: usize = 0;
                while (text_layout.next()) |_| : (index += 1) {
                    if (click_pos[0] >= prev_x and click_pos[0] <= text_layout.current_offset[0]) {
                        const dist_prev = click_pos[0] - prev_x;
                        const dist_this = text_layout.current_offset[0] - click_pos[0];
                        if (dist_prev < dist_this) {
                            this.cursor_pos = index;
                        } else {
                            this.cursor_pos = index + 1;
                        }
                        break;
                    }
                    prev_x = text_layout.current_offset[0];
                } else {
                    this.cursor_pos = this.text.items.len;
                }
            }

            return this.element();
        },

        .click => |click| {
            if (!click.pressed and click.button == .left) {
                this.stage.releasePointer(this.element());
            }
            if (click.button != .left) return null;

            if (!click.pressed) return this.element();

            this.stage.setFocusedElement(this.element());
            this.stage.capturePointer(this.element());

            const click_pos = [2]f64{
                click.pos[0] - MARGIN.min[0] - style.padding.min[0],
                click.pos[1] - MARGIN.min[1] - style.padding.min[1],
            };

            var text_layout = style.text_font.textLayout(this.text.items, .{ .pos = .{ 0, 0 }, .scale = style.text_scale });
            var prev_x: f64 = 0;
            var index: usize = 0;
            while (text_layout.next()) |_| : (index += 1) {
                if (click_pos[0] >= prev_x and click_pos[0] <= text_layout.current_offset[0]) {
                    const dist_prev = click_pos[0] - prev_x;
                    const dist_this = text_layout.current_offset[0] - click_pos[0];
                    if (dist_prev < dist_this) {
                        this.selection_start = index;
                        this.cursor_pos = index;
                    } else {
                        this.selection_start = index + 1;
                        this.cursor_pos = index + 1;
                    }
                    break;
                }
                prev_x = text_layout.current_offset[0];
            } else {
                this.cursor_pos = this.text.items.len;
            }

            return this.element();
        },
        .key => |key| {
            if (!this.stage.isFocused(this.element())) {
                // We don't want the TextField to absorb any other key events unless it is focused
                switch (key.key) {
                    .enter => if (key.action == .press or key.action == .repeat) {
                        this.stage.setFocusedElement(this.element());
                        return this.element();
                    },
                    else => {},
                }
                return null;
            }
            switch (key.key) {
                .unicode => |character| switch (character) {
                    // backspace unicode character
                    0x0008 => if (key.action == .press or key.action == .repeat) {
                        // TODO: ctrl+backspace = delete previous word
                        this.backspace();
                        return this.element();
                    },
                    // delete unicode character
                    0x007F => if (key.action == .press or key.action == .repeat) {
                        // TODO: ctrl+delete = delete next word
                        const src_pos = if (this.selection_start == this.cursor_pos)
                            nextRight(this.text.items, this.cursor_pos)
                        else
                            @max(this.selection_start, this.cursor_pos);
                        const overwrite_pos = @min(this.selection_start, this.cursor_pos);

                        const bytes_removed = src_pos - overwrite_pos;
                        std.mem.copyForwards(u8, this.text.items[overwrite_pos..], this.text.items[src_pos..]);
                        this.text.shrinkRetainingCapacity(this.text.items.len - bytes_removed);

                        this.cursor_pos = overwrite_pos;
                        this.selection_start = overwrite_pos;
                        return this.element();
                    },
                    '\n', '\r' => if (key.action == .press or key.action == .repeat) {
                        this.stage.setFocusedElement(null);
                        if (this.on_enter) |on_enter| {
                            on_enter.call(.{this});
                        }
                        return this.element();
                    },
                    else => if (key.action == .press or key.action == .repeat) {
                        // control + a = select all
                        if (key.mods.control and character == 'a') {
                            this.selection_start = 0;
                            this.cursor_pos = this.text.items.len;
                            return this.element();
                        }
                        // TODO: control + c = copy
                        // TODO: control + x = cut
                        // TODO: control + v = paste
                        // TODO: control + z = undo
                        // TODO: control + y = redo

                        // Delete any text that is currently selected
                        var buf: [4]u8 = undefined;
                        const encoded_len = std.unicode.utf8Encode(character, &buf) catch unreachable;
                        this.insertReplacingSelectedText(buf[0..encoded_len]) catch @panic("OOM");

                        return this.element();
                    },
                },
                .arrow_left => if (key.action == .press or key.action == .repeat) {
                    // TODO: ctrl+left = move to beginning of previous word
                    this.cursor_pos = if (key.mods.control)
                        0
                    else
                        nextLeft(this.text.items, this.cursor_pos);
                    if (!key.mods.shift) {
                        this.selection_start = this.cursor_pos;
                    }
                    return this.element();
                },
                .arrow_right => if (key.action == .press or key.action == .repeat) {
                    // TODO: ctrl+right = move to beginning of next word
                    this.cursor_pos = if (key.mods.control)
                        this.text.items.len
                    else
                        nextRight(this.text.items, this.cursor_pos);
                    if (!key.mods.shift) {
                        this.selection_start = this.cursor_pos;
                    }
                    return this.element();
                },
                .home => if (key.action == .press or key.action == .repeat) {
                    this.cursor_pos = 0;
                    if (!key.mods.shift) {
                        this.selection_start = this.cursor_pos;
                    }
                    return this.element();
                },
                .end => if (key.action == .press or key.action == .repeat) {
                    this.cursor_pos = this.text.items.len;
                    if (!key.mods.shift) {
                        this.selection_start = this.cursor_pos;
                    }
                    return this.element();
                },
                .enter => if (key.action == .press or key.action == .repeat) {
                    this.stage.setFocusedElement(null);
                    if (this.on_enter) |on_enter| {
                        on_enter.call(.{this});
                    }
                    return this.element();
                },
                .escape => if (key.action == .press or key.action == .repeat) {
                    this.stage.setFocusedElement(null);
                },
                else => {},
            }
            return this.element();
        },
        else => {},
    }

    return null;
}

const MARGIN = seizer.geometry.Inset(f64){
    .min = .{ 2, 2 },
    .max = .{ 2, 2 },
};

pub fn getMinSize(this: *@This()) [2]f64 {
    const style = if (this.stage.isFocused(this.element()))
        this.focused_style
    else if (this.stage.isHovered(this.element()))
        this.hovered_style
    else
        this.default_style;

    return .{
        this.width * style.text_font.line_height * style.text_scale + style.padding.size()[0] + MARGIN.size()[0],
        style.text_font.line_height * style.text_scale + style.padding.size()[1] + MARGIN.size()[1],
    };
}

fn render(this: *@This(), parent_canvas: Canvas, rect: AABB) void {
    const style = if (this.stage.isFocused(this.element()))
        this.focused_style
    else if (this.stage.isHovered(this.element()))
        this.hovered_style
    else
        this.default_style;

    parent_canvas.ninePatch(
        rect.inset(MARGIN),
        style.background_image.image,
        style.background_image.inset,
        .{
            .scale = 1,
            .color = style.background_color,
        },
    );

    const pre_cursor_size = style.text_font.textSize(this.text.items[0..this.cursor_pos], style.text_scale);

    const selection_start = @min(this.cursor_pos, this.selection_start);
    const selection_end = @max(this.cursor_pos, this.selection_start);

    const pre_selection_size = style.text_font.textSize(this.text.items[0..selection_start], style.text_scale);
    const selection_size = style.text_font.textSize(this.text.items[selection_start..selection_end], style.text_scale);

    const text_rect = rect.inset(MARGIN).inset(style.padding);

    var clipped_canvas = parent_canvas.transformed(.{ .clip = text_rect });
    const canvas = clipped_canvas.canvas();

    _ = canvas.writeText(style.text_font, text_rect.min, this.text.items, .{
        .scale = style.text_scale,
        .color = style.text_color,
    });
    if (this.stage.isFocused(this.element())) {
        canvas.fillRect(
            .{
                .min = .{ text_rect.min[0] + pre_selection_size[0], text_rect.min[1] },
                .max = .{ text_rect.min[0] + pre_selection_size[0] + selection_size[0], text_rect.max[1] },
            },
            SELECTION_COLOR,
            .{},
        );
        canvas.line(
            .{ text_rect.min[0] + pre_cursor_size[0], text_rect.min[1] },
            .{ text_rect.min[0] + pre_cursor_size[0], text_rect.max[1] },
            .{
                .color = style.text_color,
            },
        );
    }
}

fn nextLeft(text: []const u8, pos: usize) usize {
    std.debug.assert(pos <= text.len);
    if (pos == 0) return 0;
    var new_pos = pos - 1;
    while (new_pos > 0 and text[new_pos] & 0b1000_0000 != 0b0000_0000) {
        new_pos -= 1;
    }
    return new_pos;
}

fn nextRight(text: []const u8, pos: usize) usize {
    std.debug.assert(pos <= text.len);
    if (pos == text.len) return text.len;
    var new_pos = pos + 1;
    while (new_pos < text.len and text[new_pos] & 0b1000_0000 != 0b0000_0000) {
        new_pos += 1;
    }
    return new_pos;
}

pub fn backspace(this: *@This()) void {
    const src_pos = @max(this.selection_start, this.cursor_pos);
    const overwrite_pos = if (this.selection_start == this.cursor_pos)
        nextLeft(this.text.items, this.cursor_pos)
    else
        @min(this.selection_start, this.cursor_pos);

    const bytes_removed = src_pos - overwrite_pos;
    std.mem.copyForwards(u8, this.text.items[overwrite_pos..], this.text.items[src_pos..]);
    this.text.shrinkRetainingCapacity(this.text.items.len - bytes_removed);

    this.cursor_pos = overwrite_pos;
    this.selection_start = overwrite_pos;
}

pub fn insertReplacingSelectedText(this: *@This(), new_text: []const u8) !void {
    const src_pos = @max(this.selection_start, this.cursor_pos);
    const overwrite_pos = @min(this.selection_start, this.cursor_pos);

    const bytes_removed = src_pos - overwrite_pos;
    std.mem.copyForwards(u8, this.text.items[overwrite_pos..], this.text.items[src_pos..]);
    this.text.shrinkRetainingCapacity(this.text.items.len - bytes_removed);

    this.cursor_pos = overwrite_pos;

    // Append new text
    try this.text.insertSlice(this.stage.gpa, this.cursor_pos, new_text);
    this.cursor_pos += new_text.len;
    this.selection_start = this.cursor_pos;
}

const seizer = @import("../../seizer.zig");
const AABB = seizer.geometry.AABB(f64);
const Element = ui.Element;
const ui = @import("../../ui.zig");
const Canvas = @import("../../Canvas.zig");
const std = @import("std");
