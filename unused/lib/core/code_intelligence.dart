import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Production code intelligence engine for termisol.
/// Provides static analysis, code quality metrics, and intelligent code insights.
class CodeIntelligence {
  static final CodeIntelligence _instance = CodeIntelligence._internal();
  factory CodeIntelligence() => _instance;

  CodeIntelligence._internal();

  bool _isInitialized = false;
  final Map<String, CodeAnalysisResult> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  bool get isInitialized => _isInitialized;

  /// Initialize the code intelligence system
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('Code intelligence initialized');
  }

  /// Analyze a file and return comprehensive code metrics
  Future<Map<String, dynamic>> analyzeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {'error': 'File not found'};
      }

      // Check cache first
      final cacheKey = filePath;
      final cached = _getCachedAnalysis(cacheKey);
      if (cached != null) {
        return cached.toJson();
      }

      final content = await file.readAsString();
      final analysis = await _performAnalysis(filePath, content);

      // Cache the result
      _cache[cacheKey] = analysis;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return analysis.toJson();
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Estimate code quality on a scale of 0.0 to 1.0
  Future<double> estimateCodeQuality(String filePath) async {
    final analysis = await analyzeFile(filePath);
    return _calculateQualityScore(analysis);
  }

  /// Get code suggestions for improvement
  Future<List<String>> getSuggestions(String filePath) async {
    final analysis = await analyzeFile(filePath);
    return _generateSuggestions(analysis);
  }

  /// Extract symbols from file
  Future<List<CodeSymbol>> extractSymbols(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      return _parseSymbols(content, filePath);
    } catch (e) {
      return [];
    }
  }

  /// Find references to a symbol
  Future<List<CodeReference>> findReferences(String filePath, String symbol) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      return _findSymbolReferences(content, symbol);
    } catch (e) {
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  // Private methods

  CodeAnalysisResult? _getCachedAnalysis(String key) {
    final cached = _cache[key];
    final timestamp = _cacheTimestamps[key];

    if (cached != null && timestamp != null) {
      // Cache for 5 minutes
      if (DateTime.now().difference(timestamp).inMinutes < 5) {
        return cached;
      } else {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }
    return null;
  }

  Future<CodeAnalysisResult> _performAnalysis(String filePath, String content) async {
    final lines = content.split('\n');
    final extension = filePath.split('.').last.toLowerCase();

    final analysis = CodeAnalysisResult(
      lineCount: lines.length,
      charCount: content.length,
      sizeBytes: content.length,
    );

    // Basic metrics
    analysis.blankLines = lines.where((line) => line.trim().isEmpty).length;
    analysis.commentLines = _countCommentLines(lines, extension);
    analysis.longestLine = lines.isNotEmpty ? lines.map((l) => l.length).reduce(max) : 0;

    // Parse symbols
    analysis.functions = _parseFunctions(content, extension);
    analysis.classes = _parseClasses(content, extension);
    analysis.imports = _parseImports(content, extension);
    analysis.exports = _parseExports(content, extension);

    // Calculate complexity
    analysis.complexity = _calculateComplexity(content, extension);

    // Lint analysis
    analysis.lints = await _performLinting(content, extension);

    return analysis;
  }

  int _countCommentLines(List<String> lines, String extension) {
    int count = 0;
    bool inBlockComment = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (extension == 'dart' || extension == 'java' || extension == 'cpp' || extension == 'c') {
        if (inBlockComment) {
          count++;
          if (trimmed.contains('*/')) inBlockComment = false;
        } else if (trimmed.startsWith('/*')) {
          count++;
          inBlockComment = !trimmed.contains('*/');
        } else if (trimmed.startsWith('//')) {
          count++;
        }
      } else if (extension == 'py') {
        if (trimmed.startsWith('#')) count++;
      } else if (extension == 'js' || extension == 'ts') {
        if (inBlockComment) {
          count++;
          if (trimmed.contains('*/')) inBlockComment = false;
        } else if (trimmed.startsWith('/*')) {
          count++;
          inBlockComment = !trimmed.contains('*/');
        } else if (trimmed.startsWith('//')) {
          count++;
        }
      }
    }

    return count;
  }

  List<CodeSymbol> _parseFunctions(String content, String extension) {
    final functions = <CodeSymbol>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (extension == 'dart') {
        final functionRegex = RegExp(r'(?:Future<[^>]*>\s+)?(?:static\s+)?(?:\w+\s+)*(\w+)\s*\([^)]*\)\s*(?:async\s*)?{');
        final match = functionRegex.firstMatch(trimmed);
        if (match != null) {
          functions.add(CodeSymbol(
            name: match.group(1)!,
            type: 'function',
            line: i + 1,
          ));
        }
      } else if (extension == 'py') {
        final functionRegex = RegExp(r'def\s+(\w+)\s*\(');
        final match = functionRegex.firstMatch(trimmed);
        if (match != null) {
          functions.add(CodeSymbol(
            name: match.group(1)!,
            type: 'function',
            line: i + 1,
          ));
        }
      }
    }

    return functions;
  }

  List<CodeSymbol> _parseClasses(String content, String extension) {
    final classes = <CodeSymbol>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (extension == 'dart') {
        final classRegex = RegExp(r'class\s+(\w+)');
        final match = classRegex.firstMatch(trimmed);
        if (match != null) {
          classes.add(CodeSymbol(
            name: match.group(1)!,
            type: 'class',
            line: i + 1,
          ));
        }
      } else if (extension == 'py') {
        final classRegex = RegExp(r'class\s+(\w+)');
        final match = classRegex.firstMatch(trimmed);
        if (match != null) {
          classes.add(CodeSymbol(
            name: match.group(1)!,
            type: 'class',
            line: i + 1,
          ));
        }
      }
    }

    return classes;
  }

  List<String> _parseImports(String content, String extension) {
    final imports = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      if (extension == 'dart') {
        if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
          final importMatch = RegExp(r"['\"]([^'\"]+)['\"]").firstMatch(trimmed);
          if (importMatch != null) {
            imports.add(importMatch.group(1)!);
          }
        }
      }
    }

    return imports;
  }

  List<String> _parseExports(String content, String extension) {
    final exports = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      if (extension == 'dart') {
        if (trimmed.startsWith('export ')) {
          final exportMatch = RegExp(r"['\"]([^'\"]+)['\"]").firstMatch(trimmed);
          if (exportMatch != null) {
            exports.add(exportMatch.group(1)!);
          }
        }
      }
    }

    return exports;
  }

  double _calculateComplexity(String content, String extension) {
    // Simplified cyclomatic complexity calculation
    double complexity = 1.0;

    // Count decision points
    final decisionKeywords = ['if', 'else', 'for', 'while', 'case', 'catch', '&&', '||', '?'];
    for (final keyword in decisionKeywords) {
      complexity += keyword.allMatches(content).length * 0.1;
    }

    // Count functions/methods
    complexity += _parseFunctions(content, extension).length * 0.2;

    return complexity.clamp(0.0, 10.0);
  }

  Future<List<LintResult>> _performLinting(String content, String extension) async {
    final lints = <LintResult>[];

    // Basic linting rules
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNumber = i + 1;

      // Check line length
      if (line.length > 120) {
        lints.add(LintResult(
          rule: 'line-length',
          message: 'Line too long (${line.length} characters)',
          severity: LintSeverity.warning,
          line: lineNumber,
        ));
      }

      // Check for TODO comments
      if (line.contains('TODO') || line.contains('FIXME') || line.contains('XXX')) {
        lints.add(LintResult(
          rule: 'todo-comment',
          message: 'TODO comment found',
          severity: LintSeverity.info,
          line: lineNumber,
        ));
      }

      // Check for print statements in production code
      if (line.contains('print(') && !line.contains('kDebugMode')) {
        lints.add(LintResult(
          rule: 'debug-print',
          message: 'Debug print statement found',
          severity: LintSeverity.warning,
          line: lineNumber,
        ));
      }
    }

    return lints;
  }

  double _calculateQualityScore(Map<String, dynamic> analysis) {
    if (analysis.containsKey('error')) return 0.0;

    double score = 1.0;

    // Penalize for lint issues
    final lints = analysis['lints'] as List? ?? [];
    final errorCount = lints.where((l) => l['severity'] == 'error').length;
    final warningCount = lints.where((l) => l['severity'] == 'warning').length;

    score -= errorCount * 0.2;
    score -= warningCount * 0.1;

    // Penalize for high complexity
    final complexity = analysis['complexity'] as double? ?? 0.0;
    if (complexity > 5.0) {
      score -= (complexity - 5.0) * 0.05;
    }

    // Penalize for low comment ratio
    final lineCount = analysis['lineCount'] as int? ?? 1;
    final commentLines = analysis['commentLines'] as int? ?? 0;
    final commentRatio = commentLines / lineCount;
    if (commentRatio < 0.1) {
      score -= (0.1 - commentRatio) * 2.0;
    }

    return score.clamp(0.0, 1.0);
  }

  List<String> _generateSuggestions(Map<String, dynamic> analysis) {
    final suggestions = <String>[];

    if (analysis.containsKey('error')) return suggestions;

    final lints = analysis['lints'] as List? ?? [];
    final complexity = analysis['complexity'] as double? ?? 0.0;
    final lineCount = analysis['lineCount'] as int? ?? 0;
    final commentLines = analysis['commentLines'] as int? ?? 0;

    if (lints.isNotEmpty) {
      suggestions.add('Fix ${lints.length} lint issues');
    }

    if (complexity > 5.0) {
      suggestions.add('Consider breaking down complex functions (complexity: ${complexity.toStringAsFixed(1)})');
    }

    if (lineCount > 500) {
      suggestions.add('Consider splitting this large file (${lineCount} lines)');
    }

    final commentRatio = commentLines / lineCount;
    if (commentRatio < 0.1) {
      suggestions.add('Add more documentation comments (current ratio: ${(commentRatio * 100).toStringAsFixed(1)}%)');
    }

    return suggestions;
  }

  List<CodeSymbol> _parseSymbols(String content, String filePath) {
    final symbols = <CodeSymbol>[];
    symbols.addAll(_parseFunctions(content, filePath.split('.').last));
    symbols.addAll(_parseClasses(content, filePath.split('.').last));
    return symbols;
  }

  List<CodeReference> _findSymbolReferences(String content, String symbol) {
    final references = <CodeReference>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains(symbol)) {
        references.add(CodeReference(
          line: i + 1,
          column: line.indexOf(symbol),
          context: line.trim(),
        ));
      }
    }

    return references;
  }
}

/// Code reference information
class CodeReference {
  final int line;
  final int column;
  final String context;

  CodeReference({
    required this.line,
    required this.column,
    required this.context,
  });
}

class CodeSymbol {
  final String name;
  final String type;
  final int line;

  CodeSymbol({required this.name, required this.type, required this.line});
}

class CodeAnalysisResult {
  final String? error;
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
    this.lineCount = 0,
    this.charCount = 0,
    this.sizeBytes = 0,
    this.functions = const [],
    this.classes = const [],
    this.imports = const [],
    this.exports = const [],
    this.lints = const [],
    this.complexity = 0,
    this.blankLines = 0,
    this.commentLines = 0,
    this.longestLine = 0,
  });
}

class LintResult {
  final String rule;
  final String message;
  final LintSeverity severity;
  final int line;

  LintResult({
    required this.rule,
    required this.message,
    this.severity = LintSeverity.warning,
    this.line = 0,
  });
}

enum LintSeverity { info, warning, error }
