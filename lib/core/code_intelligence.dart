import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Code Intelligence
///
/// Provides IDE-like features in the terminal environment: syntax
/// analysis, code quality inspection, structure extraction, and
/// intelligent navigation for common programming languages.
class CodeIntelligence {
  final Map<String, CodeFile> _files = {};
  final Map<String, CodeProject> _projects = {};
  final List<LintRule> _lintRules = [];
  final Map<String, String> _symbolCache = {};

  static const int _maxFileSize = 10 * 1024 * 1024; // 10MB
  static const Set<String> _supportedExtensions = {
    '.dart', '.py', '.js', '.ts', '.go', '.rs', '.java', '.cpp', '.c', '.h',
    '.sh', '.bash', '.yaml', '.yml', '.json', '.toml', '.xml', '.html', '.css',
    '.sql', '.rb', '.php', '.swift', '.kt', '.scala', '.lua',
  };

  Future<void> initialize() async {
    _registerDefaultLintRules();
    debugPrint('CodeIntelligence initialized');
  }

  CodeProject? openProject(String rootPath) {
    final absPath = Directory(rootPath).absolute.path;
    if (_projects.containsKey(absPath)) return _projects[absPath];
    final project = CodeProject(rootPath: absPath);
    _projects[absPath] = project;
    return project;
  }

