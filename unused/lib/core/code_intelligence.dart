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

  final Map<String, CodeAnalysisResult> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final StreamController<CodeAnalysisEvent> _eventController = StreamController.broadcast();

  bool _isInitialized = false;
  static const Duration _cacheDuration = Duration(minutes: 5);

  bool get isInitialized => _isInitialized;
  Stream<CodeAnalysisEvent> get events => _eventController.stream;

  /// Initialize the code intelligence system
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _eventController.add(CodeAnalysisEvent(
      CodeAnalysisEventType.systemInitialized,
      'Code intelligence system initialized',
    ));
  }

  /// Analyze a file and return comprehensive code metrics
  Future<CodeAnalysisResult> analyzeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      // Check cache first
      final cacheKey = filePath;
      final cached = _getCachedAnalysis(cacheKey);
      if (cached != null) {
        _eventController.add(CodeAnalysisEvent(
          CodeAnalysisEventType.cacheHit,
          'Analysis retrieved from cache',
          data: {'file': filePath},
        ));
        return cached;
      }

      final content = await file.readAsString();
      final analysis = await _performAnalysis(filePath, content);

      // Cache the result
      _cache[cacheKey] = analysis;
      _cacheTimestamps[cacheKey] = DateTime.now();

      _eventController.add(CodeAnalysisEvent(
        CodeAnalysisEventType.analysisCompleted,
        'Analysis completed for $filePath',
        data: {'file': filePath, 'quality': analysis.qualityScore},
      ));

      return analysis;
    } catch (e) {
      _eventController.add(CodeAnalysisEvent(
        CodeAnalysisEventType.analysisFailed,
        'Analysis failed for $filePath: $e',
        data: {'file': filePath, 'error': e.toString()},
      ));
      rethrow;
    }
  }

  /// Get code quality score (0.0 to 1.0)
  Future<double> getQualityScore(String filePath) async {
    final analysis = await analyzeFile(filePath);
    return analysis.qualityScore;
  }

  /// Get code improvement suggestions
  Future<List<String>> getSuggestions(String filePath) async {
    final analysis = await analyzeFile(filePath);
    return analysis.suggestions;
  }

  /// Extract symbols from file
  Future<List<CodeSymbol>> extractSymbols(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      return _parseSymbols(content, filePath);
    } catch (e) {
      debugPrint('Failed to extract symbols: $e');
      return [];
    }
  }

  /// Find references to a symbol
  Future<List<CodeReference>> findReferences(String filePath, String symbol) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      return _findSymbolReferences(content, symbol, filePath);
    } catch (e) {
      debugPrint('Failed to find references: $e');
      return [];
    }
  }

  /// Analyze project structure
  Future<ProjectAnalysis> analyzeProject(String projectPath) async {
    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) {
      throw Exception('Project directory not found: $projectPath');
    }

    final files = <String>[];
    final analysisResults = <String, CodeAnalysisResult>{};

    await for (final entity in projectDir.list(recursive: true)) {
      if (entity is File && _isSourceFile(entity.path)) {
        files.add(entity.path);
        try {
          analysisResults[entity.path] = await analyzeFile(entity.path);
        } catch (e) {
          debugPrint('Failed to analyze ${entity.path}: $e');
        }
      }
    }

    final totalFiles = files.length;
    final averageQuality = analysisResults.isEmpty
        ? 0.0
        : analysisResults.values.map((r) => r.qualityScore).reduce((a, b) => a + b) / analysisResults.length;

    final totalLines = analysisResults.values.fold<int>(0, (sum, r) => sum + r.lineCount);
    final totalComplexity = analysisResults.values.fold<double>(0.0, (sum, r) => sum + r.complexity);

    return ProjectAnalysis(
      path: projectPath,
      totalFiles: totalFiles,
      analyzedFiles: analysisResults.length,
      averageQualityScore: averageQuality,
      totalLinesOfCode: totalLines,
      averageComplexity: totalComplexity / max(1, analysisResults.length),
      fileResults: analysisResults,
    );
  }

  /// Clear analysis cache
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    _eventController.add(CodeAnalysisEvent(
      CodeAnalysisEventType.cacheCleared,
      'Analysis cache cleared',
    ));
  }

  /// Dispose resources
  void dispose() {
    clearCache();
    _eventController.close();
  }

  // Private methods

  CodeAnalysisResult? _getCachedAnalysis(String key) {
    final cached = _cache[key];
    final timestamp = _cacheTimestamps[key];

    if (cached != null && timestamp != null) {
      if (DateTime.now().difference(timestamp) < _cacheDuration) {
        return cached;
      } else {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }
    return null;
  }

  bool _isSourceFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['dart', 'py', 'js', 'ts', 'java', 'cpp', 'c', 'h', 'hpp'].contains(ext);
  }

  Future<CodeAnalysisResult> _performAnalysis(String filePath, String content) async {
    final lines = content.split('\n');
    final extension = filePath.split('.').last.toLowerCase();

    final analysis = CodeAnalysisResult(
      filePath: filePath,
      language: _detectLanguage(extension),
      lineCount: lines.length,
      charCount: content.length,
      sizeBytes: utf8.encode(content).length,
    );

    // Basic metrics
    analysis.blankLines = lines.where((line) => line.trim().isEmpty).length;
    analysis.commentLines = _countCommentLines(lines, extension);
    analysis.longestLine = lines.isNotEmpty ? lines.map((l) => l.length).reduce(max) : 0;

    // Parse code elements
    analysis.functions = _parseFunctions(content, extension);
    analysis.classes = _parseClasses(content, extension);
    analysis.imports = _parseImports(content, extension);
    analysis.exports = _parseExports(content, extension);
    analysis.variables = _parseVariables(content, extension);

    // Calculate metrics
    analysis.complexity = _calculateComplexity(content, extension);
    analysis.maintainabilityIndex = _calculateMaintainabilityIndex(analysis);
    analysis.halsteadMetrics = _calculateHalsteadMetrics(content);

    // Lint analysis
    analysis.lints = await _performLinting(content, extension);

    // Quality score
    analysis.qualityScore = _calculateQualityScore(analysis);

    // Generate suggestions
    analysis.suggestions = _generateSuggestions(analysis);

    return analysis;
  }

  String _detectLanguage(String extension) {
    switch (extension) {
      case 'dart': return 'Dart';
      case 'py': return 'Python';
      case 'js': return 'JavaScript';
      case 'ts': return 'TypeScript';
      case 'java': return 'Java';
      case 'cpp': case 'cc': case 'cxx': return 'C++';
      case 'c': return 'C';
      case 'h': case 'hpp': return 'C/C++ Header';
      default: return 'Unknown';
    }
  }

  int _countCommentLines(List<String> lines, String extension) {
    int count = 0;
    bool inBlockComment = false;

    for (final line in lines) {
      final trimmed = line.trim();

      switch (extension) {
        case 'dart':
        case 'java':
        case 'js':
        case 'ts':
        case 'cpp':
        case 'c':
          if (inBlockComment) {
            count++;
            if (trimmed.contains('*/')) inBlockComment = false;
          } else if (trimmed.startsWith('/*')) {
            count++;
            inBlockComment = !trimmed.contains('*/');
          } else if (trimmed.startsWith('//')) {
            count++;
          }
          break;
        case 'py':
          if (trimmed.startsWith('#')) count++;
          break;
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

      switch (extension) {
        case 'dart':
          final functionRegex = RegExp(r'(?:Future<[^>]*>\s+)?(?:static\s+)?(?:\w+\s+)*(\w+)\s*\([^)]*\)\s*(?:async\s*)?{');
          final match = functionRegex.firstMatch(trimmed);
          if (match != null) {
            functions.add(CodeSymbol(
              name: match.group(1)!,
              type: 'function',
              line: i + 1,
              context: _extractFunctionContext(lines, i),
            ));
          }
          break;
        case 'py':
          final functionRegex = RegExp(r'def\s+(\w+)\s*\(');
          final match = functionRegex.firstMatch(trimmed);
          if (match != null) {
            functions.add(CodeSymbol(
              name: match.group(1)!,
              type: 'function',
              line: i + 1,
              context: _extractFunctionContext(lines, i),
            ));
          }
          break;
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

      switch (extension) {
        case 'dart':
          final classRegex = RegExp(r'class\s+(\w+)');
          final match = classRegex.firstMatch(trimmed);
          if (match != null) {
            classes.add(CodeSymbol(
              name: match.group(1)!,
              type: 'class',
              line: i + 1,
              context: _extractClassContext(lines, i),
            ));
          }
          break;
        case 'py':
          final classRegex = RegExp(r'class\s+(\w+)');
          final match = classRegex.firstMatch(trimmed);
          if (match != null) {
            classes.add(CodeSymbol(
              name: match.group(1)!,
              type: 'class',
              line: i + 1,
              context: _extractClassContext(lines, i),
            ));
          }
          break;
      }
    }

    return classes;
  }

  List<String> _parseImports(String content, String extension) {
    final imports = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      switch (extension) {
        case 'dart':
          if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
            final importMatch = RegExp(r"['\"]([^'"]+)['\"]").firstMatch(trimmed);
            imports.add(importMatch.group(1)!);
                    }
          break;
        case 'py':
          if (trimmed.startsWith('import ') || trimmed.startsWith('from ')) {
            imports.add(trimmed);
          }
          break;
      }
    }

    return imports;
  }

  List<String> _parseExports(String content, String extension) {
    final exports = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();

      if (extension == 'dart' && trimmed.startsWith('export ')) {
        final exportMatch = RegExp(r"['\"]([^'"]+)['\"]").firstMatch(trimmed);
        exports.add(exportMatch.group(1)!);
            }
    }

    return exports;
  }

  List<CodeSymbol> _parseVariables(String content, String extension) {
    final variables = <CodeSymbol>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      switch (extension) {
        case 'dart':
          // Match variable declarations
          final varRegex = RegExp(r'(?:final|var|const|(?:\w+\s+)+)(\w+)\s*[=;]');
          final match = varRegex.firstMatch(trimmed);
          if (match != null && !['class', 'void', 'Future'].contains(match.group(1))) {
            variables.add(CodeSymbol(
              name: match.group(1)!,
              type: 'variable',
              line: i + 1,
            ));
          }
          break;
      }
    }

    return variables;
  }

  double _calculateComplexity(String content, String extension) {
    double complexity = 1.0;

    // Count decision points
    final decisionKeywords = ['if', 'else', 'for', 'while', 'case', 'catch', '&&', '||', '?', 'switch'];
    for (final keyword in decisionKeywords) {
      complexity += keyword.allMatches(content).length * 0.2;
    }

    // Count functions/methods
    complexity += _parseFunctions(content, extension).length * 0.3;

    // Count classes
    complexity += _parseClasses(content, extension).length * 0.5;

    return complexity.clamp(0.0, 50.0);
  }

  double _calculateMaintainabilityIndex(CodeAnalysisResult analysis) {
    // Microsoft Maintainability Index calculation (simplified)
    final volume = analysis.halsteadMetrics.volume;
    final complexity = analysis.complexity;
    final linesOfCode = analysis.lineCount;

    if (volume == 0 || complexity == 0) return 0.0;

    final mi = 171 - 5.2 * log(volume) - 0.23 * complexity - 16.2 * log(linesOfCode);
    return mi.clamp(0.0, 171.0);
  }

  HalsteadMetrics _calculateHalsteadMetrics(String content) {
    // Simplified Halstead complexity metrics
    final operators = RegExp(r'[+\-*/%=<>!&|^~?:;,.(){}[\]]').allMatches(content).length;
    final operands = RegExp(r'\b\w+\b').allMatches(content).length;

    final uniqueOperators = <String>{};
    final uniqueOperands = <String>{};

    for (final match in RegExp(r'[+\-*/%=<>!&|^~?:;,.(){}[\]]').allMatches(content)) {
      uniqueOperators.add(match.group(0)!);
    }

    for (final match in RegExp(r'\b\w+\b').allMatches(content)) {
      uniqueOperands.add(match.group(0)!);
    }

    final n1 = uniqueOperators.length;
    final n2 = uniqueOperands.length;
    final N1 = operators;
    final N2 = operands;

    final vocabulary = n1 + n2;
    final length = N1 + N2;
    final volume = length > 0 && vocabulary > 0 ? length * log(vocabulary) : 0.0;
    final difficulty = n1 > 0 && n2 > 0 ? (n1 * N2) / (2 * n2) : 0.0;
    final effort = difficulty * volume;

    return HalsteadMetrics(
      vocabulary: vocabulary,
      length: length,
      volume: volume,
      difficulty: difficulty,
      effort: effort,
    );
  }

  Future<List<LintResult>> _performLinting(String content, String extension) async {
    final lints = <LintResult>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNumber = i + 1;

      // Line length check
      if (line.length > 120) {
        lints.add(LintResult(
          rule: 'line-length',
          message: 'Line too long (${line.length} characters, max 120)',
          severity: LintSeverity.warning,
          line: lineNumber,
          column: 120,
        ));
      }

      // TODO comments
      if (line.contains('TODO') || line.contains('FIXME') || line.contains('XXX')) {
        lints.add(LintResult(
          rule: 'todo-comment',
          message: 'TODO comment found - consider implementing or removing',
          severity: LintSeverity.info,
          line: lineNumber,
        ));
      }

      // Debug prints in production code
      if (line.contains('print(') && !line.contains('kDebugMode')) {
        lints.add(LintResult(
          rule: 'debug-print',
          message: 'Debug print statement found in production code',
          severity: LintSeverity.warning,
          line: lineNumber,
        ));
      }

      // Empty catch blocks
      if (line.contains('catch') && !line.contains('{') && lines.length > i + 1) {
        final nextLine = lines[i + 1].trim();
        if (nextLine == '}' || nextLine.startsWith('//')) {
          lints.add(LintResult(
            rule: 'empty-catch',
            message: 'Empty catch block - add proper error handling',
            severity: LintSeverity.warning,
            line: lineNumber,
          ));
        }
      }
    }

    return lints;
  }

  double _calculateQualityScore(CodeAnalysisResult analysis) {
    double score = 1.0;

    // Penalize for lint issues
    final errorCount = analysis.lints.where((l) => l.severity == LintSeverity.error).length;
    final warningCount = analysis.lints.where((l) => l.severity == LintSeverity.warning).length;

    score -= errorCount * 0.2;
    score -= warningCount * 0.1;

    // Penalize for high complexity
    if (analysis.complexity > 10.0) {
      score -= (analysis.complexity - 10.0) * 0.02;
    }

    // Penalize for low maintainability
    if (analysis.maintainabilityIndex < 50.0) {
      score -= (50.0 - analysis.maintainabilityIndex) * 0.005;
    }

    // Reward for good documentation
    final commentRatio = analysis.commentLines / max(1, analysis.lineCount);
    if (commentRatio > 0.2) {
      score += 0.1;
    }

    return score.clamp(0.0, 1.0);
  }

  List<String> _generateSuggestions(CodeAnalysisResult analysis) {
    final suggestions = <String>[];

    if (analysis.lints.isNotEmpty) {
      suggestions.add('Fix ${analysis.lints.length} lint issues');
    }

    if (analysis.complexity > 10.0) {
      suggestions.add('Consider breaking down complex code (complexity: ${analysis.complexity.toStringAsFixed(1)})');
    }

    if (analysis.maintainabilityIndex < 50.0) {
      suggestions.add('Improve code maintainability (current MI: ${analysis.maintainabilityIndex.toStringAsFixed(1)})');
    }

    final commentRatio = analysis.commentLines / max(1, analysis.lineCount);
    if (commentRatio < 0.1) {
      suggestions.add('Add more documentation comments (current ratio: ${(commentRatio * 100).toStringAsFixed(1)}%)');
    }

    if (analysis.lineCount > 500) {
      suggestions.add('Consider splitting this large file (${analysis.lineCount} lines)');
    }

    return suggestions;
  }

  String _extractFunctionContext(List<String> lines, int startLine) {
    final context = <String>[];
    for (int i = max(0, startLine - 2); i <= min(lines.length - 1, startLine + 2); i++) {
      context.add(lines[i]);
    }
    return context.join('\n');
  }

  String _extractClassContext(List<String> lines, int startLine) {
    final context = <String>[];
    for (int i = max(0, startLine - 1); i <= min(lines.length - 1, startLine + 3); i++) {
      context.add(lines[i]);
    }
    return context.join('\n');
  }

  List<CodeSymbol> _parseSymbols(String content, String filePath) {
    final extension = filePath.split('.').last;
    final symbols = <CodeSymbol>[];
    symbols.addAll(_parseFunctions(content, extension));
    symbols.addAll(_parseClasses(content, extension));
    symbols.addAll(_parseVariables(content, extension));
    return symbols;
  }

  List<CodeReference> _findSymbolReferences(String content, String symbol, String filePath) {
    final references = <CodeReference>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final index = line.indexOf(symbol);
      if (index != -1) {
        references.add(CodeReference(
          file: filePath,
          line: i + 1,
          column: index,
          context: line.trim(),
        ));
      }
    }

    return references;
  }
}

