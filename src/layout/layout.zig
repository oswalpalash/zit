const std = @import("std");
const renderer_mod = @import("../render/render.zig");

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
    pub fn init(x: u16, y: u16, width: u16, height: u16) Rect {
        return Rect{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    /// Check if a point is inside the rectangle
    pub fn contains(self: Rect, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
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
        const new_width = if (self.width > insets.left + insets.right)
            self.width - insets.left - insets.right
        else
            0;
        const new_height = if (self.height > insets.top + insets.bottom)
            self.height - insets.top - insets.bottom
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
        return Rect{
            .x = if (self.x > insets.left) self.x - insets.left else 0,
            .y = if (self.y > insets.top) self.y - insets.top else 0,
            .width = self.width + insets.left + insets.right,
            .height = self.height + insets.top + insets.bottom,
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
    pub fn init(top: u16, right: u16, bottom: u16, left: u16) EdgeInsets {
        return EdgeInsets{
            .top = top,
            .right = right,
            .bottom = bottom,
            .left = left,
        };
    }

    /// Create uniform insets (same value for all sides)
    pub fn all(value: u16) EdgeInsets {
        return EdgeInsets{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }

    /// Create horizontal and vertical insets
    pub fn symmetric(horizontal: u16, vertical: u16) EdgeInsets {
        return EdgeInsets{
            .top = vertical,
            .right = horizontal,
            .bottom = vertical,
            .left = horizontal,
        };
    }
};

/// Direction for flex layouts
pub const FlexDirection = enum {
    row,
    column,
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
    pub fn init(min_width: u16, max_width: u16, min_height: u16, max_height: u16) Constraints {
        return Constraints{
            .min_width = min_width,
            .max_width = max_width,
            .min_height = min_height,
            .max_height = max_height,
        };
    }

    /// Create tight constraints (min = max)
    pub fn tight(width: u16, height: u16) Constraints {
        return Constraints{
            .min_width = width,
            .max_width = width,
            .min_height = height,
            .max_height = height,
        };
    }

    /// Create constraints with no maximum
    pub fn loose(min_width: u16, min_height: u16) Constraints {
        return Constraints{
            .min_width = min_width,
            .max_width = std.math.maxInt(u16),
            .min_height = min_height,
            .max_height = std.math.maxInt(u16),
        };
    }

    /// Create constraints that are bounded by the given size
    pub fn bounded(max_width: u16, max_height: u16) Constraints {
        return Constraints{
            .min_width = 0,
            .max_width = max_width,
            .min_height = 0,
            .max_height = max_height,
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
    pub fn init(width: u16, height: u16) Size {
        return Size{
            .width = width,
            .height = height,
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
    /// Flex factor (0 = non-flexible)
    flex: u16,
    /// Alignment in the cross axis
    cross_alignment: ?FlexAlignment,
    /// Margin around the child
    margin_insets: EdgeInsets,
    /// Cached size from last layout
    cached_size: Size,

    /// Create a new flex child
    pub fn init(element: LayoutElement, flex: u16) FlexChild {
        return FlexChild{
            .element = element,
            .flex = flex,
            .cross_alignment = null,
            .margin_insets = EdgeInsets.all(0),
            .cached_size = Size.zero(),
        };
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
};

/// Flex layout manager
pub const FlexLayout = struct {
    /// Base layout
    base: Layout,
    /// Direction of the flex layout
    direction: FlexDirection,
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

    /// Initialize a new flex layout
    pub fn init(allocator: std.mem.Allocator, direction: FlexDirection) !*FlexLayout {
        const layout = try allocator.create(FlexLayout);
        layout.* = FlexLayout{
            .base = Layout.init(allocator),
            .direction = direction,
            .main_alignment = .start,
            .cross_alignment = .start,
            .children = std.ArrayList(FlexChild).empty,
            .padding_insets = EdgeInsets.all(0),
            .gap_size = 0,
        };
        return layout;
    }

    /// Clean up flex layout resources
    pub fn deinit(self: *FlexLayout) void {
        self.children.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    /// Set the main axis alignment
    pub fn mainAlignment(self: *FlexLayout, alignment: FlexAlignment) *FlexLayout {
        self.main_alignment = alignment;
        return self;
    }

    /// Set the cross axis alignment
    pub fn crossAlignment(self: *FlexLayout, alignment: FlexAlignment) *FlexLayout {
        self.cross_alignment = alignment;
        return self;
    }

    /// Set the padding
    pub fn padding(self: *FlexLayout, padding_value: EdgeInsets) *FlexLayout {
        self.padding_insets = padding_value;
        return self;
    }

    /// Set the gap between children
    pub fn gap(self: *FlexLayout, gap_value: u16) *FlexLayout {
        self.gap_size = gap_value;
        return self;
    }

    /// Add a child element
    pub fn addChild(self: *FlexLayout, child: FlexChild) !void {
        try self.children.append(self.base.allocator, child);
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*FlexLayout, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *FlexLayout, constraints: Constraints) Size {
        // Apply padding to constraints
        const padded_constraints = Constraints{
            .min_width = if (constraints.min_width > self.padding_insets.left + self.padding_insets.right)
                constraints.min_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .max_width = if (constraints.max_width > self.padding_insets.left + self.padding_insets.right)
                constraints.max_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .min_height = if (constraints.min_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.min_height - self.padding_insets.top - self.padding_insets.bottom
            else
                0,
            .max_height = if (constraints.max_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.max_height - self.padding_insets.top - self.padding_insets.bottom
            else
                0,
        };

        // First pass: measure non-flex children and calculate total flex factor
        var total_flex: u16 = 0;
        var total_main_size: u16 = 0;
        var max_cross_size: u16 = 0;

        // Calculate total gap size
        const total_gap_size = if (self.children.items.len > 1)
            (self.children.items.len - 1) * self.gap_size
        else
            0;

        // First pass: measure non-flex children
        for (self.children.items) |*child| {
            if (child.flex == 0) {
                // Non-flex child: measure with unbounded constraints in flex direction
                const child_constraints = if (self.direction == .row)
                    Constraints{
                        .min_width = 0,
                        .max_width = padded_constraints.max_width,
                        .min_height = padded_constraints.min_height,
                        .max_height = padded_constraints.max_height,
                    }
                else
                    Constraints{
                        .min_width = padded_constraints.min_width,
                        .max_width = padded_constraints.max_width,
                        .min_height = 0,
                        .max_height = padded_constraints.max_height,
                    };

                // Account for margin in constraints
                const margin_adjusted_constraints = Constraints{
                    .min_width = if (child_constraints.min_width > child.margin_insets.left + child.margin_insets.right)
                        child_constraints.min_width - child.margin_insets.left - child.margin_insets.right
                    else
                        0,
                    .max_width = if (child_constraints.max_width > child.margin_insets.left + child.margin_insets.right)
                        child_constraints.max_width - child.margin_insets.left - child.margin_insets.right
                    else
                        0,
                    .min_height = if (child_constraints.min_height > child.margin_insets.top + child.margin_insets.bottom)
                        child_constraints.min_height - child.margin_insets.top - child.margin_insets.bottom
                    else
                        0,
                    .max_height = if (child_constraints.max_height > child.margin_insets.top + child.margin_insets.bottom)
                        child_constraints.max_height - child.margin_insets.top - child.margin_insets.bottom
                    else
                        0,
                };

                // Measure the child
                const size = child.element.layout(margin_adjusted_constraints);
                child.cached_size = size;

                // Update total sizes
                if (self.direction == .row) {
                    total_main_size += size.width + child.margin_insets.left + child.margin_insets.right;
                    max_cross_size = @max(max_cross_size, size.height + child.margin_insets.top + child.margin_insets.bottom);
                } else {
                    total_main_size += size.height + child.margin_insets.top + child.margin_insets.bottom;
                    max_cross_size = @max(max_cross_size, size.width + child.margin_insets.left + child.margin_insets.right);
                }
            } else {
                total_flex += child.flex;
            }
        }

        // Calculate remaining space for flex children
        const main_axis_size = if (self.direction == .row)
            padded_constraints.max_width
        else
            padded_constraints.max_height;

        const remaining_space = if (main_axis_size > total_main_size + total_gap_size)
            main_axis_size - total_main_size - total_gap_size
        else
            0;

        // Second pass: Layout flex children
        if (total_flex > 0) {
            const flex_unit_size: u16 = @intCast(remaining_space / total_flex);

            for (self.children.items) |*child| {
                if (child.flex > 0) {
                    // Calculate main size for this child
                    const main_size = flex_unit_size * child.flex;

                    // Create constraints for flex child based on direction
                    const child_constraints = if (self.direction == .row)
                        Constraints{
                            .min_width = main_size,
                            .max_width = main_size,
                            .min_height = 0,
                            .max_height = padded_constraints.max_height,
                        }
                    else
                        Constraints{
                            .min_width = 0,
                            .max_width = padded_constraints.max_width,
                            .min_height = main_size,
                            .max_height = main_size,
                        };

                    // Account for margin in constraints
                    const margin_adjusted_constraints = Constraints{
                        .min_width = if (child_constraints.min_width > child.margin_insets.left + child.margin_insets.right)
                            child_constraints.min_width - child.margin_insets.left - child.margin_insets.right
                        else
                            0,
                        .max_width = if (child_constraints.max_width > child.margin_insets.left + child.margin_insets.right)
                            child_constraints.max_width - child.margin_insets.left - child.margin_insets.right
                        else
                            0,
                        .min_height = if (child_constraints.min_height > child.margin_insets.top + child.margin_insets.bottom)
                            child_constraints.min_height - child.margin_insets.top - child.margin_insets.bottom
                        else
                            0,
                        .max_height = if (child_constraints.max_height > child.margin_insets.top + child.margin_insets.bottom)
                            child_constraints.max_height - child.margin_insets.top - child.margin_insets.bottom
                        else
                            0,
                    };

                    // Layout the child
                    const size = child.element.layout(margin_adjusted_constraints);
                    child.cached_size = size;

                    // Update cross size
                    if (self.direction == .row) {
                        child.cached_size.width = size.width + child.margin_insets.left + child.margin_insets.right;
                        child.cached_size.height = size.height + child.margin_insets.top + child.margin_insets.bottom;
                    } else {
                        child.cached_size.width = size.height + child.margin_insets.top + child.margin_insets.bottom;
                        child.cached_size.height = size.width + child.margin_insets.left + child.margin_insets.right;
                    }

                    max_cross_size = @max(max_cross_size, child.cached_size.height);
                }
            }
        }

        var current_position: u16 = 0;

        // Apply main axis alignment
        var offset: u16 = 0;
        if (self.main_alignment != .start) {
            var used_space = total_main_size + total_gap_size;
            if (total_flex > 0) {
                used_space += remaining_space;
            }

            const free_space = if (main_axis_size > used_space) main_axis_size - used_space else 0;

            switch (self.main_alignment) {
                .start => offset = 0,
                .center => offset = @intCast(free_space / 2),
                .end => offset = @intCast(free_space),
                .space_between => offset = 0,
                .space_evenly => offset = 0,
                .space_around => offset = 0,
            }
        }

        current_position = offset;

        // Layout the children
        for (self.children.items) |*child| {
            var child_main_size: u16 = 0;
            var child_cross_size: u16 = 0;

            if (child.flex > 0) {
                // Use cached size for flex child
                child_main_size = child.cached_size.width + child.margin_insets.left + child.margin_insets.right;
                child_cross_size = child.cached_size.height + child.margin_insets.top + child.margin_insets.bottom;
            } else {
                // Use cached size for non-flex child
                if (self.direction == .row) {
                    child_main_size = child.cached_size.width + child.margin_insets.left + child.margin_insets.right;
                    child_cross_size = child.cached_size.height + child.margin_insets.top + child.margin_insets.bottom;
                } else {
                    child_main_size = child.cached_size.height + child.margin_insets.top + child.margin_insets.bottom;
                    child_cross_size = child.cached_size.width + child.margin_insets.left + child.margin_insets.right;
                }
            }

            // Move to next position
            current_position += child_main_size;
            if (self.children.items.len > 1) {
                current_position += self.gap_size;
            }
        }

        // Return final size including padding
        const content_size = if (self.direction == .row)
            Size{
                .width = @intCast(total_main_size + remaining_space + total_gap_size),
                .height = max_cross_size,
            }
        else
            Size{
                .width = max_cross_size,
                .height = @intCast(total_main_size + remaining_space + total_gap_size),
            };

        return Size{
            .width = content_size.width + self.padding_insets.left + self.padding_insets.right,
            .height = content_size.height + self.padding_insets.top + self.padding_insets.bottom,
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

        // Calculate layout again to get positions
        _ = self.calculateLayout(Constraints.tight(rect.width, rect.height));

        // Calculate layout information
        const is_row = self.direction == .row;
        const main_axis_size = if (is_row) padded_rect.width else padded_rect.height;
        const cross_axis_size = if (is_row) padded_rect.height else padded_rect.width;

        // First pass: measure non-flex children and calculate total flex factor
        var total_flex: u16 = 0;
        var total_main_size: u16 = 0;
        var max_cross_size: u16 = 0;

        // Calculate total gap size
        const total_gap_size = if (self.children.items.len > 1)
            (self.children.items.len - 1) * self.gap_size
        else
            0;

        // First pass: measure non-flex children
        for (self.children.items) |child| {
            if (child.flex == 0) {
                if (is_row) {
                    total_main_size += child.cached_size.width + child.margin_insets.left + child.margin_insets.right;
                    max_cross_size = @max(max_cross_size, child.cached_size.height + child.margin_insets.top + child.margin_insets.bottom);
                } else {
                    total_main_size += child.cached_size.height + child.margin_insets.top + child.margin_insets.bottom;
                    max_cross_size = @max(max_cross_size, child.cached_size.width + child.margin_insets.left + child.margin_insets.right);
                }
            } else {
                total_flex += child.flex;
            }
        }

        // Calculate remaining space for flex children
        const remaining_space = if (main_axis_size > total_main_size + total_gap_size)
            main_axis_size - total_main_size - total_gap_size
        else
            0;

        // Second pass: Layout flex children
        if (total_flex > 0) {
            const flex_unit_size: u16 = @intCast(remaining_space / total_flex);

            for (self.children.items) |*child| {
                if (child.flex > 0) {
                    // Calculate main size for this child
                    const main_size = flex_unit_size * child.flex;

                    // Create constraints for flex child based on direction
                    const child_constraints = if (self.direction == .row)
                        Constraints{
                            .min_width = main_size,
                            .max_width = main_size,
                            .min_height = 0,
                            .max_height = padded_rect.height,
                        }
                    else
                        Constraints{
                            .min_width = 0,
                            .max_width = padded_rect.width,
                            .min_height = main_size,
                            .max_height = main_size,
                        };

                    // Account for margin in constraints
                    const margin_adjusted_constraints = Constraints{
                        .min_width = if (child_constraints.min_width > child.margin_insets.left + child.margin_insets.right)
                            child_constraints.min_width - child.margin_insets.left - child.margin_insets.right
                        else
                            0,
                        .max_width = if (child_constraints.max_width > child.margin_insets.left + child.margin_insets.right)
                            child_constraints.max_width - child.margin_insets.left - child.margin_insets.right
                        else
                            0,
                        .min_height = if (child_constraints.min_height > child.margin_insets.top + child.margin_insets.bottom)
                            child_constraints.min_height - child.margin_insets.top - child.margin_insets.bottom
                        else
                            0,
                        .max_height = if (child_constraints.max_height > child.margin_insets.top + child.margin_insets.bottom)
                            child_constraints.max_height - child.margin_insets.top - child.margin_insets.bottom
                        else
                            0,
                    };

                    // Layout the child
                    const size = child.element.layout(margin_adjusted_constraints);
                    child.cached_size = size;

                    // Update cross size
                    if (self.direction == .row) {
                        child.cached_size.width = size.width + child.margin_insets.left + child.margin_insets.right;
                        child.cached_size.height = size.height + child.margin_insets.top + child.margin_insets.bottom;
                    } else {
                        child.cached_size.width = size.height + child.margin_insets.top + child.margin_insets.bottom;
                        child.cached_size.height = size.width + child.margin_insets.left + child.margin_insets.right;
                    }

                    max_cross_size = @max(max_cross_size, child.cached_size.height);
                }
            }
        }

        var current_position: u16 = 0;

        // Apply main axis alignment
        var offset: u16 = 0;
        if (self.main_alignment != .start) {
            var used_space = total_main_size + total_gap_size;
            if (total_flex > 0) {
                used_space += remaining_space;
            }

            const free_space = if (main_axis_size > used_space) main_axis_size - used_space else 0;

            switch (self.main_alignment) {
                .start => offset = 0,
                .center => offset = @intCast(free_space / 2),
                .end => offset = @intCast(free_space),
                .space_between => offset = 0,
                .space_evenly => offset = 0,
                .space_around => offset = 0,
            }
        }

        current_position = offset;

        // Render each child
        for (self.children.items) |child| {
            var child_main_size: u16 = 0;
            var child_cross_size: u16 = 0;

            // Get child size
            if (is_row) {
                child_main_size = child.cached_size.width;
                child_cross_size = child.cached_size.height;
            } else {
                child_main_size = child.cached_size.height;
                child_cross_size = child.cached_size.width;
            }

            // Calculate cross axis position (alignment)
            const cross_position: u16 = 0;
            const alignment = child.cross_alignment orelse self.cross_alignment;

            // Calculate cross offset based on alignment
            var cross_offset: u16 = 0;
            const cross_free_space = if (cross_axis_size > child_cross_size) cross_axis_size - child_cross_size else 0;

            switch (alignment) {
                .start => cross_offset = 0,
                .center => cross_offset = @intCast(cross_free_space / 2),
                .end => cross_offset = @intCast(cross_free_space),
                .space_between, .space_around, .space_evenly => cross_offset = 0,
            }

            // Calculate child rect
            const child_rect = if (is_row)
                Rect{
                    .x = padded_rect.x + current_position + child.margin_insets.left,
                    .y = padded_rect.y + cross_position + child.margin_insets.top,
                    .width = child_main_size,
                    .height = child_cross_size,
                }
            else
                Rect{
                    .x = padded_rect.x + cross_position + child.margin_insets.left,
                    .y = padded_rect.y + current_position + child.margin_insets.top,
                    .width = child_cross_size,
                    .height = child_main_size,
                };

            // Render child
            child.element.render(renderer, child_rect);

            // Move to next position
            if (is_row) {
                current_position += child_main_size + child.margin_insets.left + child.margin_insets.right;
            } else {
                current_position += child_main_size + child.margin_insets.top + child.margin_insets.bottom;
            }

            if (self.children.items.len > 1) {
                current_position += self.gap_size;
            }
        }
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
        const padded_constraints = Constraints{
            .min_width = if (constraints.min_width > self.padding_insets.left + self.padding_insets.right)
                constraints.min_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .max_width = if (constraints.max_width > self.padding_insets.left + self.padding_insets.right)
                constraints.max_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .min_height = if (constraints.min_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.min_height - self.padding_insets.top - self.padding_insets.bottom
            else
                0,
            .max_height = if (constraints.max_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.max_height - self.padding_insets.top - self.padding_insets.bottom
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
            .width = child_size.width + self.padding_insets.left + self.padding_insets.right,
            .height = child_size.height + self.padding_insets.top + self.padding_insets.bottom,
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

/// Grid layout manager
pub const GridLayout = struct {
    /// Base layout
    base: Layout,
    /// Number of columns
    columns: u16,
    /// Number of rows
    rows: u16,
    /// Cell elements (stored in row-major order)
    cells: std.ArrayList(?LayoutElement),
    /// Padding inside the container
    padding_insets: EdgeInsets,
    /// Gap between cells
    gap_size: u16,

    /// Initialize a new grid layout
    pub fn init(allocator: std.mem.Allocator, columns: u16, rows: u16) !*GridLayout {
        const layout = try allocator.create(GridLayout);

        layout.* = GridLayout{
            .base = Layout.init(allocator),
            .columns = columns,
            .rows = rows,
            .cells = std.ArrayList(?LayoutElement).empty,
            .padding_insets = EdgeInsets.all(0),
            .gap_size = 0,
        };

        // Initialize cells
        try layout.initCells(columns, rows);

        return layout;
    }

    /// Clean up grid layout resources
    pub fn deinit(self: *GridLayout) void {
        self.cells.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    /// Set the padding
    pub fn padding(self: *GridLayout, padding_value: EdgeInsets) *GridLayout {
        self.padding_insets = padding_value;
        return self;
    }

    /// Set the gap between cells
    pub fn gap(self: *GridLayout, gap_value: u16) *GridLayout {
        self.gap_size = gap_value;
        return self;
    }

    /// Add a child element to a specific cell
    pub fn addChild(self: *GridLayout, element: LayoutElement, column: u16, row: u16) !void {
        if (column >= self.columns or row >= self.rows) {
            return error.OutOfBounds;
        }

        const index = @as(usize, row) * @as(usize, self.columns) + @as(usize, column);
        self.cells.items[index] = element;
    }

    /// Calculate the layout for this element
    pub fn layoutFn(ctx: *anyopaque, constraints: Constraints) Size {
        const self = @as(*GridLayout, @ptrCast(@alignCast(ctx)));
        return self.calculateLayout(constraints);
    }

    /// Calculate the layout for this element
    pub fn calculateLayout(self: *GridLayout, constraints: Constraints) Size {
        // Apply padding to constraints
        const padded_constraints = Constraints{
            .min_width = if (constraints.min_width > self.padding_insets.left + self.padding_insets.right)
                constraints.min_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .max_width = if (constraints.max_width > self.padding_insets.left + self.padding_insets.right)
                constraints.max_width - self.padding_insets.left - self.padding_insets.right
            else
                0,
            .min_height = if (constraints.min_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.min_height - self.padding_insets.top - self.padding_insets.bottom
            else
                0,
            .max_height = if (constraints.max_height > self.padding_insets.top + self.padding_insets.bottom)
                constraints.max_height - self.padding_insets.top - self.padding_insets.bottom
            else
                0,
        };

        // Calculate total gap size
        const total_horizontal_gap = if (self.columns > 1) (self.columns - 1) * self.gap_size else 0;
        const total_vertical_gap = if (self.rows > 1) (self.rows - 1) * self.gap_size else 0;

        // Calculate cell dimensions
        const cell_width = if (self.columns > 0 and padded_constraints.max_width > total_horizontal_gap)
            (padded_constraints.max_width - total_horizontal_gap) / self.columns
        else
            0;

        const cell_height = if (self.rows > 0 and padded_constraints.max_height > total_vertical_gap)
            (padded_constraints.max_height - total_vertical_gap) / self.rows
        else
            0;

        // Create cell constraints
        const cell_constraints = Constraints.tight(cell_width, cell_height);

        // Layout each cell
        for (self.cells.items) |cell_opt| {
            if (cell_opt) |cell| {
                _ = cell.layout(cell_constraints);
            }
        }

        // Return final size including padding
        return Size{
            .width = if (padded_constraints.max_width > 0)
                padded_constraints.max_width + self.padding_insets.left + self.padding_insets.right
            else
                0,
            .height = if (padded_constraints.max_height > 0)
                padded_constraints.max_height + self.padding_insets.top + self.padding_insets.bottom
            else
                0,
        };
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

        // Calculate cell dimensions
        const total_horizontal_gap = if (self.columns > 1) (self.columns - 1) * self.gap_size else 0;
        const total_vertical_gap = if (self.rows > 1) (self.rows - 1) * self.gap_size else 0;

        const cell_width = if (self.columns > 0 and padded_rect.width > total_horizontal_gap)
            (padded_rect.width - total_horizontal_gap) / self.columns
        else
            0;

        const cell_height = if (self.rows > 0 and padded_rect.height > total_vertical_gap)
            (padded_rect.height - total_vertical_gap) / self.rows
        else
            0;

        // Render each cell
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < self.columns) : (col += 1) {
                const index = @as(usize, row) * @as(usize, self.columns) + @as(usize, col);
                if (index < self.cells.items.len) {
                    if (self.cells.items[index]) |cell| {
                        const x = padded_rect.x + col * (cell_width + self.gap_size);
                        const y = padded_rect.y + row * (cell_height + self.gap_size);

                        const cell_rect = Rect{
                            .x = x,
                            .y = y,
                            .width = cell_width,
                            .height = cell_height,
                        };

                        cell.render(renderer, cell_rect);
                    }
                }
            }
        }
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
    fn initCells(self: *GridLayout, columns: u16, rows: u16) !void {
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

    /// Initialize a new constraint layout
    pub fn init(allocator: std.mem.Allocator) !*ConstraintLayout {
        const layout = try allocator.create(ConstraintLayout);
        layout.* = ConstraintLayout{
            .base = Layout.init(allocator),
            .children = std.ArrayList(ConstraintChild).empty,
            .padding_insets = EdgeInsets.all(0),
        };
        return layout;
    }

    /// Clean up resources
    pub fn deinit(self: *ConstraintLayout) void {
        self.children.deinit(self.base.allocator);
        self.base.allocator.destroy(self);
    }

    /// Set padding around the content area
    pub fn padding(self: *ConstraintLayout, padding_value: EdgeInsets) *ConstraintLayout {
        self.padding_insets = padding_value;
        return self;
    }

    /// Add a child with positioning constraints
    pub fn addChild(self: *ConstraintLayout, element: LayoutElement, spec: ConstraintSpec) !void {
        try self.children.append(self.base.allocator, ConstraintChild{
            .element = element,
            .spec = spec,
        });
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

        const available_width = if (width > self.padding_insets.left + self.padding_insets.right)
            width - self.padding_insets.left - self.padding_insets.right
        else
            0;
        const available_height = if (height > self.padding_insets.top + self.padding_insets.bottom)
            height - self.padding_insets.top - self.padding_insets.bottom
        else
            0;

        for (self.children.items) |*child| {
            self.layoutChild(child, available_width, available_height);
        }

        return Size.init(width, height);
    }

    /// Render children at their resolved rectangles
    pub fn renderLayout(self: *ConstraintLayout, renderer: *renderer_mod.Renderer, rect: Rect) void {
        const width = rect.width;
        const height = rect.height;

        const available_width = if (width > self.padding_insets.left + self.padding_insets.right)
            width - self.padding_insets.left - self.padding_insets.right
        else
            0;
        const available_height = if (height > self.padding_insets.top + self.padding_insets.bottom)
            height - self.padding_insets.top - self.padding_insets.bottom
        else
            0;

        // Ensure layout data is up to date relative to this rect
        for (self.children.items) |*child| {
            self.layoutChild(child, available_width, available_height);

            const adjusted_rect = Rect{
                .x = rect.x + child.resolved_rect.x,
                .y = rect.y + child.resolved_rect.y,
                .width = child.resolved_rect.width,
                .height = child.resolved_rect.height,
            };
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

    fn layoutChild(self: *ConstraintLayout, child: *ConstraintChild, available_width: u16, available_height: u16) void {
        const spec = child.spec;

        const max_width = spec.max_width orelse available_width;
        const max_height = spec.max_height orelse available_height;

        const range_min_width = if (spec.min_width) |mw| @min(mw, max_width) else 0;
        const range_min_height = if (spec.min_height) |mh| @min(mh, max_height) else 0;

        const target_width = blk: {
            if (spec.width) |fixed| break :blk fixed;
            if (spec.left != null and spec.right != null and available_width > spec.left.? + spec.right.?) {
                break :blk available_width - spec.left.? - spec.right.?;
            }
            break :blk max_width;
        };

        const target_height = blk: {
            if (spec.height) |fixed| break :blk fixed;
            if (spec.top != null and spec.bottom != null and available_height > spec.top.? + spec.bottom.?) {
                break :blk available_height - spec.top.? - spec.bottom.?;
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
                if (available_width > resolved_width) break :blk self.padding_insets.left + (available_width - resolved_width) / 2;
                break :blk self.padding_insets.left;
            }
            if (spec.left) |left_offset| break :blk self.padding_insets.left + left_offset;
            if (spec.right) |right_offset| {
                if (available_width > resolved_width + right_offset) {
                    break :blk self.padding_insets.left + available_width - resolved_width - right_offset;
                }
                break :blk self.padding_insets.left;
            }
            break :blk self.padding_insets.left;
        };

        const y = blk: {
            if (spec.center_y) {
                if (available_height > resolved_height) break :blk self.padding_insets.top + (available_height - resolved_height) / 2;
                break :blk self.padding_insets.top;
            }
            if (spec.top) |top_offset| break :blk self.padding_insets.top + top_offset;
            if (spec.bottom) |bottom_offset| {
                if (available_height > resolved_height + bottom_offset) {
                    break :blk self.padding_insets.top + available_height - resolved_height - bottom_offset;
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
