<h1 align="center">Termisol</h1>

<p align="center">
  <strong>A modern, GPU-accelerated terminal emulator built with Flutter</strong>
</p>

<p align="center">
  Cross-platform • AI-powered • VR-ready • Designed for developers who demand more
</p>

---

## Overview

Termisol is a feature-rich terminal emulator that breaks from the GTK/Qt mold by leveraging Flutter's cross-platform capabilities and Skia/Impeller GPU rendering. It provides true **xterm-256color** emulation via the xterm.dart package with a real PTY backend, delivering a responsive terminal experience across Linux, macOS, Windows, Android, and Meta Quest VR.

## Key Features

### Terminal Emulation
- **xterm-256color** — Full ANSI/VT100 terminal emulation with 256-color support
- **Real PTY backend** — Native pseudo-terminal on desktop, process-based on Android
- **GPU-accelerated rendering** — Skia/Impeller backend targeting 60 FPS
- **50,000-line scrollback** — Configurable with memory-efficient compression
- **Bracketed paste mode** — Safe multiline paste handling
- **OSC 8 hyperlinks** — Ctrl+click to open URLs from terminal output

### Tab & Pane Management
- **Tabbed interface** — Create, close, rename, duplicate, reorder tabs via drag
- **Split panes** — Horizontal and vertical splits with draggable dividers
- **Session persistence** — Restore previous tabs and working directories on restart
- **Directory tracking** — Tab titles auto-update via OSC 7 and prompt parsing
- **Broadcast input** — Send keystrokes to all tabs simultaneously (Ctrl+Shift+B)

### AI Integration
- **NVIDIA NIM API** — Cloud AI via `/ai <query>` command with multiple model support
- **Local fallback** — Android auto-detects local Gemma 4:4b LLM server if cloud unavailable
- **Command assistance** — Get explanations, suggestions, and error analysis

### Developer Tools
- **Built-in editor** — Full-featured text editor with undo/redo, syntax highlighting, find/replace
- **Command aliases** — Configure shortcuts (e.g., `g` → `git`, `gs` → `git status`)
- **Smart autocomplete** — Command suggestions based on history and context
- **Search** — Find text in terminal buffer with case-sensitivity toggle
- **Copy mode** — Scrollable, selectable view of terminal history (Ctrl+Shift+C)
- **Hints mode** — Letter overlays on URLs/paths for quick keyboard access (Ctrl+Shift+H)
- **Command palette** — Fuzzy-find all actions (Ctrl+Shift+P)

### Customization
- **Themes** — Dark, Light, and Retro (amber-on-black CRT aesthetic)
- **Fonts** — Cascadia Code, Fira Code, JetBrains Mono, Source Code Pro, Droid Sans Mono
- **Opacity** — Background transparency slider (50-100%)
- **Zoom** — Font size control (Ctrl+=/Ctrl+-/Ctrl+0)
- **Ligatures** — Programming ligature support in compatible fonts

### Accessibility
- **Screen reader support** — TTS integration for interface elements
- **High contrast mode** — Enhanced visibility option
- **Color blind modes** — Protanopia, deuteranopia, tritanopia filters
- **Keyboard navigation** — Full keyboard control with customizable shortcuts
- **Font/cursor scaling** — Adjustable sizes for visibility

### Platform-Specific Features
- **Linux/macOS/Windows** — Native window management with proper title bar
- **Android** — Landscape/portrait support, immersive mode
- **Meta Quest VR** — OpenXR integration with controller input mapping

### Performance & Reliability
- **GPU rendering** — Sub-16ms frame times for smooth scrolling
- **Ring buffer scrollback** — Memory-efficient with automatic compression
- **Crash recovery** — Session state saved for automatic restoration
- **Health monitoring** — Built-in diagnostics and error reporting

## Installation

### Prerequisites
- Flutter SDK 3.29.0+ with Dart 3.11.0+
- Platform-specific build tools (Xcode, Android Studio, Visual Studio, etc.)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/your-username/termisol.git
cd termisol

# Install dependencies
flutter pub get

# Run in development
flutter run -d linux      # or: android, windows, macos

