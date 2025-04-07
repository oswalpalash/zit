# Zit - A Text User Interface Library for Zig

Zit is a TUI (Text User Interface) library for Zig that enables developers to create interactive terminal applications. The library provides tools for terminal manipulation, input handling, rendering, layout management, and widget creation.

## Features

- **Terminal handling**: Cross-platform terminal operations with raw mode support
- **Text rendering**: Support for colors (named colors), styles (bold, italic, underline), and basic text drawing
- **Layout system**: Basic layout management with Rect-based positioning
- **Widget library**: Core UI components including:
  - Labels
  - Buttons
  - Checkboxes
  - Progress bars
  - Lists
- **Input handling**: Keyboard and mouse event processing
- **Event system**: Basic event handling for widgets

## Installation

Add Zit to your project:

```bash
# Clone the repository
git clone https://github.com/oswalpalash/zit.git

# Add as a dependency in your build.zig
```

In your `build.zig`:

```zig
const zit_dep = b.dependency("zit", .{
    .target = target,
    .optimize = optimize,
});

const zit_module = zit_dep.module("zit");
exe.addModule("zit", zit_module);
```

## Quick Start

Here's a simple example to get you started:

```zig
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
    try input_handler.enableMouse();

    // Create a label
    var label = try zit.widget.Label.init(allocator, "Hello, Zit!");
    defer label.deinit();
    label.setAlignment(.center);
    label.setColor(
        zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
        zit.render.Color{ .named_color = zit.render.NamedColor.blue }
    );

    // Main event loop
    var running = true;
    while (running) {
        // Clear the buffer
        renderer.back.clear();
        
        // Draw the label
        const label_rect = zit.layout.Rect.init(
            if (width > 20) (width - 20) / 2 else 0,
            if (height > 1) height / 2 else 0,
            20,
            1
        );
        try label.widget.layout(label_rect);
        try label.widget.draw(&renderer);
        
        // Render to screen
        try renderer.render();
        
        // Poll for events with a 100ms timeout
        const event = try input_handler.pollEvent(100);
        
        if (event) |e| {
            switch (e) {
                .key => |key| {
                    // Exit on 'q' key
                    if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                        running = false;
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
```

## Core Components

### Terminal Handling

The terminal module provides basic terminal operations:

```zig
// Initialize terminal
var term = try zit.terminal.init(allocator);

// Enable raw mode for direct input
try term.enableRawMode();

// Get terminal dimensions
const width = term.width;
const height = term.height;

// Move cursor and clear screen
try term.moveCursor(x, y);
try term.clear();
```

### Input Handling

The input module processes keyboard and mouse events:

```zig
// Initialize input handler
var input_handler = zit.input.InputHandler.init(allocator, &term);
try input_handler.enableMouse();

// Poll for events with timeout
const event = try input_handler.pollEvent(100);

// Handle different event types
if (event) |e| {
    switch (e) {
        .key => |key| {
            // Handle key press
            if (key.key == 'q' and !key.modifiers.ctrl and !key.modifiers.alt) {
                // Exit on 'q'
            }
        },
        .mouse => |mouse| {
            // Handle mouse event
        },
        .resize => |resize| {
            // Handle terminal resize
        },
        else => {},
    }
}
```

### Rendering

The render module manages screen drawing:

```zig
// Initialize renderer
var renderer = try zit.render.Renderer.init(allocator, width, height);

// Clear the back buffer
renderer.back.clear();

// Draw text with color and style
renderer.drawStr(
    x, y, "Hello, World!",
    zit.render.Color{ .named_color = zit.render.NamedColor.bright_white },
    zit.render.Color{ .named_color = zit.render.NamedColor.blue },
    zit.render.Style.init(true, false, false) // bold
);

// Draw a box
renderer.drawBox(
    x, y, width, height,
    zit.render.BorderStyle.single,
    zit.render.Color{ .named_color = zit.render.NamedColor.white },
    zit.render.Color{ .named_color = zit.render.NamedColor.default },
    zit.render.Style{}
);

// Render to screen
try renderer.render();
```

### Widgets

The widget module provides basic UI components:

```zig
// Create a label
var label = try zit.widget.Label.init(allocator, "Hello, Zit!");
label.setAlignment(.center);
label.setColor(fg_color, bg_color);

// Create a button
var button = try zit.widget.Button.init(allocator, "Click Me!");
button.setColors(normal_fg, normal_bg, hover_fg, hover_bg);
button.setBorder(.rounded);
button.setOnPress(onButtonPress);

// Create a checkbox
var checkbox = try zit.widget.Checkbox.init(allocator, "Enable Feature");
checkbox.setColors(normal_fg, normal_bg, checked_fg, checked_bg);
checkbox.setOnChange(onCheckboxChange);

// Create a progress bar
var progress_bar = try zit.widget.ProgressBar.init(allocator);
progress_bar.setValue(30);
progress_bar.setShowPercentage(true);
progress_bar.setColors(fg, bg, empty_fg, empty_bg);
progress_bar.setBorder(.single);

// Create a list
var list = try zit.widget.List.init(allocator);
try list.addItem("Option 1");
try list.addItem("Option 2");
list.setSelectedIndex(0);
list.setOnSelect(onListSelect);
list.setColors(normal_fg, normal_bg, selected_fg, selected_bg);
list.setBorder(.single);
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
