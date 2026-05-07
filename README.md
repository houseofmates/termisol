# Termisol

A cross-platform, feature-rich terminal emulator built with Flutter. Termisol delivers a modern terminal experience on Linux desktop, Android (including Quest 2 VR), with advanced AI integration and extensive customization options.

## Features

### Terminal Core
- Full xterm-256color emulation via xterm.dart
- PTY support for local shells (bash, zsh, fish)
- Configurable scrollback buffer (up to 100,000 lines)
- Text selection with mouse and keyboard
- Bracketed paste mode support
- Copy-on-select option

### Tab Management
- Create/close/switch tabs with keyboard shortcuts
- Visual tab bar with dynamic titles
- Tab-specific working directories
- Shortcuts: `Ctrl+T` (new), `Ctrl+W` (close), `Ctrl+Tab` (next)

### Search
- Real-time search with `Ctrl+F`
- Case-sensitive/insensitive toggle
- Match counter and navigation
- Auto-scroll to matches

### Settings System
- YAML-based configuration with live reload
- Font family, size, and ligature support
- Cursor style and blink settings
- Color scheme customization
- Clipboard behavior controls
- Shell and working directory selection

### AI Integration (NVIDIA NIM)
- Natural language to shell command translation
- Command error analysis and suggestions
- Command safety checking
- Streaming responses
- Configurable endpoint and model selection

### VR Support (Quest 2)
- Holographic terminal view
- Hand tracking UI indicators
- Haptic feedback controls
- Virtual keyboard for VR input

### Performance
- Real-time FPS counter overlay
- Adaptive frame rate management
- Frame time history graphs
- GPU acceleration support

### Backends
- Local PTY (Linux, macOS, Windows)
- SSH remote connections via dartssh2
- Android shell support

## Getting Started

### Prerequisites
- Flutter SDK 3.22.0 or later
- Dart SDK 3.11.0 or later
- For Linux: GTK development headers
- For Android: Android SDK and NDK

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/termisol.git
cd termisol

# Install dependencies
flutter pub get

# Run on Linux
flutter run -d linux

# Run on Android
flutter run -d android

# Build release for Linux
flutter build linux

# Build APK for Android
flutter build apk

# Build Android App Bundle
flutter build appbundle
```

### Linux Packaging

#### DEB Package
```bash
flutter build linux --release
cd build/linux/x64/release/bundle
# Use a tool like `dpkg-deb` to package the bundle directory
```

#### AppImage
```bash
flutter build linux --release
# Use appimage-builder with the provided appimage/ configuration
```

### Configuration

User configuration is stored in `~/.config/termisol/config.yaml`. The default configuration can be overridden per-profile.

Example:
```yaml
terminal:
  scrollback_lines: 50000

font:
  family: "JetBrainsMono"
  size: 14.0

shell:
  type: "zsh"
  arguments: ["-l"]

ai:
  enabled: true
  api_key: "your-api-key"
  endpoint: "https://api.nvidia.com/nim"
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | New tab |
| `Ctrl+W` | Close tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+Shift+C` | Copy |
| `Ctrl+Shift+V` | Paste |
| `Ctrl+Shift+A` | Select all |
| `Ctrl+F` | Search |
| `Ctrl+,` | Settings |
| `Ctrl+=` | Zoom in |
| `Ctrl+-` | Zoom out |
| `Ctrl+0` | Reset zoom |

## Architecture

```
lib/
├── main.dart                 # Entry point
├── app.dart                  # Root app widget
├── config/                   # Configuration management
│   ├── config_manager.dart
│   ├── termisol_config.dart
│   └── termisol_config.yaml
├── core/                     # Terminal core
│   ├── terminal_engine.dart
│   ├── pty_handler.dart
│   └── performance_monitor.dart
├── ui/                       # User interface
│   ├── terminal_widget.dart
│   ├── tab_manager.dart
│   ├── clipboard_manager.dart
│   ├── search_overlay.dart
│   ├── settings_sheet.dart
│   ├── settings_items.dart
│   └── shortcut_manager.dart
├── backends/                 # Connection backends
│   ├── local_backend.dart
│   ├── ssh_backend.dart
│   └── android_shell_backend.dart
├── ai/                       # AI integration
│   ├── ai_assistant.dart
│   ├── ai_prompt_engine.dart
│   └── nvidia_nim_client.dart
└── vr/                       # VR support
    └── vr_terminal.dart
```

## Testing

```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/
```

## Contributing

Contributions are welcome. Please ensure:
- Code follows Flutter best practices
- All async operations have proper error handling
- Resources are properly disposed
- Tests are included for new features

## License

MIT License - see LICENSE file for details.
