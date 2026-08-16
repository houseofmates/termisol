<h1 align="center">termisol</h1>

<p align="center">
  <strong>a modern, gpu-accelerated terminal emulator built with flutter</strong>
</p>

<p align="center">
  cross-platform • ai-powered • vr-ready • designed for developers who demand more
</p>

<div align="center">
  <img src="https://img.shields.io/badge/flutter-3.29+-10b981?style=flat-square" alt="flutter" />
  <img src="https://img.shields.io/badge/license-mates-green?style=flat-square" alt="license" />
</div>

<hr>

## made for

termisol was built because most terminal emulators look like they were designed by a committee that never met. this is a flutter app that looks like something you'd want to leave open all day. it has a dark theme, a retro amber theme, a light theme, opacity sliders, monospaced fonts you actually like (cascadia code, fira code, jetbrains mono), and a built-in editor with syntax highlighting so you can stop opening gedit every time you need to edit a config file.

## what makes it different

most terminal emulators are gtk or qt apps that look and feel exactly the same. termisol is a flutter app that looks like something you'd want to leave open all day. the mood is the point: dark theme, low contrast but high readability, no floating action buttons, no card heaviness. the gpu rendering via skia/impeller targets 60 fps so scrolling through thousands of lines feels smooth. and the built-in ai integration via nvidia nim is for those moments when you've been staring at an error message for too long.

## features

### terminal emulation
- **xterm-256color** — full ansi/vt100 terminal emulation with 256-color support
- **real pty backend** — native pseudo-terminal on desktop, process-based on android
- **gpu-accelerated rendering** — skia/impeller backend targeting 60 fps
- **50,000-line scrollback** — configurable with memory-efficient compression
- **bracketed paste mode** — safe multiline paste handling
- **osc 8 hyperlinks** — ctrl+click to open urls from terminal output

### tab & pane management
- **tabbed interface** — create, close, rename, duplicate, reorder tabs via drag
- **split panes** — horizontal and vertical splits with draggable dividers
- **session persistence** — restore previous tabs and working directories on restart
- **directory tracking** — tab titles auto-update via osc 7 and prompt parsing
- **broadcast input** — send keystrokes to all tabs simultaneously (ctrl+shift+b)

### ai integration
- **nvidia nim api** — cloud ai via `/ai <query>` command with multiple model support
- **local fallback** — android auto-detects local gemma 4:4b llm server if cloud unavailable
- **command assistance** — get explanations, suggestions, and error analysis

### developer tools
- **built-in editor** — full-featured text editor with undo/redo, syntax highlighting, find/replace
- **command aliases** — configure shortcuts (e.g., `g` → `git`, `gs` → `git status`)
- **smart autocomplete** — command suggestions based on history and context
- **search** — find text in terminal buffer with case-sensitivity toggle
- **copy mode** — scrollable, selectable view of terminal history (ctrl+shift+c)
- **hints mode** — letter overlays on urls/paths for quick keyboard access (ctrl+shift+h)
- **command palette** — fuzzy-find all actions (ctrl+shift+p)

### customization
- **themes** — dark, light, and retro (amber-on-black crt aesthetic)
- **fonts** — cascadia code, fira code, jetbrains mono, source code pro, droid sans mono
- **opacity** — background transparency slider (50-100%)
- **zoom** — font size control (ctrl+=/ctrl+-/ctrl+0)
- **ligatures** — programming ligature support in compatible fonts

### accessibility
- **screen reader support** — tts integration for interface elements
- **high contrast mode** — enhanced visibility option
- **color blind modes** — protanopia, deuteranopia, tritanopia filters
- **keyboard navigation** — full keyboard control with customizable shortcuts
- **font/cursor scaling** — adjustable sizes for visibility

### platform-specific features
- **linux/macos/windows** — native window management with proper title bar
- **android** — landscape/portrait support, immersive mode
- **meta quest vr** — openxr integration with controller input mapping

### performance & reliability
- **gpu rendering** — sub-16ms frame times for smooth scrolling
- **ring buffer scrollback** — memory-efficient with gzip compression for old lines
- **throttled rendering** — frame rate control prevents gpu saturation
- **backpressure flow control** — handles high-throughput output without blocking
- **session persistence** — automatic state saving with crash recovery
- **health monitoring** — built-in diagnostics and error reporting

<hr>

## what it is not for

