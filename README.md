<h1 align="center">termisol</h1>

<p align="center">
  <strong>a modern, GPU-accelerated terminal emulator built with flutter</strong>
</p>

<p align="center">
  cross-platform • AI-powered • VR-ready • designed for developers who demand more
</p>

---

<h2 align="center">overview</h2>

termisol is a feature-rich terminal emulator that breaks from the GTK/Qt mold by leveraging flutter's cross-platform capabilities and skia/impeller GPU rendering. it provides true **xterm-256color** emulation via the xterm.dart package with a real PTY backend, delivering a responsive terminal experience across linux, macOS, windows, android, and meta quest VR.

<h2 align="center">key features</h2>

<h3 align="center">terminal emulation</h3>

- **xterm-256color** — full ANSI/VT100 terminal emulation with 256-color support
- **real PTY backend** — native pseudo-terminal on desktop, process-based on android
- **GPU-accelerated rendering** — skia/impeller backend targeting 60 FPS
- **50,000-line scrollback** — configurable with memory-efficient compression
- **bracketed paste mode** — safe multiline paste handling
- **OSC 8 hyperlinks** — ctrl+click to open URLs from terminal output

<h3 align="center">tab & pane management</h3>

- **tabbed interface** — create, close, rename, duplicate, reorder tabs via drag
- **split panes** — horizontal and vertical splits with draggable dividers
- **session persistence** — restore previous tabs and working directories on restart
- **directory tracking** — tab titles auto-update via OSC 7 and prompt parsing
- **broadcast input** — send keystrokes to all tabs simultaneously (ctrl+shift+B)

<h3 align="center">AI integration</h3>

- **NVIDIA NIM API** — cloud AI via `/ai <query>` command with multiple model support
- **local fallback** — android auto-detects local gemma 4:4b LLM server if cloud unavailable
- **command assistance** — get explanations, suggestions, and error analysis

<h3 align="center">developer tools</h3>

- **built-in editor** — full-featured text editor with undo/redo, syntax highlighting, find/replace
- **command aliases** — configure shortcuts (e.g., `g` → `git`, `gs` → `git status`)
- **smart autocomplete** — command suggestions based on history and context
- **search** — find text in terminal buffer with case-sensitivity toggle
- **copy mode** — scrollable, selectable view of terminal history (ctrl+shift+C)
- **hints mode** — letter overlays on URLs/paths for quick keyboard access (ctrl+shift+H)
- **command palette** — fuzzy-find all actions (ctrl+shift+P)

<h3 align="center">customization</h3>

- **themes** — dark, light, and retro (amber-on-black CRT aesthetic)
- **fonts** — cascadia code, fira code, jetbrains mono, source code pro, droid sans mono
- **opacity** — background transparency slider (50-100%)
- **zoom** — font size control (ctrl+=/ctrl+-/ctrl+0)
- **ligatures** — programming ligature support in compatible fonts

<h3 align="center">accessibility</h3>

- **screen reader support** — TTS integration for interface elements
- **high contrast mode** — enhanced visibility option
- **color blind modes** — protanopia, deuteranopia, tritanopia filters
- **keyboard navigation** — full keyboard control with customizable shortcuts
- **font/cursor scaling** — adjustable sizes for visibility

<h3 align="center">platform-specific features</h3>

- **linux/macOS/windows** — native window management with proper title bar
- **android** — landscape/portrait support, immersive mode
- **meta quest VR** — openXR integration with controller input mapping

<h3 align="center">performance & reliability</h3>

- **GPU rendering** — sub-16ms frame times for smooth scrolling
- **ring buffer scrollback** — memory-efficient with automatic compression
- **crash recovery** — session state saved for automatic restoration
- **health monitoring** — built-in diagnostics and error reporting

<h2 align="center">installation</h2>

<h3 align="center">prerequisites</h3>

- flutter SDK 3.29.0+ with dart 3.11.0+
- platform-specific build tools (xcode, android studio, visual studio, etc.)

<h3 align="center">build from source</h3>

```bash
# clone the repository
git clone https://github.com/your-username/termisol.git
cd termisol

# install dependencies
flutter pub get

# run in development
flutter run -d linux      # or: android, windows, macos

# build release
flutter build linux --release
flutter build apk --release
flutter build windows --release
flutter build macos --release
```

