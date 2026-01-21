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
- **Unicode width**: `unicode_width.measure` is used to gate emoji/double-width handling.

## Color Modes
- **Truecolor (24-bit)**: Used when `color_level == .truecolor`; `render.Color.rgb` and gradients map directly to ANSI 24-bit sequences.
- **ANSI 256**: Enabled when `colors_256` is true; `Color.ansi256` and bright named colors are available.
- **ANSI 16**: Fallback for legacy/dumb/linux console; avoid gradients and prefer `NamedColor`.

## Known Quirks & Recommendations
- **tmux/screen**: Ensure `TERM` inside is `tmux-256color`/`screen-256color` and enable `set -g default-terminal` accordingly; pass-through truecolor with `terminal-overrides` (`Tc`). Sync output (DEC 2026) is usually safe.
- **macOS raw mode**: The driver uses a simplified raw-mode path via `stty` for macOS; avoid mixing external `stty` changes while Zit is active.
- **Linux console/dumb**: Unicode and italic are disabled; stick to ASCII, avoid emoji, and use single-line borders.
- **Kitty/WezTerm**: Kitty keyboard protocol is enabled when available; ensure applications handle extended key codes gracefully.
- **Nested terminals**: When running inside SSH or a container, rely on the outer terminal’s exports; avoid forcing `TERM` to xterm-256color unless you know the host supports it.

## Runtime Checks
Use capabilities directly when toggling features:
```zig
const caps = term.capabilities;
const fg = if (caps.rgb_colors) render.Color.rgb(40, 180, 255) else render.Color.named(.cyan);
if (caps.synchronized_output) try term.beginSynchronizedOutput();
if (caps.bracketed_paste) try term.enableBracketedPaste();
```
