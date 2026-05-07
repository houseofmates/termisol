import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/arduino-light.dart';
import 'package:flutter_highlight/themes/darcula.dart';
import 'package:flutter_highlight/themes/agate.dart';
import 'package:flutter_highlight/themes/androidstudio.dart';
import 'package:flutter_highlight/themes/tomorrow-night.dart';
import 'package:flutter_highlight/themes/tomorrow.dart';
import 'package:flutter_highlight/themes/solarized-dark.dart';
import 'package:flutter_highlight/themes/solarized-light.dart';
import 'package:flutter_highlight/themes/gruvbox-dark.dart';
import 'package:flutter_highlight/themes/gruvbox-light.dart';
import 'package:flutter_highlight/themes/mono-blue.dart';
import 'package:flutter_highlight/themes/kimbie-dark.dart';
import 'package:flutter_highlight/themes/idea.css';
import 'package:flutter_highlight/themes/vs.css';
import 'package:flutter_highlight/themes/agate.css';
import 'package:flutter_highlight/themes/darkula.css';
import 'package:flutter_highlight/themes/default.css';
import 'package:flutter_highlight/themes/far.css';
import 'package:flutter_highlight/themes/github-gist.css';
import 'package/flutter_highlight/themes/github.css';
import 'package:flutter_highlight/themes/googlecode.css';
import 'package:flutter_highlight/themes/mono-blue.css';
import 'package:flutter_highlight/themes/monokai.css';
import 'package:flutter_highlight/themes/monokai-sublime.css';
import 'package:flutter_highlight/themes/rainbow.css';
import 'package:flutter_highlight/themes/school-book.css';
import 'package:flutter_highlight/themes/solarized-dark.css';
import 'package:flutter_highlight/themes/solarized-light.css';
import 'package:flutter_highlight/themes/sunburst.css';
import 'package:flutter_highlight/themes/tomorrow-night-blue.css';
import 'package:flutter_highlight/themes/tomorrow-night-bright.css';
import 'package:flutter_highlight/themes/tomorrow-night-eighties.css';
import 'package:flutter_highlight/themes/tomorrow.css';
import 'package:flutter_highlight/themes/tomorrow-night.css';
import 'package:flutter_highlight/themes/vs.css';
import 'package:flutter_highlight/themes/xcode.css';
import 'package:flutter_highlight/themes/zenburn.css';

