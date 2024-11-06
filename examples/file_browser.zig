pub const main = seizer.main;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
var display: seizer.Display = undefined;
var toplevel_surface: seizer.Display.ToplevelSurface = undefined;
var render_listener: seizer.Display.ToplevelSurface.OnRenderListener = undefined;
var input_listener: seizer.Display.ToplevelSurface.OnInputListener = undefined;

var _font: seizer.Canvas.Font = undefined;
var ui_image: seizer.image.Image(seizer.color.argbf32_premultiplied) = undefined;
var _stage: *seizer.ui.Stage = undefined;

pub fn init() !void {
    try display.init(gpa.allocator(), seizer.getLoop());

    try display.initToplevelSurface(&toplevel_surface, .{});
    toplevel_surface.setOnInput(&input_listener, onToplevelInputEvent, null);
    toplevel_surface.setOnRender(&render_listener, onRender, null);

    _font = try seizer.Canvas.Font.fromFileContents(
        gpa.allocator(),
        @embedFile("./assets/PressStart2P_8.fnt"),
        &.{
            .{ .name = "PressStart2P_8.png", .contents = @embedFile("./assets/PressStart2P_8.png") },
        },
    );
    errdefer _font.deinit();

    ui_image = try seizer.image.Image(seizer.color.argbf32_premultiplied).fromMemory(gpa.allocator(), @embedFile("./assets/ui.png"));
    errdefer ui_image.free(gpa.allocator());

    _stage = try seizer.ui.Stage.create(gpa.allocator(), .{
        .padding = .{
            .min = .{ 16, 16 },
            .max = .{ 16, 16 },
        },
        .text_font = &_font,
        .text_scale = 1,
        .text_color = seizer.color.argbf32_premultiplied.WHITE,
        .background_image = seizer.Canvas.NinePatch.init(ui_image.slice(.{ 0, 0 }, .{ 48, 48 }), seizer.geometry.Inset(u32).initXY(16, 16)),
        .background_color = seizer.color.argbf32_premultiplied.WHITE,
    });
    errdefer _stage.destroy();

    const file_browser = try FileBrowserElement.create(_stage, .{});
    defer file_browser.release();
    _stage.setRoot(file_browser.element());

    seizer.setDeinit(deinit);
}

pub fn deinit() void {
    _stage.destroy();

    _font.deinit();
    ui_image.free(gpa.allocator());

    toplevel_surface.deinit();
    display.deinit();
    _ = gpa.deinit();
}

fn onToplevelInputEvent(listener: *seizer.Display.ToplevelSurface.OnInputListener, surface: *seizer.Display.ToplevelSurface, event: seizer.input.Event) !void {
    _ = listener;
    if (_stage.processEvent(event)) |_| {
        try surface.requestAnimationFrame();
        try display.connection.sendRequest(@TypeOf(surface.wl_surface)._SPECIFIED_INTERFACE, surface.wl_surface, .commit, .{});
    }
}

fn onRender(listener: *seizer.Display.ToplevelSurface.OnRenderListener, surface: *seizer.Display.ToplevelSurface) anyerror!void {
    _ = listener;

    const canvas = try surface.canvas();
    canvas.clear(.{ .r = 0.5, .g = 0.5, .b = 0.7, .a = 1.0 });

    _stage.needs_layout = true;
    _stage.render(canvas, canvas.size());

    try surface.present();
}

