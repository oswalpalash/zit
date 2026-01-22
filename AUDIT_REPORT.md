# Zit TUI Library Audit Report

## Scope
- Audited widget abstractions for API consistency, init patterns, callback naming, string ownership, and parent linkage.
- Audited test coverage (unit tests + snapshot infrastructure) and missing edge cases.

## Abstraction Findings (with file:line references)

### API and Compile-Time Mismatches
- `createLabel` calls `Label.init(allocator)` with no text, but `Label.init` requires a `text` argument. The same mismatch shows up in widget tests, meaning the current API and tests are out of sync. `src/widget/widget.zig:127`, `src/widget/widgets/label.zig:41`, `src/widget/widgets/tab_view.zig:644`, `src/widget/widgets/split_pane.zig:190`.
- `createScrollbar` calls `Scrollbar.init(allocator)` and then `setOrientation`, but `Scrollbar.init` requires an orientation argument and there is no `setOrientation` method. `src/widget/widget.zig:184`, `src/widget/widgets/scrollbar.zig:53`.
- `ScrollContainer` calls methods and fields that do not exist on `Scrollbar` (`setMaxValue`, `max_value`) and calls underscored Widget methods (`handle_event`, `get_preferred_size`) that don’t exist on `Widget`. `src/widget/widgets/scroll_container.zig:145`, `src/widget/widgets/scroll_container.zig:364`, `src/widget/widgets/scroll_container.zig:365`, `src/widget/widgets/scroll_container.zig:148`, `src/widget/widgets/scroll_container.zig:549`.
- `ScrollContainer`’s border config fields are inconsistent: `border` is typed as `render.Color` but used as `BorderStyle` and `style` is typed as `render.Style` but used as optional border character data. `src/widget/widgets/scroll_container.zig:49`, `src/widget/widgets/scroll_container.zig:124`, `src/widget/widgets/scroll_container.zig:131`, `src/widget/widgets/scroll_container.zig:235`.
- `Modal` size negotiation is split: `layoutFn` uses `getPreferredSize` that expands to fit content, while the vtable `getPreferredSizeFn` returns the fixed width/height (ignores content). This causes inconsistent layout behavior depending on which call path is used. `src/widget/widgets/modal.zig:205`, `src/widget/widgets/modal.zig:228`, `src/widget/widgets/modal.zig:258`.

### Rendering Safety Issues
- Label truncation uses a fixed 256-byte buffer and slices by `rect.width` without clamping; any width > 256 will slice out of bounds. `src/widget/widgets/label.zig:129`.
- Button truncation uses a fixed 256-byte buffer and slices by `inner_width` without clamping; wide buttons can overrun the buffer. `src/widget/widgets/button.zig:126`.
- Checkbox truncation uses a fixed 256-byte buffer and slices by `rect.width` without clamping, and it draws `[` at `rect.x - 1` which underflows when `rect.x == 0`. `src/widget/widgets/checkbox.zig:114`, `src/widget/widgets/checkbox.zig:120`.

### Parent Linkage Gaps
- `TabView` does not set the parent on tab content when a tab is added; only the `TabBar` is linked. This breaks parent-based traversal (e.g. modal stacking or focus traversal that expects parent links). `src/widget/widgets/tab_view.zig:341`.
- `Modal.setContent` assigns content but does not set the parent pointer. `src/widget/widgets/modal.zig:77`.
- `ScrollContainer` sets `content` and creates scrollbars without linking them to the container via `Widget.parent`. `src/widget/widgets/scroll_container.zig:68`, `src/widget/widgets/scroll_container.zig:98`.