  Future<CodeAnalysisResult> analyzeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return CodeAnalysisResult(error: 'File not found: $filePath');
      }

      final stat = await file.stat();
      if (stat.size > _maxFileSize) {
        return CodeAnalysisResult(error: 'File too large (${stat.size} bytes)');
      }

      final ext = _getExtension(filePath);
      if (!_supportedExtensions.contains(ext)) {
        return CodeAnalysisResult(error: 'Unsupported file type: $ext');
      }

      final content = await file.readAsString();
      final lines = content.split('\n');

      final result = CodeAnalysisResult(
        filePath: filePath,
        extension: ext,
        lineCount: lines.length,
        charCount: content.length,
        sizeBytes: stat.size,
        functions: _extractFunctions(content, ext),
        classes: _extractClasses(content, ext),
        imports: _extractImports(content, ext),
        exports: _extractExports(content, ext),
        lints: _runLintChecks(content, ext),
        complexity: _calculateComplexity(content, ext),
        blankLines: lines.where((l) => l.trim().isEmpty).length,
        commentLines: _countCommentLines(lines, ext),
        longestLine: lines.map((l) => l.length).reduce(max),
      );

      _symbolCache[filePath] = content;
      return result;
    } catch (e) {
      return CodeAnalysisResult(error: e.toString());
    }
  }

  Future<Map<String, List<int>>> findSymbolReferences(String filePath, String symbol) async {
    final result = <String, List<int>>{};
    try {
      final content = _symbolCache[filePath] ?? await File(filePath).readAsString();
      final lines = content.split('\n');
      final positions = <int>[];
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains(symbol)) {
          positions.add(i + 1);
        }
      }
      result[filePath] = positions;
    } catch (e) {
      // Ignore
    }
    return result;
  }

  Future<List<String>> proposeFix(String filePath, String error) async {
    try {
      final content = _symbolCache[filePath] ?? await File(filePath).readAsString();
      final ext = _getExtension(filePath);
      final suggestions = <String>[];

      if (error.contains('undefined') || error.contains('not found') || error.contains('Unresolved')) {
        final availableImports = await _suggestImports(filePath, content, ext);
        suggestions.addAll(availableImports);
      }

      if (error.contains('syntax') || error.contains('Syntax')) {
        suggestions.add('Check bracket/parenthesis matching');
        suggestions.add('Verify string literal termination');
      }

      return suggestions;
    } catch (e) {
      return ['Unable to suggest fix: $e'];
    }
  }

  Future<double> estimateCodeQuality(String filePath) async {
    try {
      final analysis = await analyzeFile(filePath);
      if (analysis.error != null) return 0.0;

      double score = 1.0;
      if (analysis.lintCount > 0) score -= min(0.3, analysis.lintCount * 0.05);
      if (analysis.complexity > 20) score -= 0.1;
      final commentRatio = analysis.lineCount > 0 ? analysis.commentLines / analysis.lineCount : 0;
      if (commentRatio < 0.05) score -= 0.1;
      if (analysis.longestLine > 120) score -= 0.1;

      return score.clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }

  void closeProject(String rootPath) {
    _projects.remove(rootPath);
  }

  // ── Parsing helpers ──────────────────────────────────────────────────

  List<CodeSymbol> _extractFunctions(String content, String ext) {
    final symbols = <CodeSymbol>[];
    try {
      final pattern = _functionPatterns(ext);
      for (final match in pattern.allMatches(content)) {
        final name = match.group(1);
        if (name != null && name.isNotEmpty) {
          symbols.add(CodeSymbol(name: name, type: 'function', line: _findLine(content, match.start)));
        }
      }
    } catch (_) {}
    return symbols;
  }

  List<CodeSymbol> _extractClasses(String content, String ext) {
    final symbols = <CodeSymbol>[];
    try {
      final classMatch = RegExp(r'(?:class|struct|interface|enum)\s+(\w+)', multiLine: true);
      for (final match in classMatch.allMatches(content)) {
        symbols.add(CodeSymbol(name: match.group(1)!, type: 'class', line: _findLine(content, match.start)));
      }
    } catch (_) {}
    return symbols;
  }

  List<String> _extractImports(String content, String ext) {
    final imports = <String>[];
    try {
      final pattern = _importPatterns(ext);
      for (final match in pattern.allMatches(content)) {
        if (match.group(1) != null) {
          imports.add(match.group(1)!);
        }
      }
    } catch (_) {}
    return imports.toSet().toList();
  }

  List<String> _extractExports(String content, String ext) {
    final exports = <String>[];
    try {
      final exportPattern = RegExp(r'export\s+(?:default\s+)?(?:class|function|const|let|var)?\s*(\w+)', multiLine: true);
      for (final match in exportPattern.allMatches(content)) {
        if (match.group(1) != null) exports.add(match.group(1)!);
      }
    } catch (_) {}
    return exports;
  }

  int _countCommentLines(List<String> lines, String ext) {
    int count = 0;
    bool inBlockComment = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('#') || trimmed.startsWith('--')) count++;
      if (trimmed.contains('/*') || trimmed.contains('"""')) inBlockComment = true;
      if (inBlockComment) count++;
      if (trimmed.contains('*/') || trimmed.contains('"""')) inBlockComment = false;
    }
    return count;
  }

  double _calculateComplexity(String content, String ext) {
    int branches = 1;
    branches += RegExp(r'\b(if|else if|for|while|case|catch|switch)\b').allMatches(content).length;
    branches += RegExp(r'&&|\|\|').allMatches(content).length;
    return branches.toDouble();
  }

  int _findLine(String content, int position) {
    return content.substring(0, min(position, content.length)).split('\n').length;
  }

  Future<List<String>> _suggestImports(String filePath, String content, String ext) async {
    return [];
  }

  // ── Lint rules ──────────────────────────────────────────────────────

  List<LintResult> _runLintChecks(String content, String ext) {
    final results = <LintResult>[];
    for (final rule in _lintRules) {
      for (final match in rule.pattern.allMatches(content)) {
        results.add(LintResult(
          rule: rule.name,
          message: rule.message,
          severity: rule.severity,
          line: _findLine(content, match.start),
        ));
      }
    }
    return results;
  }

  void _registerDefaultLintRules() {
    _lintRules.addAll([
      LintRule(name: 'todo', pattern: RegExp(r'TODO', caseSensitive: true), message: 'TODO found', severity: LintSeverity.info),
      LintRule(name: 'fixme', pattern: RegExp(r'FIXME', caseSensitive: true), message: 'FIXME found', severity: LintSeverity.warning),
      LintRule(name: 'hack', pattern: RegExp(r'HACK', caseSensitive: true), message: 'HACK found', severity: LintSeverity.warning),
      LintRule(name: 'debug_print', pattern: RegExp(r'debugPrint\(|print\(|console\.log\(', caseSensitive: false), message: 'Debug print statement', severity: LintSeverity.info),
      LintRule(name: 'long_line', pattern: RegExp(r'^.{121,}$', multiLine: true), message: 'Line exceeds 120 characters', severity: LintSeverity.info),
    ]);
  }

  String _getExtension(String path) => path.contains('.') ? path.substring(path.lastIndexOf('.')) : '';

  RegExp _functionPatterns(String ext) {
    switch (ext) {
      case '.dart': return RegExp(r'(?:void|int|String|bool|double|Future|Stream|Widget|State|dynamic|[A-Z]\w*)\s+(\w+)\s*\(', multiLine: true);
      case '.py': return RegExp(r'def\s+(\w+)\s*\(', multiLine: true);
      case '.js': case '.ts': return RegExp(r'(?:function|async\s+function)\s+(\w+)|(\w+)\s*=\s*(?:async\s*)?\(', multiLine: true);
      default: return RegExp(r'(?:function|def|fn|func|fun)\s+(\w+)', multiLine: true, caseSensitive: false);
    }
  }

  RegExp _importPatterns(String ext) {
    switch (ext) {
      case '.dart': return RegExp(r"""import\s+['"](.+?)['"];""", multiLine: true);
      case '.py': return RegExp(r'(?:from|import)\s+(\S+)', multiLine: true);
      case '.js': case '.ts': return RegExp(r"""(?:import|require)\s*\(?['"](.+?)['"]\)?""", multiLine: true);
      default: return RegExp(r"""(?:import|use|require)\s+['"](.+?)['"]""", multiLine: true);
    }
  }

  void dispose() {
    _files.clear();
    _projects.clear();
    _symbolCache.clear();
    _lintRules.clear();
  }
}

