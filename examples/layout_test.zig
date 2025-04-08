const std = @import("std");
const zit = @import("zit");
const memory = zit.memory;

pub fn main() !void {
    // Initialize memory manager
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var memory_manager = try memory.MemoryManager.init(allocator, 1024 * 1024, 100);
    defer memory_manager.deinit();

    // Initialize terminal with memory manager
    var term = try zit.terminal.init(memory_manager.getArenaAllocator());
    defer term.deinit() catch {};

    // Get terminal size
    const width = term.width;
    const height = term.height;

    // Initialize renderer with memory manager
    var renderer = try zit.render.Renderer.init(memory_manager.getArenaAllocator(), width, height);
    defer renderer.deinit();

    // Enable raw mode
    try term.enableRawMode();
    defer term.disableRawMode() catch {};

    // Initialize input handler with memory manager
    var input_handler = zit.input.InputHandler.init(memory_manager.getArenaAllocator(), &term);

    // Clear screen
    try term.clear();

    // Create layout example
    var layout_example = try createLayoutExample(memory_manager.getWidgetPoolAllocator());
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
        if (height > 2) {
            const instruction_y = if (height > 2) height - 2 else 0;
            renderer.drawStr(2, instruction_y, "Press 'q' to quit", 
                zit.render.Color.named(zit.render.NamedColor.bright_white), 
                zit.render.Color.named(zit.render.NamedColor.default), 
                zit.render.Style{});
        }

        // Layout and render the example
        const layout_height = if (height > 3) height - 3 else 0;
        const layout_rect = zit.layout.Rect.init(0, 1, layout_height/3, width/2);
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
    // Grid layouts
    grid_layouts: std.ArrayList(*zit.layout.GridLayout),

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
        .grid_layouts = std.ArrayList(*zit.layout.GridLayout).init(allocator),
    };
    
    // Create a main flex layout (vertical)
    example.flex_layout = try zit.layout.FlexLayout.init(allocator, .column);
    try example.flex_layouts.append(example.flex_layout);
    _ = example.flex_layout.padding(zit.layout.EdgeInsets.all(1));

    // Create a grid layout
    example.grid_layout = try zit.layout.GridLayout.init(allocator, 2, 2);
    _ = example.grid_layout.padding(zit.layout.EdgeInsets.all(1));
    try example.grid_layouts.append(example.grid_layout);

    // Create nested layouts
    example.nested_layout = try zit.layout.FlexLayout.init(allocator, .row);
    try example.flex_layouts.append(example.nested_layout);
    _ = example.nested_layout.padding(zit.layout.EdgeInsets.all(1));

    // Create text elements
    const title = try TextElement.init(allocator, "Layout Test", 
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Style.init(true, false, false));
    try example.text_elements.append(title);

    const subtitle = try TextElement.init(allocator, "Nested Layouts", 
        zit.render.Color.named(zit.render.NamedColor.white),
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Style{});
    try example.text_elements.append(subtitle);

    // Create box elements
    const box1 = try BoxElement.init(allocator, 
        zit.render.BorderStyle.single,
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.blue),
        zit.render.Style{},
        ' ');
    try example.box_elements.append(box1);

    const box2 = try BoxElement.init(allocator, 
        zit.render.BorderStyle.double,
        zit.render.Color.named(zit.render.NamedColor.bright_white),
        zit.render.Color.named(zit.render.NamedColor.green),
        zit.render.Style{},
        ' ');
    try example.box_elements.append(box2);

    // Create sized boxes
    const sized_box1 = try zit.layout.SizedBox.init(allocator, box1.asElement(), 10, 5);
    try example.sized_boxes.append(sized_box1);

    const sized_box2 = try zit.layout.SizedBox.init(allocator, box2.asElement(), 15, 3);
    try example.sized_boxes.append(sized_box2);

    // Create paddings
    const padding1 = try zit.layout.Padding.init(allocator, box1.asElement(), zit.layout.EdgeInsets.all(2));
    try example.paddings.append(padding1);

    const padding2 = try zit.layout.Padding.init(allocator, box2.asElement(), zit.layout.EdgeInsets.symmetric(1, 3));
    try example.paddings.append(padding2);

    // Create centers
    const center1 = try zit.layout.Center.init(allocator, example.flex_layout.asElement(), true, true);
    try example.centers.append(center1);

    const center2 = try zit.layout.Center.init(allocator, example.grid_layout.asElement(), true, true);
    try example.centers.append(center2);

    // Build the layout hierarchy
    try example.flex_layout.addChild(zit.layout.FlexChild.init(title.asElement(), 0));
    try example.flex_layout.addChild(zit.layout.FlexChild.init(example.grid_layout.asElement(), 1));
    try example.flex_layout.addChild(zit.layout.FlexChild.init(subtitle.asElement(), 0));
    try example.flex_layout.addChild(zit.layout.FlexChild.init(example.nested_layout.asElement(), 1));

    try example.grid_layout.addChild(box1.asElement(), 0, 0);
    try example.grid_layout.addChild(box2.asElement(), 1, 1);

    try example.nested_layout.addChild(zit.layout.FlexChild.init(sized_box1.asElement(), 1));
    try example.nested_layout.addChild(zit.layout.FlexChild.init(padding1.asElement(), 0));
    try example.nested_layout.addChild(zit.layout.FlexChild.init(sized_box2.asElement(), 1));
    try example.nested_layout.addChild(zit.layout.FlexChild.init(padding2.asElement(), 0));

    // Set the root element to be the flex layout
    example.element = example.flex_layout.asElement();

    return example;
}

// Destroy the layout example
fn destroyLayoutExample(example: *LayoutExample) void {
    // First deinitialize the ArrayLists that don't own their elements
    example.flex_layouts.deinit();
    example.grid_layouts.deinit();

    // Destroy all elements that we own directly
    for (example.text_elements.items) |element| {
        element.deinit();
    }
    example.text_elements.deinit();

    for (example.box_elements.items) |element| {
        element.deinit();
    }
    example.box_elements.deinit();

    for (example.sized_boxes.items) |element| {
        element.deinit();
    }
    example.sized_boxes.deinit();

    for (example.paddings.items) |element| {
        element.deinit();
    }
    example.paddings.deinit();

    for (example.centers.items) |element| {
        element.deinit();
    }
    example.centers.deinit();

    // Finally deinitialize the layouts themselves
    example.flex_layout.deinit();
    example.grid_layout.deinit();
    example.nested_layout.deinit();

    example.allocator.destroy(example);
}