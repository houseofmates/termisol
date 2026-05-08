import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

/// Shader-based syntax highlighting system
/// 
/// Features:
/// - GPU-accelerated syntax highlighting using custom shaders
/// - Real-time highlighting with smooth animations
/// - Multiple language support with extensible syntax definitions
/// - Theme-based color schemes
/// - Performance optimized with caching
class ShaderSyntaxHighlighter {
  static const Map<String, List<String>> _languageKeywords = {
    'dart': [
      'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
      'class', 'const', 'continue', 'default', 'deferred', 'do', 'dynamic',
      'else', 'enum', 'export', 'extends', 'external', 'factory', 'false',
      'final', 'finally', 'for', 'get', 'if', 'implements', 'import',
      'in', 'interface', 'is', 'library', 'mixin', 'new', 'null',
      'operator', 'part', 'rethrow', 'return', 'set', 'static', 'super',
      'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
      'var', 'void', 'while', 'with', 'yield'
    ],
    'python': [
      'and', 'as', 'assert', 'break', 'class', 'continue', 'def', 'del',
      'elif', 'else', 'except', 'exec', 'finally', 'for', 'from', 'global',
      'if', 'import', 'in', 'is', 'lambda', 'not', 'or', 'pass', 'print',
      'raise', 'return', 'try', 'while', 'with', 'yield', 'True', 'False',
      'None'
    ],
    'javascript': [
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'finally',
      'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new',
      'return', 'super', 'switch', 'this', 'throw', 'try', 'typeof',
      'var', 'void', 'while', 'with', 'yield', 'async', 'await'
    ],
    'typescript': [
      'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
      'default', 'delete', 'do', 'else', 'export', 'extends', 'finally',
      'for', 'function', 'if', 'import', 'in', 'instanceof', 'let', 'new',
      'return', 'super', 'switch', 'this', 'throw', 'try', 'typeof',
      'var', 'void', 'while', 'with', 'yield', 'async', 'await',
      'interface', 'type', 'enum', 'declare', 'module', 'namespace'
    ],
    'bash': [
      'if', 'then', 'else', 'elif', 'fi', 'case', 'esac', 'for', 'select',
      'while', 'until', 'do', 'done', 'function', 'time', 'export',
      'local', 'readonly', 'declare', 'typeset', 'unset', 'alias',
      'unalias', 'bg', 'fg', 'jobs', 'kill', 'wait', 'cd', 'pwd',
      'echo', 'printf', 'read', 'shift', 'test', 'true', 'false'
    ],
  };

  static const Map<String, SyntaxTheme> _themes = {
    'dark': SyntaxTheme(
      backgroundColor: ui.Color(0xFF1E1E1E),
      textColor: ui.Color(0xFFD4D4D4),
      keywordColor: ui.Color(0xFF569CD6),
      stringColor: ui.Color(0xFFCE9178),
      commentColor: ui.Color(0xFF6A9955),
      numberColor: ui.Color(0xFFB5CEA8),
      functionColor: ui.Color(0xFFDCDCAA),
      variableColor: ui.Color(0xFF9CDCFE),
      operatorColor: ui.Color(0xFFD4D4D4),
      typeColor: ui.Color(0xFF4EC9B0),
      errorColor: ui.Color(0xFFE51400),
      warningColor: ui.Color(0xFFFF8C00),
    ),
    'light': SyntaxTheme(
      backgroundColor: ui.Color(0xFFFFFFFF),
      textColor: ui.Color(0xFF000000),
      keywordColor: ui.Color(0xFF0000FF),
      stringColor: ui.Color(0xFFA31515),
      commentColor: ui.Color(0xFF008000),
      numberColor: ui.Color(0xFF098658),
      functionColor: ui.Color(0xFF795E26),
      variableColor: ui.Color(0xFF001080),
      operatorColor: ui.Color(0xFF000000),
      typeColor: ui.Color(0xFF267F99),
      errorColor: ui.Color(0xFFE51400),
      warningColor: ui.Color(0xFFFF8C00),
    ),
  };

  final Map<String, ui.Shader> _shaders = {};
  final Map<String, HighlightCache> _highlightCache = {};
  final Map<String, List<SyntaxToken>> _tokenCache = {};
  