### API Consistency and Ownership Policy
- Callback naming and signatures are inconsistent across widgets (e.g., `setOnPress`, `setOnChange`, `setOnSelectionChanged`, `setOnSelect`, `setOnTabChanged`), and some callbacks accept context pointers while others do not. This makes the API feel ad-hoc and complicates generic patterns. Examples: `src/widget/widgets/button.zig:88`, `src/widget/widgets/checkbox.zig:84`, `src/widget/widgets/dropdown_menu.zig:189`, `src/widget/widgets/list.zig:223`, `src/widget/widgets/color_picker.zig:56`, `src/widget/widgets/context_menu.zig:69`, `src/widget/widgets/tab_view.zig:450`.
- `TabBar` and `TabItem` accept borrowed titles without a documented ownership contract. TabView duplicates titles, but standalone TabBar usage is unclear and can lead to dangling references. `src/widget/widgets/tab_view.zig:11`, `src/widget/widgets/tab_view.zig:35`.

## Widget-by-Widget Summary (init pattern, ownership, callbacks, parent linkage)

- **advanced_controls**: init varies by control; mostly duplicates label/options; callbacks are `on_toggle`, `on_change`, `on_click`, etc.; no parent linkage (leaf widgets).
- **autocomplete_input**: init wraps `InputField` and owns it; suggestions duplicated; callback `on_select` without ctx; parent linkage set for input field.
- **base_widget**: consistent vtable; parent pointer exists but many containers don’t set it consistently.
- **block**: init no args; title owned; setChild sets parent.
- **button**: init requires text; text owned; callback `setOnPress` no ctx; no parent linkage.
- **canvas**: init w/ size; owns cells; no callbacks; no parent linkage.
- **chart**: init no args; owns series labels/values; no callbacks; no parent linkage.
- **checkbox**: init requires label; label owned; callback `setOnChange` no ctx; no parent linkage.
- **color_picker**: init requires palette; owns palette; `setOnChange` includes ctx; no parent linkage.
- **container**: init no args; children stored as pointers; addChild sets parent.
- **context_menu**: init no args; labels owned; callback with ctx; no parent linkage.
- **date_time_picker**: init no args; no string ownership; `setOnChange` no ctx; no parent linkage.
- **dropdown_menu**: init no args; labels owned; `setOnSelectionChanged` no ctx; no parent linkage.
- **file_browser**: init requires path; owns entries/path; callbacks without ctx; no parent linkage.
- **gauge**: init no args; label owned; no callbacks; no parent linkage.
- **image**: init requires size; owns pixel buffer; no callbacks; no parent linkage.
- **indicators**: init no args; no callbacks; no parent linkage.
- **input_field**: init max_length; owns buffer/placeholder; callbacks for change/submit/validation; no parent linkage.
- **label**: init requires text; text owned; no callbacks; no parent linkage.
- **list**: init no args; items owned; callbacks `setOnSelect`/`setOnItemActivated` no ctx; no parent linkage.
- **log_view**: init no args; entries owned; no callbacks; no parent linkage.
- **markdown**: init requires text; text owned; no callbacks; no parent linkage.
- **menubar**: init no args; labels owned; callbacks per item; no parent linkage.
- **modal**: init no args; title owned; callback `setOnClose`; parent linkage missing for content.
- **paragraph**: init requires text; text owned; no callbacks; no parent linkage.
- **popup**: init requires message; message owned; no callbacks; no parent linkage.
- **progress_bar**: init no args; no callbacks; no parent linkage.
- **rich_text**: init no args; spans owned; no callbacks; no parent linkage.
- **screen_manager**: init no args; labels duplicated; lifecycle callbacks; sets parent via `primeEntry`.
- **scroll_container**: init no args; owns scrollbars; content is borrowed; parent linkage missing for content/scrollbars.
- **scrollbar**: init requires orientation; no text ownership; callback `setOnValueChanged` no ctx; no parent linkage.
- **sparkline**: init no args; no callbacks; no parent linkage.
- **split_pane**: init no args; child pointers borrowed; setFirst/setSecond set parent.
- **syntax_highlighter**: init no args; owns rules; no callbacks; no parent linkage.
- **tab_view / tab_bar**: init no args; titles owned in TabView; callbacks in both with inconsistent signatures; parent linkage missing for content.
- **table**: init no args; owns columns/rows unless interner; callbacks `setOnRowSelected` no ctx; no parent linkage.
- **text_area**: init max_bytes; owns buffer/placeholder; callbacks for change/submit/validation; no parent linkage.
- **toast**: init no args; messages owned; no callbacks; no parent linkage.
- **tree_view**: init no args; labels owned; no callbacks; no parent linkage.

