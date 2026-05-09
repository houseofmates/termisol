# termisol

a terminal emulator built with Flutter. it uses the real `xterm.dart` package for terminal emulation and `pty` for shell integration. AI features are cloud-only via NVIDIA NIM, with an optional local gemma 4:4b fallback on Android if a local LLM server is detected.

## what it actually does

- **terminal emulation**: full xterm-256color via the `xterm.dart` package, with a real PTY backend
- **tabs**: create, close, reorder, rename, duplicate, and close-other tabs
- **split panes**: horizontal and vertical splits with draggable resizers (kitty-style)
- **directory tracking**: tab titles show the current working directory automatically
- **session restore**: reopens previous tabs with their working directories on startup
- **command aliases**: type `g` → `git`, `gs` → `git status`, etc. configurable in settings
- **copy mode**: `ctrl+shift+c` enters a scrollable, selectable view of terminal history
- **cloud AI**: `/ai <query>` forwards to NVIDIA NIM. requires API key and network
- **android local fallback**: if NVIDIA NIM is unreachable on Android, probes localhost for a local gemma 4:4b model
- **themes**: dark, light, and retro (amber-on-black) terminal themes
- **performance overlay**: `ctrl+shift+o` toggles an FPS/frame-time HUD
- **search**: `ctrl+f` finds text in the terminal buffer with case-sensitive toggle
- **long command notifications**: audio alert when a command runs longer than 40 seconds
- **command palette**: `ctrl+shift+p` fuzzy-finds all available actions
- **zoom**: `ctrl+=` / `ctrl+-` / `ctrl+0` to change font size
- **text editor**: built-in editor with syntax highlighting via `flutter_highlight`

## what it does NOT do

- **no VR**: the `lib/vr/` OpenXR implementation was removed. it was incomplete fiction with compile errors
- **no custom GPU renderer**: rendering is handled by `xterm.dart`'s built-in `TerminalView`, wrapped in a `RepaintBoundary` for paint isolation
- **no offline AI on desktop**: desktop builds are cloud-only. no quantized model is bundled
- **no sixel/kitty/iterm2 graphics in the terminal grid**: `GraphicsProtocolHandler` exists but is not wired into the active `TerminalView`

## recent fixes (2026-05-08)

- **Split panes**: fully implemented with draggable dividers, double-click to equalize, min-size enforcement
- **Directory tracking**: real-time CWD detection via OSC 7 and prompt parsing
- **Session restore**: saves and restores all tabs with working directories
- **Command aliases**: fully functional alias system with defaults and custom aliases
- **Copy mode**: enter a scrollable, selectable view of terminal history
- **Theme switcher**: dark/light/retro themes with live switching
- **Performance overlay**: real-time FPS and frame-time display
- **Tab management**: duplicate tab, close others, close to the right
- **Long command notifier**: wired into UI with active-command indicators on tabs
- **Codebase cleanup**: 120+ placeholder files moved to `unused/`, 0 compilation errors

## architecture

```
lib/
├── main.dart                  # entry point
├── app.dart                   # MaterialApp with theme switching
├── core/
│   ├── terminal_session.dart  # wraps xterm Terminal + PTY backend
│   ├── pty_backend.dart       # cross-platform PTY
│   ├── directory_tracker.dart # CWD detection for tab titles
│   ├── command_alias_system.dart # alias expansion
│   ├── session_persistence.dart # save/restore tabs
│   ├── termisol_core_integration.dart # frame timing metrics
│   ├── gpu_renderer.dart      # RepaintBoundary wrapper
│   ├── service_registry.dart  # lazy-loading registry
│   └── ...
├── ai/
│   └── ai_terminal_assistant.dart  # NVIDIA NIM client
├── ui/
│   ├── home_screen.dart       # tabs, toolbar, command palette, splits
│   ├── terminal_view.dart     # wraps xterm TerminalView + copy mode
│   ├── split_pane.dart        # resizable split panes
│   ├── command_palette.dart   # fuzzy action finder
│   ├── search_overlay.dart    # find in terminal
│   ├── copy_mode_overlay.dart # scrollback copy mode
│   ├── performance_overlay.dart # FPS HUD
│   ├── settings_page.dart     # settings with aliases/themes
│   └── edit.dart              # text editor
└── packages/
    ├── xterm/                 # local fork of xterm.dart
    └── pty/                   # local PTY package
```

## getting started

```bash
flutter pub get
flutter run -d linux      # or android, windows, macos
```

## configuration

Settings are stored in `SharedPreferences`. Key settings:

```yaml
terminal:
  scrollback_lines: 50000
  font_size: 14.0

ai:
  enabled: true
  api_key: "your-nvidia-nim-key"
  model: "nvidia-llama-3.1-8b-instruct"
```

## keyboard shortcuts

| shortcut | action |
|----------|--------|
| `Ctrl+T` | new tab |
| `Ctrl+Shift+T` | duplicate tab |
| `Ctrl+W` | close tab |
| `Ctrl+Shift+W` | close all other tabs |
| `Ctrl+Tab` | next tab |
| `Ctrl+Shift+C` | copy (or enter copy mode if no selection) |
| `Ctrl+Shift+V` | paste |
| `Ctrl+F` | find in terminal |
| `Ctrl+Shift+P` | command palette |
| `Ctrl+Shift+O` | toggle performance overlay |
| `Ctrl+=` / `Ctrl+-` | zoom in / out |
| `Ctrl+0` | reset zoom |

## AI usage

Type `/ai <question>` in the terminal. On desktop, this always goes to NVIDIA NIM. On Android, if the cloud request fails and a local gemma endpoint was detected at startup, it falls back to the local model.

## license

MIT License. See `LICENSE`.
