# Style Guide

## Callback naming
- Use `setOnX` for callback setters (examples: `setOnClose`, `setOnValueChanged`).
- Keep callback fields named `on_x` or `on_xxx` to match the setter name.

## String ownership
- If a widget stores a string beyond the call, it must duplicate the data and own it.
- Owned strings are freed by the widget (typically in `deinit` or before replacing them in a setter).
- Borrowed strings are not freed by the widget; the caller owns the lifetime.
- When in doubt, prefer owning copies for stored data and document the behavior in the setter.

## Parent linkage
- Composite widgets must set `child.parent = &self.widget` when adding children.
- Remove operations must clear `child.parent = null`.
- Lazy-created content must also be linked when instantiated.