/// Code analysis result
class CodeAnalysisResult {
  final String filePath;
  final String language;
  final int lineCount;
  final int charCount;
  final int sizeBytes;
  List<CodeSymbol> functions;
  List<CodeSymbol> classes;
  List<CodeSymbol> variables;
  List<String> imports;
  List<String> exports;
  List<LintResult> lints;
  double complexity;
  double maintainabilityIndex;
  HalsteadMetrics halsteadMetrics;
  double qualityScore;
  List<String> suggestions;

  int blankLines = 0;
  int commentLines = 0;
  int longestLine = 0;

  CodeAnalysisResult({
    required this.filePath,
    required this.language,
    required this.lineCount,
    required this.charCount,
    required this.sizeBytes,
    this.functions = const [],
    this.classes = const [],
    this.variables = const [],
    this.imports = const [],
    this.exports = const [],
    this.lints = const [],
    this.complexity = 0.0,
    this.maintainabilityIndex = 0.0,
    this.halsteadMetrics = const HalsteadMetrics(),
    this.qualityScore = 0.0,
    this.suggestions = const [],
  });

  int get codeLines => lineCount - blankLines - commentLines;

  @override
  String toString() {
    return 'CodeAnalysisResult(file: $filePath, language: $language, quality: ${qualityScore.toStringAsFixed(2)}, complexity: ${complexity.toStringAsFixed(1)})';
  }
}

