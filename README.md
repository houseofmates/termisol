<h1 align="center">termisol</h1>

<p align="center">
  <strong>a modern, gpu-accelerated terminal emulator built with flutter</strong>
</p>

<<<<<<< Updated upstream
<p align="center">
  cross-platform • ai-powered • vr-ready • designed for developers who demand more
</p>
=======
<h2 align="center">made for</h2>

>>>>>>> Stashed changes

<hr>

<<<<<<< Updated upstream
<h2 align="center">overview</h2>

<p align="center">termisol is a feature-rich terminal emulator that breaks from the gtk/qt mold by leveraging flutter's cross-platform capabilities and skia/impeller gpu rendering. it provides true <strong>xterm-256color</strong> emulation via the xterm.dart package with a real pty backend, delivering a responsive terminal experience across linux, macos, windows, android, and meta quest vr.</p>
=======
<h2 align="center">what makes it different</h2>


most terminal emulators are gtk or qt apps that look and feel exactly the same. termisol is a flutter app that looks like something you'd want to leave open all day. it has a dark theme, a retro amber theme, a light theme, opacity sliders, monospaced fonts you actually like (cascadia code, fira code, jetbrains mono), and a built-in editor with syntax highlighting so you can stop opening gedit every time you need to edit a config file.
>>>>>>> Stashed changes

<h2 align="center">key features</h2>

<h3 align="center">terminal emulation</h3>

<<<<<<< Updated upstream
- **xterm-256color** — full ansi/vt100 terminal emulation with 256-color support
- **real pty backend** — native pseudo-terminal on desktop, process-based on android
- **gpu-accelerated rendering** — skia/impeller backend targeting 60 fps
- **50,000-line scrollback** — configurable with memory-efficient compression
- **bracketed paste mode** — safe multiline paste handling
- **osc 8 hyperlinks** — ctrl+click to open urls from terminal output
=======
<h2 align="center">features</h2>

>>>>>>> Stashed changes

<h3 align="center">tab & pane management</h3>

<<<<<<< Updated upstream
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

<p align="center">flutter sdk 3.29.0+ with dart 3.11.0+<br>platform-specific build tools (xcode, android studio, visual studio, etc.)</p>

<h3 align="center">build from source</h3>

<pre align="center"><code>git clone https://github.com/your-username/termisol.git
cd termisol
flutter pub get
flutter run -d linux      # or: android, windows, macos
=======
<h2 align="center">what it is not for</h2>


- **no offline ai on desktop** — desktop builds are cloud-only. no quantized model is bundled. if nim is unreachable, there is nowhere to fall back to.
- **no sixel, kitty, or iterm2 graphics in the terminal grid** — graphicsprotocolhandler exists but is not wired into the active terminal view. if you need image previews in the terminal you are using the wrong tool.
- **not designed for everyone** — the alias system, the split panes, the broadcast input, the ai feature — these were all built for specific ways of working. if your terminal needs are different there is no obligation here.
- **android local fallback is opt-in** — it only activates if a local llm server is detected at startup on android. you cannot rely on it as a primary workflow.

<h2 align="center">installation</h2>


