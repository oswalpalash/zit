# Widget Catalog

A quick index of the public Zit widget API with roles, related examples, and enforced coverage references. Use this alongside `docs/WIDGET_GUIDE.md` for implementation details.

## Core Controls
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| Label | Read-only text with alignment and style helpers. | `examples/hello_world.zig` | `src/testing/golden/label_basic.snap` |
| Button | Focusable action control with border and pressed state styling. | `examples/widget_examples/button_example.zig` | `src/testing/golden/button_basic.snap` |
| Checkbox | Toggleable boolean control with label text. | `examples/realworld/widget_gallery.zig` | `src/testing/golden/checkbox_checked.snap` |
| InputField | Single-line editable input with placeholder and cursor handling. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| AutocompleteInput | Editable input with filtered suggestions. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| TextArea | Multi-line editor with cursor and viewport state. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| ToggleSwitch | Compact on/off switch control. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| RadioGroup | Mutually exclusive option selector. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| Slider | Numeric range selector with a visual track. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| ColorPicker | Terminal color selection control. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| RatingStars | Compact rating selector and display. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| ProgressBar | Horizontal or vertical progress display. | `examples/realworld/widget_gallery.zig` | `src/testing/golden/progress_bar_50.snap` |

## Layout and Containers
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| Container | Basic parent container with optional border and fill. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| FlexContainer | Flexbox-style row or column layout. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| GridContainer | Grid layout with explicit rows and columns. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| ScrollContainer | Scrollable viewport with child clipping. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| Scrollbar | Standalone scroll position indicator. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| SplitPane | Two-pane layout with horizontal or vertical split orientation. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| Block | Styled rectangular region for grouped content. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| Paragraph | Wrapped text block for longer copy. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |

## Navigation and Structure
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| TabView | Tabbed content region with tab selection. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| TabBar | Standalone tab navigation strip. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| MenuBar | Top-level menus with dropdown items. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| Breadcrumbs | Path navigation with segment styling. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| Pagination | Paged navigation for data sets. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| ScreenManager | Stack of screens with lifecycle and transition hooks. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| StatusBar | Low-height status line for app state. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| Toolbar | Horizontal command strip. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| Accordion | Expandable section list. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| WizardStepper | Multi-step workflow progress and navigation. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| CommandPalette | Searchable command picker. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |

## Overlays and Menus
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| Modal | Dialog container with title, body, and border. | `examples/realworld/widget_gallery.zig` | `src/testing/golden/modal_basic.snap` |
| Popup | Inline popup message box. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| ToastManager | Timed notification stack. | `examples/widget_examples/notifications_example.zig` | `examples/widget_examples/notifications_example.zig` |
| NotificationCenter | Aggregated notification list. | `examples/realworld/dashboard_demo.zig` | `examples/realworld/dashboard_demo.zig` |
| DropdownMenu | Selectable option list. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| ContextMenu | Contextual menu list. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |

## Data Visualization and Indicators
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| Table | Column and row data view. | `examples/widget_examples/table_example.zig` | `src/testing/golden/table_basic.snap` |
| List | Scrollable list with selection and highlight state. | `examples/realworld/widget_gallery.zig` | `src/testing/golden/list_items.snap` |
| TreeView | Hierarchical list with expand and collapse state. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| Chart | Bars, lines, pie charts, and scatter plots. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| Sparkline | Inline trendline for compact metrics. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| Gauge | Meter display with directional fill. | `examples/realworld/widget_gallery.zig` | `examples/realworld/widget_gallery.zig` |
| BatteryIndicator | Battery level and charging state indicator. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| SignalStrength | Signal quality indicator. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| ResourceMeter | Resource usage meter for CPU, memory, or similar values. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| TrafficLight | Three-state status indicator. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |

## Content and Media
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| Markdown | Render headings, lists, and paragraphs. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| RichText | Inline spans with mixed styles. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| SyntaxHighlighter | Tokenized code block rendering. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| ImageWidget | Block or braille rendering for pixel data. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |
| Canvas | Immediate-mode drawing surface. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |
| LogView | Scrollable log entries with level styling. | `examples/realworld/widget_gallery_extended.zig` | `examples/realworld/widget_gallery_extended.zig` |

## Files and Utilities
| Widget | Use | Example | Coverage Reference |
| --- | --- | --- | --- |
| FileBrowser | Directory tree with file previews. | `examples/widget_examples/file_browser_example.zig` | `examples/widget_examples/file_browser_example.zig` |
| DateTimePicker | Date and time selection. | `examples/realworld/widget_gallery_layouts.zig` | `examples/realworld/widget_gallery_layouts.zig` |

## Notes
- Golden snapshots live under `src/testing/golden/`; broader visual coverage references point to deterministic examples exercised by `zig build release-check`.
- `scripts/check_widget_coverage.py` validates every public widget export, every catalog row, and every backticked catalog file path.
- `examples/realworld/file_manager.zig` and `examples/widget_examples/file_manager_example.zig` are full applications built from public widgets, not separate public widget exports.
- For a one-stop tour of the catalog, run `zig build widget-showcase` from a real terminal.
