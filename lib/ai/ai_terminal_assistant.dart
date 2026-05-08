import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/production_config_system.dart';

/// NVIDIA AI-powered terminal assistant with context awareness and intelligent suggestions.
/// Integrates with NVIDIA AI services for code generation, terminal command assistance, and system optimization.
class NvidiaAITerminalAssistant {
  static const String nvidiaApiBaseUrl = 'https://api.nvidia.com/v1';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxContextLength = 4096;
  static const int maxRetries = 3;

  final StreamController<AIEvent> _eventController = StreamController.broadcast();
  final List<AIConversation> _conversations = [];
  final Map<String, AIContext> _activeContexts = {};

  String? _apiKey;
  bool _isInitialized = false;
  int _totalRequests = 0;
  int _successfulRequests = 0;
  DateTime? _lastRequestTime;

  /// Stream of AI events
  Stream<AIEvent> get events => _eventController.stream;

  /// Whether the AI assistant is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Success rate of AI requests
  double get successRate {
    return _totalRequests > 0 ? _successfulRequests / _totalRequests : 0.0;
  }

  /// Number of active conversations
  int get activeConversationCount => _conversations.length;

  NvidiaAITerminalAssistant() {
    _initialize();
  }

  Future<void> _initialize() async {
    final config = ProductionConfigSystem();

    // Wait for config to initialize
    if (!config.initialized) {
      await config.initialize();
    }

    // Get API key from config (would be set securely)
    _apiKey = config.get<String>('ai.api_key');

    // Enable AI features based on config
    final aiEnabled = config.get<bool>('ai.enabled', true);
    if (aiEnabled == true && (_apiKey?.isNotEmpty ?? false)) {
      _isInitialized = true;
      debugPrint('NVIDIA AI Terminal Assistant initialized');
    } else {
      debugPrint('NVIDIA AI Terminal Assistant disabled - no API key or disabled in config');
    }
  }

  /// Process text input and return AI response
  Future<AIResponse> processText({
    required String input,
    required AICapability capability,
    required String contextId,
    bool preferLocal = false,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) {
      return AIResponse.failure(
        'AI assistant not initialized',
        contextId: contextId,
      );
    }

    _totalRequests++;
    _lastRequestTime = DateTime.now();

    try {
      // Get or create context
      final context = _getOrCreateContext(contextId);

      // Update context with new input
      context.addMessage(AIMessage.user(input, metadata: metadata));

      // Prepare request based on capability
      final request = _prepareAIRequest(input, capability, context, preferLocal);

      // Make API call with retries
      AIResponse response = await _makeAPIRequestWithRetry(request);

      if (response.success) {
        _successfulRequests++;

        // Update context with response
        context.addMessage(AIMessage.assistant(response.output));

        // Emit success event
        _eventController.add(AIEvent.responseGenerated(
          contextId,
          capability,
          response.output.length,
        ));
      } else {
        // Emit failure event
        _eventController.add(AIEvent.requestFailed(contextId, capability, response.error!));
      }

      return response;

    } catch (e) {
      final error = 'AI processing failed: $e';
      _eventController.add(AIEvent.requestFailed(contextId, capability, error));

      return AIResponse.failure(
        error,
        contextId: contextId,
      );
    }
  }

  AIContext _getOrCreateContext(String contextId) {
    return _activeContexts[contextId] ??= AIContext(contextId);
  }

  Map<String, dynamic> _prepareAIRequest(
    String input,
    AICapability capability,
    AIContext context,
    bool preferLocal,
  ) {
    final config = ProductionConfigSystem();
    final model = config.get<String>('ai.model', 'nvidia-llama-3.1-8b-instruct');
    final maxTokens = config.get<int>('ai.max_tokens', 4096);
    final temperature = config.get<double>('ai.temperature', 0.7);

    // Build prompt based on capability
    final systemPrompt = _getSystemPrompt(capability);
    final conversationHistory = context.getRecentMessages(maxContextLength);

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...conversationHistory,
    ];