```bash
<h1 align="center">flutter must be on your path</h1>

export path="$home/flutter-sdk/bin:$path"

<h1 align="center">install dependencies and run</h1>

flutter pub get
flutter run -d linux      # or android, windows, macos

<h1 align="center">release build</h1>

>>>>>>> Stashed changes
flutter build linux --release
flutter build apk --release
flutter build windows --release
flutter build macos --release
</code></pre>

<h3 align="center">debian package</h3>

<pre align="center"><code>./build_deb.sh
sudo dpkg -i termisol_*.deb
</code></pre>

<h3 align="center">android apk</h3>

<pre align="center"><code>./build_apk.sh
# apk output: build/app/outputs/flutter-apk/app-release.apk
</code></pre>

<h2 align="center">configuration</h2>

<p align="center">settings are stored via sharedpreferences and persisted across sessions. configure through the in-app settings page or programmatically:</p>

<div align="center">
<table>
  <thead>
    <tr><th>setting</th><th>default</th><th>description</th></tr>
  </thead>
  <tbody>
    <tr><td><code>scrollback_lines</code></td><td>50000</td><td>maximum scrollback buffer size</td></tr>
    <tr><td><code>font_size</code></td><td>14.0</td><td>terminal font size</td></tr>
    <tr><td><code>font_family</code></td><td>droidsansmono</td><td>terminal font</td></tr>
    <tr><td><code>bg_opacity</code></td><td>1.0</td><td>background opacity (0.5-1.0)</td></tr>
    <tr><td><code>ai.enabled</code></td><td>true</td><td>enable ai features</td></tr>
    <tr><td><code>ai.api_key</code></td><td>—</td><td>nvidia nim api key</td></tr>
  </tbody>
</table>
</div>

<h2 align="center">keyboard shortcuts</h2>

<h3 align="center">terminal</h3>

<div align="center">
<table>
  <thead>
    <tr><th>shortcut</th><th>action</th></tr>
  </thead>
  <tbody>
    <tr><td>ctrl+n</td><td>new tab</td></tr>
    <tr><td>ctrl+t</td><td>duplicate tab</td></tr>
    <tr><td>ctrl+w</td><td>close tab</td></tr>
    <tr><td>ctrl+shift+w</td><td>close all other tabs</td></tr>
    <tr><td>ctrl+tab</td><td>next tab</td></tr>
    <tr><td>ctrl+c</td><td>copy selection</td></tr>
    <tr><td>ctrl+shift+c</td><td>send interrupt (sigint)</td></tr>
    <tr><td>ctrl+v</td><td>paste</td></tr>
    <tr><td>ctrl+a</td><td>select all / copy all content</td></tr>
    <tr><td>ctrl+f</td><td>find in terminal</td></tr>
    <tr><td>ctrl+shift+p</td><td>command palette</td></tr>
    <tr><td>ctrl+shift+o</td><td>toggle performance overlay</td></tr>
    <tr><td>ctrl+shift+b</td><td>toggle broadcast input</td></tr>
    <tr><td>ctrl+shift+h</td><td>hints mode</td></tr>
    <tr><td>ctrl+= / ctrl+-</td><td>zoom in / out</td></tr>
    <tr><td>ctrl+0</td><td>reset zoom</td></tr>
  </tbody>
</table>
</div>

<h3 align="center">built-in editor (<code>edit &lt;filename&gt;</code>)</h3>

<div align="center">
<table>
  <thead>
    <tr><th>shortcut</th><th>action</th></tr>
  </thead>
  <tbody>
    <tr><td>ctrl+z</td><td>undo</td></tr>
    <tr><td>ctrl+x</td><td>redo</td></tr>
    <tr><td>ctrl+c</td><td>copy</td></tr>
    <tr><td>ctrl+v</td><td>paste</td></tr>
    <tr><td>ctrl+a</td><td>select all</td></tr>
    <tr><td>ctrl+s</td><td>save</td></tr>
    <tr><td>ctrl+o</td><td>open file</td></tr>
    <tr><td>ctrl+w</td><td>close editor</td></tr>
    <tr><td>ctrl+f</td><td>find</td></tr>
    <tr><td>ctrl+shift+d</td><td>duplicate line</td></tr>
    <tr><td>tab</td><td>indent (2 spaces)</td></tr>
  </tbody>
</table>
</div>

<h3 align="center">accessibility</h3>

<div align="center">
<table>
  <thead>
    <tr><th>shortcut</th><th>action</th></tr>
  </thead>
  <tbody>
    <tr><td>ctrl+alt+a</td><td>toggle screen reader</td></tr>
    <tr><td>ctrl+alt+h</td><td>toggle high contrast</td></tr>
    <tr><td>ctrl+alt+f</td><td>increase font scale</td></tr>
    <tr><td>ctrl+alt+d</td><td>decrease font scale</td></tr>
  </tbody>
</table>
</div>

<h2 align="center">ai commands</h2>

<pre align="center"><code># ask a question
/ai how do i find files larger than 100mb?

# get command help
/ai explain: git rebase -i head~3

# debug errors
/ai why is this failing: [paste error message]
</code></pre>

<h2 align="center">architecture</h2>

<pre align="center"><code>lib/
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
</code></pre>

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

<p align="center">see <a href="contributing.md">contributing.md</a> for development guidelines.</p>

<h2 align="center">license</h2>

<p align="center"><a href="license">the mates license</a></p>

<hr>

<p align="center">
  built with flutter • powered by xterm.dart • ai by nvidia nim
</p>
