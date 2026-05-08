import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Custom exception for AI suggestion failures
class AISuggestionException implements Exception {
  final String message;
  const AISuggestionException(this.message);
  
  @override
  String toString() => 'AISuggestionException: $message';
}

/// Context-Aware AI Suggestions with NVIDIA NIM integration
class ContextAwareAISuggestions {
  static final ContextAwareAISuggestions _instance = ContextAwareAISuggestions._internal();
  factory ContextAwareAISuggestions() => _instance;
  ContextAwareAISuggestions._internal();

  final String _nimEndpoint = 'https://integrate.nvidia.com/v1/chat/completions';
  final String _apiKey = 'nvapi-'; // User will need to set this
  final Map<String, List<String>> _contextCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  
  static const Duration _cacheTimeout = Duration(minutes: 10);
  static const Duration _cleanupInterval = Duration(minutes: 5);
  
  final _suggestionController = StreamController<AISuggestionEvent>.broadcast();
  Stream<AISuggestionEvent> get events => _suggestionController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startCleanupTimer();
    _isInitialized = true;
    debugPrint('🧠 Context-Aware AI Suggestions initialized');
  }

  Future<List<AISuggestion>> getSuggestions({
    required String currentCommand,
    required String currentDirectory,
    required List<String> commandHistory,
    required Map<String, dynamic> environment,
  }) async {
    final cacheKey = _generateCacheKey(currentCommand, currentDirectory);
    
    // Check cache first
    if (_contextCache.containsKey(cacheKey)) {
      final cachedSuggestions = _contextCache[cacheKey]!;
      return cachedSuggestions.map((s) => AISuggestion(
        text: s,
        confidence: 0.8,
        source: AISuggestionSource.cache,
        context: currentDirectory,
      )).toList();
    }

    try {
      final context = _buildContext(currentDirectory, commandHistory, environment);
      final prompt = _buildPrompt(currentCommand, context);
      
      final response = await _callNVIDIA(prompt);
      final suggestions = _parseSuggestions(response);
      
      // Cache the results
      _contextCache[cacheKey] = suggestions.map((s) => s.text).toList();
      _cacheTimestamps[cacheKey] = DateTime.now();
      
      _suggestionController.add(AISuggestionEvent(
        type: AISuggestionEventType.suggestionsGenerated,
        data: {
          'command': currentCommand,
          'suggestions': suggestions.length,
          'source': 'nvidia_nim',
        },
      ));
      
      return suggestions;
      
    } catch (e) {
      debugPrint('❌ Failed to get AI suggestions: $e');
      return _getFallbackSuggestions(currentCommand, currentDirectory);
    }
  }

  Future<List<AISuggestion>> getErrorSolution({
    required String error,
    required String command,
    required String currentDirectory,
    required List<String> commandHistory,
  }) async {
    try {
      final prompt = _buildErrorPrompt(error, command, currentDirectory, commandHistory);
      final response = await _callNVIDIA(prompt);
      final solutions = _parseErrorSolutions(response);
      
      _suggestionController.add(AISuggestionEvent(
        type: AISuggestionEventType.errorSolutionGenerated,
        data: {
          'error': error,
          'solutions': solutions.length,
        },
      ));
      
      return solutions;
      
    } catch (e) {
      debugPrint('❌ Failed to get error solution: $e');
      return _getFallbackErrorSolutions(error);
    }
  }

  Future<List<AISuggestion>> getCodeFormatting({
    required String code,
    required String language,
    required String currentDirectory,
  }) async {
    try {
      final prompt = _buildFormattingPrompt(code, language, currentDirectory);
      final response = await _callNVIDIA(prompt);
      final formattedCode = _parseFormattedCode(response);
      
      return [AISuggestion(
        text: formattedCode,
        confidence: 0.9,
        source: AISuggestionSource.nvidia,
        context: 'formatting',
      )];
      
    } catch (e) {
      debugPrint('❌ Failed to format code: $e');
      return [];
    }
  }

  Future<List<AISuggestion>> getOptimizationRecommendations({
    required Map<String, dynamic> performanceMetrics,
    required String currentDirectory,
  }) async {
    try {
      final prompt = _buildOptimizationPrompt(performanceMetrics, currentDirectory);
      final response = await _callNVIDIA(prompt);
      final recommendations = _parseOptimizationRecommendations(response);
      
      _suggestionController.add(AISuggestionEvent(
        type: AISuggestionEventType.optimizationGenerated,
        data: {
          'recommendations': recommendations.length,
          'metrics': performanceMetrics,
        },
      ));
      
      return recommendations;
      
    } catch (e) {
      debugPrint('❌ Failed to get optimization recommendations: $e');
      return _getFallbackOptimizationRecommendations(performanceMetrics);
    }
  }

  String _generateCacheKey(String command, String directory) {
    return '${command.hashCode}_${directory.hashCode}';
  }

  Map<String, dynamic> _buildContext(
    String currentDirectory,
    List<String> commandHistory,
    Map<String, dynamic> environment,
  ) {
    return {
      'current_directory': currentDirectory,
      'recent_commands': commandHistory.take(10).toList(),
      'environment': environment,
      'timestamp': DateTime.now().toIso8601String(),
      'project_type': _detectProjectType(currentDirectory),
      'available_tools': _detectAvailableTools(),
    };
  }

  String _buildPrompt(String currentCommand, Map<String, dynamic> context) {
    return '''
You are an expert terminal assistant. Based on the following context, suggest relevant commands or improvements:

Current Command: $currentCommand
Current Directory: ${context['current_directory']}
Project Type: ${context['project_type']}
Recent Commands: ${context['recent_commands'].join(', ')}
Available Tools: ${context['available_tools']}

Provide 3-5 concise, helpful suggestions. Format each suggestion as:
SUGGESTION: [command/text]
REASON: [brief explanation]
CONFIDENCE: [0.1-1.0]

Focus on:
1. Command completion or correction
2. Better alternatives
3. Context-aware improvements
4. Next logical steps
5. Common mistakes to avoid
''';
  }

  String _buildErrorPrompt(
    String error,
    String command,
    String currentDirectory,
    List<String> commandHistory,
  ) {
    return '''
You are an expert terminal troubleshooter. Help solve this error:

Error: $error
Command: $command
Directory: $currentDirectory
Recent Commands: ${commandHistory.take(5).join(', ')}

Provide 2-3 solutions. Format each as:
SOLUTION: [fix/command]
EXPLANATION: [why this works]
CONFIDENCE: [0.1-1.0]

Focus on:
1. Immediate fixes
2. Root cause analysis
3. Prevention methods
''';
  }

  String _buildFormattingPrompt(String code, String language, String currentDirectory) {
    return '''
Format this $language code according to best practices:

Code:
$code

Directory: $currentDirectory

Return only the formatted code, no explanations.
''';
  }

  String _buildOptimizationPrompt(Map<String, dynamic> metrics, String currentDirectory) {
    return '''
Analyze these performance metrics and suggest optimizations:

Metrics: ${jsonEncode(metrics)}
Directory: $currentDirectory

Provide 3-5 optimization suggestions. Format each as:
OPTIMIZATION: [suggestion]
IMPACT: [high/medium/low]
EFFORT: [easy/medium/hard]
CONFIDENCE: [0.1-1.0]

Focus on:
1. Terminal performance
2. Resource usage
3. Workflow improvements
4. Command optimization
5. System tuning
''';
  }

  Future<String> _callNVIDIA(String prompt) async {
    final response = await http.post(
      Uri.parse(_nimEndpoint),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'nvidia/nemotron-4-340b-instruct',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 1000,
        'temperature': 0.7,
      }),
    );

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
        throw AISuggestionException('Failed to parse NVIDIA API response: $e');
      }
    } else {
      throw AISuggestionException('NVIDIA API error: ${response.statusCode} - ${response.reasonPhrase}');
    }
  }

  List<AISuggestion> _parseSuggestions(String response) {
    final suggestions = <AISuggestion>[];
    final lines = response.split('\n');
    
    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('SUGGESTION:') && 
          lines[i + 1].startsWith('REASON:') && 
          lines[i + 2].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(11).trim();
        final reason = lines[i + 1].substring(7).trim();
        final confidence = double.tryParse(lines[i + 2].substring(11).trim()) ?? 0.5;
        
        suggestions.add(AISuggestion(
          text: text,
          confidence: confidence,
          source: AISuggestionSource.nvidia,
          context: reason,
        ));
      }
    }
    
    return suggestions;
  }

  List<AISuggestion> _parseErrorSolutions(String response) {
    final solutions = <AISuggestion>[];
    final lines = response.split('\n');
    
    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('SOLUTION:') && 
          lines[i + 1].startsWith('EXPLANATION:') && 
          lines[i + 2].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(10).trim();
        final explanation = lines[i + 1].substring(12).trim();
        final confidence = double.tryParse(lines[i + 2].substring(11).trim()) ?? 0.5;
        
        solutions.add(AISuggestion(
          text: text,
          confidence: confidence,
          source: AISuggestionSource.nvidia,
          context: explanation,
        ));
      }
    }
    
    return solutions;
  }

  String _parseFormattedCode(String response) {
    // Extract code block from response
    final codeBlock = RegExp(r'```(?:\w+)?\n([\s\S]*?)\n```');
    final match = codeBlock.firstMatch(response);
    return match?.group(1) ?? response.trim();
  }

  List<AISuggestion> _parseOptimizationRecommendations(String response) {
    final recommendations = <AISuggestion>[];
    final lines = response.split('\n');
    
    for (int i = 0; i < lines.length - 3; i += 4) {
      if (lines[i].startsWith('OPTIMIZATION:') && 
          lines[i + 1].startsWith('IMPACT:') && 
          lines[i + 2].startsWith('EFFORT:') && 
          lines[i + 3].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(13).trim();
        final impact = lines[i + 1].substring(7).trim();
        final effort = lines[i + 2].substring(7).trim();
        final confidence = double.tryParse(lines[i + 3].substring(11).trim()) ?? 0.5;
        
        recommendations.add(AISuggestion(
          text: text,
          confidence: confidence,
          source: AISuggestionSource.nvidia,
          context: 'Impact: $impact, Effort: $effort',
        ));
      }
    }
    
    return recommendations;
  }

  List<AISuggestion> _getFallbackSuggestions(String command, String directory) {
    final suggestions = <AISuggestion>[];
    
    // Simple pattern-based fallbacks
    if (command.startsWith('git')) {
      suggestions.add(AISuggestion(
        text: 'git status',
        confidence: 0.6,
        source: AISuggestionSource.fallback,
        context: 'Common git command',
      ));
    } else if (command.startsWith('ls')) {
      suggestions.add(AISuggestion(
        text: 'ls -la',
        confidence: 0.7,
        source: AISuggestionSource.fallback,
        context: 'Detailed listing',
      ));
    }
    
    return suggestions;
  }

  List<AISuggestion> _getFallbackErrorSolutions(String error) {
    return [
      AISuggestion(
        text: 'Check command syntax and try again',
        confidence: 0.5,
        source: AISuggestionSource.fallback,
        context: 'General troubleshooting',
      ),
      AISuggestion(
        text: 'Use --help flag for command assistance',
        confidence: 0.6,
        source: AISuggestionSource.fallback,
        context: 'Get help',
      ),
    ];
  }

  List<AISuggestion> _getFallbackOptimizationRecommendations(Map<String, dynamic> metrics) {
    return [
      AISuggestion(
        text: 'Clear terminal history and cache',
        confidence: 0.4,
        source: AISuggestionSource.fallback,
        context: 'Basic optimization',
      ),
      AISuggestion(
        text: 'Use aliases for frequently used commands',
        confidence: 0.5,
        source: AISuggestionSource.fallback,
        context: 'Workflow improvement',
      ),
    ];
  }

  String _detectProjectType(String directory) {
    if (directory.contains('node_modules')) return 'nodejs';
    if (directory.contains('requirements.txt') || directory.contains('venv')) return 'python';
    if (directory.contains('Cargo.toml')) return 'rust';
    if (directory.contains('go.mod')) return 'go';
    if (directory.contains('.git')) return 'git';
    return 'unknown';
  }

  List<String> _detectAvailableTools() {
    return ['git', 'npm', 'yarn', 'docker', 'python', 'node', 'go', 'rust'];
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupCache();
    });
  }

  void _cleanupCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTimeout) {
        expiredKeys.add(entry.key);
      }
    }
    
    for (final key in expiredKeys) {
      _contextCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (expiredKeys.isNotEmpty) {
      debugPrint('🧠 Cleaned ${expiredKeys.length} expired AI suggestion cache entries');
    }
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _suggestionController.close();
    _contextCache.clear();
    _cacheTimestamps.clear();
  }
}

class AISuggestion {
  final String text;
  final double confidence;
  final AISuggestionSource source;
  final String context;
  
  AISuggestion({
    required this.text,
    required this.confidence,
    required this.source,
    required this.context,
  });
}

class AISuggestionEvent {
  final AISuggestionEventType type;
  final Map<String, dynamic>? data;
  
  AISuggestionEvent({
    required this.type,
    this.data,
  });
}

enum AISuggestionSource {
  nvidia,
  cache,
  fallback,
}

enum AISuggestionEventType {
  suggestionsGenerated,
  errorSolutionGenerated,
  optimizationGenerated,
}
