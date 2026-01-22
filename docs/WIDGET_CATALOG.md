# Widget Catalog

A quick index of Zit widgets with their roles, related examples, and snapshot references. Use this alongside `docs/WIDGET_GUIDE.md` for implementation details.

## Core Controls
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| Label | Read-only text with alignment and style helpers. | `examples/hello_world.zig` | `src/testing/golden/label_basic.snap` |
| Button | Clickable control with focus styling and borders. | `examples/widget_examples/button_example.zig` | `src/testing/golden/button_basic.snap` |
| Checkbox | Toggleable boolean control with label. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/checkbox_basic.snap` |
| InputField | Single-line editable input with placeholder/cursor. | `examples/widget_examples/form_wizard_example.zig` | `src/testing/golden/input_field_basic.snap` |
| TextArea | Multi-line editor with cursor and selection helpers. | `examples/widget_examples/form_wizard_example.zig` | `src/testing/golden/text_area_basic.snap` |
| ProgressBar | Horizontal/vertical progress display. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/progress_bar_basic.snap` |
| List | Scrollable list with selection/highlight. | `examples/demo.zig` | `src/testing/golden/list_basic.snap` |
| Table | Column/row data view with sorting and editing. | `examples/widget_examples/table_example.zig` | `src/testing/golden/table_basic.snap` |
| TreeView | Hierarchical list with expand/collapse. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/tree_view_basic.snap` |

## Layout and Containers
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| Container | Basic parent container with optional border/fill. | `examples/demo.zig` | `src/testing/golden/container_basic.snap` |
| FlexContainer | Flexbox-style row/column layout. | `examples/layout_test.zig` | `src/testing/golden/flex_layout.snap` |
| GridContainer | Grid layout with explicit rows/columns. | `examples/layout_test.zig` | `src/testing/golden/grid_layout.snap` |
| ScrollContainer | Scrollable viewport with optional scrollbars. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/scroll_container_basic.snap` |
| SplitPane | Resizable two-pane layout (vertical or horizontal). | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/split_pane_basic.snap` |

## Navigation and Structure
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| TabView | Tabbed navigation with tab bar. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/tab_view_basic.snap` |
| MenuBar | Top-level menus with dropdown items. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/menu_bar_basic.snap` |
| Breadcrumbs | Path navigation with segment styling. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/breadcrumbs_basic.snap` |
| Pagination | Paged navigation for data sets. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/pagination_basic.snap` |
| ScreenManager | Stack of screens with transitions. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/screen_manager_basic.snap` |

## Overlays and Menus
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| Modal | Dialog container with title/body. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/modal_basic.snap` |
| Popup | Inline popup message box. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/popup_basic.snap` |
| ToastManager | Timed notifications stack. | `examples/widget_examples/notifications_example.zig` | `src/testing/golden/toast_basic.snap` |
| DropdownMenu | Selectable option list. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/dropdown_basic.snap` |
| ContextMenu | Right-click menu list. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/context_menu_basic.snap` |

## Data Visualization
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| Chart | Bars/lines/pie/scatter plots. | `examples/widget_examples/system_monitor_example.zig` | `src/testing/golden/chart_basic.snap` |
| Sparkline | Tiny trendline for inline metrics. | `examples/widget_examples/system_monitor_example.zig` | `src/testing/golden/sparkline_basic.snap` |
| Gauge | Meter display with colored fill. | `examples/widget_examples/system_monitor_example.zig` | `src/testing/golden/gauge_basic.snap` |
| Indicators | Battery/signal/resource status widgets. | `examples/widget_examples/system_monitor_example.zig` | `src/testing/golden/indicators_basic.snap` |

## Content and Media
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| Markdown | Render headings, lists, and paragraphs. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/markdown_basic.snap` |
| RichText | Inline spans with mixed styles. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/rich_text_basic.snap` |
| SyntaxHighlighter | Tokenized code blocks. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/syntax_basic.snap` |
| ImageWidget | Block/braille rendering for pixel data. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/image_basic.snap` |
| Canvas | Immediate-mode drawing surface. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/canvas_basic.snap` |

## Utilities
| Widget | Use | Example | Snapshot |
| --- | --- | --- | --- |
| FileBrowser | Directory tree with file previews. | `examples/widget_examples/file_browser_example.zig` | `src/testing/golden/file_browser_basic.snap` |
| FileManager | Multi-pane file manager. | `examples/widget_examples/file_manager_example.zig` | `src/testing/golden/file_manager_basic.snap` |
| DateTimePicker | Date/time selection. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/date_time_picker_basic.snap` |
| LogView | Scrollable log entries with level coloring. | `examples/widget_examples/showcase_demo.zig` | `src/testing/golden/log_view_basic.snap` |
| Form widgets | WizardStepper, Accordion, CommandPalette, NotificationCenter. | `examples/widget_examples/form_wizard_example.zig` | `src/testing/golden/form_widgets_basic.snap` |

## Notes
- Snapshots live under `src/testing/golden/` and are exercised by widget unit tests.
- Layout examples under `examples/layout_test.zig` show how to wire Flex/Grid layouts without a full app loop.
- For a one-stop tour of the catalog, run `zig build widget-showcase`.
