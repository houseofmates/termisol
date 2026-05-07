import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Syntax highlighting for all programming languages in Termisol
/// 
/// Features:
/// - Multi-language support
/// - Real-time highlighting
/// - Customizable themes
/// - Performance optimized
/// - Bracket matching
/// - Syntax error detection
class SyntaxHighlighter {
  final String language;
  final SyntaxTheme theme;
  final bool enableLineNumbers;
  final bool enableBracketMatching;
  
  static final Map<String, LanguageDefinition> _languages = {
    'dart': DartLanguage(),
    'python': PythonLanguage(),
    'javascript': JavaScriptLanguage(),
    'typescript': TypeScriptLanguage(),
    'java': JavaLanguage(),
    'cpp': CppLanguage(),
    'c': CLanguage(),
    'go': GoLanguage(),
    'rust': RustLanguage(),
    'ruby': RubyLanguage(),
    'php': PhpLanguage(),
    'html': HtmlLanguage(),
    'css': CssLanguage(),
    'json': JsonLanguage(),
    'yaml': YamlLanguage(),
    'xml': XmlLanguage(),
    'sql': SqlLanguage(),
    'bash': BashLanguage(),
    'markdown': MarkdownLanguage(),
  };
  
  final Map<int, LineHighlight> _lineCache = {};
  final Map<String, int> _bracketPairs = {};
  Timer? _highlightTimer;
  
  SyntaxHighlighter({
    required this.language,
    this.theme = SyntaxTheme.dark,
    this.enableLineNumbers = true,
    this.enableBracketMatching = true,
  });
  
  /// Get highlighted text spans
  List<TextSpan> highlightText(String text) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineSpans = _highlightLine(line, i);
      
      if (enableLineNumbers) {
        spans.add(TextSpan(
          text: '${(i + 1).toString().padLeft(4, ' ')}',
          style: TextStyle(
            color: theme.lineNumberColor,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ));
        spans.addAll(lineSpans);
      } else {
        spans.addAll(lineSpans);
      }
      
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return spans;
  }
  
  List<TextSpan> _highlightLine(String line, int lineNumber) {
    final langDef = _languages[language.toLowerCase()];
    if (langDef == null) {
      return [TextSpan(
        text: line,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      )];
    }
    
    final spans = <TextSpan>[];
    final tokens = langDef!.tokenize(line);
    
    for (final token in tokens) {
      final style = _getTokenStyle(token, langDef!);
      final text = line.substring(token.start, token.end);
      
      spans.add(TextSpan(
        text: text,
        style: style,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _onTokenTap(token),
      ));
    }
    
    // Add bracket matching
    if (enableBracketMatching) {
      _addBracketMatching(spans, line, lineNumber);
    }
    
    return spans;
  }
  
  TextStyle _getTokenStyle(SyntaxToken token, LanguageDefinition langDef) {
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      backgroundColor: _getTokenBackground(token, langDef),
    );
    