    return {
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': false,
      'capability': capability.name,
      'prefer_local': preferLocal,
    };
  }

  String _getSystemPrompt(AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
        return 'You are an intelligent terminal assistant. Help users with terminal commands, '
               'explain concepts, and provide helpful suggestions. Be concise but informative.';

      case AICapability.code_generation:
        return 'You are a programming assistant. Generate high-quality, well-documented code. '
               'Follow best practices and include error handling.';

      case AICapability.command_suggestion:
        return 'You are a terminal command expert. Suggest safe, efficient commands. '
               'Explain what each command does and warn about potentially dangerous operations.';

      case AICapability.system_analysis:
        return 'You are a system analysis expert. Help diagnose issues, optimize performance, '
               'and explain system behavior. Provide actionable recommendations.';

      case AICapability.documentation:
        return 'You are a technical documentation specialist. Create clear, comprehensive '
               'documentation with examples and best practices.';

      }
  }

  Future<AIResponse> _makeAPIRequestWithRetry(Map<String, dynamic> request) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await _makeAPIRequest(request);
        return response;
      } catch (e) {
        if (attempt == maxRetries) {
          return AIResponse.failure('All retry attempts failed: $e');
        }

        // Exponential backoff
        await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
        debugPrint('AI request retry $attempt: $e');
      }
    }

    // This should never be reached
    return AIResponse.failure('Unexpected error in retry logic');
  }

  Future<AIResponse> _makeAPIRequest(Map<String, dynamic> request) async {
    if (_apiKey == null) {
      throw Exception('API key not configured');
    }

    final url = Uri.parse('$nvidiaApiBaseUrl/chat/completions');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    };

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(request),
    ).timeout(requestTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices']?[0]?['message']?['content'] ?? '';

      return AIResponse.success(content.toString());
    } else {
      throw Exception('API request failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Get intelligent command suggestions based on current context
  Future<List<String>> getCommandSuggestions({
    required String currentInput,
    required String contextId,
    int maxSuggestions = 5,
  }) async {
    if (!_isInitialized) return [];

    try {
      _getOrCreateContext(contextId); // Ensure context exists
      final prompt = 'Based on the current terminal session and input "$currentInput", '
                     'suggest $maxSuggestions relevant terminal commands. '
                     'Return only the commands, one per line, no explanations.';

      final response = await processText(
        input: prompt,
        capability: AICapability.command_suggestion,
        contextId: '${contextId}_suggestions',
        preferLocal: true,
      );

      if (response.success) {
        final suggestions = response.output
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .take(maxSuggestions)
            .toList();

        _eventController.add(AIEvent.suggestionsGenerated(contextId, suggestions.length));
        return suggestions;
      }

      return [];
    } catch (e) {
      debugPrint('Command suggestion failed: $e');
      return [];
    }
  }

  /// Analyze terminal output for issues and suggestions
  Future<AnalysisResult> analyzeTerminalOutput({
    required String output,
    required String contextId,
  }) async {
    if (!_isInitialized) {
      return AnalysisResult.empty();
    }

    try {
      final prompt = 'Analyze this terminal output for errors, warnings, or opportunities for improvement:\n\n$output\n\n'
                     'Provide a JSON response with: {"errors": [], "warnings": [], "suggestions": [], "summary": ""}';

      final response = await processText(
        input: prompt,
        capability: AICapability.system_analysis,
        contextId: '${contextId}_analysis',
        preferLocal: true,
      );

      if (response.success) {
        try {
          final data = jsonDecode(response.output);
          return AnalysisResult(
            errors: (data['errors'] as List<dynamic>?)?.cast<String>() ?? [],
            warnings: (data['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
            suggestions: (data['suggestions'] as List<dynamic>?)?.cast<String>() ?? [],
            summary: (data['summary'] as String?) ?? '',
          );
        } catch (e) {
          debugPrint('Failed to parse analysis response: $e');
        }
      }

      return AnalysisResult.empty();
    } catch (e) {
      debugPrint('Terminal analysis failed: $e');
      return AnalysisResult.empty();
    }
  }

  /// Generate code based on description
  Future<String?> generateCode({
    required String description,
    required String language,
    required String contextId,
  }) async {
    if (!_isInitialized) return null;

    try {
      final prompt = 'Generate $language code for: $description\n\n'
                     'Include proper error handling, comments, and follow best practices.';

      final response = await processText(
        input: prompt,
        capability: AICapability.code_generation,
        contextId: '${contextId}_code',
        preferLocal: false,
      );

      return response.success ? response.output : null;
    } catch (e) {
      debugPrint('Code generation failed: $e');
      return null;
    }
  }

  /// Clear conversation context
  void clearContext(String contextId) {
    _activeContexts.remove(contextId);
    _eventController.add(AIEvent.contextCleared(contextId));
  }

  /// Get AI assistant statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'totalRequests': _totalRequests,
      'successfulRequests': _successfulRequests,
      'successRate': successRate,
      'activeContexts': _activeContexts.length,
      'lastRequestTime': _lastRequestTime?.toIso8601String(),
    };
  }

  /// Dispose resources
  void dispose() {
    _eventController.close();
    _activeContexts.clear();
    _conversations.clear();
    debugPrint('NVIDIA AI Terminal Assistant disposed');
  }
}

/// AI response wrapper
class AIResponse {
  final bool success;
  final String output;
  final String? error;
  final String? contextId;
  final DateTime timestamp;

  const AIResponse._({
    required this.success,
    required this.output,
    this.error,
    this.contextId,
    required this.timestamp,
  });

  factory AIResponse.success(String output, {String? contextId}) {
    return AIResponse._(
      success: true,
      output: output,
      contextId: contextId,
      timestamp: DateTime.now(),
    );
  }

  factory AIResponse.failure(String error, {String? contextId}) {
    return AIResponse._(
      success: false,
      output: '',
      error: error,
      contextId: contextId,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'output': output,
    'error': error,
    'contextId': contextId,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// AI capability types
enum AICapability {
  text_generation,
  code_generation,
  command_suggestion,
  system_analysis,
  documentation,
}

/// AI conversation context
class AIContext {
  final String id;
  final List<AIMessage> _messages = [];
  static const int maxMessages = 50;

  AIContext(this.id);

  void addMessage(AIMessage message) {
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeAt(0);
    }
  }

  List<Map<String, String>> getRecentMessages(int maxLength) {
    final recent = _messages.sublist(maxLength > _messages.length ? 0 : _messages.length - maxLength);

    return recent.map((msg) => {
      'role': msg.role,
      'content': msg.content,
    }).toList();
  }
}


/// Analysis result for terminal output
class AnalysisResult {
  final List<String> errors;
  final List<String> warnings;
  final List<String> suggestions;
  final String summary;

  const AnalysisResult({
    required this.errors,
    required this.warnings,
    required this.suggestions,
    required this.summary,
  });

  factory AnalysisResult.empty() {
    return const AnalysisResult(
      errors: [],
      warnings: [],
      suggestions: [],
      summary: '',
    );
  }

  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;
  int get totalIssues => errors.length + warnings.length + suggestions.length;
}

/// AI event types
class AIEvent {
  final AIEventType type;
  final String? contextId;
  final AICapability? capability;
  final int? length;
  final String? error;
  final int? count;

  const AIEvent._(this.type, {
    this.contextId,
    this.capability,
    this.length,
    this.error,
    this.count,
  });

  factory AIEvent.responseGenerated(String contextId, AICapability capability, int length) {
    return AIEvent._(AIEventType.responseGenerated,
      contextId: contextId,
      capability: capability,
      length: length,
    );
  }

  factory AIEvent.requestFailed(String contextId, AICapability capability, String error) {
    return AIEvent._(AIEventType.requestFailed,
      contextId: contextId,
      capability: capability,
      error: error,
    );
  }

  factory AIEvent.suggestionsGenerated(String contextId, int count) {
    return AIEvent._(AIEventType.suggestionsGenerated,
      contextId: contextId,
      count: count,
    );
  }

  factory AIEvent.contextCleared(String contextId) {
    return AIEvent._(AIEventType.contextCleared, contextId: contextId);
  }
}

/// AI conversation data structure
class AIConversation {
  final String id;
  final List<AIMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? context;

  AIConversation({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.context,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'context': context,
  };
}

/// AI message data structure
class AIMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  AIMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata,
  });

  factory AIMessage.user(String content, {Map<String, dynamic>? metadata}) {
    return AIMessage(
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
  }

  factory AIMessage.assistant(String content, {Map<String, dynamic>? metadata}) {
    return AIMessage(
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
}

/// AI event types
enum AIEventType {
  responseGenerated,
  requestFailed,
  suggestionsGenerated,
  contextCleared,
}

class AIServiceResponse {
  final bool success;
  final String output;
  final double confidence;
  final Duration processingTime;

  AIServiceResponse({
    required this.success,
    required this.output,
    required this.confidence,
    required this.processingTime,
  });
}