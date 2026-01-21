const std = @import("std");
const renderer_mod = @import("../render/render.zig");

fn checkedDimension(value: anytype, comptime label: []const u8) u16 {
    if (@TypeOf(value) == comptime_int or @TypeOf(value) == comptime_float) {
        if (value < 0 or value > std.math.maxInt(u16)) {
            const msg = std.fmt.comptimePrint("zit: {s} must fit within u16", .{label});
            @compileError(msg);
        }
        return @intCast(value);
    }

    const casted = std.math.cast(u16, value) orelse std.debug.panic("zit: {s} must fit within u16 (got {any})", .{ label, value });
    return casted;
}

fn validateMinMaxComptime(min_raw: anytype, max_raw: anytype, comptime name: []const u8) void {
    const min_comptime = @TypeOf(min_raw) == comptime_int or @TypeOf(min_raw) == comptime_float;
    const max_comptime = @TypeOf(max_raw) == comptime_int or @TypeOf(max_raw) == comptime_float;
    if (min_comptime and max_comptime) {
        if (max_raw < min_raw) {
            const msg = std.fmt.comptimePrint("zit: {s} minimum must not exceed maximum", .{name});
            @compileError(msg);
        }
    }
}

fn saturatingAdd(a: u16, b: u16) u16 {
    const sum = std.math.add(u32, a, b) catch std.math.maxInt(u32);
    return @intCast(@min(sum, std.math.maxInt(u16)));
}

fn intersectsViewport(rect: Rect, renderer: *renderer_mod.Renderer) bool {
    if (rect.width == 0 or rect.height == 0) return false;
    if (renderer.back.width == 0 or renderer.back.height == 0) return false;
    return rect.x < renderer.back.width and rect.y < renderer.back.height;
}

/// Layout system module
///
/// This module provides functionality for arranging UI elements:
/// - Widget tree with parent-child relationships
/// - Flexbox/grid layout algorithms
/// - Geometry constraints and dynamic resizing
/// - Margin and padding support
/// Represents a rectangle with position and size
pub const Rect = struct {
    /// X coordinate (column)
    x: u16,
    /// Y coordinate (row)
    y: u16,
    /// Width in columns
    width: u16,
    /// Height in rows
    height: u16,

    /// Create a new rectangle
    pub fn init(x: anytype, y: anytype, width: anytype, height: anytype) Rect {
        return Rect{
            .x = checkedDimension(x, "rect.x"),
            .y = checkedDimension(y, "rect.y"),
            .width = checkedDimension(width, "rect.width"),
            .height = checkedDimension(height, "rect.height"),
        };
    }

    /// Check if a point is inside the rectangle
    pub fn contains(self: Rect, x: u16, y: u16) bool {
        const max_x = std.math.add(u32, self.x, self.width) catch std.math.maxInt(u32);
        const max_y = std.math.add(u32, self.y, self.height) catch std.math.maxInt(u32);
        return x >= self.x and @as(u32, x) < max_x and
            y >= self.y and @as(u32, y) < max_y;
    }

    /// Get the intersection of two rectangles
    pub fn intersection(self: Rect, other: Rect) ?Rect {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        if (x1 >= x2 or y1 >= y2) {
            return null; // No intersection
        }

        return Rect{
            .x = x1,
            .y = y1,
            .width = x2 - x1,
            .height = y2 - y1,
        };
    }

    /// Shrink the rectangle by the given insets
    pub fn shrink(self: Rect, insets: EdgeInsets) Rect {
        const new_x = self.x + insets.left;
        const new_y = self.y + insets.top;
        const combined_width = saturatingAdd(insets.left, insets.right);
        const combined_height = saturatingAdd(insets.top, insets.bottom);
        const new_width = if (self.width > combined_width)
            self.width - combined_width
        else
            0;
        const new_height = if (self.height > combined_height)
            self.height - combined_height
        else
            0;

        return Rect{
            .x = new_x,
            .y = new_y,
            .width = new_width,
            .height = new_height,
        };
    }

    /// Expand the rectangle by the given insets
    pub fn expand(self: Rect, insets: EdgeInsets) Rect {
        const combined_width = saturatingAdd(insets.left, insets.right);
        const combined_height = saturatingAdd(insets.top, insets.bottom);
        const expanded_width = saturatingAdd(self.width, combined_width);
        const expanded_height = saturatingAdd(self.height, combined_height);

        return Rect{
            .x = if (self.x > insets.left) self.x - insets.left else 0,
            .y = if (self.y > insets.top) self.y - insets.top else 0,
            .width = expanded_width,
            .height = expanded_height,
        };
    }
};

/// Insets for each edge of a rectangle
pub const EdgeInsets = struct {
    /// Top inset
    top: u16,
    /// Right inset
    right: u16,
    /// Bottom inset
    bottom: u16,
    /// Left inset
    left: u16,

    /// Create new insets
    pub fn init(top: anytype, right: anytype, bottom: anytype, left: anytype) EdgeInsets {
        return EdgeInsets{
            .top = checkedDimension(top, "insets.top"),
            .right = checkedDimension(right, "insets.right"),
            .bottom = checkedDimension(bottom, "insets.bottom"),
            .left = checkedDimension(left, "insets.left"),
        };
    }

    /// Create uniform insets (same value for all sides)
    pub fn all(value: anytype) EdgeInsets {
        const converted = checkedDimension(value, "insets.all");
        return EdgeInsets{
            .top = converted,
            .right = converted,
            .bottom = converted,
            .left = converted,
        };
    }

    /// Create horizontal and vertical insets
    pub fn symmetric(horizontal: anytype, vertical: anytype) EdgeInsets {
        const h = checkedDimension(horizontal, "insets.horizontal");
        const v = checkedDimension(vertical, "insets.vertical");
        return EdgeInsets{
            .top = v,
            .right = h,
            .bottom = v,
            .left = h,
        };
    }
};

/// Direction for flex layouts
pub const FlexDirection = enum {
    row,
    column,
};

/// Layout flow for horizontal containers.
pub const LayoutDirection = enum {
    ltr,
    rtl,
};

/// Alignment options for flex layouts
pub const FlexAlignment = enum {
    start,
    center,
    end,
    space_between,
    space_around,
    space_evenly,
};

/// Size specification for widgets
pub const SizeSpec = enum {
    /// Fixed size in cells
    fixed,
    /// Proportional size (flex)
    flex,
    /// Content-based size
    content,
};

/// Layout constraints for widgets
pub const Constraints = struct {
    /// Minimum width
    min_width: u16,
    /// Maximum width
    max_width: u16,
    /// Minimum height
    min_height: u16,
    /// Maximum height
    max_height: u16,

    /// Create new constraints
    pub fn init(min_width_in: anytype, max_width_in: anytype, min_height_in: anytype, max_height_in: anytype) Constraints {
        validateMinMaxComptime(min_width_in, max_width_in, "width constraints");
        validateMinMaxComptime(min_height_in, max_height_in, "height constraints");

        const min_width = checkedDimension(min_width_in, "constraints.min_width");
        const max_width = checkedDimension(max_width_in, "constraints.max_width");
        const min_height = checkedDimension(min_height_in, "constraints.min_height");
        const max_height = checkedDimension(max_height_in, "constraints.max_height");

        if (max_width < min_width) {
            std.debug.panic("zit: max_width {d} smaller than min_width {d}", .{ max_width, min_width });
        }
        if (max_height < min_height) {
            std.debug.panic("zit: max_height {d} smaller than min_height {d}", .{ max_height, min_height });
        }

        return Constraints{
            .min_width = min_width,
            .max_width = max_width,
            .min_height = min_height,
            .max_height = max_height,
        };
    }

    /// Create tight constraints (min = max)
    pub fn tight(width: anytype, height: anytype) Constraints {
        const w = checkedDimension(width, "constraints.tight.width");
        const h = checkedDimension(height, "constraints.tight.height");
        return Constraints{
            .min_width = w,
            .max_width = w,
            .min_height = h,
            .max_height = h,
        };
    }

    /// Create constraints with no maximum
    pub fn loose(min_width: anytype, min_height: anytype) Constraints {
        const min_w = checkedDimension(min_width, "constraints.loose.min_width");
        const min_h = checkedDimension(min_height, "constraints.loose.min_height");
        return Constraints{
            .min_width = min_w,
            .max_width = std.math.maxInt(u16),
            .min_height = min_h,
            .max_height = std.math.maxInt(u16),
        };
    }

    /// Create constraints that are bounded by the given size
    pub fn bounded(max_width: anytype, max_height: anytype) Constraints {
        const max_w = checkedDimension(max_width, "constraints.bounded.max_width");
        const max_h = checkedDimension(max_height, "constraints.bounded.max_height");
        return Constraints{
            .min_width = 0,
            .max_width = max_w,
            .min_height = 0,
            .max_height = max_h,
        };
    }

    /// Constrain a size to fit within these constraints
    pub fn constrain(self: Constraints, width: u16, height: u16) Size {
        const constrained_width = std.math.clamp(width, self.min_width, self.max_width);
        const constrained_height = std.math.clamp(height, self.min_height, self.max_height);
        return Size.init(constrained_width, constrained_height);
    }

    /// Check if these constraints are tight (min = max)
    pub fn isTight(self: Constraints) bool {
        return self.min_width == self.max_width and self.min_height == self.max_height;
    }

    /// Enforce a minimum size on these constraints
    pub fn enforce(self: Constraints, min_width: u16, min_height: u16) Constraints {
        return Constraints{
            .min_width = @max(self.min_width, min_width),
            .max_width = @max(self.max_width, min_width),
            .min_height = @max(self.min_height, min_height),
            .max_height = @max(self.max_height, min_height),
        };
    }
};

/// Size with width and height
pub const Size = struct {
    /// Width in columns
    width: u16,
    /// Height in rows
    height: u16,

    /// Create a new size
    pub fn init(width: anytype, height: anytype) Size {
        return Size{
            .width = checkedDimension(width, "size.width"),
            .height = checkedDimension(height, "size.height"),
        };
    }

    /// Create a size with zero dimensions
    pub fn zero() Size {
        return Size{
            .width = 0,
            .height = 0,
        };
    }
};

