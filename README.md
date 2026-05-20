<h1 align="center">termisol</h1>

<p align="center">
  <strong>a modern, gpu-accelerated terminal emulator built with flutter</strong>
</p>

<p align="center">
  cross-platform • ai-powered • vr-ready • designed for developers who demand more
</p>

---

<h2 align="center">overview</h2>


termisol is a feature-rich terminal emulator that breaks from the gtk/qt mold by leveraging flutter's cross-platform capabilities and skia/impeller gpu rendering. it provides true **xterm-256color** emulation via the xterm.dart package with a real pty backend, delivering a responsive terminal experience across linux, macos, windows, android, and meta quest vr.

<h2 align="center">key features</h2>


<h3 align="center">terminal emulation</h3>

- **xterm-256color** — full ansi/vt100 terminal emulation with 256-color support
- **real pty backend** — native pseudo-terminal on desktop, process-based on android
- **gpu-accelerated rendering** — skia/impeller backend targeting 60 fps
- **50,000-line scrollback** — configurable with memory-efficient compression
- **bracketed paste mode** — safe multiline paste handling
- **osc 8 hyperlinks** — ctrl+click to open urls from terminal output

<h3 align="center">tab & pane management</h3>

- **tabbed interface** — create, close, rename, duplicate, reorder tabs via drag
- **split panes** — horizontal and vertical splits with draggable dividers
- **session persistence** — restore previous tabs and working directories on restart
- **directory tracking** — tab titles auto-update via osc 7 and prompt parsing
- **broadcast input** — send keystrokes to all tabs simultaneously (ctrl+shift+b)

<h3 align="center">ai integration</h3>

- **nvidia nim api** — cloud ai via `/ai <query>` command with multiple model support
- **local fallback** — android auto-detects local gemma 4:4b llm server if cloud unavailable
- **command assistance** — get explanations, suggestions, and error analysis

<h3 align="center">developer tools</h3>

- **built-in editor** — full-featured text editor with undo/redo, syntax highlighting, find/replace
- **command aliases** — configure shortcuts (e.g., `g` → `git`, `gs` → `git status`)
- **smart autocomplete** — command suggestions based on history and context
- **search** — find text in terminal buffer with case-sensitivity toggle
- **copy mode** — scrollable, selectable view of terminal history (ctrl+shift+c)
- **hints mode** — letter overlays on urls/paths for quick keyboard access (ctrl+shift+h)
- **command palette** — fuzzy-find all actions (ctrl+shift+p)

<h3 align="center">customization</h3>

- **themes** — dark, light, and retro (amber-on-black crt aesthetic)
- **fonts** — cascadia code, fira code, jetbrains mono, source code pro, droid sans mono
- **opacity** — background transparency slider (50-100%)
- **zoom** — font size control (ctrl+=/ctrl+-/ctrl+0)
- **ligatures** — programming ligature support in compatible fonts

<h3 align="center">accessibility</h3>

- **screen reader support** — tts integration for interface elements
- **high contrast mode** — enhanced visibility option
- **color blind modes** — protanopia, deuteranopia, tritanopia filters
- **keyboard navigation** — full keyboard control with customizable shortcuts
- **font/cursor scaling** — adjustable sizes for visibility

<h3 align="center">platform-specific features</h3>

- **linux/macos/windows** — native window management with proper title bar
- **android** — landscape/portrait support, immersive mode
- **meta quest vr** — openxr integration with controller input mapping

<h3 align="center">performance & reliability</h3>

- **gpu rendering** — sub-16ms frame times for smooth scrolling
- **ring buffer scrollback** — memory-efficient with automatic compression
- **crash recovery** — session state saved for automatic restoration
- **health monitoring** — built-in diagnostics and error reporting

<h2 align="center">installation</h2>


<h3 align="center">prerequisites</h3>

- flutter sdk 3.29.0+ with dart 3.11.0+
- platform-specific build tools (xcode, android studio, visual studio, etc.)

<h3 align="center">build from source</h3>


