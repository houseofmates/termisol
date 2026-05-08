import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Custom exception for debugging failures
class DebugException implements Exception {
  final String message;
  const DebugException(this.message);
  
  @override
  String toString() => 'DebugException: $message';
}

/// NVIDIA NIM AI Debugger - Built-in formatting, debugging, and error solving
class NVIDOTerminalDebugger {
  static final NVIDOTerminalDebugger _instance = NVIDOTerminalDebugger._internal();
  factory NVIDOTerminalDebugger() => _instance;
  NVIDOTerminalDebugger._internal();

  final String _nimEndpoint = 'https://integrate.nvidia.com/v1/chat/completions';
  String? _apiKey;
  final Map<String, DebugSession> _debugSessions = {};
  final Map<String, CodeFormat> _formatCache = {};
  
  bool _isInitialized = false;
  
  static const Duration _timeout = Duration(seconds: 30);
  
  final _debugController = StreamController<DebugEvent>.broadcast();
  Stream<DebugEvent> get events => _debugController.stream;

  /// Initialize with API key
  Future<void> initialize(String apiKey) async {
    if (apiKey.isEmpty || !apiKey.startsWith('nvapi-')) {
      throw const DebugException('Invalid NVIDIA API key format');
    }
    _apiKey = apiKey;
    _isInitialized = true;
    debugPrint('🐛 NVIDIA AI Debugger initialized');
  }

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  Future<DebugResult> debugError({
    required String error,
    required String command,
    required String output,
    required String currentDirectory,
    List<String>? commandHistory,
  }) async {
    final sessionId = _generateSessionId();
    
    try {
      final prompt = _buildDebugPrompt(
        error: error,
        command: command,
        output: output,
        currentDirectory: currentDirectory,
        commandHistory: commandHistory ?? [],
      );
      
      final response = await _callNVIDIA(prompt);
      final debugAnalysis = _parseDebugResponse(response);
      
      final session = DebugSession(
        id: sessionId,
        error: error,
        command: command,
        analysis: debugAnalysis,
        timestamp: DateTime.now(),
        directory: currentDirectory,
      );
      
      _debugSessions[sessionId] = session;
      
      _debugController.add(DebugEvent(
        type: DebugEventType.debugCompleted,
        data: {
          'session_id': sessionId,
          'error': error,
          'solutions': debugAnalysis.solutions.length,
        },
      ));
      
      return DebugResult(
        success: true,
        sessionId: sessionId,
        analysis: debugAnalysis,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to debug error: $e');
      return DebugResult.error(e.toString());
    }
  }

  Future<FormatResult> formatCode({
    required String code,
    required String language,
    required String currentDirectory,
    FormattingOptions? options,
  }) async {
    final cacheKey = _generateFormatCacheKey(code, language);
    
    // Check cache first
    if (_formatCache.containsKey(cacheKey)) {
      final cachedFormat = _formatCache[cacheKey]!;
      return FormatResult(
        success: true,
        formattedCode: cachedFormat.formattedCode,
        fromCache: true,
      );
    }
    
    try {
      final prompt = _buildFormatPrompt(
        code: code,
        language: language,
        currentDirectory: currentDirectory,
        options: options ?? FormattingOptions(),
      );
      
      final response = await _callNVIDIA(prompt);
      final formattedCode = _parseFormatResponse(response);
      
      // Cache the result
      _formatCache[cacheKey] = CodeFormat(
        originalCode: code,
        formattedCode: formattedCode,
        language: language,
        timestamp: DateTime.now(),
      );
      
      _debugController.add(DebugEvent(
        type: DebugEventType.formatCompleted,
        data: {
          'language': language,
          'code_length': code.length,
          'formatted_length': formattedCode.length,
        },
      ));
      
      return FormatResult(
        success: true,
        formattedCode: formattedCode,
        fromCache: false,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to format code: $e');
      return FormatResult.error(e.toString());
    }
  }

  Future<AnalysisResult> analyzeCode({
    required String code,
    required String language,
    required String currentDirectory,
    AnalysisType analysisType = AnalysisType.general,
  }) async {
    try {
      final prompt = _buildAnalysisPrompt(
        code: code,
        language: language,
        currentDirectory: currentDirectory,
        analysisType: analysisType,
      );
      
      final response = await _callNVIDIA(prompt);
      final analysis = _parseAnalysisResponse(response);
      
      _debugController.add(DebugEvent(
        type: DebugEventType.analysisCompleted,
        data: {
          'language': language,
          'analysis_type': analysisType.toString(),
          'issues_found': analysis.issues.length,
        },
      ));
      
      return AnalysisResult(
        success: true,
        analysis: analysis,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to analyze code: $e');
      return AnalysisResult.error(e.toString());
    }
  }

  Future<OptimizeResult> optimizeCode({
    required String code,
    required String language,
    required String currentDirectory,
    List<String>? optimizationGoals,
  }) async {
    try {
      final prompt = _buildOptimizationPrompt(
        code: code,
        language: language,
        currentDirectory: currentDirectory,
        optimizationGoals: optimizationGoals ?? ['performance', 'readability'],
      );
      
      final response = await _callNVIDIA(prompt);
      final optimization = _parseOptimizationResponse(response);
      
      _debugController.add(DebugEvent(
        type: DebugEventType.optimizationCompleted,
        data: {
          'language': language,
          'optimizations': optimization.suggestions.length,
        },
      ));
      
      return OptimizeResult(
        success: true,
        optimization: optimization,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to optimize code: $e');
      return OptimizeResult.error(e.toString());
    }
  }

  String _buildDebugPrompt({
    required String error,
    required String command,
    required String output,
    required String currentDirectory,
    required List<String> commandHistory,
  }) {
    return '''
You are an expert terminal and system debugger. Analyze this error and provide solutions:

ERROR: $error
COMMAND: $command
OUTPUT: $output
CURRENT DIRECTORY: $currentDirectory
RECENT COMMANDS: ${commandHistory.length >= 5 ? commandHistory.sublist(commandHistory.length - 5).join(', ') : commandHistory.join(', ')}

Provide a comprehensive analysis in this format:

ROOT_CAUSE: [Identify the root cause]
EXPLANATION: [Explain why this error occurs]
SOLUTIONS: [Provide 2-3 specific solutions]
- SOLUTION_1: [First solution with steps]
- SOLUTION_2: [Second solution with steps]
- SOLUTION_3: [Third solution with steps if applicable]

PREVENTION: [How to prevent this error in the future]
RELATED_COMMANDS: [Suggest related commands that might help]
CONFIDENCE: [0.1-1.0 confidence level]

Focus on practical, actionable solutions that a developer can implement immediately.
''';
  }

  String _buildFormatPrompt({
    required String code,
    required String language,
    required String currentDirectory,
    required FormattingOptions options,
  }) {
    return '''
Format this $language code according to best practices and the specified options:

CODE:
```$language
$code
```

OPTIONS:
- Indent size: ${options.indentSize}
- Use tabs: ${options.useTabs}
- Line length: ${options.maxLineLength}
- Sort imports: ${options.sortImports}
- Remove unused imports: ${options.removeUnusedImports}

Return ONLY the formatted code without any explanations or markdown formatting.
Follow the official style guide for $language.
''';
  }

  String _buildAnalysisPrompt({
    required String code,
    required String language,
    required String currentDirectory,
    required AnalysisType analysisType,
  }) {
    String analysisFocus = '';
    switch (analysisType) {
      case AnalysisType.security:
        analysisFocus = 'security vulnerabilities and potential exploits';
        break;
      case AnalysisType.performance:
        analysisFocus = 'performance bottlenecks and optimization opportunities';
        break;
      case AnalysisType.codeQuality:
        analysisFocus = 'code quality, maintainability, and best practices';
        break;
      case AnalysisType.general:
        analysisFocus = 'general issues, bugs, and improvements';
        break;
    }
    
    return '''
Analyze this $language code for $analysisFocus:

CODE:
```$language
$code
```

CURRENT DIRECTORY: $currentDirectory

Provide analysis in this format:

ISSUES: [List all issues found]
- ISSUE_1: [Description with severity (low/medium/high/critical)]
- ISSUE_2: [Description with severity]
- ISSUE_3: [Description with severity]

RECOMMENDATIONS: [List specific recommendations]
- REC_1: [Actionable recommendation]
- REC_2: [Actionable recommendation]

METRICS: [Code quality metrics]
- Complexity: [Low/Medium/High]
- Maintainability: [Score 1-10]
- Test Coverage: [Estimated if applicable]

CONFIDENCE: [0.1-1.0 confidence level]
''';
  }

  String _buildOptimizationPrompt({
    required String code,
    required String language,
    required String currentDirectory,
    required List<String> optimizationGoals,
  }) {
    return '''
Optimize this $language code for the following goals: ${optimizationGoals.join(', ')}

CODE:
```$language
$code
```

CURRENT DIRECTORY: $currentDirectory

Provide optimization suggestions in this format:

OPTIMIZATIONS: [List optimization suggestions]
- OPT_1: [Optimization with expected impact]
- OPT_2: [Optimization with expected impact]
- OPT_3: [Optimization with expected impact]

OPTIMIZED_CODE: [Provide the optimized version of the code]

PERFORMANCE_GAIN: [Estimated performance improvement]
COMPLEXITY_CHANGE: [How complexity changes]

CONFIDENCE: [0.1-1.0 confidence level]
''';
  }

  Future<String> _callNVIDIA(String prompt) async {
    if (_apiKey == null) {
      throw DebugException('NVIDIA API key not initialized');
    }
    
    final response = await http.post(
      Uri.parse(_nimEndpoint),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'nvidia/nemotron-4-340b-instruct',
        'messages': [
          {'role': 'system', 'content': 'You are an expert developer and system administrator with deep knowledge of terminal operations, debugging, and code optimization.'},
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 2000,
        'temperature': 0.3,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices[0] as Map<String, dynamic>;
          final message = firstChoice['message'] as Map<String, dynamic>?;
          return message?['content'] as String? ?? '';
        }
        return '';
      } catch (e) {
        throw DebugException('Failed to parse NVIDIA API response: $e');
      }
    } else {
      throw DebugException('NVIDIA API error: ${response.statusCode} - ${response.reasonPhrase}');
    }
  }

  DebugAnalysis _parseDebugResponse(String response) {
    final lines = response.split('\n');
    String? rootCause;
    String? explanation;
    final solutions = <String>[];
    String? prevention;
    final relatedCommands = <String>[];
    double confidence = 0.5;

    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('ROOT_CAUSE:')) {
        rootCause = line.substring(11).trim();
      } else if (line.startsWith('EXPLANATION:')) {
        explanation = line.substring(12).trim();
      } else if (line.startsWith('SOLUTIONS:')) {
        currentSection = 'solutions';
      } else if (line.startsWith('PREVENTION:')) {
        prevention = line.substring(11).trim();
        currentSection = 'prevention';
      } else if (line.startsWith('RELATED_COMMANDS:')) {
        currentSection = 'commands';
      } else if (line.startsWith('CONFIDENCE:')) {
        confidence = double.tryParse(line.substring(11).trim()) ?? 0.5;
      } else if (currentSection == 'solutions' && line.startsWith('- SOLUTION_')) {
        solutions.add(line.substring(line.indexOf(':') + 1).trim());
      } else if (currentSection == 'commands' && line.trim().isNotEmpty) {
        relatedCommands.add(line.trim());
      }
    }

    return DebugAnalysis(
      rootCause: rootCause ?? 'Unknown',
      explanation: explanation ?? 'No explanation available',
      solutions: solutions,
      prevention: prevention ?? 'No prevention advice available',
      relatedCommands: relatedCommands,
      confidence: confidence,
    );
  }

  String _parseFormatResponse(String response) {
    // Extract code block from response
    final codeBlock = RegExp(r'```(?:\w+)?\n([\s\S]*?)\n```');
    final match = codeBlock.firstMatch(response);
    
    if (match != null) {
      return match.group(1) ?? response.trim();
    }
    
    // If no code block, return the response as-is (might already be just code)
    return response.trim();
  }

  CodeAnalysis _parseAnalysisResponse(String response) {
    final lines = response.split('\n');
    final issues = <CodeIssue>[];
    final recommendations = <String>[];
    String complexity = 'Medium';
    int maintainability = 5;
    String testCoverage = 'Unknown';
    double confidence = 0.5;

    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('ISSUES:')) {
        currentSection = 'issues';
      } else if (line.startsWith('RECOMMENDATIONS:')) {
        currentSection = 'recommendations';
      } else if (line.startsWith('METRICS:')) {
        currentSection = 'metrics';
      } else if (line.startsWith('CONFIDENCE:')) {
        confidence = double.tryParse(line.substring(11).trim()) ?? 0.5;
      } else if (currentSection == 'issues' && line.startsWith('- ISSUE_')) {
        final match = RegExp(r'- ISSUE_\d+: (.+) \((low|medium|high|critical)\)').firstMatch(line);
        if (match != null) {
          issues.add(CodeIssue(
            description: match.group(1) ?? '',
            severity: match.group(2) ?? 'medium',
          ));
        }
      } else if (currentSection == 'recommendations' && line.startsWith('- REC_')) {
        recommendations.add(line.substring(line.indexOf(':') + 1).trim());
      } else if (currentSection == 'metrics') {
        if (line.contains('Complexity:')) {
          complexity = line.split(':').last.trim();
        } else if (line.contains('Maintainability:')) {
          maintainability = int.tryParse(line.split(':').last.trim()) ?? 5;
        } else if (line.contains('Test Coverage:')) {
          testCoverage = line.split(':').last.trim();
        }
      }
    }