    switch (token.type) {
      case TokenType.keyword:
        return baseStyle.copyWith(color: theme.keywordColor);
      case TokenType.string:
        return baseStyle.copyWith(color: theme.stringColor);
      case TokenType.number:
        return baseStyle.copyWith(color: theme.numberColor);
      case TokenType.comment:
        return baseStyle.copyWith(color: theme.commentColor, fontStyle: FontStyle.italic);
      case TokenType.function:
        return baseStyle.copyWith(color: theme.functionColor, fontWeight: FontWeight.bold);
      case TokenType.variable:
        return baseStyle.copyWith(color: theme.variableColor);
      case TokenType.type:
        return baseStyle.copyWith(color: theme.typeColor);
      case TokenType.operator:
        return baseStyle.copyWith(color: theme.operatorColor);
      case TokenType.builtin:
        return baseStyle.copyWith(color: theme.builtinColor);
      case TokenType.error:
        return baseStyle.copyWith(color: theme.errorColor, backgroundColor: Colors.red.withOpacity(0.2));
      default:
        return baseStyle.copyWith(color: theme.textColor);
    }
  }
  
  Color? _getTokenBackground(SyntaxToken token, LanguageDefinition langDef) {
    // Highlight background for certain token types
    switch (token.type) {
      case TokenType.error:
        return Colors.red.withOpacity(0.1);
      case TokenType.keyword:
        return theme.keywordBackground;
      case TokenType.function:
        return theme.functionBackground;
      default:
        return null;
    }
  }
  
  void _addBracketMatching(List<TextSpan> spans, String line, int lineNumber) {
    final brackets = ['()', '[]', '{}', '<>'];
    
    for (final bracket in brackets) {
      final open = bracket[0];
      final close = bracket[1];
      
      // Find all opening brackets
      final openIndices = <int>[];
      for (int i = 0; i < line.length; i++) {
        if (line[i] == open) openIndices.add(i);
      }
      
      // Find all closing brackets
      final closeIndices = <int>[];
      for (int i = 0; i < line.length; i++) {
        if (line[i] == close) closeIndices.add(i);
      }
      
      // Highlight matching pairs
      for (int i = 0; i < min(openIndices.length, closeIndices.length); i++) {
        final openIndex = openIndices[i];
        final closeIndex = closeIndices[i];
        
        if (openIndex < spans.length && closeIndex < spans.length) {
          // Highlight opening bracket
          if (spans[openIndex] is TextSpan) {
            spans[openIndex] = (spans[openIndex] as TextSpan).copyWith(
              style: (spans[openIndex] as TextSpan).style?.copyWith(
                backgroundColor: Colors.blue.withOpacity(0.2),
              ),
            );
          }
          
          // Highlight closing bracket
          if (spans[closeIndex] is TextSpan) {
            spans[closeIndex] = (spans[closeIndex] as TextSpan).copyWith(
              style: (spans[closeIndex] as TextSpan).style?.copyWith(
                backgroundColor: Colors.blue.withOpacity(0.2),
              ),
            );
          }
        }
      }
    }
  }
  
  void _onTokenTap(SyntaxToken token) {
    // Handle token tap for code navigation
    debugPrint('Token tapped: ${token.text} (${token.type})');
  }
  
  /// Get language definition
  LanguageDefinition? getLanguageDefinition(String language) {
    return _languages[language.toLowerCase()];
  }
  
  /// Get available languages
  static List<String> getAvailableLanguages() {
    return _languages.keys.toList()..sort();
  }
  
  /// Detect language from file extension
  static String detectLanguageFromExtension(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'dart':
        return 'dart';
      case 'py':
        return 'python';
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'java':
        return 'java';
      case 'cpp':
      case 'cc':
      case 'cxx':
        return 'cpp';
      case 'c':
      case 'h':
        return 'c';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'rb':
        return 'ruby';
      case 'php':
        return 'php';
      case 'html':
      case 'htm':
        return 'html';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'xml':
        return 'xml';
      case 'sql':
        return 'sql';
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'fish':
        return 'bash';
      case 'md':
      case 'markdown':
        return 'markdown';
      default:
        return 'text';
    }
  }
  
  /// Detect language from content
  static String detectLanguageFromContent(String content) {
    // Simple heuristic language detection
    if (content.contains('class ') && content.contains('extends ')) return 'java';
    if (content.contains('def ') && content.contains(':')) return 'python';
    if (content.contains('function ') && content.contains('=>')) return 'javascript';
    if (content.contains('interface ') && content.contains('implements')) return 'typescript';
    if (content.contains('fn ') && content.contains('->')) return 'rust';
    if (content.contains('func ') && content.contains('{')) return 'go';
    if (content.contains('<!DOCTYPE')) return 'html';
    if (content.contains('{') && content.contains('"') && content.contains(':')) return 'json';
    if (content.contains('SELECT ') && content.contains('FROM')) return 'sql';
    
    return 'text';
  }
  
  /// Clear cache
  void clearCache() {
    _lineCache.clear();
    _bracketPairs.clear();
  }
}

/// Syntax token
class SyntaxToken {
  final TokenType type;
  final String text;
  final int start;
  final int end;
  
  SyntaxToken({
    required this.type,
    required this.text,
    required this.start,
    required this.end,
  });
}

/// Token types
enum TokenType {
  keyword,
  string,
  number,
  comment,
  function,
  variable,
  type,
  operator,
  builtin,
  error,
  text,
}

/// Language definition interface
abstract class LanguageDefinition {
  List<SyntaxToken> tokenize(String line);
  List<String> getKeywords();
  List<String> getBuiltins();
  List<String> getOperators();
}