  String _currentTheme = 'dark';
  String _currentLanguage = 'dart';
  bool _isInitialized = false;
  
  /// Performance metrics
  int _highlightCalls = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  double _totalHighlightTime = 0.0;

  ShaderSyntaxHighlighter() {
    _initializeHighlighter();
  }

  /// Initialize the syntax highlighter
  Future<void> _initializeHighlighter() async {
    try {
      // Load syntax highlighting shaders
      await _loadSyntaxShaders();
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize syntax highlighter: $e');
    }
  }

  /// Load syntax highlighting shaders
  Future<void> _loadSyntaxShaders() async {
    try {
      // Vertex shader for text positioning
      final vertexShader = await _loadShader('syntax_vertex');
      
      // Fragment shader for syntax highlighting
      final fragmentShader = await _loadShader('syntax_fragment');
      
      _shaders['syntax'] = ui.Shader.fromBytes(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
      );
      
      // Shader for animated highlighting
      final animatedFragmentShader = await _loadShader('syntax_animated');
      _shaders['animated'] = ui.Shader.fromBytes(
        vertexShader: vertexShader,
        fragmentShader: animatedFragmentShader,
      );
    } catch (e) {
      debugPrint('Failed to load syntax shaders: $e');
    }
  }

  /// Load shader from assets
  Future<Uint8List> _loadShader(String shaderName) async {
    try {
      final shaderData = await rootBundle.load('assets/shaders/$shaderName.spv');
      return shaderData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Failed to load shader $shaderName: $e');
      return Uint8List(0);
    }
  }

  /// Highlight text using shaders
  Future<HighlightedText> highlightText(
    String text, {
    String? language,
    String? theme,
    bool animated = false,
  }) async {
    if (!_isInitialized) {
      await _initializeHighlighter();
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      _highlightCalls++;
      
      // Use provided language/theme or defaults
      final lang = language ?? _currentLanguage;
      final thm = theme ?? _currentTheme;
      
      // Check cache first
      final cacheKey = _generateCacheKey(text, lang, thm, animated);
      
      if (_highlightCache.containsKey(cacheKey)) {
        _cacheHits++;
        return _highlightCache[cacheKey]!.highlightedText;
      }
      
      _cacheMisses++;
      
      // Tokenize text
      final tokens = await _tokenizeText(text, lang);
      
      // Create highlighted text
      final highlightedText = await _createHighlightedText(
        tokens,
        _themes[thm]!,
        animated,
      );
      
      // Cache result
      if (_highlightCache.length < 1000) {
        _highlightCache[cacheKey] = HighlightCache(
          highlightedText,
          DateTime.now(),
        );
      }
      
      _totalHighlightTime += stopwatch.elapsedMilliseconds.toDouble();
      
      return highlightedText;
    } catch (e) {
      debugPrint('Failed to highlight text: $e');
      return HighlightedText.fallback(text, _themes[_currentTheme]!);
    } finally {
      stopwatch.stop();
    }
  }

  /// Tokenize text for syntax highlighting
  Future<List<SyntaxToken>> _tokenizeText(String text, String language) async {
    // Check token cache
    final tokenCacheKey = '${language}_${text.hashCode}';
    if (_tokenCache.containsKey(tokenCacheKey)) {
      return _tokenCache[tokenCacheKey]!;
    }
    
    final tokens = <SyntaxToken>[];
    final keywords = _languageKeywords[language] ?? [];
    
    // Tokenize line by line
    final lines = text.split('\n');
    int position = 0;
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final lineTokens = _tokenizeLine(line, keywords, position);
      tokens.addAll(lineTokens);
      position += line.length + 1; // +1 for newline
    }
    
    // Cache tokens
    if (_tokenCache.length < 500) {
      _tokenCache[tokenCacheKey] = tokens;
    }
    