    return CodeAnalysis(
      issues: issues,
      recommendations: recommendations,
      complexity: complexity,
      maintainability: maintainability,
      testCoverage: testCoverage,
      confidence: confidence,
    );
  }

  CodeOptimization _parseOptimizationResponse(String response) {
    final lines = response.split('\n');
    final suggestions = <String>[];
    String? optimizedCode;
    String? performanceGain;
    String? complexityChange;
    double confidence = 0.5;

    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('OPTIMIZATIONS:')) {
        currentSection = 'optimizations';
      } else if (line.startsWith('OPTIMIZED_CODE:')) {
        currentSection = 'code';
      } else if (line.startsWith('PERFORMANCE_GAIN:')) {
        performanceGain = line.substring(16).trim();
      } else if (line.startsWith('COMPLEXITY_CHANGE:')) {
        complexityChange = line.substring(18).trim();
      } else if (line.startsWith('CONFIDENCE:')) {
        confidence = double.tryParse(line.substring(11).trim()) ?? 0.5;
      } else if (currentSection == 'optimizations' && line.startsWith('- OPT_')) {
        suggestions.add(line.substring(line.indexOf(':') + 1).trim());
      } else if (currentSection == 'code') {
        optimizedCode = (optimizedCode ?? '') + line + '\n';
      }
    }

    return CodeOptimization(
      suggestions: suggestions,
      optimizedCode: optimizedCode?.trim() ?? '',
      performanceGain: performanceGain ?? 'Unknown',
      complexityChange: complexityChange ?? 'No change',
      confidence: confidence,
    );
  }

  String _generateSessionId() {
    return 'debug_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
  }

  String _generateFormatCacheKey(String code, String language) {
    return '${code.hashCode}_${language}';
  }

  List<DebugSession> getDebugHistory() {
    return _debugSessions.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Map<String, dynamic> getStatistics() {
    return {
      'debug_sessions': _debugSessions.length,
      'format_cache': _formatCache.length,
      'total_solutions': _debugSessions.values
          .fold(0, (sum, session) => sum + session.analysis.solutions.length),
    };
  }

  Future<void> dispose() async {
    _debugController.close();
    _debugSessions.clear();
    _formatCache.clear();
  }
}