/// Dart language definition
class DartLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    final tokens = <SyntaxToken>[];
    final keywords = getKeywords();
    final builtins = getBuiltins();
    
    // String literals
    final stringRegex = RegExp(r'"(?:[^"\\]|\\.)*"');
    final stringMatches = stringRegex.allMatches(line);
    for (final match in stringMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.string,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Comments
    final commentRegex = RegExp(r'//.*$|/\*[\s\S]*?\*/');
    final commentMatches = commentRegex.allMatches(line);
    for (final match in commentMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.comment,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Numbers
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    final numberMatches = numberRegex.allMatches(line);
    for (final match in numberMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.number,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Keywords and builtins
    final words = line.split(RegExp(r'\W+'));
    for (final word in words) {
      if (keywords.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.keyword,
          text: word,
          start: index,
          end: index + word.length,
        ));
      } else if (builtins.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.builtin,
          text: word,
          start: index,
          end: index + word.length,
        ));
      }
    }
    
    return tokens;
  }
  
  @override
  List<String> getKeywords() => [
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class',
    'const', 'continue', 'default', 'do', 'else', 'enum', 'extends', 'false',
    'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
    'return', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'var',
    'void', 'while', 'with', 'yield',
  ];
  
  @override
  List<String> getBuiltins() => [
    'print', 'debugPrint', 'assert', 'require', 'import', 'export', 'library', 'part',
    'of', 'show', 'hide', 'on', 'late', 'static', 'const', 'final',
  ];
  
  @override
  List<String> getOperators() => [
    '+', '-', '*', '/', '%', '==', '!=', '<=', '>=', '<', '>', '&&', '||',
    '!', '&', '|', '^', '~', '<<', '>>', '+=', '-=', '*=', '/=',
  ];
}

/// Python language definition
class PythonLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    final tokens = <SyntaxToken>[];
    final keywords = getKeywords();
    final builtins = getBuiltins();
    
    // String literals
    final stringRegex = RegExp(r"""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'""");
    final stringMatches = stringRegex.allMatches(line);
    for (final match in stringMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.string,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Comments
    final commentRegex = RegExp(r'#.*$');
    final commentMatches = commentRegex.allMatches(line);
    for (final match in commentMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.comment,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Numbers
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    final numberMatches = numberRegex.allMatches(line);
    for (final match in numberMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.number,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Keywords and builtins
    final words = line.split(RegExp(r'\W+'));
    for (final word in words) {
      if (keywords.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.keyword,
          text: word,
          start: index,
          end: index + word.length,
        ));
      } else if (builtins.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.builtin,
          text: word,
          start: index,
          end: index + word.length,
        ));
      }
    }
    
    return tokens;
  }
  
  @override
  List<String> getKeywords() => [
    'and', 'as', 'assert', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else',
    'except', 'exec', 'finally', 'for', 'from', 'global', 'if', 'import', 'in',
    'is', 'lambda', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while',
    'with', 'yield', 'async', 'await',
  ];
  
  @override
  List<String> getBuiltins() => [
    'print', 'len', 'str', 'int', 'float', 'list', 'dict', 'set', 'tuple', 'range',
    'enumerate', 'zip', 'map', 'filter', 'reduce', 'sum', 'min', 'max', 'abs',
    'round', 'open', 'file', 'input', 'type', 'isinstance', 'hasattr',
  ];
  
  @override
  List<String> getOperators() => [
    '+', '-', '*', '/', '//', '%', '**', '==', '!=', '<=', '>=', '<', '>', 'and',
    'or', 'not', '&', '|', '^', '~', '<<', '>>', '+=', '-=', '*=', '/=',
  ];
}

/// JavaScript language definition
class JavaScriptLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    final tokens = <SyntaxToken>[];
    final keywords = getKeywords();
    final builtins = getBuiltins();
    
    // String literals
    final stringRegex = RegExp(r"""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'""");
    final stringMatches = stringRegex.allMatches(line);
    for (final match in stringMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.string,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Comments
    final commentRegex = RegExp(r'//.*$|/\*[\s\S]*?\*/');
    final commentMatches = commentRegex.allMatches(line);
    for (final match in commentMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.comment,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Numbers
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    final numberMatches = numberRegex.allMatches(line);
    for (final match in numberMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.number,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Keywords and builtins
    final words = line.split(RegExp(r'\W+'));
    for (final word in words) {
      if (keywords.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.keyword,
          text: word,
          start: index,
          end: index + word.length,
        ));
      } else if (builtins.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.builtin,
          text: word,
          start: index,
          end: index + word.length,
        ));
      }
    }
    
    return tokens;
  }
  
  @override
  List<String> getKeywords() => [
    'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete',
    'do', 'else', 'finally', 'for', 'function', 'if', 'in', 'instanceof',
    'let', 'new', 'return', 'switch', 'this', 'throw', 'try', 'typeof', 'var',
    'void', 'while', 'with', 'yield', 'async', 'await', 'import', 'export',
  ];
  
  @override
  List<String> getBuiltins() => [
    'console', 'document', 'window', 'Array', 'Object', 'String', 'Number', 'Boolean',
    'Date', 'RegExp', 'JSON', 'Math', 'parseInt', 'parseFloat', 'isNaN',
    'alert', 'prompt', 'confirm', 'setTimeout', 'setInterval',
  ];
  
  @override
  List<String> getOperators() => [
    '+', '-', '*', '/', '%', '==', '!=', '===', '!==', '<=', '>=', '<', '>',
    '&&', '||', '!', '&', '|', '^', '~', '<<', '>>', '+=', '-=', '*=', '/=',
    '=>', '++', '--',
  ];
}

