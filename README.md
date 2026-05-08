# termisol

a next-generation terminal emulator built with Flutter for cross-platform excellence. Termisol combines the power of traditional terminals with cloud AI integration and a modern visual design.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## ✨ why termisol?

termisol is a complete command-line workspace designed for modern developers, system administrators, and power users who demand more from their terminal experience.

**what makes termisol different:**
- **cloud AI integration**: query external AI services from the terminal (requires API key)
- **smart file management**: built-in file browser with editing preview
- **performance optimized**: damage-aware terminal rendering with paragraph caching
- **cross-platform**: linux desktop and android mobile

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🚀 core features

### terminal excellence
- **full xterm-256color emulation** with complete VT100/VT220 compatibility
- **high-performance rendering** with GPU acceleration and sub-16ms frame times
- **intelligent scrollback buffer** supporting up to 100,000 lines with semantic search
- **advanced text selection** with keyboard and mouse support
- **bracketed paste mode** preventing accidental command execution
- **configurable cursor styles** with customizable blink rates

### tab management & workspace
- **dynamic tab system** with live previews and session persistence
- **smart tab grouping** for organizing related terminal sessions
- **tab-specific working directories** and shell configurations
- **quick switch navigation** with keyboard shortcuts and visual indicators
- **session synchronization** across devices and platforms

### search & navigation
- **real-time incremental search** with regex support
- **semantic command history** that understands what you're looking for
- **smart filtering** by command type, directory, or time period
- **quick jump navigation** to any line or command instantly

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🤖 AI integration

termisol features cutting-edge AI assistance that makes the command line accessible to everyone:

### natural language Processing
- **command translation**: type "show me all running processes" and get `ps aux`
- **intent recognition**: understands what you want to do, not just what you type
- **contextual suggestions**: learns your workflow and predicts your next commands
- **error analysis**: explains command failures in plain English and suggests fixes

### Ssmart features
- **code explanation**: hover over any code snippet for instant AI-powered explanations
- **performance optimization**: analyzes your commands and suggests faster alternatives
- **security monitoring**: warns about potentially dangerous commands before execution
- **learning m**: interactive tutorials that adapt to your skill level

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🎬 multimedia capabilities

### image viewer
- **comprehensive format support**: JPEG, PNG, WebP, AVIF, HEIC, TIFF, SVG
- **Iinteractive viewing**: zoom, pan, rotate with smooth animations
- **batch operations**: view multiple images in a gallery format
- **metadata display**: EXIF data and image information on demand

### video player
- **inline video playback** with full controls (play, pause, seek, volume)
- **format support**: MP4, WebM, AVI, MKV, MOV
- **subtitle rendering** with customizable styling
- **picture-in-picture mode** for multitasking

### audio visualizer
- **real-time audio visualization** with multiple visualization types
- **spectrum analyzer**, waveform display, and frequency bars
- **support for common audio formats**: MP3, WAV, FLAC, OGG
- **interactive controls** for playback and visualization settings

### 3D model viewer
- **3D model inspection** directly in the terminal
- **format support**: OBJ, STL, GLTF, PLY
- **interactive controls**: rotate, zoom, pan with mouse/touch
- **wireframe and solid rendering modes**

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🛠️ development Tools

### integrated file manager
- **dual-pane interface** with drag-and-drop support
- **editing preview** with syntax highlighting for 200+ languages
- **batch operations**: copy, move, delete, rename with undo support
- *file type detection** and appropriate application launching

### git integration
- **visual git operations**: commit, push, pull with GUI feedback
- **branch management** with merge conflict resolution
- **commit history visualization** with diff viewing
- **staging area management** with selective commits

### docker support
- **container management** directly from the terminal
- **image browsing** and layer inspection
- **log viewing** with real-time updates
- **resource monitoring** for running containers

### database client
- **multi-database support**: PostgreSQL, MySQL, SQLite, Redis
- **Query editor** with syntax highlighting and auto-completion
- **Result visualization** with export options
- **Connection management** with saved profiles

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🎨 User Interface & Experience

### Theming & Customization
- **20+ built-in themes** including dark, light, and high-contrast variants
- **Custom theme creation** with live preview
- **Font management** with ligature support and fallback handling
- **UI scaling** for high-DPI displays and accessibility

### Performance Monitoring
- **Real-time FPS counter** with frame time history
- **Resource usage monitoring** (CPU, memory, GPU)
- **Thermal management** with automatic performance scaling
- **Performance profiling** with bottleneck identification

### Smart Features
- **Global hotkeys** with customizable bindings
- **Native notifications** with sound alerts
- **Clipboard history** with intelligent filtering
- **Auto-completion** with fuzzy matching
- **Error detection** with automatic fix suggestions

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 📱 Platform Support

### Desktop (Linux)
- **Native performance** with GTK integration
- **System tray integration** with quick actions
- **Global menu support** with keyboard shortcuts
- **File association** handling for terminal applications

