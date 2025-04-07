const std = @import("std");
const zit = @import("zit");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = try zit.terminal.init(allocator);
    defer term.deinit() catch {};

    // Get terminal size
    const width = term.width;
    const height = term.height;

    // Initialize renderer
    var renderer = try zit.render.Renderer.init(allocator, width, height);
    defer renderer.deinit();

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    // Initialize input handler
    var input_handler = zit.input.InputHandler.init(allocator, &term);

    // Clear screen
    try term.clear();

    // Create layout example
    var layout_example = try createLayoutExample(allocator);
    defer destroyLayoutExample(layout_example);

    // Main event loop
    while (true) {
        // Clear the buffer
        renderer.back.clear();
        
        // Draw title
        const title = "Zit Layout Test";
        // Safely calculate centered position
        const title_len = @as(u16, @intCast(title.len));
        const title_x = if (width > title_len) 
            (width - title_len) / 2
        else 
            0;
        
        renderer.drawStr(title_x, 0, title, zit.render.Color.named(zit.render.NamedColor.bright_white), zit.render.Color.named(zit.render.NamedColor.blue), zit.render.Style.init(true, false, false));
        
        // Draw instructions
        renderer.drawStr(2, height - 2, "Press 'q' to quit", 
            zit.render.Color.named(zit.render.NamedColor.bright_white), 
            zit.render.Color.named(zit.render.NamedColor.default), 
            zit.render.Style{});

        // Layout and render the example
        const layout_rect = zit.layout.Rect.init(0, 1, width, height - 3);
        layout_example.render(&renderer, layout_rect);
        
        // Render to screen
        try renderer.render();
        
        // Poll for events with a 100ms timeout
        const event = try input_handler.pollEvent(100);
        
        if (event) |e| {
            switch (e) {
                .key => |key| {
                    // Exit on 'q' key
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        break;
                    }
                },
                .resize => |resize| {
                    // Resize renderer
                    try renderer.resize(resize.width, resize.height);
                },
                else => {},
            }
        }
    }
    
    // Clean up
    try term.clear();
    try term.moveCursor(0, 0);
}

// Layout example structure
const LayoutExample = struct {
    element: zit.layout.LayoutElement,
    allocator: std.mem.Allocator,
    
    // Flex layout
    flex_layout: *zit.layout.FlexLayout,
    // Grid layout
    grid_layout: *zit.layout.GridLayout,
    // Nested layouts
    nested_layout: *zit.layout.FlexLayout,
    // Text elements
    text_elements: std.ArrayList(*TextElement),
    // Box elements
    box_elements: std.ArrayList(*BoxElement),
    // Sized boxes
    sized_boxes: std.ArrayList(*zit.layout.SizedBox),
    // Paddings
    paddings: std.ArrayList(*zit.layout.Padding),
    // Centers
    centers: std.ArrayList(*zit.layout.Center),
    // Flex layouts
    flex_layouts: std.ArrayList(*zit.layout.FlexLayout),

    pub fn render(self: *LayoutExample, renderer: *zit.render.Renderer, rect: zit.layout.Rect) void {
        // Layout and render the element
        _ = self.flex_layout.asElement().layout(zit.layout.Constraints.tight(rect.width, rect.height));
        self.flex_layout.asElement().render(renderer, rect);
    }
};