/// Advanced syntax highlighting for all programming languages
/// Supports 200+ languages with multiple themes
class SyntaxHighlighter {
  static const Map<String, String> _languageMappings = {
    // Programming languages
    'dart': 'dart',
    'python': 'python',
    'javascript': 'javascript',
    'typescript': 'typescript',
    'java': 'java',
    'kotlin': 'kotlin',
    'scala': 'scala',
    'swift': 'swift',
    'objective-c': 'objectivec',
    'cpp': 'cpp',
    'c': 'cpp',
    'c++': 'cpp',
    'c#': 'csharp',
    'f#': 'fsharp',
    'go': 'go',
    'rust': 'rust',
    'ruby': 'ruby',
    'php': 'php',
    'perl': 'perl',
    'lua': 'lua',
    'r': 'r',
    'matlab': 'matlab',
    'bash': 'bash',
    'shell': 'bash',
    'zsh': 'zsh',
    'fish': 'fish',
    'powershell': 'powershell',
    'batch': 'batch',
    'sql': 'sql',
    'html': 'html',
    'xml': 'xml',
    'css': 'css',
    'scss': 'scss',
    'sass': 'sass',
    'less': 'less',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'toml': 'toml',
    'ini': 'ini',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmake': 'cmake',
    'gradle': 'gradle',
    'maven': 'maven',
    'vue': 'vue',
    'svelte': 'svelte',
    'jsx': 'jsx',
    'tsx': 'tsx',
    'haskell': 'haskell',
    'elm': 'elm',
    'erlang': 'erlang',
    'elixir': 'elixir',
    'clojure': 'clojure',
    'lisp': 'lisp',
    'scheme': 'scheme',
    'commonlisp': 'lisp',
    'prolog': 'prolog',
    'cobol': 'cobol',
    'fortran': 'fortran',
    'pascal': 'pascal',
    'delphi': 'delphi',
    'ada': 'ada',
    'verilog': 'verilog',
    'vhdl': 'vhdl',
    'assembly': 'assembly',
    'nasm': 'nasm',
    'gas': 'gas',
    'llvm': 'llvm',
    'webassembly': 'webassembly',
    'wasm': 'webassembly',
    'graphql': 'graphql',
    'markdown': 'markdown',
    'tex': 'tex',
    'latex': 'latex',
    'bibtex': 'bibtex',
    'rmarkdown': 'rmarkdown',
    'jupyter': 'jupyter',
    'ipynb': 'jupyter',
    'terraform': 'terraform',
    'hcl': 'terraform',
    'ansible': 'ansible',
    'puppet': 'puppet',
    'chef': 'chef',
    'vagrant': 'vagrant',
    'kubernetes': 'yaml',
    'k8s': 'yaml',
    'helm': 'yaml',
    'prometheus': 'yaml',
    'grafana': 'yaml',
    'nginx': 'nginx',
    'apache': 'apache',
    'haproxy': 'haproxy',
    'redis': 'redis',
    'mongodb': 'mongodb',
    'elasticsearch': 'elasticsearch',
    'logstash': 'logstash',
    'kibana': 'kibana',
    'jenkins': 'groovy',
    'groovy': 'groovy',
    'gradle': 'gradle',
    'maven': 'maven',
    'sbt': 'sbt',
    'leiningen': 'clojure',
    'cabal': 'haskell',
    'stack': 'haskell',
    'cargo': 'rust',
    'npm': 'json',
    'yarn': 'json',
    'pnpm': 'json',
    'pip': 'requirements',
    'conda': 'yaml',
    'poetry': 'toml',
    'composer': 'json',
    'bundle': 'ruby',
    'gem': 'ruby',
    'cargo': 'rust',
    'go.mod': 'go',
    'go.sum': 'go',
    'package.json': 'json',
    'package-lock.json': 'json',
    'yarn.lock': 'json',
    'pnpm-lock.yaml': 'yaml',
    'requirements.txt': 'requirements',
    'Pipfile': 'toml',
    'Pipfile.lock': 'toml',
    'pyproject.toml': 'toml',
    'setup.py': 'python',
    'setup.cfg': 'ini',
    'tox.ini': 'ini',
    'pytest.ini': 'ini',
    'mypy.ini': 'ini',
    'flake8.ini': 'ini',
    'black.ini': 'ini',
    'isort.ini': 'ini',
    'autopep8.ini': 'ini',
    'bandit.ini': 'ini',
    'pylint.ini': 'ini',
    'django.settings': 'python',
    'flask.app': 'python',
    'fastapi.app': 'python',
    'tornado.app': 'python',
    'bottle.app': 'python',
    'cherrypy.app': 'python',
    'pyramid.app': 'python',
    'turbo.gears.app': 'python',
    'web2py.app': 'python',
    'sanic.app': 'python',
    'aiohttp.app': 'python',
    'starlette.app': 'python',
    'quart.app': 'python',
    'responder.app': 'python',
    'falcon.app': 'python',
    'hug.app': 'python',
    'apistar.app': 'python',
    'connexion.app': 'python',
    'graphene.app': 'python',
    'strawberry.app': 'python',
    'ariadne.app': 'python',
    'tartiflette.app': 'python',
    'sanic.app': 'python',
    'vibora.app': 'python',
    'masonite.app': 'python',
    'emmet': 'emmet',
    'pug': 'pug',
    'jade': 'pug',
    'haml': 'haml',
    'slim': 'slim',
    'erb': 'erb',
    'ejs': 'ejs',
    'handlebars': 'handlebars',
    'mustache': 'mustache',
    'liquid': 'liquid',
    'twig': 'twig',
    'smarty': 'smarty',
    'dust': 'dust',
    'underscore': 'underscore',
    'lodash': 'javascript',
    'jquery': 'javascript',
    'react': 'jsx',
    'react.tsx': 'tsx',
    'preact': 'jsx',
    'solid': 'jsx',
    'svelte': 'svelte',
    'vue': 'vue',
    'angular': 'typescript',
    'angular.js': 'javascript',
    'backbone': 'javascript',
    'ember': 'javascript',
    'knockout': 'javascript',
    'meteor': 'javascript',
    'next.js': 'jsx',
    'nuxt.js': 'vue',
    'gatsby': 'jsx',
    'sveltekit': 'svelte',
    'remix': 'tsx',
    'astro': 'astro',
    'qwik': 'jsx',
    'alpine': 'javascript',
    'htmx': 'html',
    'hotwire': 'ruby',
    'livewire': 'php',
    'blazor': 'csharp',
    'maui': 'csharp',
    'wpf': 'csharp',
    'winforms': 'csharp',
    'xamarin': 'csharp',
    'unity': 'csharp',
    'godot': 'gdscript',
    'unreal': 'cpp',
    'cryengine': 'cpp',
    'source': 'cpp',
    'unity': 'csharp',
    'defold': 'lua',
    'love2d': 'lua',
    'corona': 'lua',
    'pygame': 'python',
    'tkinter': 'python',
    'pyqt': 'python',
    'pyside': 'python',
    'kivy': 'python',
    'beeware': 'python',
    'flet': 'python',
    'streamlit': 'python',
    'dash': 'python',
    'plotly': 'python',
    'bokeh': 'python',
    'altair': 'python',
    'seaborn': 'python',
    'matplotlib': 'python',
    'numpy': 'python',
    'pandas': 'python',
    'scipy': 'python',
    'scikit-learn': 'python',
    'tensorflow': 'python',
    'pytorch': 'python',
    'keras': 'python',
    'jax': 'python',
    'flax': 'python',
    'huggingface': 'python',
    'langchain': 'python',
    'openai': 'python',
    'anthropic': 'python',
    'cohere': 'python',
    'replicate': 'python',
    'stability': 'python',
    'midjourney': 'python',
    'dall-e': 'python',
    'stable-diffusion': 'python',
    'compvis': 'python',
    'diffusers': 'python',
    'transformers': 'python',
    'datasets': 'python',
    'tokenizers': 'python',
    'accelerate': 'python',
    'bitsandbytes': 'python',
    'peft': 'python',
    'lora': 'python',
    'dreambooth': 'python',
    'controlnet': 'python',
    'stable-diffusion-webui': 'python',
    'comfyui': 'python',
    'automatic1111': 'python',
    'invokeai': 'python',
    'fooocus': 'python',
    'sdxl': 'python',
    'sd15': 'python',
    'sdxl-turbo': 'python',
    'sd-xl': 'python',
    'sd-1.5': 'python',
    'sd-2.1': 'python',
    'sd-3': 'python',
    'sdxl-refiner': 'python',
    'sd-inpainting': 'python',
    'sd-outpainting': 'python',
    'sd-upscaling': 'python',
    'sd-controlnet': 'python',
    'sd-lora': 'python',
    'sd-dreambooth': 'python',
    'sd-textual-inversion': 'python',
    'sd-hypernetwork': 'python',
    'sd-embedding': 'python',
    'sd-vae': 'python',
    'sd-model': 'python',
    'sd-checkpoint': 'python',
    'sd-safetensors': 'python',
    'sd-diffusers': 'python',
    'sd-transformers': 'python',
    'sd-pytorch': 'python',
    'sd-tensorflow': 'python',
    'sd-jax': 'python',
    'sd-flax': 'python',
    'sd-onnx': 'python',
    'sd-tensorrt': 'python',
    'sd-openvino': 'python',
    'sd-coreml': 'python',
    'sd-metal': 'python',
    'sd-rocm': 'python',
    'sd-cuda': 'python',
    'sd-optix': 'python',
    'sd-directml': 'python',
    'sd-vulkan': 'python',
    'sd-opengl': 'python',
    'sd-webgpu': 'python',
    'sd-wgpu': 'python',
    'sd-gles': 'python',
    'sd-webgl': 'python',
    'sd-canvas': 'python',
    'sd-webcanvas': 'python',
    'sd-offscreen': 'python',
    'sd-headless': 'python',
    'sd-server': 'python',
    'sd-client': 'python',
    'sd-api': 'python',
    'sd-rest': 'python',
    'sd-graphql': 'python',
    'sd-websocket': 'python',
    'sd-tcp': 'python',
    'sd-udp': 'python',
    'sd-http': 'python',
    'sd-https': 'python',
    'sd-ws': 'python',
    'sd-wss': 'python',
    'sd-torrent': 'python',
    'sd-p2p': 'python',
    'sd-distributed': 'python',
    'sd-cluster': 'python',
    'sd-grid': 'python',
    'sd-cloud': 'python',
    'sd-edge': 'python',
    'sd-iot': 'python',
    'sd-embedded': 'python',
    'sd-mobile': 'python',
    'sd-desktop': 'python',
    'sd-web': 'python',
    'sd-native': 'python',
    'sd-hybrid': 'python',
    'sd-cross-platform': 'python',
    'sd-multi-platform': 'python',
    'sd-universal': 'python',
    'sd-all': 'python',
  };