### Mobile (Android)
- **Touch-optimized interface** with gesture support
- **Virtual keyboard** with terminal-specific keys
- **Background execution** with notification controls
- **Export/import** of configurations and sessions

### VR (Meta Quest 2)
- **Immersive terminal environment** with 3D workspace
- **Hand tracking** for natural interaction
- **Haptic feedback** for tactile response
- **Multiple virtual monitors** for productivity

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🏗️ Architecture

Termisol is built with a modular, extensible architecture:

```
lib/
├── core/                      # Terminal engine and performance
│   ├── terminal_engine.dart   # Core terminal emulation
│   ├── pty_handler.dart       # PTY process management
│   ├── performance_monitor.dart # Real-time performance tracking
│   ├── adaptive_renderer.dart  # GPU-accelerated rendering
│   └── smart_memory_manager.dart # Memory optimization
├── ui/                        # User interface components
│   ├── terminal_view.dart     # Main terminal widget
│   ├── tab_manager.dart       # Tab system management
│   ├── file_manager.dart      # File browser interface
│   ├── video_player.dart      # Media playback controls
│   └── settings_sheet.dart    # Configuration interface
├── ai/                        # AI integration
│   ├── ai_assistant.dart      # Main AI coordinator
│   ├── nvidia_ai_client.dart  # NVIDIA NIM integration
│   └── local_ai_fallback.dart # Offline AI support
├── backends/                  # Connection backends
│   ├── local_backend.dart     # Local PTY connections
│   ├── ssh_backend.dart       # Remote SSH connections
│   └── android_shell.dart    # Android shell integration
├── multimedia/                # Media handling
│   ├── image_viewer.dart      # Image display and manipulation
│   ├── video_renderer.dart    # Video playback engine
│   ├── audio_visualizer.dart  # Audio visualization
│   └── model_3d_viewer.dart   # 3D model rendering
└── vr/                        # Virtual reality support
    ├── vr_terminal.dart       # VR terminal environment
    └── hand_tracking.dart     # VR interaction system
```

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK** 3.22.0 or later
- **Dart SDK** 3.11.0 or later
- **Platform-specific requirements**:
  - Linux: GTK development headers, libpty
  - Android: Android SDK and NDK
  - VR: Meta Quest 2 with developer mode

### Quick Start

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/termisol.git
cd termisol

# Install dependencies
flutter pub get

# Run on your preferred platform
flutter run -d linux          # Linux desktop
flutter run -d android        # Android device/emulator
flutter run -d windows        # Windows desktop
flutter run -d macos          # macOS desktop

# Build for release
flutter build linux --release
flutter build apk --release
flutter build appbundle --release
```

### Installation Packages

#### Linux
```bash
# DEB Package (Ubuntu/Debian)
sudo dpkg -i termisol_1.0.0_amd64.deb

# AppImage (Universal Linux)
chmod +x termisol.AppImage
./termisol.AppImage

# Tarball (Manual install)
tar -xzf termisol-linux-x64.tar.gz
./termisol/termisol
```

#### Android
```bash
# Install APK
adb install termisol-mobile-1.0.0.apk

# Or install from Google Play Store (link coming soon)
```

### First Run Configuration

On first launch, Termisol will guide you through:

1. **Shell Selection**: Choose your preferred shell (bash, zsh, fish, etc.)
2. **Theme Setup**: Select from pre-built themes or create custom
3. **AI Configuration**: Set up AI assistance with your preferred provider
4. **Keyboard Shortcuts**: Customize hotkeys for your workflow
5. **Performance Settings**: Optimize for your hardware

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## ⚙️ Configuration

Termisol uses YAML-based configuration stored in `~/.config/termisol/config.yaml`.

### Basic Configuration

```yaml
# Terminal settings
terminal:
  scrollback_lines: 50000
  font_family: "JetBrains Mono"
  font_size: 14.0
  cursor_style: "block"
  cursor_blink: true
  theme: "dark_plus"

# Shell configuration
shell:
  type: "zsh"
  arguments: ["-l"]
  working_directory: "~"

# AI integration
ai:
  enabled: true
  provider: "nvidia_nim"
  api_key: "your-api-key"
  endpoint: "https://api.nvidia.com/nim"
  model: "llama3-70b-instruct"
  local_fallback: true

# Performance settings
performance:
  gpu_acceleration: true
  max_fps: 144
  adaptive_quality: true
  memory_limit: "512MB"

# Multimedia
multimedia:
  image_viewer: true
  video_player: true
  audio_visualizer: true
  model_3d_viewer: true
```

### Advanced Configuration

```yaml
# Keyboard shortcuts
shortcuts:
  new_tab: "Ctrl+T"
  close_tab: "Ctrl+W"
  next_tab: "Ctrl+Tab"
  previous_tab: "Ctrl+Shift+Tab"
  search: "Ctrl+F"
  settings: "Ctrl+,"
  ai_assist: "Ctrl+Shift+A"