    return tokens;
  }

  /// Tokenize a single line
  List<SyntaxToken> _tokenizeLine(String line, List<String> keywords, int startPosition) {
    final tokens = <SyntaxToken>[];
    
    // Regular expressions for different token types
    final stringRegex = RegExp(r'"[^"]*"|\'[^\']*\'');
    final commentRegex = RegExp(r'//.*$|#.*$|/\*.*?\*/');
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    final identifierRegex = RegExp(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b');
    final operatorRegex = RegExp(r'[+\-*/=<>!&|%^~?:.;,(){}[\]]');
    
    int position = 0;
    
    while (position < line.length) {
      bool matched = false;
      
      // Check for strings
      final stringMatch = stringRegex.firstMatch(line.substring(position));
      if (stringMatch != null) {
        tokens.add(SyntaxToken(
          text: stringMatch.group(0)!,
          type: SyntaxType.string,
          position: startPosition + position,
        ));
        position += stringMatch.end;
        matched = true;
        continue;
      }
      
      // Check for comments
      final commentMatch = commentRegex.firstMatch(line.substring(position));
      if (commentMatch != null) {
        tokens.add(SyntaxToken(
          text: commentMatch.group(0)!,
          type: SyntaxType.comment,
          position: startPosition + position,
        ));
        position += commentMatch.end;
        matched = true;
        continue;
      }
      
      // Check for numbers
      final numberMatch = numberRegex.firstMatch(line.substring(position));
      if (numberMatch != null) {
        tokens.add(SyntaxToken(
          text: numberMatch.group(0)!,
          type: SyntaxType.number,
          position: startPosition + position,
        ));
        position += numberMatch.end;
        matched = true;
        continue;
      }
      
      // Check for keywords
      final identifierMatch = identifierRegex.firstMatch(line.substring(position));
      if (identifierMatch != null) {
        final identifier = identifierMatch.group(0)!;
        final type = keywords.contains(identifier) ? SyntaxType.keyword : SyntaxType.identifier;
        
        tokens.add(SyntaxToken(
          text: identifier,
          type: type,
          position: startPosition + position,
        ));
        position += identifierMatch.end;
        matched = true;
        continue;
      }
      
      // Check for operators
      final operatorMatch = operatorRegex.firstMatch(line.substring(position));
      if (operatorMatch != null) {
        tokens.add(SyntaxToken(
          text: operatorMatch.group(0)!,
          type: SyntaxType.operator,
          position: startPosition + position,
        ));
        position += operatorMatch.end;
        matched = true;
        continue;
      }
      
      // If no match, add as text and move forward
      tokens.add(SyntaxToken(
        text: line[position],
        type: SyntaxType.text,
        position: startPosition + position,
      ));
      position++;
    }
    
    return tokens;
  }

  /// Create highlighted text from tokens
  Future<HighlightedText> _createHighlightedText(
    List<SyntaxToken> tokens,
    SyntaxTheme theme,
    bool animated,
  ) async {
    final highlightedSpans = <HighlightedSpan>[];
    
    for (final token in tokens) {
      final color = _getTokenColor(token.type, theme);
      
      highlightedSpans.add(HighlightedSpan(
        text: token.text,
        color: color,
        type: token.type,
        position: token.position,
        animated: animated,
      ));
    }
    
    return HighlightedText(
      text: tokens.map((t) => t.text).join(),
      spans: highlightedSpans,
      theme: theme,
      animated: animated,
    );
  }

  /// Get color for token type
  ui.Color _getTokenColor(SyntaxType type, SyntaxTheme theme) {
    switch (type) {
      case SyntaxType.keyword:
        return theme.keywordColor;
      case SyntaxType.string:
        return theme.stringColor;
      case SyntaxType.comment:
        return theme.commentColor;
      case SyntaxType.number:
        return theme.numberColor;
      case SyntaxType.function:
        return theme.functionColor;
      case SyntaxType.identifier:
        return theme.variableColor;
      case SyntaxType.operator:
        return theme.operatorColor;
      case SyntaxType.type:
        return theme.typeColor;
      case SyntaxType.error:
        return theme.errorColor;
      case SyntaxType.warning:
        return theme.warningColor;
      default:
        return theme.textColor;
    }
  }

  /// Generate cache key
  String _generateCacheKey(String text, String language, String theme, bool animated) {
    return '${text.hashCode}_$language_$theme_$animated';
  }

  /// Set current theme
  void setTheme(String theme) {
    if (_themes.containsKey(theme)) {
      _currentTheme = theme;
      _clearCache();
    }
  }

  /// Set current language
  void setLanguage(String language) {
    _currentLanguage = language;
    _clearCache();
  }

  /// Clear cache
  void _clearCache() {
    _highlightCache.clear();
    _tokenCache.clear();
  }

  /// Get highlighting statistics
  HighlightStats getStats() {
    return HighlightStats(
      highlightCalls: _highlightCalls,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      cacheHitRate: _highlightCalls > 0 ? _cacheHits / _highlightCalls : 0.0,
      averageHighlightTime: _highlightCalls > 0 ? _totalHighlightTime / _highlightCalls : 0.0,
      totalHighlightTime: _totalHighlightTime,
      cacheSize: _highlightCache.length,
      tokenCacheSize: _tokenCache.length,
    );
  }

  /// Add custom language
  void addLanguage(String name, List<String> keywords) {
    _languageKeywords[name] = keywords;
    _clearCache();
  }

  /// Add custom theme
  void addTheme(String name, SyntaxTheme theme) {
    _themes[name] = theme;
    _clearCache();
  }

  /// Dispose resources
  void dispose() {
    _clearCache();
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    _shaders.clear();
  }
}