class DebugSession {
  final String id;
  final String error;
  final String command;
  final DebugAnalysis analysis;
  final DateTime timestamp;
  final String directory;
  
  DebugSession({
    required this.id,
    required this.error,
    required this.command,
    required this.analysis,
    required this.timestamp,
    required this.directory,
  });
}

class DebugAnalysis {
  final String rootCause;
  final String explanation;
  final List<String> solutions;
  final String prevention;
  final List<String> relatedCommands;
  final double confidence;
  
  DebugAnalysis({
    required this.rootCause,
    required this.explanation,
    required this.solutions,
    required this.prevention,
    required this.relatedCommands,
    required this.confidence,
  });
}

class CodeFormat {
  final String originalCode;
  final String formattedCode;
  final String language;
  final DateTime timestamp;
  
  CodeFormat({
    required this.originalCode,
    required this.formattedCode,
    required this.language,
    required this.timestamp,
  });
}

class CodeIssue {
  final String description;
  final String severity;
  
  CodeIssue({
    required this.description,
    required this.severity,
  });
}

class CodeAnalysis {
  final List<CodeIssue> issues;
  final List<String> recommendations;
  final String complexity;
  final int maintainability;
  final String testCoverage;
  final double confidence;
  
  CodeAnalysis({
    required this.issues,
    required this.recommendations,
    required this.complexity,
    required this.maintainability,
    required this.testCoverage,
    required this.confidence,
  });
}