// Simple text element
const TextElement = struct {
    text: []const u8,
    fg_color: zit.render.Color,
    bg_color: zit.render.Color,
    style: zit.render.Style,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, text: []const u8, fg: zit.render.Color, bg: zit.render.Color, style: zit.render.Style) !*TextElement {
        const element = try allocator.create(TextElement);
        element.* = TextElement{
            .text = text,
            .fg_color = fg,
            .bg_color = bg,
            .style = style,
            .allocator = allocator,
        };
        return element;
    }
    
    pub fn deinit(self: *TextElement) void {
        self.allocator.destroy(self);
    }
    
    pub fn layoutFn(ctx: *anyopaque, constraints: zit.layout.Constraints) zit.layout.Size {
        const self = @as(*TextElement, @ptrCast(@alignCast(ctx)));
        
        // Simple layout: just use the text length and a height of 1
        const width = @min(@as(u16, @intCast(self.text.len)), constraints.max_width);
        const height: u16 = 1;
        
        return zit.layout.Size.init(width, height);
    }
    
    pub fn renderFn(ctx: *anyopaque, renderer: *zit.render.Renderer, rect: zit.layout.Rect) void {
        const self = @as(*TextElement, @ptrCast(@alignCast(ctx)));
        
        // Render the text
        renderer.drawStr(rect.x, rect.y, self.text, self.fg_color, self.bg_color, self.style);
    }
    
    pub fn asElement(self: *TextElement) zit.layout.LayoutElement {
        return zit.layout.LayoutElement{
            .layoutFn = TextElement.layoutFn,
            .renderFn = TextElement.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

// Simple box element
const BoxElement = struct {
    border_style: zit.render.BorderStyle,
    fg_color: zit.render.Color,
    bg_color: zit.render.Color,
    style: zit.render.Style,
    fill_char: u21,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, border: zit.render.BorderStyle, fg: zit.render.Color, bg: zit.render.Color, style: zit.render.Style, fill: u21) !*BoxElement {
        const element = try allocator.create(BoxElement);
        element.* = BoxElement{
            .border_style = border,
            .fg_color = fg,
            .bg_color = bg,
            .style = style,
            .fill_char = fill,
            .allocator = allocator,
        };
        return element;
    }
    
    pub fn deinit(self: *BoxElement) void {
        self.allocator.destroy(self);
    }
    
    pub fn layoutFn(ctx: *anyopaque, constraints: zit.layout.Constraints) zit.layout.Size {
        _ = ctx;
        
        // Use minimum constraints, but ensure at least 3x3
        const width = @max(constraints.min_width, 3);
        const height = @max(constraints.min_height, 3);
        
        return zit.layout.Size.init(width, height);
    }
    
    pub fn renderFn(ctx: *anyopaque, renderer: *zit.render.Renderer, rect: zit.layout.Rect) void {
        const self = @as(*BoxElement, @ptrCast(@alignCast(ctx)));
        
        // Draw the box
        renderer.drawBox(rect.x, rect.y, rect.width, rect.height, 
            self.border_style, self.fg_color, self.bg_color, self.style);
        
        // Fill the inside if needed
        if (self.fill_char != ' ' and rect.width > 2 and rect.height > 2) {
            renderer.fillRect(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2, 
                self.fill_char, self.fg_color, self.bg_color, self.style);
        }
    }
    
    pub fn asElement(self: *BoxElement) zit.layout.LayoutElement {
        return zit.layout.LayoutElement{
            .layoutFn = BoxElement.layoutFn,
            .renderFn = BoxElement.renderFn,
            .ctx = @ptrCast(@alignCast(self)),
        };
    }
};

// Create the layout example
fn createLayoutExample(allocator: std.mem.Allocator) !*LayoutExample {
    const example = try allocator.create(LayoutExample);
    example.* = LayoutExample{
        .element = undefined,
        .allocator = allocator,
        .flex_layout = undefined,
        .grid_layout = undefined,
        .nested_layout = undefined,
        .text_elements = std.ArrayList(*TextElement).init(allocator),
        .box_elements = std.ArrayList(*BoxElement).init(allocator),
        .sized_boxes = std.ArrayList(*zit.layout.SizedBox).init(allocator),
        .paddings = std.ArrayList(*zit.layout.Padding).init(allocator),
        .centers = std.ArrayList(*zit.layout.Center).init(allocator),
        .flex_layouts = std.ArrayList(*zit.layout.FlexLayout).init(allocator),
    };
    
    // Create a main flex layout (vertical)
    example.flex_layout = try zit.layout.FlexLayout.init(allocator, .column);
    try example.flex_layouts.append(example.flex_layout);
    _ = example.flex_layout.padding(zit.layout.EdgeInsets.all(1))
                       .gap(1);
    _ = example.flex_layout.mainAlignment(.center);
    _ = example.flex_layout.crossAlignment(.center);
    
    // Create text elements for headers
    const header1 = try TextElement.init(allocator, "Flex Layout Example (Row)", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style.init(true, false, false));
    try example.text_elements.append(header1);
    
    const header2 = try TextElement.init(allocator, "Grid Layout Example (2x2)", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style.init(true, false, false));
    try example.text_elements.append(header2);
    
    const header3 = try TextElement.init(allocator, "Nested Layout Example", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style.init(true, false, false));
    try example.text_elements.append(header3);
    
    // Create a row flex layout for the first example
    const row_flex = try zit.layout.FlexLayout.init(allocator, .row);
    try example.flex_layouts.append(row_flex);
    _ = row_flex.padding(zit.layout.EdgeInsets.all(1))
           .gap(2)
           .mainAlignment(.space_between)
           .crossAlignment(.center);
    
    // Create box elements for the row flex
    const box1 = try BoxElement.init(allocator, .single, 
        zit.render.Color.named(zit.render.NamedColor.red),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, ' ');
    try example.box_elements.append(box1);
    
    const box2 = try BoxElement.init(allocator, .double, 
        zit.render.Color.named(zit.render.NamedColor.green),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, ' ');
    try example.box_elements.append(box2);
    
    const box3 = try BoxElement.init(allocator, .rounded, 
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, ' ');
    try example.box_elements.append(box3);
    
    // Add boxes to row flex
    const sized_box1 = try zit.layout.SizedBox.init(allocator, box1.asElement(), 10, 5);
    try example.sized_boxes.append(sized_box1);
    const sized_box2 = try zit.layout.SizedBox.init(allocator, box2.asElement(), 10, 5);
    try example.sized_boxes.append(sized_box2);
    const sized_box3 = try zit.layout.SizedBox.init(allocator, box3.asElement(), 10, 5);
    try example.sized_boxes.append(sized_box3);
    
    try row_flex.addChild(zit.layout.FlexChild.init(sized_box1.asElement(), 0));
    try row_flex.addChild(zit.layout.FlexChild.init(sized_box2.asElement(), 0));
    try row_flex.addChild(zit.layout.FlexChild.init(sized_box3.asElement(), 0));
    
    // Create a grid layout for the second example
    example.grid_layout = try zit.layout.GridLayout.init(allocator, 2, 2);
    _ = example.grid_layout.padding(zit.layout.EdgeInsets.all(1))
                       .gap(1);
    
    // Create box elements for the grid
    const grid_box1 = try BoxElement.init(allocator, .single, 
        zit.render.Color.named(zit.render.NamedColor.yellow),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, '░');
    try example.box_elements.append(grid_box1);
    
    const grid_box2 = try BoxElement.init(allocator, .double, 
        zit.render.Color.named(zit.render.NamedColor.magenta),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, '▒');
    try example.box_elements.append(grid_box2);
    
    const grid_box3 = try BoxElement.init(allocator, .rounded, 
        zit.render.Color.named(zit.render.NamedColor.cyan),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, '▓');
    try example.box_elements.append(grid_box3);
    
    const grid_box4 = try BoxElement.init(allocator, .thick, 
        zit.render.Color.named(zit.render.NamedColor.white),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, '█');
    try example.box_elements.append(grid_box4);
    
    // Add boxes to grid
    try example.grid_layout.addChild(grid_box1.asElement(), 0, 0);
    try example.grid_layout.addChild(grid_box2.asElement(), 1, 0);
    try example.grid_layout.addChild(grid_box3.asElement(), 0, 1);
    try example.grid_layout.addChild(grid_box4.asElement(), 1, 1);
    
    // Create a nested layout for the third example
    example.nested_layout = try zit.layout.FlexLayout.init(allocator, .row);
    try example.flex_layouts.append(example.nested_layout);
    _ = example.nested_layout.padding(zit.layout.EdgeInsets.all(1))
                         .gap(1)
                         .mainAlignment(.center)
                         .crossAlignment(.center);
    
    // Create a nested column layout
    const nested_column = try zit.layout.FlexLayout.init(allocator, .column);
    try example.flex_layouts.append(nested_column);
    _ = nested_column.padding(zit.layout.EdgeInsets.all(0))
                .gap(1)
                .mainAlignment(.center)
                .crossAlignment(.center);
    
    // Create text elements for the nested layout
    const text1 = try TextElement.init(allocator, "Top", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.red),
        zit.render.Style{});
    try example.text_elements.append(text1);
    
    const text2 = try TextElement.init(allocator, "Middle", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.green),
        zit.render.Style{});
    try example.text_elements.append(text2);
    
    const text3 = try TextElement.init(allocator, "Bottom", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Style{});
    try example.text_elements.append(text3);
    
    // Create padding elements for the text
    const padded_text1 = try zit.layout.Padding.init(allocator, text1.asElement(), 
        zit.layout.EdgeInsets.all(1));
    try example.paddings.append(padded_text1);
    const padded_text2 = try zit.layout.Padding.init(allocator, text2.asElement(), 
        zit.layout.EdgeInsets.all(1));
    try example.paddings.append(padded_text2);
    const padded_text3 = try zit.layout.Padding.init(allocator, text3.asElement(), 
        zit.layout.EdgeInsets.all(1));
    try example.paddings.append(padded_text3);
    
    // Add text to nested column
    try nested_column.addChild(zit.layout.FlexChild.init(padded_text1.asElement(), 0));
    try nested_column.addChild(zit.layout.FlexChild.init(padded_text2.asElement(), 0));
    try nested_column.addChild(zit.layout.FlexChild.init(padded_text3.asElement(), 0));
    
    // Create a box for the right side
    const nested_box = try BoxElement.init(allocator, .double, 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.default),
        zit.render.Style{}, ' ');
    try example.box_elements.append(nested_box);
    
    // Create a centered text element for the box
    const centered_text = try TextElement.init(allocator, "Centered", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Style.init(true, false, false));
    try example.text_elements.append(centered_text);
    
    // Create a center element
    const center_element = try zit.layout.Center.init(allocator, centered_text.asElement(), true, true);
    try example.centers.append(center_element);
    
    // Create a sized box for the nested box
    const nested_sized_box = try zit.layout.SizedBox.init(allocator, nested_box.asElement(), 20, 10);
    try example.sized_boxes.append(nested_sized_box);
    
    // Create a padding element for the center element
    const padded_center = try zit.layout.Padding.init(allocator, center_element.asElement(), 
        zit.layout.EdgeInsets.all(1));
    try example.paddings.append(padded_center);
    
    // Create a container for the centered text
    const center_container = try zit.layout.FlexLayout.init(allocator, .column);
    try example.flex_layouts.append(center_container);
    try center_container.addChild(zit.layout.FlexChild.init(nested_sized_box.asElement(), 0));
    try center_container.addChild(zit.layout.FlexChild.init(padded_center.asElement(), 0));
    
    // Add elements to nested layout
    try example.nested_layout.addChild(zit.layout.FlexChild.init(nested_column.asElement(), 1));
    try example.nested_layout.addChild(zit.layout.FlexChild.init(center_container.asElement(), 2));
    
    // Add all sections to main layout
    try example.flex_layout.addChild(zit.layout.FlexChild.init(row_flex.asElement(), 0));
    try example.flex_layout.addChild(zit.layout.FlexChild.init(example.grid_layout.asElement(), 1));
    try example.flex_layout.addChild(zit.layout.FlexChild.init(example.nested_layout.asElement(), 2));
    
    return example;
}

