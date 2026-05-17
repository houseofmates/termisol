<h1 align="center">termisol</h1>

a terminal emulator built with flutter instead of a native toolkit. it uses the real xterm.dart package for terminal emulation and pty for shell integration. ai features are cloud-only via nvidia nim, with an optional local gemma 4:4b fallback on android if a local llm server is detected.

## made for

termisol was made for the way house works — the way a terminal should feel to use, not just look like. it was not designed for everyone, and that is the point.

## what makes it different

most terminal emulators are GTK or Qt apps that look and feel exactly the same. termisol is a flutter app that looks like something you'd want to leave open all day. it has a dark theme, a retro amber theme, a light theme, opacity sliders, monospaced fonts you actually like (cascadia code, fira code, jetbrains mono), and a built-in editor with syntax highlighting so you can stop opening gedit every time you need to edit a config file.

it also talks to nvidia nim via a slash command and can talk to a local gemma on android. it keeps an eye on how long your commands run and makes a sound when something needs your attention. it manages tabs the way a terminal should — duplicate, close others, close to the right, drag to reorder.

none of this was accidental. every feature is there because it is what the work actually needs.

## features

- **xterm-256color** emulation via xterm.dart with a real pty backend
- **tabs** — create, close, reorder, rename, duplicate, close-others, close-to-the-right
- **split panes** — horizontal and vertical, draggable resizers, double-click to equalize
- **directory tracking** — tab titles show the current working directory via osc 7 and prompt parsing
- **session restore** — reopens previous tabs with their working directories on startup
- **command aliases** — g becomes git, gs becomes git status, fully configurable in settings
- **copy mode** — ctrl+shift+c enters a scrollable, selectable view of terminal history
- **hints mode** — ctrl+shift+h overlays letter labels on urls, paths, and emails — type the letters to open them
- **broadcast input** — ctrl+shift+b sends every keystroke to every open tab simultaneously
- **osc 8 hyperlinks** — ctrl+click on urls printed by modern tools to open them
- **cloud ai** — /ai forwards to nvidia nim; requires api key and network
- **android local fallback** — if nim is unreachable on android, probes localhost for gemma 4:4b
- **themes** — dark, light, retro (amber-on-black)
- **fonts** — droidsansmono, fira code, jetbrains mono, cascadia code, source code pro
- **opacity** — background opacity slider from 50% to 100%
- **performance overlay** — ctrl+shift+o toggles an fps and frame-time hud
- **search** — ctrl+f finds text in the terminal buffer with a case-sensitive toggle
- **long command notifications** — audio alert and tab indicator when a command runs longer than 40 seconds
- **command palette** — ctrl+shift+p fuzzy-finds all available actions
- **zoom** — ctrl+= / ctrl+- / ctrl+0 to change font size
- **built-in editor** — syntax highlighting, ctrl+z undo, ctrl+s save, ctrl+w close, tab indent, auto-reindent on enter

## what it is not for

- **no offline ai on desktop** — desktop builds are cloud-only. no quantized model is bundled. if nim is unreachable, there is nowhere to fall back to.
- **no sixel, kitty, or iterm2 graphics in the terminal grid** — GraphicsProtocolHandler exists but is not wired into the active terminal view. if you need image previews in the terminal you are using the wrong tool.
- **not designed for everyone** — the alias system, the split panes, the broadcast input, the ai feature — these were all built for specific ways of working. if your terminal needs are different there is no obligation here.
- **android local fallback is opt-in** — it only activates if a local llm server is detected at startup on android. you cannot rely on it as a primary workflow.

## installation

```bash
# flutter must be on your PATH
export path="$home/flutter-sdk/bin:$path"

# install dependencies and run
flutter pub get
flutter run -d linux      # or android, windows, macos

# release build
flutter build linux --release
```

configuration lives in sharedpreferences and is persisted across sessions. the important keys to know about:

```
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

you can also reach the ai settings from inside the app through the settings page. no yaml editing required after the first time.

<h1 align="center">keyboard shortcuts</h1>

| shortcut | action |
|---|---|
| ctrl+n | new tab |
| ctrl+t | duplicate tab |
| ctrl+w | close tab |
| ctrl+shift+w | close all other tabs |
| ctrl+tab | next tab |
| ctrl+c | copy selected text |
| ctrl+shift+c | interrupt (original ctrl+c behavior) |
| ctrl+v | paste |
| ctrl+a | copy all terminal content |
| ctrl+f | find text in terminal |
| ctrl+shift+p | command palette |
| ctrl+shift+o | toggle performance overlay |
| ctrl+shift+b | toggle broadcast input |
| ctrl+shift+h | hints mode |
| ctrl+= / ctrl+- | zoom in / out |
| ctrl+0 | reset zoom |
| /ai <query> | ask nvidia nim a question |

<h1 align="center">license</h1>

<a href="file:///home/house/license_templates/mates_license.md">the mates license</a>
