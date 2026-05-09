# termisol

a terminal emulator built with flutter. it uses the real `xterm.dart` package for terminal emulation and `pty` for shell integration. ai features are cloud-only via nvidia nim, with an optional local gemma 4:4b fallback on android if a local llm server is detected.

## what it actually does

- **terminal emulation**: full xterm-256color via the `xterm.dart` package, with a real pty backend
- **tabs**: create, close, reorder, rename, duplicate, close-others, close-to-the-right
- **split panes**: horizontal and vertical splits with draggable resizers (kitty-style), double-click to equalize
- **directory tracking**: tab titles show the current working directory automatically (via osc 7 and prompt parsing)
- **session restore**: reopens previous tabs with their working directories on startup
- **command aliases**: type `g` → `git`, `gs` → `git status`, etc. configurable in settings
- **copy mode**: `ctrl+shift+c` enters a scrollable, selectable view of terminal history
- **hints mode**: `ctrl+shift+h` overlays letter labels on urls/paths/emails — type the letters to open them
- **broadcast input**: `ctrl+shift+b` sends all keystrokes to every open tab simultaneously
- **osc 8 hyperlinks**: `ctrl+click` on urls printed by modern tools to open them
- **cloud ai**: `/ai <query>` forwards to nvidia nim. requires api key and network
- **android local fallback**: if nvidia nim is unreachable on android, probes localhost for a local gemma 4:4b model
- **themes**: dark, light, and retro (amber-on-black) terminal themes
- **fonts**: choose from droidsansmono, fira code, jetbrains mono, cascadia code, source code pro
- **opacity**: background opacity slider (50%–100%)
- **performance overlay**: `ctrl+shift+o` toggles an fps/frame-time hud
- **search**: `ctrl+f` finds text in the terminal buffer with case-sensitive toggle
- **long command notifications**: audio alert + tab indicator when a command runs longer than 40 seconds
- **command palette**: `ctrl+shift+p` fuzzy-finds all available actions
- **zoom**: `ctrl+=` / `ctrl+-` / `ctrl+0` to change font size
- **text editor**: built-in editor with syntax highlighting via `flutter_highlight`

## what it does not do

- **no vr**: the `lib/vr/` openxr implementation was removed. it was incomplete fiction with compile errors
- **no custom gpu renderer**: rendering is handled by `xterm.dart`'s built-in `terminalview`, wrapped in a `repaintboundary` for paint isolation
- **no offline ai on desktop**: desktop builds are cloud-only. no quantized model is bundled
- **no sixel/kitty/iterm2 graphics in the terminal grid**: `graphicsprotocolhandler` exists but is not wired into the active `terminalview`

## recent fixes (2026-05-08)

- **split panes**: fully implemented with draggable dividers, double-click to equalize, min-size enforcement
- **directory tracking**: real-time cwd detection via osc 7 and prompt parsing
- **session restore**: saves and restores all tabs with working directories
- **command aliases**: fully functional alias system with defaults and custom aliases
- **copy mode**: enter a scrollable, selectable view of terminal history
- **hints mode**: kitty-style url/path hinting with letter labels
- **broadcast input**: send keystrokes to all tabs simultaneously
- **osc 8 hyperlinks**: ctrl+click to open urls printed by terminal apps
- **theme switcher**: dark/light/retro themes with live switching
- **font selector**: 5 monospace font families
- **background opacity**: 50–100% slider
- **performance overlay**: real-time fps and frame-time display
- **tab management**: duplicate tab, close others, close to the right, long-command indicators
- **codebase cleanup**: 120+ placeholder files moved to `unused/`, 0 compilation errors

## architecture