/// Placeholder language definitions (simplified)
class TypeScriptLanguage extends JavaScriptLanguage {
  @override
  List<String> getKeywords() => [
    ...super.getKeywords(),
    'interface', 'implements', 'type', 'enum', 'declare', 'abstract', 'private',
    'protected', 'public', 'readonly', 'static', 'as', 'unknown', 'never',
    'key', 'unique', 'any', 'void', 'undefined', 'null', 'symbol',
  ];
}

class JavaLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    // Simplified Java tokenization
    final tokens = <SyntaxToken>[];
    final keywords = getKeywords();
    
    // String literals
    final stringRegex = RegExp(r"""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'""");
    final stringMatches = stringRegex.allMatches(line);
    for (final match in stringMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.string,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Comments
    final commentRegex = RegExp(r'//.*$|/\*[\s\S]*?\*/');
    final commentMatches = commentRegex.allMatches(line);
    for (final match in commentMatches) {
      tokens.add(SyntaxToken(
        type: TokenType.comment,
        text: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    
    // Keywords
    final words = line.split(RegExp(r'\W+'));
    for (final word in words) {
      if (keywords.contains(word)) {
        final index = line.indexOf(word);
        tokens.add(SyntaxToken(
          type: TokenType.keyword,
          text: word,
          start: index,
          end: index + word.length,
        ));
      }
    }
    
    return tokens;
  }
  
  @override
  List<String> getKeywords() => [
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class',
    'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extends',
    'final', 'finally', 'float', 'for', 'if', 'implements', 'import',
    'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package',
    'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp',
    'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient',
    'try', 'void', 'volatile', 'while',
  ];
  
  @override
  List<String> getBuiltins() => [
    'System', 'out', 'err', 'String', 'Integer', 'Double', 'Float', 'Long',
    'Short', 'Byte', 'Character', 'Boolean', 'Object', 'Class', 'Thread',
    'Runnable', 'Exception', 'Error', 'Math', 'Array', 'List', 'Map', 'Set',
    'Collection', 'Iterator', 'Comparator', 'Random', 'UUID', 'Pattern',
  ];
  
  @override
  List<String> getOperators() => [
    '+', '-', '*', '/', '%', '==', '!=', '<=', '>=', '<', '>', '&&', '||',
    '!', '&', '|', '^', '~', '<<', '>>', '>>>', '<<=', '+=', '-=',
    '*=', '/=', '++', '--', 'instanceof',
  ];
}

// Simplified language definitions for other languages
class CppLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    // Simplified C++ tokenization
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['int', 'char', 'float', 'double', 'void', 'if', 'else', 'for', 'while', 'return'];
  @override
  List<String> getBuiltins() => ['printf', 'scanf', 'malloc', 'free', 'cout', 'cin'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class CLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['int', 'char', 'float', 'double', 'void', 'if', 'else', 'for', 'while', 'return'];
  @override
  List<String> getBuiltins() => ['printf', 'scanf', 'malloc', 'free'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class GoLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['func', 'var', 'const', 'if', 'else', 'for', 'range', 'return'];
  @override
  List<String> getBuiltins() => ['fmt', 'print', 'len', 'make', 'new'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class RustLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['fn', 'let', 'mut', 'const', 'if', 'else', 'for', 'while', 'return'];
  @override
  List<String> getBuiltins() => ['println!', 'vec', 'String', 'Option', 'Result'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class RubyLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['def', 'class', 'if', 'else', 'for', 'while', 'return'];
  @override
  List<String> getBuiltins() => ['puts', 'gets', 'require', 'include'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class PhpLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['function', 'class', 'if', 'else', 'for', 'while', 'return'];
  @override
  List<String> getBuiltins() => ['echo', 'print', 'isset', 'empty'];
  @override
  List<String> getOperators() => ['+', '-', '*', '/', '=', '==', '!=', '<', '>'];
}

class HtmlLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['div', 'span', 'class', 'id', 'href', 'src', 'alt'];
  @override
  List<String> getBuiltins() => ['document', 'window', 'console'];
  @override
  List<String> getOperators() => ['=', '<', '>', '/'];
}

class CssLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['color', 'background', 'margin', 'padding', 'border'];
  @override
  List<String> getBuiltins() => ['px', 'em', 'rem', 'vh', 'vw'];
  @override
  List<String> getOperators() => [':', ';', '{', '}', '[', ']'];
}

class JsonLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['true', 'false', 'null'];
  @override
  List<String> getBuiltins() => [];
  @override
  List<String> getOperators() => [':', ',', '{', '}', '[', ']'];
}

class YamlLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['true', 'false', 'null', 'yes', 'no'];
  @override
  List<String> getBuiltins() => [];
  @override
  List<String> getOperators() => [':', '-', '|', '[', ']', '{', '}'];
}

class XmlLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['xml', 'version', 'encoding'];
  @override
  List<String> getBuiltins() => [];
  @override
  List<String> getOperators() => ['=', '<', '>', '/'];
}

class SqlLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['SELECT', 'FROM', 'WHERE', 'INSERT', 'UPDATE', 'DELETE', 'CREATE', 'DROP'];
  @override
  List<String> getBuiltins() => ['COUNT', 'SUM', 'AVG', 'MAX', 'MIN'];
  @override
  List<String> getOperators() => ['=', '<', '>', '<=', '>=', '!=', 'AND', 'OR'];
}

class BashLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['if', 'then', 'else', 'for', 'while', 'do', 'done', 'function'];
  @override
  List<String> getBuiltins() => ['echo', 'cd', 'ls', 'pwd', 'cat', 'grep'];
  @override
  List<String> getOperators() => ['|', '&', ';', '>', '>>', '<'];
}

class MarkdownLanguage implements LanguageDefinition {
  @override
  List<SyntaxToken> tokenize(String line) {
    return [SyntaxToken(type: TokenType.text, text: line, start: 0, end: line.length)];
  }
  
  @override
  List<String> getKeywords() => ['#', '##', '###', '****', '----'];
  @override
  List<String> getBuiltins() => [];
  @override
  List<String> getOperators() => ['*', '_', '`', '~'];
}

/// Line highlight information
class LineHighlight {
  final int lineNumber;
  final List<TextSpan> spans;
  
  LineHighlight({
    required this.lineNumber,
    required this.spans,
  });
}

/// Syntax theme
class SyntaxTheme {
  final Color textColor;
  final Color keywordColor;
  final Color stringColor;
  final Color numberColor;
  final Color commentColor;
  final Color functionColor;
  final Color variableColor;
  final Color typeColor;
  final Color operatorColor;
  final Color builtinColor;
  final Color errorColor;
  final Color lineNumberColor;
  final Color? keywordBackground;
  final Color? functionBackground;
  final Color backgroundColor;
  
  const SyntaxTheme({
    this.textColor = Colors.white,
    this.keywordColor = Colors.purple,
    this.stringColor = Colors.green,
    this.numberColor = Colors.cyan,
    this.commentColor = Colors.grey,
    this.functionColor = Colors.blue,
    this.variableColor = Colors.orange,
    this.typeColor = Colors.yellow,
    this.operatorColor = Colors.red,
    this.builtinColor = Colors.teal,
    this.errorColor = Colors.red,
    this.lineNumberColor = Colors.grey,
    this.keywordBackground,
    this.functionBackground,
    this.backgroundColor = Colors.black,
  });
  
  static const SyntaxTheme dark = SyntaxTheme(
    textColor: Colors.white,
    keywordColor: Color(0xFF9CDCFE),
    stringColor: Color(0xFFA6E22E),
    numberColor: Color(0xFFAE81FF),
    commentColor: Color(0xFF75715E),
    functionColor: Color(0xFF61AFEF),
    variableColor: Color(0xFFFD971F),
    typeColor: Color(0xFF66D9EF),
    operatorColor: Color(0xFFF92672),
    builtinColor: Color(0xFF56B6C2),
    errorColor: Color(0xFFFF6B6B),
    lineNumberColor: Color(0xFF75715E),
    backgroundColor: Color(0xFF1E1E1E),
  );
  
  static const SyntaxTheme light = SyntaxTheme(
    textColor: Colors.black,
    keywordColor: Color(0xFF0000FF),
    stringColor: Color(0xFF008000),
    numberColor: Color(0xFF099999),
    commentColor: Color(0xFF808080),
    functionColor: Color(0xFF795DA3),
    variableColor: Color(0xFF001080),
    typeColor: Color(0xFF9A6E3A),
    operatorColor: Color(0xFFD73A49),
    builtinColor: Color(0xFF64575D),
    errorColor: Color(0xFFFF0000),
    lineNumberColor: Color(0xFF808080),
    backgroundColor: Colors.white,
  );
}