```bash
<h1 align="center">clone the repository</h1>

git clone https://github.com/your-username/termisol.git
cd termisol

<h1 align="center">install dependencies</h1>

flutter pub get

<h1 align="center">run in development</h1>

flutter run -d linux      # or: android, windows, macos

<h1 align="center">build release</h1>

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

<h3 align="center">android apk</h3>


```bash
./build_apk.sh
<h1 align="center">apk output: build/app/outputs/flutter-apk/app-release.apk</h1>

```

<h2 align="center">configuration</h2>


settings are stored via sharedpreferences and persisted across sessions. configure through the in-app settings page or programmatically:

| setting | default | description |
|---------|---------|-------------|
| `scrollback_lines` | 50000 | maximum scrollback buffer size |
| `font_size` | 14.0 | terminal font size |
| `font_family` | droidsansmono | terminal font |
| `bg_opacity` | 1.0 | background opacity (0.5-1.0) |
| `ai.enabled` | true | enable ai features |
| `ai.api_key` | — | nvidia nim api key |

<h2 align="center">keyboard shortcuts</h2>


<h3 align="center">terminal</h3>

| shortcut | action |
|----------|--------|
| ctrl+n | new tab |
| ctrl+t | duplicate tab |
| ctrl+w | close tab |
| ctrl+shift+w | close all other tabs |
| ctrl+tab | next tab |
| ctrl+c | copy selection |
| ctrl+shift+c | send interrupt (sigint) |
| ctrl+v | paste |
| ctrl+a | select all / copy all content |
| ctrl+f | find in terminal |
| ctrl+shift+p | command palette |
| ctrl+shift+o | toggle performance overlay |
| ctrl+shift+b | toggle broadcast input |
| ctrl+shift+h | hints mode |
| ctrl+= / ctrl+- | zoom in / out |
| ctrl+0 | reset zoom |

<h3 align="center">built-in editor (`edit <filename>`)</h3>

| shortcut | action |
|----------|--------|
| ctrl+z | undo |
| ctrl+x | redo |
| ctrl+c | copy |
| ctrl+v | paste |
| ctrl+a | select all |
| ctrl+s | save |
| ctrl+o | open file |
| ctrl+w | close editor |
| ctrl+f | find |
| ctrl+shift+d | duplicate line |
| tab | indent (2 spaces) |

<h3 align="center">accessibility</h3>

| shortcut | action |
|----------|--------|
| ctrl+alt+a | toggle screen reader |
| ctrl+alt+h | toggle high contrast |
| ctrl+alt+f | increase font scale |
| ctrl+alt+d | decrease font scale |

<h2 align="center">ai commands</h2>


```bash
<h1 align="center">ask a question</h1>

/ai how do i find files larger than 100mb?

<h1 align="center">get command help</h1>

/ai explain: git rebase -i head~3

<h1 align="center">debug errors</h1>

/ai why is this failing: [paste error message]
```

<h2 align="center">architecture</h2>


```
lib/
├── main.dart              # entry point with error handling
├── app.dart               # root materialapp with vr detection
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
├── ai/                    # ai integration
│   ├── ai_terminal_assistant.dart
│   └── local_ai_service.dart
├── vr/                    # vr support
│   ├── vr_terminal_view.dart
│   └── openxr_session.dart
└── config/                # theming and configuration
    └── pkm_theme.dart

packages/
├── pty/                   # platform-specific pty bindings
└── xterm/                 # terminal emulation library
```

<h2 align="center">technical highlights</h2>


- **service registry pattern** — lazy-loading dependency injection reduces startup time
- **ring buffer scrollback** — memory-efficient with gzip compression for old lines
- **throttled rendering** — frame rate control prevents gpu saturation
- **backpressure flow control** — handles high-throughput output without blocking
- **session persistence** — automatic state saving with crash recovery

<h2 align="center">limitations</h2>


- **desktop ai is cloud-only** — no bundled local model; requires nvidia nim api access
- **graphics protocols** — sixel/kitty/iterm2 image protocols not rendered in terminal grid
- **android local ai** — opt-in; requires separate llm server app running locally

<h2 align="center">contributing</h2>


see [contributing.md](contributing.md) for development guidelines.

<h2 align="center">license</h2>


[the mates license](license)

---

<p align="center">
  built with flutter • powered by xterm.dart • ai by nvidia nim
</p>