const FileBrowserElement = struct {
    stage: *seizer.ui.Stage,
    reference_count: usize = 1,
    parent: ?seizer.ui.Element = null,

    top_bar_back_button: *seizer.ui.Element.Button,
    top_bar_forward_button: *seizer.ui.Element.Button,
    top_bar_refresh_button: *seizer.ui.Element.Button,
    top_bar_address_label: *seizer.ui.Element.Label,
    top_bar_up_button: *seizer.ui.Element.Button,

    top_bar_back_button_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },
    top_bar_forward_button_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },
    top_bar_refresh_button_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },
    top_bar_address_label_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },
    top_bar_up_button_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },

    directory: std.fs.Dir,
    history: std.ArrayListUnmanaged([]const u8) = .{},
    history_index: usize = 0,

    arena: std.heap.ArenaAllocator,
    entries_rect: seizer.geometry.Rect(f64) = .{ .pos = .{ 0, 0 }, .size = .{ 0, 0 } },
    entries: ?std.ArrayListUnmanaged(Entry) = null,
    hovered: ?usize = null,

    /// spacing between lines, given as a multiple of lineHeight
    spacing: f64 = 1.5,

    const HOVERED_BG_COLOR = seizer.color.fromSRGB(0xFF, 0xFF, 0xFF, 0x80);
    const MARKED_BG_COLOR = seizer.color.fromSRGB(0x00, 0x00, 0x00, 0x80);

    pub const Entry = struct {
        name: []const u8,
        marked: bool = false,

        fn lessThan(_: void, a: @This(), b: @This()) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    };

    pub const CreateOptions = struct {
        /// Must be opened with the `iterate` permission
        directory: ?std.fs.Dir = null,
    };

    pub fn create(stage: *seizer.ui.Stage, options: CreateOptions) !*@This() {
        const this = try stage.gpa.create(@This());
        errdefer stage.gpa.destroy(this);

        var directory = options.directory orelse try std.fs.cwd().openDir(".", .{ .iterate = true });
        errdefer directory.close();

        const top_bar_back_button = try seizer.ui.Element.Button.create(stage, "<");
        errdefer top_bar_back_button.element().release();
        top_bar_back_button.on_click = .{ .userdata = this, .callback = onBackClicked };

        const top_bar_forward_button = try seizer.ui.Element.Button.create(stage, ">");
        errdefer top_bar_forward_button.element().release();
        top_bar_forward_button.on_click = .{ .userdata = this, .callback = onForwardClicked };

        const top_bar_refresh_button = try seizer.ui.Element.Button.create(stage, "refresh");
        errdefer top_bar_refresh_button.element().release();
        top_bar_refresh_button.on_click = .{ .userdata = this, .callback = onRefreshClicked };

        const top_bar_address_label = try seizer.ui.Element.Label.create(stage, "");
        errdefer top_bar_address_label.element().release();

        const top_bar_up_button = try seizer.ui.Element.Button.create(stage, "up");
        errdefer top_bar_up_button.element().release();
        top_bar_up_button.on_click = .{ .userdata = this, .callback = onUpClicked };

        this.* = .{
            .stage = stage,
            .directory = directory,
            .arena = std.heap.ArenaAllocator.init(stage.gpa),

            // .top_bar_flexbox = top_bar_flexbox,
            .top_bar_back_button = top_bar_back_button,
            .top_bar_forward_button = top_bar_forward_button,
            .top_bar_refresh_button = top_bar_refresh_button,
            .top_bar_address_label = top_bar_address_label,
            .top_bar_up_button = top_bar_up_button,
        };

        const current_filepath = try directory.realpathAlloc(stage.gpa, ".");
        errdefer stage.gpa.free(current_filepath);

        try this.history.append(stage.gpa, current_filepath);
        errdefer {
            for (this.history.items) |item| {
                stage.gpa.free(item);
            }
            this.history.deinit(stage.gpa);
        }

        this.top_bar_back_button.element().setParent(this.element());
        this.top_bar_forward_button.element().setParent(this.element());
        this.top_bar_refresh_button.element().setParent(this.element());
        this.top_bar_address_label.element().setParent(this.element());
        this.top_bar_up_button.element().setParent(this.element());

        try this.refresh();

        return this;
    }

    pub fn refresh(this: *@This()) !void {
        this.hovered = null;
        if (this.entries) |*entries| {
            entries.deinit(this.stage.gpa);
            this.entries = null;
        }
        _ = this.arena.reset(.retain_capacity);

        this.top_bar_address_label.text.deinit(this.stage.gpa);
        this.top_bar_address_label.text = std.ArrayListUnmanaged(u8).fromOwnedSlice(try this.directory.realpathAlloc(this.stage.gpa, "."));

        var entries = std.ArrayListUnmanaged(Entry){};
        errdefer entries.deinit(this.stage.gpa);

        var iterator = this.directory.iterate();
        while (try iterator.next()) |entry| {
            try entries.append(this.stage.gpa, .{
                .name = try this.arena.allocator().dupe(u8, entry.name),
            });
        }

        std.sort.insertion(Entry, entries.items, {}, Entry.lessThan);

        this.entries = entries;
        this.stage.needs_layout = true;
    }

    pub fn element(this: *@This()) seizer.ui.Element {
        return .{
            .ptr = this,
            .interface = &INTERFACE,
        };
    }

    const INTERFACE = seizer.ui.Element.Interface.getTypeErasedFunctions(@This(), .{
        .acquire_fn = acquire,
        .release_fn = release,
        .set_parent_fn = setParent,
        .get_parent_fn = getParent,

        .process_event_fn = processEvent,
        .get_min_size_fn = getMinSize,
        .layout_fn = layout,
        .render_fn = fileBrowserRender,
    });

    fn acquire(this: *@This()) void {
        this.reference_count += 1;
    }

    fn release(this: *@This()) void {
        this.reference_count -= 1;
        if (this.reference_count == 0) {
            this.top_bar_back_button.element().release();
            this.top_bar_forward_button.element().release();
            this.top_bar_refresh_button.element().release();
            this.top_bar_address_label.element().release();
            this.top_bar_up_button.element().release();
            if (this.entries) |*entries| {
                entries.deinit(this.stage.gpa);
            }

            for (this.history.items) |item| {
                this.stage.gpa.free(item);
            }
            this.history.deinit(this.stage.gpa);

            this.arena.deinit();
            this.directory.close();
            this.stage.gpa.destroy(this);
        }
    }

    fn setParent(this: *@This(), new_parent: ?seizer.ui.Element) void {
        this.parent = new_parent;
    }

    fn getParent(this: *@This()) ?seizer.ui.Element {
        return this.parent;
    }

    fn processEvent(this: *@This(), event: seizer.input.Event) ?seizer.ui.Element {
        const font = this.stage.default_style.text_font;
        const scale = this.stage.default_style.text_scale;

        switch (event) {
            .hover => |hover| {
                this.hovered = null;
                const top_bar_elements = &[_]std.meta.Tuple(&.{ seizer.ui.Element, seizer.geometry.Rect(f64) }){
                    .{ this.top_bar_back_button.element(), this.top_bar_back_button_rect },
                    .{ this.top_bar_forward_button.element(), this.top_bar_forward_button_rect },
                    .{ this.top_bar_refresh_button.element(), this.top_bar_refresh_button_rect },
                    .{ this.top_bar_address_label.element(), this.top_bar_address_label_rect },
                    .{ this.top_bar_up_button.element(), this.top_bar_up_button_rect },
                };
                for (top_bar_elements) |top_bar_element| {
                    if (top_bar_element[1].contains(hover.pos)) {
                        return top_bar_element[0].processEvent(.{
                            .hover = hover.transform(seizer.geometry.mat4.translate(f64, top_bar_element[1].pos ++ .{0})),
                        });
                    }
                }

                var pos: [2]f64 = this.entries_rect.pos;
                if (this.entries) |entries| {
                    for (entries.items, 0..) |entry, i| {
                        pos[1] += @floor((this.spacing - 1) * font.line_height);
                        const rect = seizer.geometry.Rect(f64){
                            .pos = pos,
                            .size = .{ this.entries_rect.size[0], font.textSize(entry.name, scale)[1] },
                        };
                        if (rect.contains(hover.pos)) {
                            this.hovered = i;
                            return this.element();
                        }
                        pos[1] += rect.size[1];
                    }
                }
            },
            .click => |click| if (click.button == .left and click.pressed) {
                const top_bar_elements = &[_]std.meta.Tuple(&.{ seizer.ui.Element, seizer.geometry.Rect(f64) }){
                    .{ this.top_bar_back_button.element(), this.top_bar_back_button_rect },
                    .{ this.top_bar_forward_button.element(), this.top_bar_forward_button_rect },
                    .{ this.top_bar_refresh_button.element(), this.top_bar_refresh_button_rect },
                    .{ this.top_bar_address_label.element(), this.top_bar_address_label_rect },
                    .{ this.top_bar_up_button.element(), this.top_bar_up_button_rect },
                };
                for (top_bar_elements) |top_bar_element| {
                    if (top_bar_element[1].contains(click.pos)) {
                        return top_bar_element[0].processEvent(.{
                            .click = click.transform(seizer.geometry.mat4.translate(f64, top_bar_element[1].pos ++ .{0})),
                        });
                    }
                }

                if (this.entries) |entries| {
                    for (entries.items) |*entry| {
                        entry.marked = false;
                    }
                }

                var pos: [2]f64 = this.entries_rect.pos;
                if (this.entries) |entries| {
                    for (entries.items) |*entry| {
                        pos[1] += @floor((this.spacing - 1) * font.line_height);
                        const rect = seizer.geometry.Rect(f64){
                            .pos = pos,
                            .size = .{ this.entries_rect.size[0], font.textSize(entry.name, scale)[1] },
                        };
                        if (rect.contains(click.pos)) {
                            entry.marked = true;
                            return this.element();
                        }
                        pos[1] += rect.size[1];
                    }
                }
            },
            else => {},
        }
        return null;
    }

    pub fn getMinSize(this: *@This()) [2]f64 {
        var top_bar_min_size = [2]f64{ 0, 0 };
        const top_bar_elements = &[_]seizer.ui.Element{
            this.top_bar_back_button.element(),
            this.top_bar_forward_button.element(),
            this.top_bar_refresh_button.element(),
            this.top_bar_address_label.element(),
            this.top_bar_up_button.element(),
        };
        for (top_bar_elements) |top_bar_element| {
            const size = top_bar_element.getMinSize();
            top_bar_min_size[0] += size[0];
            top_bar_min_size[1] = @max(top_bar_min_size[1], size[1]);
        }

        var entries_min_size = [2]f64{ 0, 0 };
        if (this.entries) |entries| {
            for (entries.items) |entry| {
                // add some extra spacing between text
                entries_min_size[1] += (this.spacing - 1) * this.stage.default_style.text_font.line_height;
                const entry_size = this.stage.default_style.text_font.textSize(entry.name, this.stage.default_style.text_scale);
                entries_min_size[0] = @max(entries_min_size[0], entry_size[0]);
                entries_min_size[1] += entry_size[1];
            }
        }
        return .{
            @max(top_bar_min_size[0], entries_min_size[0]),
            top_bar_min_size[1] + entries_min_size[1],
        };
    }

    pub fn layout(this: *@This(), min: [2]f64, max: [2]f64) [2]f64 {
        _ = min;

        var pos = [2]f64{ 0, 0 };
        this.top_bar_back_button_rect = .{
            .pos = pos,
            .size = this.top_bar_back_button.element().getMinSize(),
        };
        pos[0] += this.top_bar_back_button_rect.size[0];

        this.top_bar_forward_button_rect = .{
            .pos = pos,
            .size = this.top_bar_forward_button.element().getMinSize(),
        };
        pos[0] += this.top_bar_forward_button_rect.size[0];

        this.top_bar_refresh_button_rect = .{
            .pos = pos,
            .size = this.top_bar_refresh_button.element().getMinSize(),
        };
        pos[0] += this.top_bar_refresh_button_rect.size[0];

        this.top_bar_up_button_rect.size = this.top_bar_up_button.element().getMinSize();
        this.top_bar_up_button_rect.pos[0] = max[0] - this.top_bar_up_button_rect.size[0];

        this.top_bar_address_label_rect.pos = pos;
        this.top_bar_address_label_rect.size[0] = this.top_bar_up_button_rect.pos[0] - this.top_bar_address_label_rect.pos[0];
        this.top_bar_address_label_rect.size[1] = this.top_bar_address_label.element().getMinSize()[1];

        const top_bar_height = std.mem.max(f64, &.{
            this.top_bar_back_button_rect.size[1],
            this.top_bar_forward_button_rect.size[1],
            this.top_bar_refresh_button_rect.size[1],
            this.top_bar_address_label_rect.size[1],
            this.top_bar_up_button_rect.size[1],
        });

        this.entries_rect.pos = [2]f64{ 0, top_bar_height };
        this.entries_rect.size = [2]f64{ max[0], 0 };
        if (this.entries) |entries| {
            for (entries.items) |entry| {
                // add some extra spacing between text
                this.entries_rect.size[1] += (this.spacing - 1) * this.stage.default_style.text_font.line_height;
                const entry_size = this.stage.default_style.text_font.textSize(entry.name, this.stage.default_style.text_scale);
                this.entries_rect.size[0] = @max(this.entries_rect.size[0], entry_size[0]);
                this.entries_rect.size[1] += entry_size[1];
            }
        }
        return max;
    }

    fn fileBrowserRender(this: *@This(), canvas: seizer.Canvas, rect: seizer.geometry.Rect(f64)) void {
        const entries = this.entries orelse return;

        const element_hovered = if (this.stage.hovered_element) |hovered| hovered.ptr == this.element().ptr else false;

        const top_bar_elements = &[_]std.meta.Tuple(&.{ seizer.ui.Element, seizer.geometry.Rect(f64) }){
            .{ this.top_bar_back_button.element(), this.top_bar_back_button_rect },
            .{ this.top_bar_forward_button.element(), this.top_bar_forward_button_rect },
            .{ this.top_bar_refresh_button.element(), this.top_bar_refresh_button_rect },
            .{ this.top_bar_address_label.element(), this.top_bar_address_label_rect },
            .{ this.top_bar_up_button.element(), this.top_bar_up_button_rect },
        };
        for (top_bar_elements) |top_bar_element| {
            top_bar_element[0].render(canvas, top_bar_element[1]);
        }

        var pos = this.entries_rect.pos;
        for (entries.items, 0..) |entry, i| {
            pos[1] += @floor((this.spacing - 1) * this.stage.default_style.text_font.line_height);

            const entry_hovered = this.hovered != null and this.hovered.? == i;
            if (element_hovered and entry_hovered) {
                canvas.fillRect(
                    pos,
                    .{ rect.size[0], this.stage.default_style.text_font.line_height },
                    .{ .color = HOVERED_BG_COLOR },
                );
            }

            // const bg_color: ?seizer.color.argbf32_premultiplied = if (entry.marked) MARKED_BG_COLOR else null;

            pos[1] += canvas.writeText(this.stage.default_style.text_font, pos, entry.name, .{})[1];
        }
    }

    // Callbacks

    fn onUpClicked(userdata: ?*anyopaque, _: *seizer.ui.Element.Button) void {
        const this: *@This() = @ptrCast(@alignCast(userdata));

        var old_directory = this.directory;
        var new_directory = this.directory.openDir("..", .{ .iterate = true }) catch {
            return;
        };
        this.history.ensureUnusedCapacity(this.stage.gpa, 1) catch return;

        this.directory = new_directory;
        this.refresh() catch |err| {
            std.log.warn("failed to refresh files: {}", .{err});
            this.directory = old_directory;
            new_directory.close();
            return;
        };

        old_directory.close();
        this.history.appendAssumeCapacity(this.directory.realpathAlloc(this.stage.gpa, ".") catch return);
        this.history_index += 1;
    }

    fn onBackClicked(userdata: ?*anyopaque, _: *seizer.ui.Element.Button) void {
        const this: *@This() = @ptrCast(@alignCast(userdata));

        if (this.history_index <= 0) return;

        const new_index = this.history_index - 1;

        var old_directory = this.directory;
        var new_directory = std.fs.cwd().openDir(this.history.items[new_index], .{ .iterate = true }) catch return;

        this.directory = new_directory;
        this.refresh() catch |err| {
            std.log.warn("failed to refresh files: {}", .{err});
            this.directory = old_directory;
            new_directory.close();
            return;
        };

        old_directory.close();
        this.history_index = new_index;
    }

    fn onForwardClicked(userdata: ?*anyopaque, _: *seizer.ui.Element.Button) void {
        const this: *@This() = @ptrCast(@alignCast(userdata));

        if (this.history_index >= this.history.items.len - 1) return;

        const new_index = this.history_index + 1;

        var old_directory = this.directory;
        var new_directory = std.fs.cwd().openDir(this.history.items[new_index], .{ .iterate = true }) catch return;

        this.directory = new_directory;
        this.refresh() catch |err| {
            std.log.warn("failed to refresh files: {}", .{err});
            this.directory = old_directory;
            new_directory.close();
            return;
        };

        old_directory.close();
        this.history_index = new_index;
    }

    fn onRefreshClicked(userdata: ?*anyopaque, _: *seizer.ui.Element.Button) void {
        const this: *@This() = @ptrCast(@alignCast(userdata));
        this.refresh() catch |err| {
            std.log.warn("failed to refresh files: {}", .{err});
            return;
        };
    }
};

const seizer = @import("seizer");
const std = @import("std");
