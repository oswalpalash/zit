# Terminal Compatibility

Zit adapts to terminal capabilities at runtime via `terminal.capabilities.detect*`. This guide summarizes supported terminals, how features are detected, and common quirks.

## Supported Terminals
- Truecolor-first: Kitty, WezTerm, Alacritty, Ghostty, iTerm2, Windows Terminal, VS Code integrated terminal.
- Truecolor via VTE/TERM hints: Apple Terminal, GNOME Terminal, Konsole, Foot, xterm-256color and derivatives.
- Multiplexers: tmux, screen (inherits host capabilities when properly configured).
- Minimal: linux console, `dumb` terminals (falls back to basic 16-color, limited Unicode).

## Feature Detection
- **Program detection**: environment probes (`TERM`, `TERM_PROGRAM`, `VTE_VERSION`, `WT_SESSION`, etc.) map to `TerminalProgram`.
- **Color depth**: `ColorLevel` is inferred from `COLORTERM`/`TERM` suffixes and known programs (16, 256, or truecolor).
- **Styling flags**: booleans for italic/underline/strikethrough/ligatures/emoji/double-width. Conservative defaults on linux console and dumb terminals.
- **Input/graphics extras**: `kitty_keyboard`, `kitty_graphics`, `synchronized_output`, `bracketed_paste`, and `iterm2_integration` are enabled when the program is known to support them.
- **Unicode width**: `unicode_width.measure` determines grapheme cell width from generated Unicode 17 data. East Asian `W/F` characters and default emoji use two cells; ambiguous characters default to one cell when no language/font context is available. Emoji/text variation selectors override the base presentation. When Unicode, emoji, or double-width output is disabled, the renderer stores a single-cell ASCII fallback instead of emitting a glyph whose terminal width it cannot represent safely.

## Color Modes
- **Truecolor (24-bit)**: Used when `color_level == .truecolor`; `render.Color.rgb` and gradients map directly to ANSI 24-bit sequences.
- **ANSI 256**: Enabled when `colors_256` is true; `Color.ansi256` and bright named colors are available.
- **ANSI 16**: Fallback for legacy/dumb/linux console; avoid gradients and prefer `NamedColor`.

## Known Quirks & Recommendations
- **tmux/screen**: Ensure `TERM` inside is `tmux-256color`/`screen-256color` and enable `set -g default-terminal` accordingly; pass-through truecolor with `terminal-overrides` (`Tc`). Sync output (DEC 2026) is usually safe.
- **macOS raw mode**: The driver uses a simplified raw-mode path via `stty` for macOS; avoid mixing external `stty` changes while Zit is active.
- **POSIX resize signals**: Zit installs a reference-counted SIGWINCH handler while `Terminal` instances are live and restores the prior handler after the last `Terminal.deinit`.
- **Mode cleanup**: `Terminal` owns cursor, mouse, focus-reporting, synchronized-output, bracketed-paste, alternate-screen, and Kitty keyboard state. Setup records a cleanup obligation before fallible ANSI output, and `deinit` restores VT modes before raw/console modes so Windows ConPTY output remains available. ANSI output is sent through the terminal instance's `stdout_fd`.
- **Terminal focus**: `enableFocusEvents` / `InputHandler.enableFocus` opt into xterm-compatible DECSET 1004 reporting. `InputHandler` returns `.focus` with `focused = true` for `CSI I` and `false` for `CSI O`; `event.fromInputEvent` maps this to `.terminal_focus`, not widget `.focus_change`. Cleanup sends DECRST 1004. See the [xterm control-sequence specification](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-FocusIn_FocusOut).
- **Bracketed paste**: When enabled, `InputHandler` decodes `ESC[200~` and `ESC[201~` into `KeyCode.BRACKETED_PASTE_START` / `KeyCode.BRACKETED_PASTE_END`; pasted text bytes continue through normal UTF-8 key decoding. `InputField` and `TextArea` consume the delimiters so single-line paste newlines do not accidentally submit the field.
- **Linux console/dumb**: Unicode and italic are disabled; stick to ASCII, avoid emoji, and use single-line borders.
- **Long grapheme clusters**: renderer cells keep up to 32 UTF-8 bytes inline. Longer combining or joined clusters retain their measured cell width but render as the first printable codepoint (or `?`) so fixed-size buffers remain allocation-free and never store partial UTF-8.
- **Text controls**: renderer draw calls are cell-oriented. C0/C1 controls, including ESC and CR/LF, are isolated at grapheme boundaries and rendered as `?` rather than copied into terminal output; CRLF occupies one fallback cell. Split multiline content into rows before drawing it.
- **Grapheme boundaries**: measurement, clipping, editing, and rendering implement Unicode 17 extended grapheme boundaries from generated Unicode Character Database properties. The allocation-free iterator is checked against all 766 cases in the official Unicode 17 `GraphemeBreakTest.txt` fixture. Cell width remains a terminal policy, not a claim of complete Unicode text shaping.
- **Kitty/WezTerm/Ghostty**: Raw mode pushes Kitty keyboard protocol flag 1 once per `Terminal` instance and pops that owned stack entry during cleanup. `InputHandler` decodes its CSI-u ASCII/control keys, keypad navigation, and Shift/Alt/Ctrl modifiers. Lock-state bits are ignored; events requiring unsupported Super/Hyper/Meta semantics or unknown private-use key codes are returned as `.unknown` instead of losing information. Setup/teardown write failures are non-fatal during raw-mode transitions and can be inspected with `Terminal.optionalFeatureFailureCount()` / `Terminal.lastOptionalFeatureFailure()`; `Terminal.deinit` retries and reports an unpopped owned entry.
- **Nested terminals**: When running inside SSH or a container, rely on the outer terminal’s exports; avoid forcing `TERM` to xterm-256color unless you know the host supports it.

## Runtime Checks
Use capabilities directly when toggling features:
```zig
const caps = term.capabilities;
const fg = if (caps.rgb_colors) render.Color.rgb(40, 180, 255) else render.Color.named(.cyan);
if (caps.synchronized_output) try term.beginSynchronizedOutput();
if (caps.bracketed_paste) try term.enableBracketedPaste();
```

## Updating Unicode Data

Run `python3 scripts/generate_unicode_grapheme_data.py` from the repository root to download the pinned Unicode sources, verify their SHA-256 hashes, and regenerate the Zig property tables, grapheme and width fixtures, and Unicode license. Normal builds and tests use the checked-in files and do not require network access. Source URLs and hashes are recorded in [`src/terminal/testdata/README.md`](../src/terminal/testdata/README.md).