## Test Coverage Audit

### Coverage Map (widgets)
- **Has tests**: advanced_controls, autocomplete_input, base_widget, block, canvas, chart, color_picker, context_menu, date_time_picker, file_browser, gauge, image, indicators, input_field, list, log_view, markdown, menubar, paragraph, popup, rich_text, screen_manager, sparkline, split_pane, syntax_highlighter, tab_view, table, text_area, toast, tree_view.
- **No tests**: button, checkbox, container, dropdown_menu, label, modal, progress_bar, scroll_container, scrollbar.

### Gaps in Existing Tests (examples with file:line references)
- **List**: tests cover typeahead and empty state only; missing drag-reorder, cross-list drop, smooth scrolling, and virtual provider behavior. `src/widget/widgets/list.zig:803`.
- **Table**: tests cover typeahead, preferred size clamp, empty input, sorting/grouping, and inline edit; missing column resize, row provider sampling, and grid/selection rendering. `src/widget/widgets/table.zig:1353`.
- **TabView**: tests cover lazy loading, reorder, and closable tabs; missing parent linkage validation, TabBar keyboard interactions, and focus transfer into tab content. `src/widget/widgets/tab_view.zig:635`.
- **TextArea**: tests cover undo, cursor nav, validation, and multi-cursor basics; missing clipboard integration, selection render, scroll bounds, and placeholder rendering. `src/widget/widgets/text_area.zig:969`.
- **InputField**: tests cover undo, clipboard, masks, and validation; missing resize/ensureCapacity, cursor clamping at bounds, and placeholder rendering for long widths. `src/widget/widgets/input_field.zig:687`.
- **ScreenManager**: tests cover lifecycle hooks; missing parent linkage checks and animation completion ordering under rapid push/pop. `src/widget/widgets/screen_manager.zig:346`.
- **Chart**: tests cover stacked bar/area/pie/scatter render; missing axis labels, legend overflow, and empty-series behavior. `src/widget/widgets/chart.zig:479`.
- **TreeView**: tests cover expansion and cache; missing selection bounds at top/bottom and scroll behavior. `src/widget/widgets/tree_view.zig:303`.

### Snapshot Testing
- Snapshot infrastructure exists, but only one golden file is present (`src/testing/golden/button_basic.snap`), limiting regression coverage for UI rendering across widgets.

## Prioritized Plan for Today

1. **Unblock compile-time/API mismatches**
   - Fix `createLabel`/`Label.init` mismatch and update stale tests (`tab_view`, `split_pane`).
   - Fix `createScrollbar` and reconcile Scrollbar API surface.
   - Repair `ScrollContainer` to match `Scrollbar` and `Widget` APIs (method names, types, and fields).

2. **Stabilize core widget abstractions**
   - Define a consistent callback naming/signature convention (e.g., `setOnX` + optional ctx or `*Widget` + data) and align the most-used widgets first.
   - Establish a clear ownership policy for strings (borrowed vs owned) and document it (TabBar/TabItem in particular).
   - Standardize parent linkage for composite widgets (TabView content, Modal, ScrollContainer).

3. **Fix rendering safety issues**
   - Replace fixed-size truncation buffers with bounds-checked slices or dynamic buffers; guard underflow cases like `rect.x - 1`.

4. **Raise test coverage on critical UI primitives**
   - Add unit tests for untested widgets (button, checkbox, container, dropdown_menu, label, modal, progress_bar, scroll_container, scrollbar).
   - Add targeted edge-case tests for scroll/resize, long text truncation, and focus/parent linkage invariants.

5. **Expand snapshot coverage**
   - Add golden snapshots for core widgets (button, label, checkbox, list, table, modal, scroll_container) to catch regressions in rendering.