/// Code symbol information
class CodeSymbol {
  final String name;
  final String type;
  final int line;
  final String? context;

  CodeSymbol({
    required this.name,
    required this.type,
    required this.line,
    this.context,
  });

  @override
  String toString() => '$type $name at line $line';
}

/// Code reference information
class CodeReference {
  final String file;
  final int line;
  final int column;
  final String context;

  CodeReference({
    required this.file,
    required this.line,
    required this.column,
    required this.context,
  });

  @override
  String toString() => '$file:$line:$column - $context';
}

/// Halstead complexity metrics
class HalsteadMetrics {
  final int vocabulary;
  final int length;
  final double volume;
  final double difficulty;
  final double effort;

  const HalsteadMetrics({
    this.vocabulary = 0,
    this.length = 0,
    this.volume = 0.0,
    this.difficulty = 0.0,
    this.effort = 0.0,
  });

  @override
  String toString() => 'HalsteadMetrics(volume: ${volume.toStringAsFixed(1)}, difficulty: ${difficulty.toStringAsFixed(1)}, effort: ${effort.toStringAsFixed(1)})';
}

/// Lint result
class LintResult {
  final String rule;
  final String message;
  final LintSeverity severity;
  final int line;
  final int? column;

  LintResult({
    required this.rule,
    required this.message,
    required this.severity,
    required this.line,
    this.column,
  });

  @override
  String toString() => '$severity: $rule at line $line - $message';
}

enum LintSeverity {
  info,
  warning,
  error,
}

/// Project analysis result
class ProjectAnalysis {
  final String path;
  final int totalFiles;
  final int analyzedFiles;
  final double averageQualityScore;
  final int totalLinesOfCode;
  final double averageComplexity;
  final Map<String, CodeAnalysisResult> fileResults;

  ProjectAnalysis({
    required this.path,
    required this.totalFiles,
    required this.analyzedFiles,
    required this.averageQualityScore,
    required this.totalLinesOfCode,
    required this.averageComplexity,
    required this.fileResults,
  });

  @override
  String toString() {
    return 'ProjectAnalysis(path: $path, files: $analyzedFiles/$totalFiles, avgQuality: ${averageQualityScore.toStringAsFixed(2)}, totalLOC: $totalLinesOfCode)';
  }
}

/// Code analysis events
class CodeAnalysisEvent {
  final CodeAnalysisEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  CodeAnalysisEvent(
    this.type,
    this.message, {
    this.data,
  }) : timestamp = DateTime.now();
}

enum CodeAnalysisEventType {
  systemInitialized,
  analysisCompleted,
  analysisFailed,
  cacheHit,
  cacheCleared,
}