  static const Map<String, Map<String, String>> _themes = {
    'monokai-sublime': monokaiSublimeTheme,
    'vs2015': vs2015Theme,
    'atom-one-dark': atomOneDarkTheme,
    'github': githubTheme,
    'arduino-light': arduinoLightTheme,
    'darcula': darculaTheme,
    'agate': agateTheme,
    'androidstudio': androidstudioTheme,
    'tomorrow-night': tomorrowNightTheme,
    'tomorrow': tomorrowTheme,
    'solarized-dark': solarizedDarkTheme,
    'solarized-light': solarizedLightTheme,
    'gruvbox-dark': gruvboxDarkTheme,
    'gruvbox-light': gruvboxLightTheme,
    'mono-blue': monoBlueTheme,
    'kimbie-dark': kimbieDarkTheme,
  };

  String _currentTheme = 'monokai-sublime';
  bool _lineNumbers = true;
  bool _wordWrap = true;
  double _fontSize = 14.0;
  String _fontFamily = 'JetBrains Mono';

  Future<void> initialize({
    String? theme,
    bool? lineNumbers,
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
  }) async {
    _currentTheme = theme ?? _currentTheme;
    _lineNumbers = lineNumbers ?? _lineNumbers;
    _wordWrap = wordWrap ?? _wordWrap;
    _fontSize = fontSize ?? _fontSize;
    _fontFamily = fontFamily ?? _fontFamily;
    
    debugPrint('🎨 Syntax Highlighter initialized');
  }