enum LintSeverity { error, warning, info, hint }

class CodeFile {
  final String path;
  final String extension;
  int lineCount;
  int charCount;
  DateTime lastModified;

  CodeFile({
    required this.path,
    required this.extension,
    this.lineCount = 0,
    this.charCount = 0,
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.now();
}

class CodeProject {
  final String rootPath;
  final Map<String, CodeFile> files;
  final DateTime openedAt;

  CodeProject({required this.rootPath, Map<String, CodeFile>? files})
      : files = files ?? {},
        openedAt = DateTime.now();
}

class CodeSymbol {
  final String name;
  final String type;
  final int line;

  CodeSymbol({required this.name, this.type = 'unknown', this.line = 0});
}

class CodeAnalysisResult {
  final String? error;
  final String? filePath;
  final String? extension;
  final int lineCount;
  final int charCount;
  final int sizeBytes;
  final List<CodeSymbol> functions;
  final List<CodeSymbol> classes;
  final List<String> imports;
  final List<String> exports;
  final List<LintResult> lints;
  final double complexity;
  final int blankLines;
  final int commentLines;
  final int longestLine;

  CodeAnalysisResult({
    this.error,
    this.filePath,
    this.extension,
    this.lineCount = 0,
    this.charCount = 0,
    this.sizeBytes = 0,
    List<CodeSymbol>? functions,
    List<CodeSymbol>? classes,
    List<String>? imports,
    List<String>? exports,
    List<LintResult>? lints,
    this.complexity = 0.0,
    this.blankLines = 0,
    this.commentLines = 0,
    this.longestLine = 0,
  }) : functions = functions ?? [],
       classes = classes ?? [],
       imports = imports ?? [],
       exports = exports ?? [],
       lints = lints ?? [];

  int get lintCount => lints.length;
  int get errorCount => lints.where((l) => l.severity == LintSeverity.error).length;
  int get warningCount => lints.where((l) => l.severity == LintSeverity.warning).length;

  Map<String, int> get summary => {
    'lines': lineCount,
    'chars': charCount,
    'bytes': sizeBytes,
    'functions': functions.length,
    'classes': classes.length,
    'imports': imports.length,
    'lints': lintCount,
    'complexity': complexity.round(),
    'errors': errorCount,
    'warnings': warningCount,
  };
}

class LintRule {
  final String name;
  final RegExp pattern;
  final String message;
  final LintSeverity severity;

  LintRule({required this.name, required this.pattern, required this.message, this.severity = LintSeverity.warning});
}

class LintResult {
  final String rule;
  final String message;
  final LintSeverity severity;
  final int line;

  LintResult({required this.rule, required this.message, this.severity = LintSeverity.warning, this.line = 0});
}
```