class CodeOptimization {
  final List<String> suggestions;
  final String optimizedCode;
  final String performanceGain;
  final String complexityChange;
  final double confidence;
  
  CodeOptimization({
    required this.suggestions,
    required this.optimizedCode,
    required this.performanceGain,
    required this.complexityChange,
    required this.confidence,
  });
}

class DebugResult {
  final bool success;
  final String? sessionId;
  final DebugAnalysis? analysis;
  final String? error;
  
  DebugResult({
    required this.success,
    this.sessionId,
    this.analysis,
    this.error,
  });
  
  factory DebugResult.success(String sessionId, DebugAnalysis analysis) {
    return DebugResult(
      success: true,
      sessionId: sessionId,
      analysis: analysis,
    );
  }
  
  factory DebugResult.error(String error) {
    return DebugResult(
      success: false,
      error: error,
    );
  }
}

class FormatResult {
  final bool success;
  final String? formattedCode;
  final bool fromCache;
  final String? error;
  
  FormatResult({
    required this.success,
    this.formattedCode,
    required this.fromCache,
    this.error,
  });
  
  factory FormatResult.success(String formattedCode, bool fromCache) {
    return FormatResult(
      success: true,
      formattedCode: formattedCode,
      fromCache: fromCache,
    );
  }
  