```
lib/
├── main.dart                     # entry point
├── app.dart                      # materialapp with theme switching
├── core/
│   ├── terminal_session.dart     # wraps xterm terminal + pty backend
│   ├── pty_backend.dart          # cross-platform pty
│   ├── directory_tracker.dart    # cwd detection for tab titles
│   ├── command_alias_system.dart # alias expansion
│   ├── session_persistence.dart  # save/restore tabs
│   ├── hyperlink_handler.dart    # osc 8 hyperlink tracking
│   ├── termisol_core_integration.dart # frame timing metrics
│   ├── gpu_renderer.dart         # repaintboundary wrapper
│   ├── service_registry.dart     # lazy-loading registry
│   └── ...
├── ai/
│   └── ai_terminal_assistant.dart # nvidia nim client
├── ui/
│   ├── home_screen.dart          # tabs, toolbar, palette, splits, broadcast
│   ├── terminal_view.dart        # wraps xterm terminalview + copy mode
│   ├── split_pane.dart           # resizable split panes
│   ├── command_palette.dart      # fuzzy action finder
│   ├── search_overlay.dart       # find in terminal
│   ├── copy_mode_overlay.dart    # scrollback copy mode
│   ├── hints_mode.dart           # url/path hint overlay
│   ├── performance_overlay.dart  # fps hud
│   ├── settings_page.dart        # settings with aliases/themes/fonts
│   └── edit.dart                 # text editor
└── packages/
    ├── xterm/                    # local fork of xterm.dart
    └── pty/                      # local pty package
```

## getting started

```bash
flutter pub get
flutter run -d linux      # or android, windows, macos
```

## configuration

settings are stored in `sharedpreferences`. key settings:

```yaml
terminal:
  scrollback_lines: 50000
  font_size: 14.0
  font_family: droidsansmono
  bg_opacity: 1.0

ai:
  enabled: true
  api_key: "your-nvidia-nim-key"
  model: "nvidia-llama-3.1-8b-instruct"
```

## keyboard shortcuts

| shortcut | action |
|----------|--------|
| `ctrl+n` | new tab |
| `ctrl+t` | duplicate tab |
| `ctrl+w` | close tab |
| `ctrl+shift+w` | close all other tabs |
| `ctrl+tab` | next tab |
| `ctrl+c` | copy selected text |
| `ctrl+shift+c` | interrupt (original ctrl+c behavior) |
| `ctrl+v` | paste |
| `ctrl+z` | undo (standard behavior) |
| `ctrl+a` | copy all terminal content |
| `ctrl+f` | find in terminal |
| `ctrl+s` | save current file (in edit/nano) |
| `ctrl+b` | toggle transcript recording with whisper |
| `ctrl+shift+p` | command palette |
| `ctrl+shift+o` | toggle performance overlay |
| `ctrl+shift+b` | toggle broadcast input |
| `ctrl+shift+h` | hints mode |
| `ctrl+=` / `ctrl+-` | zoom in / out |
| `ctrl+0` | reset zoom |

## ai usage

type `/ai <question>` in the terminal. on desktop, this always goes to nvidia nim. on android, if the cloud request fails and a local gemma endpoint was detected at startup, it falls back to the local model.

## security

if you believe you, or an ai agent that you coordinate has found a security vulnerability, please report it privately to: john@houseofmates.space

do not open public issues for security vulnerabilities.

we will try to respond promptly and provide coordination for fixes as soon as we can

## license

mates license

copyright (c) 2026 house of mates

permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "software"), to fork the existing 
codebase or utilize the code from it in one's own projects so long as financial profit is 
not to be gained by said code/software created by the code.

termisol is provided "as is", without warranty of any kind, express or
implied, including but not limited to the warranties of merchantability,
fitness for a particular purpose and noninfringement. in no event shall the house of mates
system be liable for any claim, damages or other liability, whether in an action of 
contract, tort or otherwise, arising from, out of or in connection with the software or the
use or other dealings in the software. termisol was initially, and only made to be used
by the house of mates system. other users were never in mind for this project, and you
are expected to change significant parts of the codebase to adapt to your own preferences
and needs based on the differences in how your brain works vs. the house of mates system's.