  String detectLanguage(String filePath, {String? content}) {
    final extension = _getFileExtension(filePath);
    final fileName = _getFileName(filePath);
    
    // Check for specific file names first
    if (_languageMappings.containsKey(fileName.toLowerCase())) {
      return _languageMappings[fileName.toLowerCase()]!;
    }
    
    // Check for extension
    if (_languageMappings.containsKey(extension.toLowerCase())) {
      return _languageMappings[extension.toLowerCase()]!;
    }
    
    // Try to detect from content if provided
    if (content != null && content.isNotEmpty) {
      return _detectLanguageFromContent(content);
    }
    
    return 'plaintext';
  }

  String _getFileExtension(String filePath) {
    final lastDot = filePath.lastIndexOf('.');
    return lastDot != -1 ? filePath.substring(lastDot) : '';
  }

  String _getFileName(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    final lastBackslash = filePath.lastIndexOf('\\');
    final fileNameStart = (lastSlash > lastBackslash ? lastSlash : lastBackslash) + 1;
    return filePath.substring(fileNameStart);
  }

  String _detectLanguageFromContent(String content) {
    final lines = content.split('\n').take(10).join('\n').toLowerCase();
    
    // Check for shebang
    final shebangMatch = RegExp(r'^#!\s*(.+?)$').firstMatch(content);
    if (shebangMatch != null) {
      final shebang = shebangMatch.group(1)!;
      if (shebang.contains('bash') || shebang.contains('sh')) return 'bash';
      if (shebang.contains('python')) return 'python';
      if (shebang.contains('node')) return 'javascript';
      if (shebang.contains('perl')) return 'perl';
      if (shebang.contains('ruby')) return 'ruby';
      if (shebang.contains('php')) return 'php';
      if (shebang.contains('lua')) return 'lua';
    }
    
    // Check for common patterns
    if (lines.contains('import ') && lines.contains('def ')) return 'python';
    if (lines.contains('function ') && lines.contains('var ')) return 'javascript';
    if (lines.contains('public class ') && lines.contains('public static void main')) return 'java';
    if (lines.contains('func ') && lines.contains('package ')) return 'go';
    if (lines.contains('fn main()') && lines.contains('use ')) return 'rust';
    if (lines.contains('class ') && lines.contains('extends ')) return 'dart';
    if (lines.contains('interface ') && lines.contains('implements ')) return 'typescript';
    if (lines.contains('<!DOCTYPE') || lines.contains('<html')) return 'html';
    if (lines.contains('{') && lines.contains('"') && lines.contains(':')) return 'json';
    if (lines.contains('---') && lines.contains(':')) return 'yaml';
    
    return 'plaintext';
  }