/// Layout interface for widgets
pub const LayoutElement = struct {
    /// Function pointer for layout calculation
    layoutFn: *const fn (ctx: *anyopaque, constraints: Constraints) Size,
    /// Function pointer for rendering
    renderFn: *const fn (ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void,
    /// Context pointer for the element
    ctx: *anyopaque,

    /// Calculate layout for this element
    pub fn layout(self: *const LayoutElement, constraints: Constraints) Size {
        return self.layoutFn(self.ctx, constraints);
    }

    /// Render this element
    pub fn render(self: *const LayoutElement, renderer: *renderer_mod.Renderer, rect: Rect) void {
        self.renderFn(self.ctx, renderer, rect);
    }
};

/// Base layout manager
pub const Layout = struct {
    /// Allocator for layout operations
    allocator: std.mem.Allocator,

    /// Initialize a new layout
    pub fn init(allocator: std.mem.Allocator) Layout {
        return Layout{
            .allocator = allocator,
        };
    }
};

/// Container for a child element with flex factor and alignment
pub const FlexChild = struct {
    /// The child element
    element: LayoutElement,
    /// Flex grow factor (0 = non-flexible)
    flex_grow: u16,
    /// Flex shrink factor when overflowing
    flex_shrink: u16,
    /// Alignment in the cross axis
    cross_alignment: ?FlexAlignment,
    /// Margin around the child
    margin_insets: EdgeInsets,
    /// Optional sizing hints
    size_hints: SizeHints,
    /// Cached size from last layout
    cached_size: Size,

    const SizeHints = struct {
        min: ?Size = null,
        max: ?Size = null,
        preferred: ?Size = null,
    };

    /// Create a new flex child
    pub fn init(element: LayoutElement, flex: u16) FlexChild {
        return FlexChild{
            .element = element,
            .flex_grow = flex,
            .flex_shrink = flex,
            .cross_alignment = null,
            .margin_insets = EdgeInsets.all(0),
            .size_hints = .{},
            .cached_size = Size.zero(),
        };
    }

    /// Adjust the flex grow factor
    pub fn grow(self: FlexChild, factor: u16) FlexChild {
        var result = self;
        result.flex_grow = factor;
        return result;
    }

    /// Adjust the flex shrink factor
    pub fn shrink(self: FlexChild, factor: u16) FlexChild {
        var result = self;
        result.flex_shrink = factor;
        return result;
    }

    /// Set the cross axis alignment
    pub fn alignment(self: FlexChild, alignment_value: FlexAlignment) FlexChild {
        var result = self;
        result.cross_alignment = alignment_value;
        return result;
    }

    /// Set the margin
    pub fn margin(self: FlexChild, margin_value: EdgeInsets) FlexChild {
        var result = self;
        result.margin_insets = margin_value;
        return result;
    }

    /// Set a minimum size hint
    pub fn minSize(self: FlexChild, size: Size) FlexChild {
        var result = self;
        result.size_hints.min = size;
        return result;
    }

    /// Set a maximum size hint
    pub fn maxSize(self: FlexChild, size: Size) FlexChild {
        var result = self;
        result.size_hints.max = size;
        return result;
    }

    /// Set a preferred size hint
    pub fn preferredSize(self: FlexChild, size: Size) FlexChild {
        var result = self;
        result.size_hints.preferred = size;
        return result;
    }
};

/// Flex layout manager
pub const FlexLayout = struct {
    const LayoutMetrics = struct {
        used_main: u32,
        max_cross: u16,
        gap_total: u32,
    };

    const ChildMeasure = struct {
        main_with_margin: u16,
        cross_with_margin: u16,
        min_main: u16,
        max_main: u16,
    };

    const NaturalMeasure = struct {
        main: u16,
        min_main: u16,
        max_main: u16,
    };

    const FlexCache = struct {
        valid: bool = false,
        available_main: u16 = 0,
        available_cross: u16 = 0,
        metrics: LayoutMetrics = .{ .used_main = 0, .max_cross = 0, .gap_total = 0 },
        gap_value: u16 = 0,
        start_offset: u16 = 0,
        content_size: Size = Size.zero(),
    };

    /// Base layout
    base: Layout,
    /// Direction of the flex layout
    direction: FlexDirection,
    /// Flow direction for horizontal layouts
    layout_direction: LayoutDirection,
    /// Main axis alignment
    main_alignment: FlexAlignment,
    /// Cross axis alignment
    cross_alignment: FlexAlignment,
    /// Child widgets
    children: std.ArrayList(FlexChild),
    /// Padding inside the container
    padding_insets: EdgeInsets,
    /// Gap between children
    gap_size: u16,
    /// Cached layout results
    cache: FlexCache,
    /// Reusable measurement scratch buffers to avoid per-frame allocations
    naturals_scratch: std.ArrayListUnmanaged(NaturalMeasure),
    assigned_scratch: std.ArrayListUnmanaged(u16),

    /// Initialize a new flex layout
    pub fn init(allocator: std.mem.Allocator, direction: FlexDirection) !*FlexLayout {
        const layout = try allocator.create(FlexLayout);
        layout.* = FlexLayout{
            .base = Layout.init(allocator),
            .direction = direction,
            .layout_direction = .ltr,
            .main_alignment = .start,
            .cross_alignment = .start,
            .children = std.ArrayList(FlexChild).empty,
            .padding_insets = EdgeInsets.all(0),
            .gap_size = 0,
            .cache = .{},
            .naturals_scratch = .{},
            .assigned_scratch = .{},
        };
        return layout;
    }

    /// Clean up flex layout resources
    pub fn deinit(self: *FlexLayout) void {
        self.children.deinit(self.base.allocator);
        self.naturals_scratch.deinit(self.base.allocator);
        self.assigned_scratch.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    /// Set the main axis alignment
    pub fn mainAlignment(self: *FlexLayout, alignment: FlexAlignment) *FlexLayout {
        self.main_alignment = alignment;
        self.cache.valid = false;
        return self;
    }

    /// Set the cross axis alignment
    pub fn crossAlignment(self: *FlexLayout, alignment: FlexAlignment) *FlexLayout {
        self.cross_alignment = alignment;
        self.cache.valid = false;
        return self;
    }

    /// Set the layout direction for horizontal rows (LTR by default).
    pub fn layoutDirection(self: *FlexLayout, direction: LayoutDirection) *FlexLayout {
        self.layout_direction = direction;
        self.cache.valid = false;
        return self;
    }

    /// Set the padding
    pub fn padding(self: *FlexLayout, padding_value: EdgeInsets) *FlexLayout {
        self.padding_insets = padding_value;
        self.cache.valid = false;
        return self;
    }

    /// Set the gap between children
    pub fn gap(self: *FlexLayout, gap_value: u16) *FlexLayout {
        self.gap_size = gap_value;
        self.cache.valid = false;
        return self;
    }

    /// Add a child element
    pub fn addChild(self: *FlexLayout, child: FlexChild) !void {
        try self.children.append(self.base.allocator, child);
        self.cache.valid = false;
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*FlexLayout, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *FlexLayout, constraints: Constraints) Size {
        const padded_constraints = self.applyPadding(constraints);

        const is_row = self.direction == .row;
        const available_main = if (is_row) padded_constraints.max_width else padded_constraints.max_height;
        const available_cross = if (is_row) padded_constraints.max_height else padded_constraints.max_width;

        self.ensureCache(available_main, available_cross);

        const padded_width = saturatingAdd(self.cache.content_size.width, saturatingAdd(self.padding_insets.left, self.padding_insets.right));
        const padded_height = saturatingAdd(self.cache.content_size.height, saturatingAdd(self.padding_insets.top, self.padding_insets.bottom));

        return Size{
            .width = padded_width,
            .height = padded_height,
        };
    }

    /// Render the layout
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*FlexLayout, @ptrCast(@alignCast(ctx)));
        self.renderLayout(renderer, rect);
    }

    /// Render the layout
    pub fn renderLayout(self: *FlexLayout, renderer: *renderer_mod.Renderer, rect: Rect) void {
        // Apply padding to rect
        const padded_rect = rect.shrink(self.padding_insets);

        // Skip rendering if no space
        if (padded_rect.width == 0 or padded_rect.height == 0) {
            return;
        }

        const is_row = self.direction == .row;
        const is_rtl = is_row and self.layout_direction == .rtl;
        const available_main = if (is_row) padded_rect.width else padded_rect.height;
        const available_cross = if (is_row) padded_rect.height else padded_rect.width;

        self.ensureCache(available_main, available_cross);

        const child_count = self.children.items.len;
        if (child_count == 0) return;

        var current_position: u32 = self.cache.start_offset;
        const main_origin: u32 = if (is_row) padded_rect.x else padded_rect.y;
        const main_extent: u32 = if (is_row) padded_rect.width else padded_rect.height;
        const cross_origin: u32 = if (is_row) padded_rect.y else padded_rect.x;

        for (self.children.items, 0..) |*child, idx| {
            const margin_main_before: u16 = if (is_row) child.margin_insets.left else child.margin_insets.top;
            const margin_main_after: u16 = if (is_row) child.margin_insets.right else child.margin_insets.bottom;
            const margin_cross_before: u16 = if (is_row) child.margin_insets.top else child.margin_insets.left;
            const margin_cross_after: u16 = if (is_row) child.margin_insets.bottom else child.margin_insets.right;

            const child_main_size: u16 = if (is_row) child.cached_size.width else child.cached_size.height;
            const child_cross_size: u16 = if (is_row) child.cached_size.height else child.cached_size.width;

            const cross_with_margin: u32 = @as(u32, child_cross_size) + margin_cross_before + margin_cross_after;
            const cross_free_space: u32 = if (available_cross > cross_with_margin)
                available_cross - cross_with_margin
            else
                0;

            var cross_offset: u16 = 0;
            const alignment = child.cross_alignment orelse self.cross_alignment;
            switch (alignment) {
                .start => {},
                .center => cross_offset = @intCast(@min(cross_free_space / 2, @as(u32, std.math.maxInt(u16)))),
                .end => cross_offset = @intCast(@min(cross_free_space, @as(u32, std.math.maxInt(u16)))),
                .space_between, .space_around, .space_evenly => {},
            }

            const ltr_main = main_origin + current_position + margin_main_before;
            const rtl_main = if (main_extent > current_position + margin_main_before)
                main_origin + main_extent - (current_position + margin_main_before + child_main_size)
            else
                main_origin;
            const pos_main_u32 = if (is_rtl) rtl_main else ltr_main;
            const pos_cross_u32 = cross_origin + cross_offset + margin_cross_before;

            const child_rect = if (is_row)
                Rect{
                    .x = @intCast(@min(pos_main_u32, @as(u32, std.math.maxInt(u16)))),
                    .y = @intCast(@min(pos_cross_u32, @as(u32, std.math.maxInt(u16)))),
                    .width = child_main_size,
                    .height = child_cross_size,
                }
            else
                Rect{
                    .x = @intCast(@min(pos_cross_u32, @as(u32, std.math.maxInt(u16)))),
                    .y = @intCast(@min(pos_main_u32, @as(u32, std.math.maxInt(u16)))),
                    .width = child_cross_size,
                    .height = child_main_size,
                };

            if (!intersectsViewport(child_rect, renderer)) continue;
            child.element.render(renderer, child_rect);

            current_position += margin_main_before;
            current_position += child_main_size;
            current_position += margin_main_after;

            if (idx + 1 < child_count) {
                current_position += self.cache.gap_value;
            }
        }
    }

    fn ensureCache(self: *FlexLayout, available_main: u16, available_cross: u16) void {
        if (self.cache.valid and self.cache.available_main == available_main and self.cache.available_cross == available_cross) {
            return;
        }

        const child_count = self.children.items.len;
        const child_count_u32: u32 = @intCast(@min(child_count, @as(usize, std.math.maxInt(u32))));
        const metrics = self.measureChildren(available_main, available_cross);
        const main_limit_u32: u32 = available_main;
        const free_space: u32 = if (metrics.used_main >= main_limit_u32) 0 else main_limit_u32 - metrics.used_main;

        var gap_value: u16 = self.gap_size;
        var start_offset: u16 = 0;

        switch (self.main_alignment) {
            .start => {},
            .center => start_offset = @intCast(@min(free_space / 2, @as(u32, std.math.maxInt(u16)))),
            .end => start_offset = @intCast(@min(free_space, @as(u32, std.math.maxInt(u16)))),
            .space_between => if (child_count_u32 > 1) {
                const extra_gap = free_space / (child_count_u32 - 1);
                gap_value = @intCast(@min(@as(u32, self.gap_size) + extra_gap, @as(u32, std.math.maxInt(u16))));
            },
            .space_around => if (child_count_u32 > 0) {
                const extra_gap = free_space / child_count_u32;
                gap_value = @intCast(@min(@as(u32, self.gap_size) + extra_gap, @as(u32, std.math.maxInt(u16))));
                start_offset = @intCast(@min(@divFloor(@as(u32, gap_value), 2), @as(u32, std.math.maxInt(u16))));
            },
            .space_evenly => if (child_count_u32 > 0) {
                const extra_gap = free_space / (child_count_u32 + 1);
                gap_value = @intCast(@min(@as(u32, self.gap_size) + extra_gap, @as(u32, std.math.maxInt(u16))));
                start_offset = gap_value;
            },
        }

        const used_main_clamped: u16 = if (metrics.used_main > @as(u32, available_main))
            available_main
        else
            @intCast(metrics.used_main);

        const is_row = self.direction == .row;
        const content_size = if (is_row)
            Size.init(used_main_clamped, @min(metrics.max_cross, available_cross))
        else
            Size.init(@min(metrics.max_cross, available_cross), used_main_clamped);

        self.cache = FlexCache{
            .valid = true,
            .available_main = available_main,
            .available_cross = available_cross,
            .metrics = metrics,
            .gap_value = gap_value,
            .start_offset = start_offset,
            .content_size = content_size,
        };
    }

    fn applyPadding(self: *FlexLayout, constraints: Constraints) Constraints {
        const horizontal_padding = saturatingAdd(self.padding_insets.left, self.padding_insets.right);
        const vertical_padding = saturatingAdd(self.padding_insets.top, self.padding_insets.bottom);
        return Constraints{
            .min_width = if (constraints.min_width > horizontal_padding)
                constraints.min_width - horizontal_padding
            else
                0,
            .max_width = if (constraints.max_width > horizontal_padding)
                constraints.max_width - horizontal_padding
            else
                0,
            .min_height = if (constraints.min_height > vertical_padding)
                constraints.min_height - vertical_padding
            else
                0,
            .max_height = if (constraints.max_height > vertical_padding)
                constraints.max_height - vertical_padding
            else
                0,
        };
    }

    fn measureChildren(self: *FlexLayout, main_limit: u16, cross_limit: u16) LayoutMetrics {
        const child_count = self.children.items.len;
        const child_count_u32: u32 = @intCast(@min(child_count, @as(usize, std.math.maxInt(u32))));
        const base_gap_total: u32 = if (child_count_u32 > 1)
            (child_count_u32 - 1) * @as(u32, self.gap_size)
        else
            0;

        var used_main: u32 = 0;
        var max_cross: u16 = 0;
        var total_grow: u32 = 0;
        var total_shrink: u32 = 0;
        const allocator = self.base.allocator;

        self.naturals_scratch.clearRetainingCapacity();
        self.assigned_scratch.clearRetainingCapacity();

        if (child_count > 0) {
            self.naturals_scratch.resize(allocator, child_count) catch {
                return LayoutMetrics{ .used_main = 0, .max_cross = 0, .gap_total = 0 };
            };
            self.assigned_scratch.resize(allocator, child_count) catch {
                return LayoutMetrics{ .used_main = 0, .max_cross = 0, .gap_total = 0 };
            };
        }

        const naturals = self.naturals_scratch.items;
        var assigned_main = self.assigned_scratch.items;

        for (self.children.items, 0..) |*child, idx| {
            const measure = self.measureChild(child, main_limit, cross_limit, null);
            naturals[idx] = NaturalMeasure{
                .main = if (self.direction == .row) child.cached_size.width else child.cached_size.height,
                .min_main = measure.min_main,
                .max_main = measure.max_main,
            };

            used_main += measure.main_with_margin;
            max_cross = @max(max_cross, measure.cross_with_margin);
            total_grow += child.flex_grow;
            total_shrink += child.flex_shrink;
        }

        for (naturals, 0..) |natural, idx| {
            assigned_main[idx] = natural.main;
        }

        const main_limit_u32: u32 = main_limit;
        const base_used_with_gaps: u32 = used_main + base_gap_total;

        if (base_used_with_gaps < main_limit_u32 and total_grow > 0) {
            var free_space: u32 = main_limit_u32 - base_used_with_gaps;

            while (free_space > 0 and total_grow > 0) {
                var distributed: u32 = 0;
                for (self.children.items, 0..) |*child, idx| {
                    if (child.flex_grow == 0) continue;
                    const natural = naturals[idx];
                    if (assigned_main[idx] >= natural.max_main) continue;

                    const portion = if (free_space > 0) (free_space * child.flex_grow) / total_grow else 0;
                    const available_growth = @min(@as(u32, natural.max_main - assigned_main[idx]), portion);
                    const add_amount: u16 = @intCast(available_growth);
                    if (add_amount == 0) continue;
                    assigned_main[idx] = saturatingAdd(assigned_main[idx], add_amount);
                    distributed += @as(u32, add_amount);
                }
                if (distributed == 0) break;
                if (free_space > distributed) {
                    free_space -= distributed;
                } else {
                    free_space = 0;
                }
            }
        } else if (base_used_with_gaps > main_limit_u32 and total_shrink > 0) {
            var overflow: u32 = base_used_with_gaps - main_limit_u32;
            var shrink_total = total_shrink;

            while (overflow > 0 and shrink_total > 0) {
                var reduced: u32 = 0;
                for (self.children.items, 0..) |*child, idx| {
                    if (child.flex_shrink == 0) continue;
                    const natural = naturals[idx];
                    if (assigned_main[idx] <= natural.min_main) continue;

                    const portion = if (overflow > 0) (overflow * child.flex_shrink) / shrink_total else 0;
                    const max_reduction: u16 = @intCast(@min(@as(u32, assigned_main[idx] - natural.min_main), std.math.maxInt(u16)));
                    const reduce_amount: u16 = @intCast(@min(@as(u32, portion), @as(u32, max_reduction)));
                    if (reduce_amount == 0) continue;

                    assigned_main[idx] -= reduce_amount;
                    reduced += @as(u32, reduce_amount);

                    if (assigned_main[idx] == natural.min_main) {
                        shrink_total -= child.flex_shrink;
                    }
                }

                if (reduced == 0) break;
                if (overflow > reduced) {
                    overflow -= reduced;
                } else {
                    overflow = 0;
                }
            }
        }

        used_main = 0;
        max_cross = 0;

        for (self.children.items, 0..) |*child, idx| {
            const forced = assigned_main[idx];
            const measure = self.measureChild(child, main_limit, cross_limit, forced);
            used_main += measure.main_with_margin;
            max_cross = @max(max_cross, measure.cross_with_margin);
        }

        return LayoutMetrics{
            .used_main = used_main + base_gap_total,
            .max_cross = max_cross,
            .gap_total = base_gap_total,
        };
    }

    fn measureChild(self: *FlexLayout, child: *FlexChild, main_limit: u16, cross_limit: u16, forced_main: ?u16) ChildMeasure {
        const is_row = self.direction == .row;
        const margin_main_before: u16 = if (is_row) child.margin_insets.left else child.margin_insets.top;
        const margin_main_after: u16 = if (is_row) child.margin_insets.right else child.margin_insets.bottom;
        const margin_cross_before: u16 = if (is_row) child.margin_insets.top else child.margin_insets.left;
        const margin_cross_after: u16 = if (is_row) child.margin_insets.bottom else child.margin_insets.right;

        const content_main_limit = trimAvailable(main_limit, margin_main_before + margin_main_after);
        const content_cross_limit = trimAvailable(cross_limit, margin_cross_before + margin_cross_after);

        const size_min = child.size_hints.min orelse Size.zero();
        const default_max = if (is_row)
            Size.init(content_main_limit, content_cross_limit)
        else
            Size.init(content_cross_limit, content_main_limit);
        const size_max = child.size_hints.max orelse default_max;

        const min_main = @min(if (is_row) size_min.width else size_min.height, content_main_limit);
        const min_cross = @min(if (is_row) size_min.height else size_min.width, content_cross_limit);

        const max_main = @max(min_main, @min(if (is_row) size_max.width else size_max.height, content_main_limit));
        const max_cross = @max(min_cross, @min(if (is_row) size_max.height else size_max.width, content_cross_limit));

        var child_constraints = if (is_row)
            Constraints{
                .min_width = min_main,
                .max_width = max_main,
                .min_height = min_cross,
                .max_height = max_cross,
            }
        else
            Constraints{
                .min_width = min_cross,
                .max_width = max_cross,
                .min_height = min_main,
                .max_height = max_main,
            };

        if (forced_main) |target| {
            const clamped = std.math.clamp(target, min_main, max_main);
            if (is_row) {
                child_constraints.min_width = clamped;
                child_constraints.max_width = clamped;
            } else {
                child_constraints.min_height = clamped;
                child_constraints.max_height = clamped;
            }
        }

        const measured = child.element.layout(child_constraints);
        const preferred_width = if (child.size_hints.preferred) |pref| pref.width else measured.width;
        const preferred_height = if (child.size_hints.preferred) |pref| pref.height else measured.height;
        const resolved = child_constraints.constrain(preferred_width, preferred_height);
        child.cached_size = resolved;

        const content_main = if (is_row) resolved.width else resolved.height;
        const content_cross = if (is_row) resolved.height else resolved.width;

        return ChildMeasure{
            .main_with_margin = saturatingAdd(content_main, margin_main_before + margin_main_after),
            .cross_with_margin = saturatingAdd(content_cross, margin_cross_before + margin_cross_after),
            .min_main = min_main,
            .max_main = max_main,
        };
    }

    fn trimAvailable(value: u16, margin: u16) u16 {
        return if (value > margin) value - margin else 0;
    }

    /// Create a layout element
    pub fn asElement(self: *FlexLayout) LayoutElement {
        return LayoutElement{
            .layoutFn = FlexLayout.layoutFn,
            .renderFn = FlexLayout.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

/// SizedBox provides a layout element with a fixed size
pub const SizedBox = struct {
    /// Base layout
    base: Layout,
    /// Child element
    child: ?LayoutElement,
    /// Width
    width: ?u16,
    /// Height
    height: ?u16,

    /// Initialize a new sized box
    pub fn init(allocator: std.mem.Allocator, child: ?LayoutElement, width: ?u16, height: ?u16) !*SizedBox {
        const sized_box = try allocator.create(SizedBox);
        sized_box.* = SizedBox{
            .base = Layout.init(allocator),
            .child = child,
            .width = width,
            .height = height,
        };
        return sized_box;
    }

    /// Clean up sized box resources
    pub fn deinit(self: *SizedBox) void {
        self.base.allocator.destroy(self);
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*SizedBox, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *SizedBox, constraints: Constraints) Size {
        // Apply fixed dimensions if specified
        const width = if (self.width) |w|
            @max(constraints.min_width, @min(w, constraints.max_width))
        else
            constraints.min_width;

        const height = if (self.height) |h|
            @max(constraints.min_height, @min(h, constraints.max_height))
        else
            constraints.min_height;

        // If we have a child, layout it with our constraints
        if (self.child) |child| {
            const child_constraints = Constraints{
                .min_width = width,
                .max_width = width,
                .min_height = height,
                .max_height = height,
            };

            _ = child.layout(child_constraints);
        }

        return Size.init(width, height);
    }

    /// Render this element
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*SizedBox, @ptrCast(@alignCast(ctx)));

        // If we have a child, render it
        if (self.child) |child| {
            child.render(renderer, rect);
        }
    }

    /// Convert to a layout element
    pub fn asElement(self: *SizedBox) LayoutElement {
        return LayoutElement{
            .layoutFn = SizedBox.layoutFn,
            .renderFn = SizedBox.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

/// Padding adds space around another element
pub const Padding = struct {
    /// Base layout
    base: Layout,
    /// Child element
    child: ?LayoutElement,
    /// Padding insets
    padding_insets: EdgeInsets,

    /// Initialize a new padding element
    pub fn init(allocator: std.mem.Allocator, child: ?LayoutElement, padding_value: EdgeInsets) !*Padding {
        const padding = try allocator.create(Padding);
        padding.* = Padding{
            .base = Layout.init(allocator),
            .child = child,
            .padding_insets = padding_value,
        };
        return padding;
    }

    /// Clean up padding resources
    pub fn deinit(self: *Padding) void {
        self.base.allocator.destroy(self);
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*Padding, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *Padding, constraints: Constraints) Size {
        // Apply padding to constraints
        const horizontal_padding = saturatingAdd(self.padding_insets.left, self.padding_insets.right);
        const vertical_padding = saturatingAdd(self.padding_insets.top, self.padding_insets.bottom);
        const padded_constraints = Constraints{
            .min_width = if (constraints.min_width > horizontal_padding)
                constraints.min_width - horizontal_padding
            else
                0,
            .max_width = if (constraints.max_width > horizontal_padding)
                constraints.max_width - horizontal_padding
            else
                0,
            .min_height = if (constraints.min_height > vertical_padding)
                constraints.min_height - vertical_padding
            else
                0,
            .max_height = if (constraints.max_height > vertical_padding)
                constraints.max_height - vertical_padding
            else
                0,
        };

        // If we have a child, layout it with our constraints
        var child_size = Size.zero();
        if (self.child) |child| {
            child_size = child.layout(padded_constraints);
        }

        // Return final size with padding
        return Size{
            .width = saturatingAdd(child_size.width, horizontal_padding),
            .height = saturatingAdd(child_size.height, vertical_padding),
        };
    }

    /// Render this element
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*Padding, @ptrCast(@alignCast(ctx)));

        // Apply padding to rect
        const padded_rect = rect.shrink(self.padding_insets);

        // If we have a child, render it
        if (self.child) |child| {
            child.render(renderer, padded_rect);
        }
    }

    /// Convert to a layout element
    pub fn asElement(self: *Padding) LayoutElement {
        return LayoutElement{
            .layoutFn = Padding.layoutFn,
            .renderFn = Padding.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

/// Center aligns a child within itself
pub const Center = struct {
    /// Base layout
    base: Layout,
    /// Child element
    child: ?LayoutElement,
    /// Whether to center horizontally
    horizontal: bool,
    /// Whether to center vertically
    vertical: bool,

    /// Initialize a new center element
    pub fn init(allocator: std.mem.Allocator, child: ?LayoutElement, horizontal: bool, vertical: bool) !*Center {
        const center = try allocator.create(Center);
        center.* = Center{
            .base = Layout.init(allocator),
            .child = child,
            .horizontal = horizontal,
            .vertical = vertical,
        };
        return center;
    }

    /// Clean up center resources
    pub fn deinit(self: *Center) void {
        self.base.allocator.destroy(self);
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*Center, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *Center, constraints: Constraints) Size {
        // If we have a child, layout it with our constraints
        var child_size = Size.zero();
        if (self.child) |child| {
            child_size = child.layout(constraints);
        }

        // Return the maximum of child size and constraints minimum
        return Size{
            .width = @max(child_size.width, constraints.min_width),
            .height = @max(child_size.height, constraints.min_height),
        };
    }

    /// Render this element
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*Center, @ptrCast(@alignCast(ctx)));

        // If we have a child, render it centered
        if (self.child) |child| {
            // Get child size
            const child_size = child.layout(Constraints.bounded(rect.width, rect.height));

            // Calculate centered position
            var x = rect.x;
            var y = rect.y;

            if (self.horizontal) {
                // Safely calculate the centered position
                if (rect.width > child_size.width) {
                    x = rect.x + (rect.width - child_size.width) / 2;
                }
            }

            if (self.vertical) {
                // Safely calculate the centered position
                if (rect.height > child_size.height) {
                    y = rect.y + (rect.height - child_size.height) / 2;
                }
            }

            // Create child rect
            const child_rect = Rect{
                .x = x,
                .y = y,
                .width = child_size.width,
                .height = child_size.height,
            };

            // Render child
            child.render(renderer, child_rect);
        }
    }

    /// Convert to a layout element
    pub fn asElement(self: *Center) LayoutElement {
        return LayoutElement{
            .layoutFn = Center.layoutFn,
            .renderFn = Center.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

/// Track sizing for grid columns/rows
pub const GridTrack = union(enum) {
    fixed: u16,
    flex: u16,
};

/// Grid layout manager
pub const GridLayout = struct {
    const TrackCache = struct {
        columns: std.ArrayList(u16),
        rows: std.ArrayList(u16),
        available_width: u16 = 0,
        available_height: u16 = 0,
        horizontal_gap: u16 = 0,
        vertical_gap: u16 = 0,
        valid: bool = false,
    };

    /// Base layout
    base: Layout,
    /// Number of columns
    columns: u16,
    /// Number of rows
    rows: u16,
    /// Column track sizing
    column_tracks: std.ArrayList(GridTrack),
    /// Row track sizing
    row_tracks: std.ArrayList(GridTrack),
    /// Cell elements (stored in row-major order)
    cells: std.ArrayList(?LayoutElement),
    /// Padding inside the container
    padding_insets: EdgeInsets,
    /// Gap between cells
    gap_size: u16,
    /// Cached track resolution
    cache: TrackCache,

    /// Initialize a new grid layout
    pub fn init(allocator: std.mem.Allocator, columns: u16, rows: u16) !*GridLayout {
        const layout = try allocator.create(GridLayout);

        layout.* = GridLayout{
            .base = Layout.init(allocator),
            .columns = columns,
            .rows = rows,
            .column_tracks = std.ArrayList(GridTrack).empty,
            .row_tracks = std.ArrayList(GridTrack).empty,
            .cells = std.ArrayList(?LayoutElement).empty,
            .padding_insets = EdgeInsets.all(0),
            .gap_size = 0,
            .cache = TrackCache{
                .columns = std.ArrayList(u16).empty,
                .rows = std.ArrayList(u16).empty,
                .available_width = 0,
                .available_height = 0,
                .horizontal_gap = 0,
                .vertical_gap = 0,
                .valid = false,
            },
        };
        errdefer layout.deinit();

        try layout.column_tracks.ensureTotalCapacity(layout.base.allocator, columns);
        try layout.row_tracks.ensureTotalCapacity(layout.base.allocator, rows);

        var col_index: u16 = 0;
        while (col_index < columns) : (col_index += 1) {
            try layout.column_tracks.append(layout.base.allocator, GridTrack{ .flex = 1 });
        }

        var row_index: u16 = 0;
        while (row_index < rows) : (row_index += 1) {
            try layout.row_tracks.append(layout.base.allocator, GridTrack{ .flex = 1 });
        }

        // Initialize cells
        try layout.initCells();

        return layout;
    }

    /// Clean up grid layout resources
    pub fn deinit(self: *GridLayout) void {
        self.column_tracks.deinit(self.base.allocator);
        self.row_tracks.deinit(self.base.allocator);
        self.cells.deinit(self.base.allocator);
        self.cache.columns.deinit(self.base.allocator);
        self.cache.rows.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    fn invalidateCache(self: *GridLayout) void {
        self.cache.valid = false;
    }

    /// Set the padding
    pub fn padding(self: *GridLayout, padding_value: EdgeInsets) *GridLayout {
        self.padding_insets = padding_value;
        self.invalidateCache();
        return self;
    }

    /// Set the gap between cells
    pub fn gap(self: *GridLayout, gap_value: u16) *GridLayout {
        self.gap_size = gap_value;
        self.invalidateCache();
        return self;
    }

    /// Update the column track sizing
    pub fn setColumns(self: *GridLayout, tracks: []const GridTrack) !*GridLayout {
        self.column_tracks.clearRetainingCapacity();
        try self.column_tracks.ensureTotalCapacity(self.base.allocator, tracks.len);
        for (tracks) |track| {
            try self.column_tracks.append(self.base.allocator, track);
        }
        self.columns = @intCast(tracks.len);
        try self.initCells();
        self.invalidateCache();
        return self;
    }

    /// Update the row track sizing
    pub fn setRows(self: *GridLayout, tracks: []const GridTrack) !*GridLayout {
        self.row_tracks.clearRetainingCapacity();
        try self.row_tracks.ensureTotalCapacity(self.base.allocator, tracks.len);
        for (tracks) |track| {
            try self.row_tracks.append(self.base.allocator, track);
        }
        self.rows = @intCast(tracks.len);
        try self.initCells();
        self.invalidateCache();
        return self;
    }

    /// Add a child element to a specific cell
    pub fn addChild(self: *GridLayout, element: LayoutElement, column: u16, row: u16) !void {
        if (column >= self.columns or row >= self.rows) {
            return error.OutOfBounds;
        }

        const index = @as(usize, row) * @as(usize, self.columns) + @as(usize, column);
        self.cells.items[index] = element;
        self.invalidateCache();
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*GridLayout, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *GridLayout, constraints: Constraints) Size {
        // Apply padding to constraints
        const horizontal_padding = saturatingAdd(self.padding_insets.left, self.padding_insets.right);
        const vertical_padding = saturatingAdd(self.padding_insets.top, self.padding_insets.bottom);
        const padded_constraints = Constraints{
            .min_width = if (constraints.min_width > horizontal_padding)
                constraints.min_width - horizontal_padding
            else
                0,
            .max_width = if (constraints.max_width > horizontal_padding)
                constraints.max_width - horizontal_padding
            else
                0,
            .min_height = if (constraints.min_height > vertical_padding)
                constraints.min_height - vertical_padding
            else
                0,
            .max_height = if (constraints.max_height > vertical_padding)
                constraints.max_height - vertical_padding
            else
                0,
        };

        const total_horizontal_gap: u16 = if (self.columns > 1)
            @intCast(@min(@as(u32, self.columns - 1) * @as(u32, self.gap_size), @as(u32, std.math.maxInt(u16))))
        else
            0;
        const total_vertical_gap: u16 = if (self.rows > 1)
            @intCast(@min(@as(u32, self.rows - 1) * @as(u32, self.gap_size), @as(u32, std.math.maxInt(u16))))
        else
            0;

        const track_cache = self.ensureTrackCache(padded_constraints.max_width, padded_constraints.max_height, total_horizontal_gap, total_vertical_gap) catch {
            return Size.zero();
        };
        const column_sizes = track_cache.columns;
        const row_sizes = track_cache.rows;

        var row: usize = 0;
        while (row < row_sizes.len) : (row += 1) {
            var col: usize = 0;
            while (col < column_sizes.len) : (col += 1) {
                const index = row * column_sizes.len + col;
                if (index < self.cells.items.len) {
                    if (self.cells.items[index]) |cell| {
                        const child_constraints = Constraints.tight(column_sizes[col], row_sizes[row]);
                        _ = cell.layout(child_constraints);
                    }
                }
            }
        }

        const used_width = saturatingAdd(saturatingAdd(saturatingSum(column_sizes), total_horizontal_gap), horizontal_padding);
        const used_height = saturatingAdd(saturatingAdd(saturatingSum(row_sizes), total_vertical_gap), vertical_padding);

        return Size.init(used_width, used_height);
    }

    /// Render the layout
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*GridLayout, @ptrCast(@alignCast(ctx)));
        self.renderLayout(renderer, rect);
    }

    /// Render the layout
    pub fn renderLayout(self: *GridLayout, renderer: *renderer_mod.Renderer, rect: Rect) void {
        // Apply padding to rect
        const padded_rect = rect.shrink(self.padding_insets);

        // Skip rendering if no space
        if (padded_rect.width == 0 or padded_rect.height == 0) {
            return;
        }

        const total_horizontal_gap: u16 = if (self.columns > 1)
            @intCast(@min(@as(u32, self.columns - 1) * @as(u32, self.gap_size), @as(u32, std.math.maxInt(u16))))
        else
            0;
        const total_vertical_gap: u16 = if (self.rows > 1)
            @intCast(@min(@as(u32, self.rows - 1) * @as(u32, self.gap_size), @as(u32, std.math.maxInt(u16))))
        else
            0;

        const track_cache = self.ensureTrackCache(padded_rect.width, padded_rect.height, total_horizontal_gap, total_vertical_gap) catch return;
        const column_sizes = track_cache.columns;
        const row_sizes = track_cache.rows;

        var y: u16 = padded_rect.y;
        var row: usize = 0;
        while (row < row_sizes.len) : (row += 1) {
            var x: u16 = padded_rect.x;
            var col: usize = 0;
            while (col < column_sizes.len) : (col += 1) {
                const index = row * column_sizes.len + col;
                if (index < self.cells.items.len) {
                    if (self.cells.items[index]) |cell| {
                        const cell_rect = Rect{
                            .x = x,
                            .y = y,
                            .width = column_sizes[col],
                            .height = row_sizes[row],
                        };

                        if (!intersectsViewport(cell_rect, renderer)) {
                            continue;
                        }
                        cell.render(renderer, cell_rect);
                    }
                }
                x = saturatingAdd(x, column_sizes[col]);
                x = saturatingAdd(x, self.gap_size);
            }
            y = saturatingAdd(y, row_sizes[row]);
            y = saturatingAdd(y, self.gap_size);
        }
    }

    fn ensureTrackCache(self: *GridLayout, available_width: u16, available_height: u16, horizontal_gap: u16, vertical_gap: u16) !struct { columns: []const u16, rows: []const u16 } {
        if (self.cache.valid and
            self.cache.available_width == available_width and
            self.cache.available_height == available_height and
            self.cache.horizontal_gap == horizontal_gap and
            self.cache.vertical_gap == vertical_gap)
        {
            return .{
                .columns = self.cache.columns.items,
                .rows = self.cache.rows.items,
            };
        }

        const columns = try self.resolveTracks(self.column_tracks.items, available_width, horizontal_gap);
        defer self.base.allocator.free(columns);

        const rows = try self.resolveTracks(self.row_tracks.items, available_height, vertical_gap);
        defer self.base.allocator.free(rows);

        self.cache.columns.clearRetainingCapacity();
        try self.cache.columns.ensureTotalCapacity(self.base.allocator, columns.len);
        try self.cache.columns.appendSlice(self.base.allocator, columns);

        self.cache.rows.clearRetainingCapacity();
        try self.cache.rows.ensureTotalCapacity(self.base.allocator, rows.len);
        try self.cache.rows.appendSlice(self.base.allocator, rows);

        self.cache.available_width = available_width;
        self.cache.available_height = available_height;
        self.cache.horizontal_gap = horizontal_gap;
        self.cache.vertical_gap = vertical_gap;
        self.cache.valid = true;

        return .{
            .columns = self.cache.columns.items,
            .rows = self.cache.rows.items,
        };
    }

    fn resolveTracks(self: *GridLayout, tracks: []const GridTrack, available: u16, gap_total: u16) ![]u16 {
        const sizes = try self.base.allocator.alloc(u16, tracks.len);

        const available_for_tracks: u32 = if (available > gap_total)
            @as(u32, available) - gap_total
        else
            0;

        var remaining: u32 = available_for_tracks;
        var flex_total: u32 = 0;

        for (tracks, 0..) |track, idx| {
            switch (track) {
                .fixed => |val| {
                    const take = if (remaining > 0) @min(@as(u32, val), remaining) else 0;
                    sizes[idx] = @intCast(@min(take, @as(u32, std.math.maxInt(u16))));
                    if (remaining > take) {
                        remaining -= take;
                    } else {
                        remaining = 0;
                    }
                },
                .flex => |weight| {
                    sizes[idx] = 0;
                    flex_total += weight;
                },
            }
        }

        if (flex_total > 0 and remaining > 0) {
            var assigned_from_flex: u32 = 0;
            for (tracks, 0..) |track, idx| {
                switch (track) {
                    .fixed => {},
                    .flex => |weight| {
                        const portion = (remaining * weight) / flex_total;
                        sizes[idx] = @intCast(@min(portion, @as(u32, std.math.maxInt(u16))));
                        assigned_from_flex += portion;
                    },
                }
            }

            var leftover: u32 = if (remaining > assigned_from_flex) remaining - assigned_from_flex else 0;
            if (leftover > 0) {
                for (tracks, 0..) |track, idx| {
                    if (leftover == 0) break;
                    switch (track) {
                        .fixed => {},
                        .flex => {
                            if (sizes[idx] < std.math.maxInt(u16)) {
                                sizes[idx] += 1;
                                leftover -= 1;
                            }
                        },
                    }
                }
            }
        }

        return sizes;
    }

    fn saturatingSum(values: []const u16) u16 {
        var total: u32 = 0;
        for (values) |value| {
            total += value;
        }
        if (total > std.math.maxInt(u16)) return std.math.maxInt(u16);
        return @intCast(total);
    }

    /// Create a layout element
    pub fn asElement(self: *GridLayout) LayoutElement {
        return LayoutElement{
            .layoutFn = GridLayout.layoutFn,
            .renderFn = GridLayout.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }

    /// Initialize the grid cells
    fn initCells(self: *GridLayout) !void {
        const columns: u16 = @intCast(self.column_tracks.items.len);
        const rows: u16 = @intCast(self.row_tracks.items.len);
        // Clear any existing cells
        self.cells.clearRetainingCapacity();

        // Ensure capacity
        try self.cells.ensureTotalCapacity(self.base.allocator, @as(usize, columns) * @as(usize, rows));

        // Fill with nulls using addManyAsSlice
        const null_value: ?LayoutElement = null;
        var i: usize = 0;
        while (i < @as(usize, columns) * @as(usize, rows)) : (i += 1) {
            try self.cells.append(self.base.allocator, null_value);
        }

        self.columns = columns;
        self.rows = rows;
    }
};

test "flex layout distributes space and aligns children" {
    const allocator = std.testing.allocator;

    const Record = struct {
        rect: Rect = Rect.init(0, 0, 0, 0),
    };

    const DummyElement = struct {
        const Self = @This();
        size: Size,
        record: *Record,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            const width = std.math.clamp(self.size.width, constraints.min_width, constraints.max_width);
            const height = std.math.clamp(self.size.height, constraints.min_height, constraints.max_height);
            return Size.init(width, height);
        }

        fn render(ctx: *anyopaque, _: *renderer_mod.Renderer, rect: Rect) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.record.rect = rect;
        }

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var layout = try FlexLayout.init(allocator, .row);
    defer layout.deinit();
    _ = layout.gap(1).crossAlignment(.center).mainAlignment(.space_between);

    var rec1 = Record{};
    var child1 = DummyElement{ .size = Size.init(4, 2), .record = &rec1 };
    try layout.addChild(FlexChild.init(child1.asElement(), 0).margin(EdgeInsets{
        .top = 0,
        .right = 1,
        .bottom = 0,
        .left = 1,
    }));

    var rec2 = Record{};
    var child2 = DummyElement{ .size = Size.init(3, 3), .record = &rec2 };
    try layout.addChild(FlexChild.init(child2.asElement(), 1));

    var rec3 = Record{};
    var child3 = DummyElement{ .size = Size.init(3, 3), .record = &rec3 };
    try layout.addChild(FlexChild.init(child3.asElement(), 1));

    const reported_size = layout.calculateLayout(Constraints.tight(30, 5));
    try std.testing.expectEqual(@as(u16, 30), reported_size.width);
    try std.testing.expectEqual(@as(u16, 3), reported_size.height);

    var renderer = try renderer_mod.Renderer.init(allocator, 40, 10);
    defer renderer.deinit();

    layout.renderLayout(&renderer, Rect.init(0, 0, 30, 5));

    try std.testing.expectEqual(@as(u16, 1), rec1.rect.x);
    try std.testing.expectEqual(@as(u16, 1), rec1.rect.y);
    try std.testing.expectEqual(@as(u16, 4), rec1.rect.width);
    try std.testing.expectEqual(@as(u16, 2), rec1.rect.height);

    try std.testing.expectEqual(@as(u16, 7), rec2.rect.x);
    try std.testing.expectEqual(@as(u16, 1), rec2.rect.y);
    try std.testing.expectEqual(@as(u16, 11), rec2.rect.width);
    try std.testing.expectEqual(@as(u16, 3), rec2.rect.height);

    try std.testing.expectEqual(@as(u16, 19), rec3.rect.x);
    try std.testing.expectEqual(@as(u16, 1), rec3.rect.y);
    try std.testing.expectEqual(@as(u16, 11), rec3.rect.width);
    try std.testing.expectEqual(@as(u16, 3), rec3.rect.height);
}

test "flex layout supports rtl rows" {
    const allocator = std.testing.allocator;

    const Tracker = struct {
        rect: Rect = Rect.init(0, 0, 0, 0),
    };

    const DummyElement = struct {
        const Self = @This();
        record: *Tracker,

        fn layout(ctx: *anyopaque, _: Constraints) Size {
            _ = ctx;
            return Size.init(3, 1);
        }

        fn render(ctx: *anyopaque, _: *renderer_mod.Renderer, rect: Rect) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.record.rect = rect;
        }

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = layout,
                .renderFn = render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var left_track = Tracker{};
    var right_track = Tracker{};
    var left = DummyElement{ .record = &left_track };
    var right = DummyElement{ .record = &right_track };

    var flex = try FlexLayout.init(allocator, .row);
    defer flex.deinit();
    flex.layoutDirection(.rtl);

    try flex.addChild(FlexChild{ .element = left.asElement() });
    try flex.addChild(FlexChild{ .element = right.asElement() });

    const constraints = Constraints.tight(8, 1);
    _ = flex.calculateLayout(constraints);

    var renderer = try renderer_mod.Renderer.init(allocator, 8, 1);
    defer renderer.deinit();
    flex.renderLayout(&renderer, Rect.init(0, 0, 8, 1));

    try std.testing.expectEqual(@as(u16, 5), left_track.rect.x);
    try std.testing.expectEqual(@as(u16, 2), right_track.rect.x);
}

test "flex layout negotiates preferred and minimum sizes" {
    const allocator = std.testing.allocator;

    const DummyElement = struct {
        const Self = @This();
        size: Size,
        rect: *Rect,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            _ = constraints;
            return self.size;
        }

        fn render(ctx: *anyopaque, _: *renderer_mod.Renderer, rect: Rect) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.rect.* = rect;
        }

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var recorded = Rect.init(0, 0, 0, 0);
    var dummy = DummyElement{ .size = Size.init(2, 1), .rect = &recorded };

    var layout = try FlexLayout.init(allocator, .row);
    defer layout.deinit();
    try layout.addChild(
        FlexChild.init(dummy.asElement(), 0).minSize(Size.init(4, 3)).preferredSize(Size.init(6, 4)),
    );

    const measured = layout.calculateLayout(Constraints.tight(20, 10));
    try std.testing.expectEqual(@as(u16, 6), measured.width);
    try std.testing.expectEqual(@as(u16, 4), measured.height);

    var renderer = try renderer_mod.Renderer.init(allocator, 30, 10);
    defer renderer.deinit();

    layout.renderLayout(&renderer, Rect.init(0, 0, 20, 10));
    try std.testing.expectEqual(@as(u16, 6), recorded.width);
    try std.testing.expectEqual(@as(u16, 4), recorded.height);
}

test "flex layout shrinks flex children within constraints" {
    const allocator = std.testing.allocator;

    const Recorder = struct {
        const Self = @This();
        preferred: Size,
        rect: *Rect,

        fn layout(ctx: *anyopaque, _: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            return self.preferred;
        }

        fn render(ctx: *anyopaque, _: *renderer_mod.Renderer, rect: Rect) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.rect.* = rect;
        }

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var rect_a = Rect.init(0, 0, 0, 0);
    var rect_b = Rect.init(0, 0, 0, 0);
    var a = Recorder{ .preferred = Size.init(6, 2), .rect = &rect_a };
    var b = Recorder{ .preferred = Size.init(6, 2), .rect = &rect_b };

    var layout = try FlexLayout.init(allocator, .row);
    defer layout.deinit();
    try layout.addChild(FlexChild.init(a.asElement(), 1).minSize(Size.init(4, 2)));
    try layout.addChild(FlexChild.init(b.asElement(), 1).minSize(Size.init(3, 2)));

    const measured = layout.calculateLayout(Constraints.tight(10, 3));
    try std.testing.expectEqual(@as(u16, 10), measured.width);

    var renderer = try renderer_mod.Renderer.init(allocator, 12, 4);
    defer renderer.deinit();
    layout.renderLayout(&renderer, Rect.init(0, 0, 10, 3));

    try std.testing.expectEqual(@as(u16, 5), rect_a.width);
    try std.testing.expectEqual(@as(u16, 5), rect_b.width);
    try std.testing.expectEqual(@as(u16, 2), rect_a.height);
    try std.testing.expectEqual(@as(u16, 2), rect_b.height);
}

test "flex layout reuses cached measurements for identical constraints" {
    const allocator = std.testing.allocator;

    const Counting = struct {
        const Self = @This();
        preferred: Size,
        counter: *u32,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.counter.* += 1;
            return constraints.constrain(self.preferred.width, self.preferred.height);
        }

        fn render(_: *anyopaque, _: *renderer_mod.Renderer, _: Rect) void {}

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var layout_calls: u32 = 0;
    var counting = Counting{ .preferred = Size.init(4, 1), .counter = &layout_calls };

    var layout = try FlexLayout.init(allocator, .row);
    defer layout.deinit();
    try layout.addChild(FlexChild.init(counting.asElement(), 0));

    const measured = layout.calculateLayout(Constraints.tight(8, 3));
    try std.testing.expectEqual(@as(u16, 4), measured.width);
    try std.testing.expect(layout_calls >= 1);
    const calls_after_layout = layout_calls;

    var renderer = try renderer_mod.Renderer.init(allocator, 8, 3);
    defer renderer.deinit();
    layout.renderLayout(&renderer, Rect.init(0, 0, 8, 3));

    try std.testing.expectEqual(calls_after_layout, layout_calls);
}

test "flex layout fuzzes arbitrary constraints and children" {
    var prng = std.Random.DefaultPrng.init(0xdead_beef);
    const rand = prng.random();

    const Stub = struct {
        const Self = @This();
        preferred: Size,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            return constraints.constrain(self.preferred.width, self.preferred.height);
        }

        fn render(_: *anyopaque, _: *renderer_mod.Renderer, _: Rect) void {}

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    for (0..64) |_| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var layout = try FlexLayout.init(alloc, if (rand.boolean()) .row else .column);
        defer layout.deinit();
        _ = layout
            .gap(rand.intRangeAtMost(u16, 0, 3))
            .padding(EdgeInsets.all(rand.intRangeAtMost(u16, 0, 2)));

        var stubs = std.ArrayList(Stub).empty;
        defer stubs.deinit(alloc);

        const child_count = rand.intRangeAtMost(u8, 0, 8);
        try stubs.ensureTotalCapacity(alloc, child_count);

        for (0..child_count) |_| {
            const preferred = Size.init(
                rand.intRangeAtMost(u16, 0, 40),
                rand.intRangeAtMost(u16, 0, 20),
            );
            try stubs.append(alloc, Stub{ .preferred = preferred });

            var child = FlexChild.init(stubs.items[stubs.items.len - 1].asElement(), rand.intRangeAtMost(u16, 0, 3));
            if (rand.boolean()) {
                child = child.grow(rand.intRangeAtMost(u16, 1, 4));
            }
            if (rand.boolean()) {
                child = child.shrink(rand.intRangeAtMost(u16, 1, 4));
            }
            try layout.addChild(child);
        }

        const min_w = rand.intRangeAtMost(u16, 0, 60);
        const min_h = rand.intRangeAtMost(u16, 0, 30);
        const max_w: u16 = @intCast(@min(@as(u32, min_w) + rand.intRangeAtMost(u16, 1, 120), std.math.maxInt(u16)));
        const max_h: u16 = @intCast(@min(@as(u32, min_h) + rand.intRangeAtMost(u16, 1, 80), std.math.maxInt(u16)));
        const constraints = Constraints.init(min_w, max_w, min_h, max_h);
        const measured = layout.calculateLayout(constraints);

        try std.testing.expect(measured.width <= max_w);
        try std.testing.expect(measured.height <= max_h);
        for (layout.children.items) |child| {
            try std.testing.expect(child.cached_size.width <= max_w);
            try std.testing.expect(child.cached_size.height <= max_h);
        }
    }
}

test "grid layout resolves fixed and flexible tracks" {
    const allocator = std.testing.allocator;

    const Probe = struct {
        const Self = @This();
        record: *Rect,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            _ = self;
            return Size.init(constraints.max_width, constraints.max_height);
        }

        fn render(ctx: *anyopaque, _: *renderer_mod.Renderer, rect: Rect) void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            self.record.* = rect;
        }

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var grid = try GridLayout.init(allocator, 3, 2);
    defer grid.deinit();
    _ = grid.gap(1);
    _ = try grid.setColumns(&[_]GridTrack{
        GridTrack{ .fixed = 5 },
        GridTrack{ .flex = 1 },
        GridTrack{ .flex = 2 },
    });
    _ = try grid.setRows(&[_]GridTrack{
        GridTrack{ .flex = 1 },
        GridTrack{ .fixed = 2 },
    });

    var r1 = Rect.init(0, 0, 0, 0);
    var r2 = Rect.init(0, 0, 0, 0);
    var r3 = Rect.init(0, 0, 0, 0);

    var p1 = Probe{ .record = &r1 };
    var p2 = Probe{ .record = &r2 };
    var p3 = Probe{ .record = &r3 };

    try grid.addChild(p1.asElement(), 0, 0);
    try grid.addChild(p2.asElement(), 1, 0);
    try grid.addChild(p3.asElement(), 2, 1);

    const measured = grid.calculateLayout(Constraints.tight(24, 8));
    try std.testing.expectEqual(@as(u16, 24), measured.width);
    try std.testing.expectEqual(@as(u16, 8), measured.height);

    var renderer = try renderer_mod.Renderer.init(allocator, 30, 10);
    defer renderer.deinit();

    grid.renderLayout(&renderer, Rect.init(0, 0, 24, 8));

    try std.testing.expectEqual(@as(u16, 0), r1.x);
    try std.testing.expectEqual(@as(u16, 0), r1.y);
    try std.testing.expectEqual(@as(u16, 5), r1.width);
    try std.testing.expectEqual(@as(u16, 5), r1.height);

    try std.testing.expectEqual(@as(u16, 6), r2.x);
    try std.testing.expectEqual(@as(u16, 0), r2.y);
    try std.testing.expectEqual(@as(u16, 6), r2.width);
    try std.testing.expectEqual(@as(u16, 5), r2.height);

    try std.testing.expectEqual(@as(u16, 13), r3.x);
    try std.testing.expectEqual(@as(u16, 6), r3.y);
    try std.testing.expectEqual(@as(u16, 11), r3.width);
    try std.testing.expectEqual(@as(u16, 2), r3.height);
}

/// Constraints for positioning a child within a constraint layout
pub const ConstraintSpec = struct {
    left: ?u16 = null,
    right: ?u16 = null,
    top: ?u16 = null,
    bottom: ?u16 = null,
    center_x: bool = false,
    center_y: bool = false,
    width: ?u16 = null,
    height: ?u16 = null,
    min_width: ?u16 = null,
    max_width: ?u16 = null,
    min_height: ?u16 = null,
    max_height: ?u16 = null,

    /// Create a spec pinned to the top-left with optional size
    pub fn topLeft(x: u16, y: u16, width: ?u16, height: ?u16) ConstraintSpec {
        return ConstraintSpec{
            .left = x,
            .top = y,
            .width = width,
            .height = height,
        };
    }

    /// Create a spec centered in both axes with optional size
    pub fn centered(width: ?u16, height: ?u16) ConstraintSpec {
        return ConstraintSpec{
            .center_x = true,
            .center_y = true,
            .width = width,
            .height = height,
        };
    }
};

/// Child entry for constraint layout
pub const ConstraintChild = struct {
    element: LayoutElement,
    spec: ConstraintSpec,
    resolved_rect: Rect = Rect.init(0, 0, 0, 0),
};

/// Absolute/constraint-based layout manager. Children are positioned using anchors or explicit sizes.
pub const ConstraintLayout = struct {
    base: Layout,
    children: std.ArrayList(ConstraintChild),
    padding_insets: EdgeInsets,
    cached_available_width: u16,
    cached_available_height: u16,
    cache_valid: bool,

    /// Initialize a new constraint layout
    pub fn init(allocator: std.mem.Allocator) !*ConstraintLayout {
        const layout = try allocator.create(ConstraintLayout);
        layout.* = ConstraintLayout{
            .base = Layout.init(allocator),
            .children = std.ArrayList(ConstraintChild).empty,
            .padding_insets = EdgeInsets.all(0),
            .cached_available_width = 0,
            .cached_available_height = 0,
            .cache_valid = false,
        };
        errdefer layout.deinit();
        return layout;
    }

    /// Clean up resources
    pub fn deinit(self: *ConstraintLayout) void {
        self.children.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    fn invalidateCache(self: *ConstraintLayout) void {
        self.cache_valid = false;
    }

    /// Set padding around the content area
    pub fn padding(self: *ConstraintLayout, padding_value: EdgeInsets) *ConstraintLayout {
        self.padding_insets = padding_value;
        self.invalidateCache();
        return self;
    }

    /// Add a child with positioning constraints
    pub fn addChild(self: *ConstraintLayout, element: LayoutElement, spec: ConstraintSpec) !void {
        try self.children.append(self.base.allocator, ConstraintChild{
            .element = element,
            .spec = spec,
        });
        self.invalidateCache();
    }

    /// Layout callback for LayoutElement
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*ConstraintLayout, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Render callback for LayoutElement
    pub fn renderFn(ctx: *anyopaque, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const self = @as(*ConstraintLayout, @ptrCast(@alignCast(ctx)));
        self.renderLayout(renderer, rect);
    }

    /// Calculate layout and remember child rectangles
    pub fn calculateLayout(self: *ConstraintLayout, constraints: Constraints) Size {
        const width = constraints.max_width;
        const height = constraints.max_height;

        const horizontal_padding = saturatingAdd(self.padding_insets.left, self.padding_insets.right);
        const vertical_padding = saturatingAdd(self.padding_insets.top, self.padding_insets.bottom);

        const available_width = if (width > horizontal_padding)
            width - horizontal_padding
        else
            0;
        const available_height = if (height > vertical_padding)
            height - vertical_padding
        else
            0;

        self.ensureLayout(available_width, available_height);

        return Size.init(width, height);
    }

    /// Render children at their resolved rectangles
    pub fn renderLayout(self: *ConstraintLayout, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const width = rect.width;
        const height = rect.height;

        const horizontal_padding = saturatingAdd(self.padding_insets.left, self.padding_insets.right);
        const vertical_padding = saturatingAdd(self.padding_insets.top, self.padding_insets.bottom);

        const available_width = if (width > horizontal_padding)
            width - horizontal_padding
        else
            0;
        const available_height = if (height > vertical_padding)
            height - vertical_padding
        else
            0;

        self.ensureLayout(available_width, available_height);

        for (self.children.items) |*child| {
            const adjusted_rect = Rect{
                .x = saturatingAdd(rect.x, child.resolved_rect.x),
                .y = saturatingAdd(rect.y, child.resolved_rect.y),
                .width = child.resolved_rect.width,
                .height = child.resolved_rect.height,
            };
            if (!intersectsViewport(adjusted_rect, renderer)) continue;
            child.element.render(renderer, adjusted_rect);
        }
    }

    /// Convert to LayoutElement
    pub fn asElement(self: *ConstraintLayout) LayoutElement {
        return LayoutElement{
            .layoutFn = ConstraintLayout.layoutFn,
            .renderFn = ConstraintLayout.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }

    fn ensureLayout(self: *ConstraintLayout, available_width: u16, available_height: u16) void {
        if (self.cache_valid and self.cached_available_width == available_width and self.cached_available_height == available_height) {
            return;
        }

        for (self.children.items) |*child| {
            self.layoutChild(child, available_width, available_height);
        }

        self.cached_available_width = available_width;
        self.cached_available_height = available_height;
        self.cache_valid = true;
    }

    fn layoutChild(self: *ConstraintLayout, child: *ConstraintChild, available_width: u16, available_height: u16) void {
        const spec = child.spec;

        const max_width = spec.max_width orelse available_width;
        const max_height = spec.max_height orelse available_height;

        const range_min_width = if (spec.min_width) |mw| @min(mw, max_width) else 0;
        const range_min_height = if (spec.min_height) |mh| @min(mh, max_height) else 0;

        const target_width = blk: {
            if (spec.width) |fixed| break :blk fixed;
            if (spec.left != null and spec.right != null) {
                const anchors = saturatingAdd(spec.left.?, spec.right.?);
                if (available_width > anchors) {
                    break :blk available_width - anchors;
                }
            }
            break :blk max_width;
        };

        const target_height = blk: {
            if (spec.height) |fixed| break :blk fixed;
            if (spec.top != null and spec.bottom != null) {
                const anchors = saturatingAdd(spec.top.?, spec.bottom.?);
                if (available_height > anchors) {
                    break :blk available_height - anchors;
                }
            }
            break :blk max_height;
        };

        const child_constraints = Constraints{
            .min_width = @min(target_width, range_min_width),
            .max_width = @min(target_width, max_width),
            .min_height = @min(target_height, range_min_height),
            .max_height = @min(target_height, max_height),
        };

        const measured = child.element.layout(child_constraints);

        const natural_width = blk: {
            if (spec.width) |w| break :blk w;
            if (spec.left != null and spec.right != null) break :blk target_width;
            break :blk measured.width;
        };

        const natural_height = blk: {
            if (spec.height) |h| break :blk h;
            if (spec.top != null and spec.bottom != null) break :blk target_height;
            break :blk measured.height;
        };

        const resolved_width = std.math.clamp(natural_width, range_min_width, max_width);
        const resolved_height = std.math.clamp(natural_height, range_min_height, max_height);

        const x = blk: {
            if (spec.center_x) {
                if (available_width > resolved_width) break :blk saturatingAdd(self.padding_insets.left, (available_width - resolved_width) / 2);
                break :blk self.padding_insets.left;
            }
            if (spec.left) |left_offset| break :blk saturatingAdd(self.padding_insets.left, left_offset);
            if (spec.right) |right_offset| {
                const required = saturatingAdd(resolved_width, right_offset);
                if (available_width > required) {
                    const offset = available_width - required;
                    break :blk saturatingAdd(self.padding_insets.left, offset);
                }
                break :blk self.padding_insets.left;
            }
            break :blk self.padding_insets.left;
        };

        const y = blk: {
            if (spec.center_y) {
                if (available_height > resolved_height) break :blk saturatingAdd(self.padding_insets.top, (available_height - resolved_height) / 2);
                break :blk self.padding_insets.top;
            }
            if (spec.top) |top_offset| break :blk saturatingAdd(self.padding_insets.top, top_offset);
            if (spec.bottom) |bottom_offset| {
                const required = saturatingAdd(resolved_height, bottom_offset);
                if (available_height > required) {
                    const offset = available_height - required;
                    break :blk saturatingAdd(self.padding_insets.top, offset);
                }
                break :blk self.padding_insets.top;
            }
            break :blk self.padding_insets.top;
        };

        child.resolved_rect = Rect{
            .x = x,
            .y = y,
            .width = resolved_width,
            .height = resolved_height,
        };
    }
};

test "constraint layout resolves anchored and centered children" {
    const allocator = std.testing.allocator;

    const DummyElement = struct {
        const Self = @This();
        size: Size,

        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            _ = constraints;
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));
            return self.size;
        }

        fn render(_: *anyopaque, _: *renderer_mod.Renderer, _: Rect) void {}

        fn asElement(self: *Self) LayoutElement {
            return LayoutElement{
                .layoutFn = Self.layout,
                .renderFn = Self.render,
                .ctx = @ptrCast(@alignCast(self)),
            };
        }
    };

    var layout = try ConstraintLayout.init(allocator);
    defer layout.deinit();
    _ = layout.padding(EdgeInsets.all(1));

    var top_left = DummyElement{ .size = Size.init(5, 3) };
    try layout.addChild(top_left.asElement(), ConstraintSpec.topLeft(2, 1, 5, 3));

    var centered = DummyElement{ .size = Size.init(4, 2) };
    try layout.addChild(centered.asElement(), ConstraintSpec.centered(4, 2));

    var stretched = DummyElement{ .size = Size.init(1, 1) };
    try layout.addChild(stretched.asElement(), ConstraintSpec{
        .left = 0,
        .right = 0,
        .top = 5,
        .height = 1,
    });

    const result_size = layout.calculateLayout(Constraints.tight(40, 20));
    try std.testing.expectEqual(@as(u16, 40), result_size.width);
    try std.testing.expectEqual(@as(u16, 20), result_size.height);

    try std.testing.expectEqual(@as(u16, 3), layout.children.items[0].resolved_rect.x);
    try std.testing.expectEqual(@as(u16, 2), layout.children.items[0].resolved_rect.y);
    try std.testing.expectEqual(@as(u16, 5), layout.children.items[0].resolved_rect.width);
    try std.testing.expectEqual(@as(u16, 3), layout.children.items[0].resolved_rect.height);

    try std.testing.expectEqual(@as(u16, 18), layout.children.items[1].resolved_rect.x);
    try std.testing.expectEqual(@as(u16, 9), layout.children.items[1].resolved_rect.y);
    try std.testing.expectEqual(@as(u16, 4), layout.children.items[1].resolved_rect.width);
    try std.testing.expectEqual(@as(u16, 2), layout.children.items[1].resolved_rect.height);

    try std.testing.expectEqual(@as(u16, 1), layout.children.items[2].resolved_rect.x);
    try std.testing.expectEqual(@as(u16, 6), layout.children.items[2].resolved_rect.y);
    try std.testing.expectEqual(@as(u16, 38), layout.children.items[2].resolved_rect.width);
    try std.testing.expectEqual(@as(u16, 1), layout.children.items[2].resolved_rect.height);
}

/// LayoutGuide provides composable helpers for consistent spacing.
pub const LayoutGuide = struct {
    /// Padding to apply around computed regions
    padding: EdgeInsets = EdgeInsets.all(0),
    /// Gap between stacked regions
    gap: u16 = 1,

    pub const Regions = struct { header: Rect, content: Rect, footer: Rect };

    pub fn init(padding: EdgeInsets, gap: u16) LayoutGuide {
        return .{ .padding = padding, .gap = gap };
    }

    /// Apply padding to a rectangle.
    pub fn inset(self: LayoutGuide, rect: Rect) Rect {
        return rect.shrink(self.padding);
    }

    /// Compute header/content/footer rectangles inside a container.
    pub fn headerContentFooter(self: LayoutGuide, rect: Rect, header_height: u16, footer_height: u16) Regions {
        const inner = self.inset(rect);
        const doubled_gap = std.math.mul(u32, @as(u32, self.gap), 2) catch std.math.maxInt(u32);
        const gap_twice: u16 = @intCast(@min(doubled_gap, @as(u32, std.math.maxInt(u16))));
        const total_gap: u16 = if (inner.height >= gap_twice) gap_twice else 0;
        const usable_height = if (inner.height > total_gap) inner.height - total_gap else inner.height;

        const capped_header = @min(header_height, usable_height);
        const capped_footer = @min(footer_height, usable_height - capped_header);
        const combined_hf = saturatingAdd(capped_header, capped_footer);
        const remaining = if (usable_height > combined_hf) usable_height - combined_hf else 0;

        const header_rect = Rect.init(inner.x, inner.y, inner.width, capped_header);
        const content_y = saturatingAdd(header_rect.y, saturatingAdd(header_rect.height, if (header_rect.height > 0) self.gap else 0));
        const content_rect = Rect.init(inner.x, content_y, inner.width, remaining);
        const footer_y = saturatingAdd(content_rect.y, saturatingAdd(content_rect.height, if (capped_footer > 0) self.gap else 0));
        const footer_rect = Rect.init(inner.x, footer_y, inner.width, capped_footer);

        return .{ .header = header_rect, .content = content_rect, .footer = footer_rect };
    }

    /// Split a region into row rectangles using fixed heights.
    /// Returns the number of rows written into `out`.
    pub fn splitRows(self: LayoutGuide, rect: Rect, heights: []const u16, out: []Rect) usize {
        if (heights.len == 0 or out.len == 0) return 0;
        const inner = self.inset(rect);
        var cursor_y = inner.y;
        var count: usize = 0;
        const inner_bottom = saturatingAdd(inner.y, inner.height);

        for (heights, 0..) |h, idx| {
            if (idx >= out.len) break;
            if (cursor_y >= inner_bottom) break;
            if (h == 0) continue;

            const remaining_height = if (inner_bottom > cursor_y) inner_bottom - cursor_y else 0;
            const row_height = @min(h, remaining_height);
            out[count] = Rect.init(inner.x, cursor_y, inner.width, row_height);
            count += 1;

            const step = saturatingAdd(row_height, self.gap);
            if (remaining_height <= step) break;
            cursor_y = saturatingAdd(cursor_y, step);
        }

        return count;
    }
};

test "layout guide splits header content footer with padding" {
    const guide = LayoutGuide.init(EdgeInsets.all(1), 1);
    const regions = guide.headerContentFooter(Rect.init(0, 0, 20, 10), 2, 3);
    try std.testing.expectEqual(@as(u16, 2), regions.header.height);
    try std.testing.expectEqual(@as(u16, 3), regions.footer.height);
    try std.testing.expectEqual(@as(u16, 18), regions.header.width);
    try std.testing.expect(regions.content.height > 0);
}

/// Reflow manager for handling terminal resize events
pub const ReflowManager = struct {
    /// Root layout element
    root: ?LayoutElement,
    /// Current constraints
    constraints: Constraints,

    /// Initialize a new reflow manager
    pub fn init() ReflowManager {
        return ReflowManager{
            .root = null,
            .constraints = Constraints.init(0, 0, 0, 0),
        };
    }

    /// Set the root element
    pub fn setRoot(self: *ReflowManager, root: LayoutElement) void {
        self.root = root;
    }

    /// Handle terminal resize
    pub fn handleResize(self: *ReflowManager, width: u16, height: u16) !Size {
        self.constraints = Constraints.tight(width, height);
        if (self.root) |root| {
            return root.layout(self.constraints);
        }
        return Size.zero();
    }

    /// Render the current layout
    pub fn render(self: *ReflowManager, renderer: *renderer_mod.Renderer) void {
        if (self.root) |root| {
            const rect = Rect{
                .x = 0,
                .y = 0,
                .width = self.constraints.max_width,
                .height = self.constraints.max_height,
            };
            root.render(renderer, rect);
        }
    }
};

test "reflow manager handles rapid resize churn including zeros" {
    var layout_calls: usize = 0;

    const Stub = struct {
        fn layout(ctx: *anyopaque, constraints: Constraints) Size {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx)));
            counter.* += 1;
            return Size.init(constraints.max_width, constraints.max_height);
        }

        fn render(_: *anyopaque, _: *renderer_mod.Renderer, _: Rect) void {}
    };

    var manager = ReflowManager.init();
    const element = LayoutElement{
        .layoutFn = Stub.layout,
        .renderFn = Stub.render,
        .ctx = &layout_calls,
    };
    manager.setRoot(element);

    const changes = [_]struct { w: u16, h: u16 }{
        .{ .w = 0, .h = 0 },
        .{ .w = 80, .h = 24 },
        .{ .w = 120, .h = 5 },
        .{ .w = 20, .h = 50 },
    };

    for (changes) |change| {
        const size = try manager.handleResize(change.w, change.h);
        try std.testing.expectEqual(change.w, size.width);
        try std.testing.expectEqual(change.h, size.height);
    }

    try std.testing.expectEqual(changes.len, layout_calls);
}

test "rect shrink and expand respect bounds" {
    const rect = Rect.init(2, 3, 10, 5);
    const shrunk = rect.shrink(EdgeInsets.all(2));
    try std.testing.expectEqual(@as(u16, 6), shrunk.width);
    try std.testing.expectEqual(@as(u16, 1), shrunk.height);
    try std.testing.expectEqual(@as(u16, 4), shrunk.x);
    try std.testing.expectEqual(@as(u16, 5), shrunk.y);

    const expanded = shrunk.expand(EdgeInsets.symmetric(1, 2));
    try std.testing.expectEqual(@as(u16, 8), expanded.width);
    try std.testing.expectEqual(@as(u16, 5), expanded.height);
    try std.testing.expectEqual(@as(u16, 3), expanded.x);
    try std.testing.expectEqual(@as(u16, 3), expanded.y);
}
