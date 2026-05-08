# termisol

a terminal emulator built with Flutter. it uses the real `xterm.dart` package for terminal emulation and `pty` for shell integration. AI features are cloud-only via NVIDIA NIM, with an optional local gemma 4:4b fallback on Android if a local LLM server is detected.

## what it actually does

- **terminal emulation**: full xterm-256color via the `xterm.dart` package, with a real PTY backend
- **tabs**: create, close, reorder, and rename terminal tabs
- **cloud AI**: `/ai <query>` forwards to NVIDIA NIM. requires API key and network
- **android local fallback**: if NVIDIA NIM is unreachable on Android, probes localhost for a local gemma 4:4b model (Ollama/llama.cpp compatible endpoints)
- **real performance monitoring**: uses `SchedulerBinding.instance.addTimingsCallback` to collect actual `FrameTiming` data (build duration, raster duration, vsync overhead)
- **basic settings**: font size, theme, scrollback configured via `ProductionConfigSystem` backed by `SharedPreferences`

## what it does NOT do

- **no VR**: the `lib/vr/` OpenXR implementation was removed. it was incomplete fiction with compile errors
- **no custom GPU renderer**: rendering is handled by `xterm.dart`'s built-in `TerminalView`, wrapped in a `RepaintBoundary` for paint isolation
- **no offline AI on desktop**: desktop builds are cloud-only. no quantized model is bundled
- **no sixel/kitty/iterm2 graphics in the terminal grid**: `GraphicsProtocolHandler` exists in `lib/multimedia/` but is not wired into the active `TerminalView`
- **no "smart" features**: the ~300 files claiming intelligent this-and-that in `lib/core/` were aspirational fiction and are not imported by the working app

## architecture (honest)

```
lib/
├── main.dart                  # entry point, initializes error handling and performance monitoring
├── app.dart                   # MaterialApp with Varela Round theme
├── core/
│   ├── terminal_session.dart  # wraps xterm Terminal + TerminalController + PTY backend
│   ├── pty_backend.dart     # cross-platform PTY using the pty package
│   ├── termisol_core_integration.dart  # real frame timing metrics via SchedulerBinding
│   ├── gpu_renderer.dart      # honest name: just a RepaintBoundary wrapper
│   ├── service_registry.dart  # lazy-loading registry (only real services registered)
│   ├── service_factories.dart # only AI assistant and config system factories
│   └── robust_error_handler.dart # structured error logging
├── ai/
│   └── ai_terminal_assistant.dart  # NVIDIA NIM client with Android gemma fallback
├── ui/
│   ├── home_screen.dart       # tabs, toolbar, command palette
│   ├── terminal_view.dart     # wraps xterm TerminalView
│   ├── command_palette.dart   # quick actions
│   ├── search_overlay.dart    # find in terminal
│   └── edit.dart              # basic text editor
├── backends/
│   ├── local_backend.dart     # local shell
│   ├── ssh_backend.dart       # SSH via dartssh2
│   └── android_shell_backend.dart # Android shell
└── packages/
    ├── xterm/                 # local fork of xterm.dart (real terminal emulator)
    └── pty/                   # local PTY package
```

## getting started

```bash
flutter pub get
flutter run -d linux      # or android, windows, macos
```

## configuration

`ProductionConfigSystem` stores settings in `SharedPreferences`. key settings:

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
| `Ctrl+W` | close tab |
| `Ctrl+Tab` | next tab |
| `Ctrl+Shift+C` | copy |
| `Ctrl+Shift+V` | paste |
| `Ctrl+F` | find in terminal |
| `Ctrl+Shift+P` | command palette |

## AI usage

Type `/ai <question>` in the terminal. On desktop, this always goes to NVIDIA NIM. On Android, if the cloud request fails and a local gemma endpoint was detected at startup, it falls back to the local model.

## license

MIT License. See `LICENSE`.