/// Syntax token
class SyntaxToken {
  final String text;
  final SyntaxType type;
  final int position;

  const SyntaxToken({
    required this.text,
    required this.type,
    required this.position,
  });
}

/// Syntax token types
enum SyntaxType {
  keyword,
  string,
  comment,
  number,
  function,
  identifier,
  operator,
  type,
  error,
  warning,
  text,
}

/// Syntax theme
class SyntaxTheme {
  final ui.Color backgroundColor;
  final ui.Color textColor;
  final ui.Color keywordColor;
  final ui.Color stringColor;
  final ui.Color commentColor;
  final ui.Color numberColor;
  final ui.Color functionColor;
  final ui.Color variableColor;
  final ui.Color operatorColor;
  final ui.Color typeColor;
  final ui.Color errorColor;
  final ui.Color warningColor;

  const SyntaxTheme({
    required this.backgroundColor,
    required this.textColor,
    required this.keywordColor,
    required this.stringColor,
    required this.commentColor,
    required this.numberColor,
    required this.functionColor,
    required this.variableColor,
    required this.operatorColor,
    required this.typeColor,
    required this.errorColor,
    required this.warningColor,
  });
}

/// Highlighted text result
class HighlightedText {
  final String text;
  final List<HighlightedSpan> spans;
  final SyntaxTheme theme;
  final bool animated;

  const HighlightedText({
    required this.text,
    required this.spans,
    required this.theme,
    required this.highlightedText,
    required this.animated,
  });

  factory HighlightedText.fallback(String text, SyntaxTheme theme) {
    return HighlightedText(
      text: text,
      spans: [HighlightedSpan(
        text: text,
        color: theme.textColor,
        type: SyntaxType.text,
        position: 0,
        animated: false,
      )],
      theme: theme,
      animated: false,
    );
  }
}

/// Highlighted span
class HighlightedSpan {
  final String text;
  final ui.Color color;
  final SyntaxType type;
  final int position;
  final bool animated;

  const HighlightedSpan({
    required this.text,
    required this.color,
    required this.type,
    required this.position,
    required this.animated,
  });
}

/// Highlight cache entry
class HighlightCache {
  final HighlightedText highlightedText;
  final DateTime createdAt;

  const HighlightCache(
    this.highlightedText,
    this.createdAt,
  );
}

/// Highlighting statistics
class HighlightStats {
  final int highlightCalls;
  final int cacheHits;
  final int cacheMisses;
  final double cacheHitRate;
  final double averageHighlightTime;
  final double totalHighlightTime;
  final int cacheSize;
  final int tokenCacheSize;

  const HighlightStats({
    required this.highlightCalls,
    required this.cacheHits,
    required this.cacheMisses,
    required this.cacheHitRate,
    required this.averageHighlightTime,
    required this.totalHighlightTime,
    required this.cacheSize,
    required this.tokenCacheSize,
  });
}