# Git integration
git:
  auto_commit: false
  sign_commits: true
  default_branch: "main"
  push_strategy: "current"

# Docker integration
docker:
  socket_path: "/var/run/docker.sock"
  default_registry: "docker.io"
  auto_prune_images: false

# Database connections
databases:
  postgres:
    host: "localhost"
    port: 5432
    default_database: "postgres"
  redis:
    host: "localhost"
    port: 6379
    database: 0
```

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## ⌨️ Keyboard Shortcuts

### Terminal Navigation
| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | New tab |
| `Ctrl+W` | Close current tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+Shift+V` | Paste |
| `Ctrl+Shift+A` | Select all |
| `Ctrl+F` | Find in terminal |
| `Ctrl+G` | Go to line |
| `Ctrl+L` | Clear screen |

### Window & UI
| Shortcut | Action |
|----------|--------|
| `Ctrl+,` | Open settings |
| `Ctrl+Shift+P` | Command palette |
| `F11` | Toggle fullscreen |
| `Ctrl+0` | Reset zoom |
| `Ctrl+Plus` | Zoom in |
| `Ctrl+Minus` | Zoom out |

### AI & Features
| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+A` | AI assistant |
| `Ctrl+Shift+E` | Explain code |
| `Ctrl+Shift+F` | Fix command |
| `Ctrl+Shift+H` | Command history |
| `Ctrl+Shift+M` | Open file manager |

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🧪 Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/termisol.git
cd termisol

# Install Flutter dependencies
flutter pub get

# Get native dependencies
flutter pub run build_runner build

# Run tests
flutter test

# Build for development
flutter run --debug

# Build for release
flutter build linux --release
```

### Testing

```bash
# Run all tests
flutter test

# Run unit tests only
flutter test test/unit/

# Run integration tests
flutter test test/integration/

# Generate test coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

### Contributing

We welcome contributions! Here's how to get started:

1. **Fork the repository** and create a feature branch
2. **Follow the code style** defined in `analysis_options.yaml`
3. **Add tests** for new features and ensure all tests pass
4. **Update documentation** for any API changes
5. **Submit a pull request** with a clear description

#### Development Guidelines
- Use `flutter analyze` to check code quality
- Follow Dart naming conventions
- Write meaningful commit messages
- Include tests for bug fixes and new features
- Document public APIs with dartdoc

### Plugin Development

Termisol supports a plugin system for extending functionality:

```dart
// Example plugin structure
class MyPlugin extends TerminalPlugin {
  @override
  void initialize(TerminalContext context) {
    // Plugin initialization
  }

  @override
  List<Command> registerCommands() {
    return [
      Command('mycommand', executeMyCommand),
    ];
  }
}
```

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🔧 Troubleshooting

### Common Issues

**Terminal not rendering properly**
```bash
# Check GPU acceleration
flutter config --enable-gpu

# Verify PTY permissions
ls -la /dev/ptmx
```

**AI integration not working**
```bash
# Check API key configuration
cat ~/.config/termisol/config.yaml | grep -A 5 ai:

# Test network connectivity
curl -I https://api.nvidia.com/nim
```

**Performance issues**
```bash
# Enable performance monitoring
export TERMISOL_DEBUG_PERFORMANCE=1
flutter run -d linux

# Check memory usage
flutter pub run devtools
```

### Debug Mode

Enable debug mode for detailed logging:

```bash
# Enable debug logging
export TERMISOL_DEBUG=1
flutter run -d linux

# Performance profiling
export TERMISOL_PROFILE=1
flutter run -d linux --profile
```

### Getting Help

- **GitHub Issues**: Report bugs and request features
- **Discord Community**: Join our developer community
- **Documentation**: Check our wiki for detailed guides
- **Email Support**: support@termisol.dev

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 📄 License

Termisol is released under the MIT License. See the [LICENSE](LICENSE) file for details.

### Third-Party Licenses

Termisol incorporates several open-source libraries:

- **Flutter**: BSD 3-Clause License
- **xterm.dart**: MIT License
- **dartssh2**: MIT License
- **provider**: MIT License

A full list of dependencies and their licenses can be found in `LICENSES.md`.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 🙏 Acknowledgments

Termisol stands on the shoulders of giants:

- **Flutter Team** for the amazing cross-platform framework
- **xterm.js** community for terminal emulation standards
- **NVIDIA** for AI infrastructure and support
- **Open Source Community** for countless libraries and tools

Special thanks to all contributors who have helped make Termisol better.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## 📞 Contact

- **Website**: [termisol.dev](https://termisol.dev)
- **GitHub**: [github.com/YOUR_USERNAME/termisol](https://github.com/YOUR_USERNAME/termisol)
- **Email**: hello@termisol.dev
- **Twitter**: [@termisol_term](https://twitter.com/termisol_term)

---

**Termisol** - The terminal, reimagined for the modern developer.