<h3 align="center">debian package</h3>

```bash
./build_deb.sh
sudo dpkg -i termisol_*.deb
```

<h3 align="center">android APK</h3>

```bash
./build_apk.sh
# APK output: build/app/outputs/flutter-apk/app-release.apk
```

<h2 align="center">configuration</h2>

settings are stored via sharedpreferences and persisted across sessions. configure through the in-app settings page or programmatically:

| setting | default | description |
|---------|---------|-------------|
| `scrollback_lines` | 50000 | maximum scrollback buffer size |
| `font_size` | 14.0 | terminal font size |
| `font_family` | DroidSansMono | terminal font |
| `bg_opacity` | 1.0 | background opacity (0.5-1.0) |
| `ai.enabled` | true | enable AI features |
| `ai.api_key` | — | NVIDIA NIM API key |

<h2 align="center">keyboard shortcuts</h2>

<h3 align="center">terminal</h3>

| shortcut | action |
|----------|--------|
| ctrl+N | new tab |
| ctrl+T | duplicate tab |
| ctrl+W | close tab |
| ctrl+shift+W | close all other tabs |
| ctrl+tab | next tab |
| ctrl+C | copy selection |
| ctrl+shift+C | send interrupt (SIGINT) |
| ctrl+V | paste |
| ctrl+A | select all / copy all content |
| ctrl+F | find in terminal |
| ctrl+shift+P | command palette |
| ctrl+shift+O | toggle performance overlay |
| ctrl+shift+B | toggle broadcast input |
| ctrl+shift+H | hints mode |
| ctrl+= / ctrl+- | zoom in / out |
| ctrl+0 | reset zoom |

<h3 align="center">built-in editor (`edit <filename>`)</h3>

| shortcut | action |
|----------|--------|
| ctrl+Z | undo |
| ctrl+X | redo |
| ctrl+C | copy |
| ctrl+V | paste |
| ctrl+A | select all |
| ctrl+S | save |
| ctrl+O | open file |
| ctrl+W | close editor |
| ctrl+F | find |
| ctrl+shift+D | duplicate line |
| tab | indent (2 spaces) |

<h3 align="center">accessibility</h3>

| shortcut | action |
|----------|--------|
| ctrl+alt+A | toggle screen reader |
| ctrl+alt+H | toggle high contrast |
| ctrl+alt+F | increase font scale |
| ctrl+alt+D | decrease font scale |

<h2 align="center">AI commands</h2>

```bash
# ask a question
/ai how do I find files larger than 100MB?

# get command help
/ai explain: git rebase -i HEAD~3

# debug errors
/ai why is this failing: [paste error message]
```

<h2 align="center">architecture</h2>

```
lib/
├── main.dart              # entry point with error handling
├── app.dart               # root materialapp with VR detection
├── core/                  # core terminal functionality
│   ├── terminal_session.dart
│   ├── pty_backend.dart
│   ├── service_registry.dart
│   ├── gpu_renderer.dart
│   └── ...
├── ui/                    # user interface widgets
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
└── config/                # theming and configuration
    └── pkm_theme.dart

packages/
├── pty/                   # platform-specific PTY bindings
└── xterm/                 # terminal emulation library
```

<h2 align="center">technical highlights</h2>

- **service registry pattern** — lazy-loading dependency injection reduces startup time
- **ring buffer scrollback** — memory-efficient with gzip compression for old lines
- **throttled rendering** — frame rate control prevents GPU saturation
- **backpressure flow control** — handles high-throughput output without blocking
- **session persistence** — automatic state saving with crash recovery

<h2 align="center">limitations</h2>

- **desktop AI is cloud-only** — no bundled local model; requires NVIDIA NIM API access
- **graphics protocols** — sixel/kitty/iTerm2 image protocols not rendered in terminal grid
- **android local AI** — opt-in; requires separate LLM server app running locally

<h2 align="center">contributing</h2>

see [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

<h2 align="center">license</h2>

[the mates license](LICENSE)

---

<p align="center">
  built with https://flutter.dev/ • powered by https://github.com/TerminalStudio/xterm.dart • AI by https://build.nvidia.com/
</p>