fn destroyLayoutExample(layout_example: *LayoutExample) void {
    // Clean up in reverse order of creation
    
    // Free all size boxes
    for (layout_example.sized_boxes.items) |sized_box| {
        sized_box.deinit();
    }
    layout_example.sized_boxes.deinit();
    
    // Free all padding elements
    for (layout_example.paddings.items) |padding| {
        padding.deinit();
    }
    layout_example.paddings.deinit();
    
    // Free all center elements
    for (layout_example.centers.items) |center| {
        center.deinit();
    }
    layout_example.centers.deinit();
    
    // Free all flex layouts
    for (layout_example.flex_layouts.items) |flex_layout| {
        // Don't free the main layouts again as they're included in the list
        if (flex_layout != layout_example.flex_layout and 
            flex_layout != layout_example.nested_layout) {
            flex_layout.deinit();
        }
    }
    layout_example.flex_layouts.deinit();
    
    // Free main layouts
    layout_example.grid_layout.deinit();
    layout_example.nested_layout.deinit();
    layout_example.flex_layout.deinit();
    
    // Free box elements
    for (layout_example.box_elements.items) |box_element| {
        box_element.deinit();
    }
    layout_example.box_elements.deinit();
    
    // Free text elements
    for (layout_example.text_elements.items) |text_element| {
        text_element.deinit();
    }
    layout_example.text_elements.deinit();
    
    // Free the example itself
    layout_example.allocator.destroy(layout_example);
}