# Build release
flutter build linux --release
flutter build apk --release
flutter build windows --release
flutter build macos --release
```

### Debian Package

```bash
./build_deb.sh
sudo dpkg -i termisol_*.deb
```

### Android APK

```bash
./build_apk.sh
# APK output: build/app/outputs/flutter-apk/app-release.apk
```

## Configuration

Settings are stored via SharedPreferences and persisted across sessions. Configure through the in-app settings page or programmatically:

| Setting | Default | Description |
|---------|---------|-------------|
| `scrollback_lines` | 50000 | Maximum scrollback buffer size |
| `font_size` | 14.0 | Terminal font size |
| `font_family` | DroidSansMono | Terminal font |
| `bg_opacity` | 1.0 | Background opacity (0.5-1.0) |
| `ai.enabled` | true | Enable AI features |
| `ai.api_key` | — | NVIDIA NIM API key |

## Keyboard Shortcuts

### Terminal
| Shortcut | Action |
|----------|--------|
| Ctrl+N | New tab |
| Ctrl+T | Duplicate tab |
| Ctrl+W | Close tab |
| Ctrl+Shift+W | Close all other tabs |
| Ctrl+Tab | Next tab |
| Ctrl+C | Copy selection |
| Ctrl+Shift+C | Send interrupt (SIGINT) |
| Ctrl+V | Paste |
| Ctrl+A | Select all / Copy all content |
| Ctrl+F | Find in terminal |
| Ctrl+Shift+P | Command palette |
| Ctrl+Shift+O | Toggle performance overlay |
| Ctrl+Shift+B | Toggle broadcast input |
| Ctrl+Shift+H | Hints mode |
| Ctrl+= / Ctrl+- | Zoom in / out |
| Ctrl+0 | Reset zoom |

### Built-in Editor (`edit <filename>`)
| Shortcut | Action |
|----------|--------|
| Ctrl+Z | Undo |
| Ctrl+X | Redo |
| Ctrl+C | Copy |
| Ctrl+V | Paste |
| Ctrl+A | Select all |
| Ctrl+S | Save |
| Ctrl+O | Open file |
| Ctrl+W | Close editor |
| Ctrl+F | Find |
| Ctrl+Shift+D | Duplicate line |
| Tab | Indent (2 spaces) |

### Accessibility
| Shortcut | Action |
|----------|--------|
| Ctrl+Alt+A | Toggle screen reader |
| Ctrl+Alt+H | Toggle high contrast |
| Ctrl+Alt+F | Increase font scale |
| Ctrl+Alt+D | Decrease font scale |

## AI Commands

```bash
# Ask a question
/ai how do I find files larger than 100MB?

# Get command help
/ai explain: git rebase -i HEAD~3

# Debug errors
/ai why is this failing: [paste error message]
```

## Architecture

```
lib/
├── main.dart              # Entry point with error handling
├── app.dart               # Root MaterialApp with VR detection
├── core/                  # Core terminal functionality
│   ├── terminal_session.dart
│   ├── pty_backend.dart
│   ├── service_registry.dart
│   ├── gpu_renderer.dart
│   └── ...
├── ui/                    # User interface widgets
│   ├── home_screen.dart
│   ├── terminal_view.dart
│   ├── settings_page.dart
│   └── ...
├── ai/                    # AI integration
│   ├── ai_terminal_assistant.dart
│   └── local_ai_service.dart
├── vr/                    # VR support
│   ├── vr_terminal_view.dart
│   └── openxr_session.dart
└── config/                # Theming and configuration
    └── pkm_theme.dart

packages/
├── pty/                   # Platform-specific PTY bindings
└── xterm/                 # Terminal emulation library
```

## Technical Highlights

- **Service Registry Pattern** — Lazy-loading dependency injection reduces startup time
- **Ring Buffer Scrollback** — Memory-efficient with gzip compression for old lines
- **Throttled Rendering** — Frame rate control prevents GPU saturation
- **Backpressure Flow Control** — Handles high-throughput output without blocking
- **Session Persistence** — Automatic state saving with crash recovery

## Limitations

- **Desktop AI is cloud-only** — No bundled local model; requires NVIDIA NIM API access
- **Graphics protocols** — Sixel/Kitty/iTerm2 image protocols not rendered in terminal grid
- **Android local AI** — Opt-in; requires separate LLM server app running locally

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[The Mates License](LICENSE)

---

<p align="center">
  Built with Flutter • Powered by xterm.dart • AI by NVIDIA NIM
</p>