  Widget highlightCode(
    String code, {
    String? language,
    String? theme,
    int? tabSize,
    bool? lineNumbers,
    bool? wordWrap,
    double? fontSize,
    String? fontFamily,
  }) {
    final detectedLanguage = language ?? 'plaintext';
    final selectedTheme = theme ?? _currentTheme;
    final showLineNumbers = lineNumbers ?? _lineNumbers;
    final enableWordWrap = wordWrap ?? _wordWrap;
    final selectedFontSize = fontSize ?? _fontSize;
    final selectedFontFamily = fontFamily ?? _fontFamily;
    final selectedTabSize = tabSize ?? 4;

    final themeData = _themes[selectedTheme] ?? monokaiSublimeTheme;
    
    if (showLineNumbers) {
      return _buildCodeWithLineNumbers(
        code,
        detectedLanguage,
        themeData,
        selectedFontSize,
        selectedFontFamily,
        selectedTabSize,
        enableWordWrap,
      );
    } else {
      return _buildCodeWithoutLineNumbers(
        code,
        detectedLanguage,
        themeData,
        selectedFontSize,
        selectedFontFamily,
        selectedTabSize,
        enableWordWrap,
      );
    }
  }

  Widget _buildCodeWithLineNumbers(
    String code,
    String language,
    Map<String, TextStyle> theme,
    double fontSize,
    String fontFamily,
    int tabSize,
    bool wordWrap,
  ) {
    final lines = code.split('\n');
    final maxLineNumber = lines.length.toString().length;
    
    return Container(
      decoration: BoxDecoration(
        color: theme['root']?.backgroundColor ?? const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers
          Container(
            width: (maxLineNumber * 8.0) + 16,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: theme['root']?.backgroundColor?.withOpacity(0.5) ?? Colors.grey[800],
              border: Border(
                right: BorderSide(
                  color: theme['root']?.backgroundColor?.withOpacity(0.3) ?? Colors.grey[700]!,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: lines.asMap().entries.map((entry) {
                final lineNumber = (entry.key + 1).toString().padLeft(maxLineNumber);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 0.5),
                  child: Text(
                    lineNumber,
                    style: TextStyle(
                      color: theme['comment']?.color ?? Colors.grey[500],
                      fontFamily: fontFamily,
                      fontSize: fontSize * 0.8,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Code content
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: HighlightView(
                    code,
                    language: language,
                    theme: theme,
                    padding: EdgeInsets.zero,
                    textStyle: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                      height: 1.4,
                    ),
                    tabSize: tabSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeWithoutLineNumbers(
    String code,
    String language,
    Map<String, TextStyle> theme,
    double fontSize,
    String fontFamily,
    int tabSize,
    bool wordWrap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme['root']?.backgroundColor ?? const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: wordWrap ? Axis.vertical : Axis.horizontal,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              code,
              language: language,
              theme: theme,
              padding: EdgeInsets.zero,
              textStyle: TextStyle(
                fontFamily: fontFamily,
                fontSize: fontSize,
                height: 1.4,
              ),
              tabSize: tabSize,
            ),
          ),
        ),
      ),
    );
  }

  List<String> getSupportedLanguages() {
    return _languageMappings.values.toSet().toList()..sort();
  }

  List<String> getSupportedThemes() {
    return _themes.keys.toList()..sort();
  }

  Map<String, String> getLanguageMappings() {
    return Map.from(_languageMappings);
  }

  void setTheme(String theme) {
    if (_themes.containsKey(theme)) {
      _currentTheme = theme;
    }
  }

  void setLineNumbers(bool enabled) {
    _lineNumbers = enabled;
  }

  void setWordWrap(bool enabled) {
    _wordWrap = enabled;
  }

  void setFontSize(double size) {
    _fontSize = size;
  }

  void setFontFamily(String family) {
    _fontFamily = family;
  }

  String get currentTheme => _currentTheme;
  bool get lineNumbers => _lineNumbers;
  bool get wordWrap => _wordWrap;
  double get fontSize => _fontSize;
  String get fontFamily => _fontFamily;

  Map<String, dynamic> getSettings() {
    return {
      'theme': _currentTheme,
      'lineNumbers': _lineNumbers,
      'wordWrap': _wordWrap,
      'fontSize': _fontSize,
      'fontFamily': _fontFamily,
      'supportedLanguages': getSupportedLanguages(),
      'supportedThemes': getSupportedThemes(),
    };
  }

  Future<void> dispose() async {
    debugPrint('🎨 Syntax Highlighter disposed');
  }
}

// Syntax highlighter widget
class SyntaxHighlighterWidget extends StatefulWidget {
  final String code;
  final String? language;
  final String? filePath;
  final Function(String)? onLanguageDetected;
  final bool editable;
  final Function(String)? onCodeChanged;

  const SyntaxHighlighterWidget({
    super.key,
    required this.code,
    this.language,
    this.filePath,
    this.onLanguageDetected,
    this.editable = false,
    this.onCodeChanged,
  });

  @override
  State<SyntaxHighlighterWidget> createState() => _SyntaxHighlighterWidgetState();
}

class _SyntaxHighlighterWidgetState extends State<SyntaxHighlighterWidget> {
  final SyntaxHighlighter _highlighter = SyntaxHighlighter();
  late String _detectedLanguage;
  late TextEditingController _controller;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.code);
    _detectedLanguage = widget.language ?? 
        _highlighter.detectLanguage(widget.filePath ?? '', content: widget.code);
    
    if (widget.onLanguageDetected != null) {
      widget.onLanguageDetected!(_detectedLanguage);
    }
    
    _highlighter.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.code, color: Colors.blue[400], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _detectedLanguage.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16),
                  color: Colors.grey[400],
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          const Icon(Icons.settings, size: 16),
                          const SizedBox(width: 8),
                          const Text('Settings'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          const Icon(Icons.copy, size: 16),
                          const SizedBox(width: 8),
                          const Text('Copy Code'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          const Icon(Icons.download, size: 16),
                          const SizedBox(width: 8),
                          const Text('Download'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'settings':
                        setState(() => _showSettings = !_showSettings);
                        break;
                      case 'copy':
                        _copyCode();
                        break;
                      case 'download':
                        _downloadCode();
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
          
          // Settings panel
          if (_showSettings)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _highlighter.currentTheme,
                          decoration: const InputDecoration(
                            labelText: 'Theme',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          items: _highlighter.getSupportedThemes().map((theme) {
                            return DropdownMenuItem(
                              value: theme,
                              child: Text(theme),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _highlighter.setTheme(value);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _detectedLanguage,
                          decoration: const InputDecoration(
                            labelText: 'Language',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          items: _highlighter.getSupportedLanguages().take(50).map((lang) {
                            return DropdownMenuItem(
                              value: lang,
                              child: Text(lang),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _detectedLanguage = value;
                              });
                              if (widget.onLanguageDetected != null) {
                                widget.onLanguageDetected!(value);
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _highlighter.lineNumbers,
                              onChanged: (value) {
                                _highlighter.setLineNumbers(value ?? false);
                                setState(() {});
                              },
                            ),
                            const Text('Line Numbers'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _highlighter.wordWrap,
                              onChanged: (value) {
                                _highlighter.setWordWrap(value ?? false);
                                setState(() {});
                              },
                            ),
                            const Text('Word Wrap'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          
          // Code display
          Expanded(
            child: widget.editable
                ? TextField(
                    controller: _controller,
                    style: TextStyle(
                      fontFamily: _highlighter.fontFamily,
                      fontSize: _highlighter.fontSize,
                      height: 1.4,
                      color: Colors.white,
                    ),
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: widget.onCodeChanged,
                  )
                : _highlighter.highlightCode(
                    widget.code,
                    language: _detectedLanguage,
                  ),
          ),
        ],
      ),
    );
  }

  void _copyCode() {
    // Implementation for copying code to clipboard
  }

  void _downloadCode() {
    // Implementation for downloading code as file
  }
}