- **no offline ai on desktop** — desktop builds are cloud-only. no quantized model is bundled. if nim is unreachable, there is nowhere to fall back to.
- **no sixel, kitty, or iterm2 graphics in the terminal grid** — graphics protocol handler exists but is not wired into the active terminal view. if you need image previews in the terminal you are using the wrong tool.
- **android local ai is opt-in** — it only activates if a local llm server is detected at startup on android. you cannot rely on it as a primary workflow.
- **not designed for everyone** — the alias system, the split panes, the broadcast input, the ai feature — these were all built for specific ways of working. if your terminal needs are different there is no obligation here.

<hr>

## installation

### prerequisites
flutter sdk 3.29.0+ with dart 3.11.0+
platform-specific build tools (xcode, android studio, visual studio, etc.)

### build from source
```bash
git clone https://github.com/your-username/termisol.git
cd termisol
flutter pub get
flutter run -d linux      # or: android, windows, macos
```

### release build
```bash
flutter build linux --release
flutter build apk --release
flutter build windows --release
flutter build macos --release
```

### debian package
```bash
./build_deb.sh
sudo dpkg -i termisol_*.deb
```

### android apk
```bash
./build_apk.sh
# apk output: build/app/outputs/flutter-apk/app-release.apk
```

<hr>

## configuration

settings are stored via sharedpreferences and persisted across sessions. configure through the in-app settings page or programmatically:

| setting            | default          | description                              |
|--------------------|------------------|------------------------------------------|
| `scrollback_lines` | 50000            | maximum scrollback buffer size           |
| `font_size`        | 14.0             | terminal font size                       |
| `font_family`      | droidsansmono    | terminal font                            |
| `bg_opacity`       | 1.0              | background opacity (0.5-1.0)             |
| `ai.enabled`       | true             | enable ai features                       |
| `ai.api_key`       | —                | nvidia nim api key (stored encrypted)    |

> **security note:** the `ai.api_key` is stored using `flutter_secure_storage`, not sharedpreferences. on android this uses the keystore system; on linux it uses the gnome keyring or a file-based fallback. if flutter_secure_storage fails to initialize, the key will not be persisted and you will need to re-enter it on each launch.

## environment variables

| variable               | default           | description                              |
|------------------------|-------------------|------------------------------------------|
| `TERMISOL_LLM_URL`     | see config        | local llm server url for fallback        |
| `TERMISOL_PROXY_URL`   | `http://localhost`| proxy configuration for network requests |

<hr>

## keyboard shortcuts

### terminal
| shortcut         | action                          |
|------------------|---------------------------------|
| ctrl+n           | new tab                         |
| ctrl+t           | duplicate tab                   |
| ctrl+w           | close tab                       |
| ctrl+shift+w     | close all other tabs            |
| ctrl+tab         | next tab                        |
| ctrl+c           | copy selection                  |
| ctrl+shift+c     | send interrupt (sigint)         |
| ctrl+v           | paste                           |
| ctrl+a           | select all / copy all content   |
| ctrl+f           | find in terminal                |
| ctrl+shift+p     | command palette                 |
| ctrl+shift+o     | toggle performance overlay      |
| ctrl+shift+b     | toggle broadcast input          |
| ctrl+shift+h     | hints mode                      |
| ctrl+= / ctrl+-  | zoom in / out                   |
| ctrl+0           | reset zoom                      |

### built-in editor (`edit <filename>`)
| shortcut         | action                          |
|------------------|---------------------------------|
| ctrl+z           | undo                            |
| ctrl+x           | redo                            |
| ctrl+c           | copy                            |
| ctrl+v           | paste                           |
| ctrl+a           | select all                      |
| ctrl+s           | save                            |
| ctrl+o           | open file                       |
| ctrl+w           | close editor                    |
| ctrl+f           | find                            |
| ctrl+shift+d     | duplicate line                  |
| tab              | indent (2 spaces)               |

### accessibility
| shortcut         | action                          |
|------------------|---------------------------------|
| ctrl+alt+a       | toggle screen reader            |
| ctrl+alt+h       | toggle high contrast            |
| ctrl+alt+f       | increase font scale             |
| ctrl+alt+d       | decrease font scale             |

<hr>

## ai commands

```bash
# ask a question
/ai how do i find files larger than 100mb?

# get command help
/ai explain: git rebase -i head~3

# debug errors
/ai why is this failing: [paste error message]
```

<hr>

## architecture
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

## technical highlights

- **service registry pattern** — lazy-loading dependency injection reduces startup time
- **ring buffer scrollback** — memory-efficient with gzip compression for old lines
- **throttled rendering** — frame rate control prevents gpu saturation
- **backpressure flow control** — handles high-throughput output without blocking
- **session persistence** — automatic state saving with crash recovery

<hr>

## contributing

see [contributing.md](./contributing.md) for development guidelines.

<hr>

## license

<a href="./LICENSE">the mates license</a>