  factory FormatResult.error(String error) {
    return FormatResult(
      success: false,
      fromCache: false,
      error: error,
    );
  }
}

class AnalysisResult {
  final bool success;
  final CodeAnalysis? analysis;
  final String? error;
  
  AnalysisResult({
    required this.success,
    this.analysis,
    this.error,
  });
  
  factory AnalysisResult.success(CodeAnalysis analysis) {
    return AnalysisResult(
      success: true,
      analysis: analysis,
    );
  }
  
  factory AnalysisResult.error(String error) {
    return AnalysisResult(
      success: false,
      error: error,
    );
  }
}

class OptimizeResult {
  final bool success;
  final CodeOptimization? optimization;
  final String? error;
  
  OptimizeResult({
    required this.success,
    this.optimization,
    this.error,
  });
  
  factory OptimizeResult.success(CodeOptimization optimization) {
    return OptimizeResult(
      success: true,
      optimization: optimization,
    );
  }
  
  factory OptimizeResult.error(String error) {
    return OptimizeResult(
      success: false,
      error: error,
    );
  }
}

class FormattingOptions {
  final int indentSize;
  final bool useTabs;
  final int maxLineLength;
  final bool sortImports;
  final bool removeUnusedImports;
  
  FormattingOptions({
    this.indentSize = 2,
    this.useTabs = false,
    this.maxLineLength = 80,
    this.sortImports = true,
    this.removeUnusedImports = true,
  });
}

class DebugEvent {
  final DebugEventType type;
  final Map<String, dynamic>? data;
  
  DebugEvent({
    required this.type,
    this.data,
  });
}

enum AnalysisType {
  general,
  security,
  performance,
  codeQuality,
}

enum DebugEventType {
  debugCompleted,
  formatCompleted,
  analysisCompleted,
  optimizationCompleted,
}
