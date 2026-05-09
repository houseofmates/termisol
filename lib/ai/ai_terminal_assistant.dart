import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/production_config_system.dart';

/// cloud-only ai terminal assistant.
/// on android, detects a local gemma 4:4b model via common endpoints and falls back to it when the cloud api is unreachable.
class NvidiaAITerminalAssistant {
  static const String nvidiaApiBaseUrl = 'https://api.nvidia.com/v1';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxContextLength = 4096;
  static const int maxRetries = 3;

  final StreamController<AIEvent> _eventController = StreamController.broadcast();
  final List<AIConversation> _conversations = [];
  final Map<String, AIContext> _activeContexts = {};
  final http.Client _httpClient = http.Client();

  String? _apiKey;
  bool _isInitialized = false;
  int _totalRequests = 0;
  int _successfulRequests = 0;
  DateTime? _lastRequestTime;

  /// cached local gemma endpoint detected on this device, if any.
  String? _localGemmaEndpoint;

  /// stream of AI events
  Stream<AIEvent> get events => _eventController.stream;

  /// whether the AI assistant is initialized and ready
  bool get isInitialized => _isInitialized;

  /// success rate of AI requests
  double get successRate {
    return _totalRequests > 0 ? _successfulRequests / _totalRequests : 0.0;
  }

  /// number of active conversations
  int get activeConversationCount => _conversations.length;

  NvidiaAITerminalAssistant() {
    _initialize();
  }

  Future<void> _initialize() async {
    final config = ProductionConfigSystem();

    if (!config.initialized) {
      await config.initialize();
    }

    _apiKey = config.get<String>('ai.api_key');

    final aiEnabled = config.get<bool>('ai.enabled', true);
    if (aiEnabled == true && (_apiKey?.isNotEmpty ?? false)) {
      _isInitialized = true;
      debugPrint('AI assistant initialized (cloud)');
    } else {
      debugPrint('AI assistant disabled: no API key');
    }

    if (Platform.isAndroid) {
      await _detectLocalGemma();
    }
  }

  /// probe common local LLM endpoints to find gemma 4:4b on android.
  Future<void> _detectLocalGemma() async {
    const candidates = [
      'http://localhost:11434/api/tags',
      'http://127.0.0.1:11434/api/tags',
      'http://localhost:8080/v1/models',
      'http://127.0.0.1:8080/v1/models',
    ];

    for (final endpoint in candidates) {
      try {
        final response = await _httpClient
            .get(Uri.parse(endpoint))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          final body = response.body.toLowerCase();
          if (body.contains('gemma')) {
            _localGemmaEndpoint = endpoint.replaceAll('/api/tags', '/api/generate').replaceAll('/v1/models', '/v1/chat/completions');
            debugPrint('detected local gemma at $_localGemmaEndpoint');
            return;
          }
        }
      } catch (_) {
        // endpoint not reachable, continue probing
      }
    }
  }

  /// process text input and return AI response.
  /// on android with a local model, falls back to the local endpoint if the cloud API fails.
  Future<AIResponse> processText({
    required String input,
    required AICapability capability,
    required String contextId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized && _localGemmaEndpoint == null) {
      return AIResponse.failure(
        'AI assistant not initialized and no local model detected',
        contextId: contextId,
      );
    }

    _totalRequests++;
    _lastRequestTime = DateTime.now();

    try {
      final context = _getOrCreateContext(contextId);
      context.addMessage(AIMessage.user(input, metadata: metadata));
      final request = _prepareAIRequest(input, capability, context);

      AIResponse response;
      if (_isInitialized) {
        response = await _makeAPIRequestWithRetry(request);
        if (!response.success && _localGemmaEndpoint != null) {
          debugPrint('cloud AI failed, trying local gemma');
          response = await _makeLocalGemmaRequest(request);
        }
      } else if (_localGemmaEndpoint != null) {
        response = await _makeLocalGemmaRequest(request);
      } else {
        response = AIResponse.failure('no AI backend available');
      }

      if (response.success) {
        _successfulRequests++;
        context.addMessage(AIMessage.assistant(response.output));
        _eventController.add(AIEvent.responseGenerated(
          contextId,
          capability,
          response.output.length,
        ));
      } else {
        _eventController.add(AIEvent.requestFailed(contextId, capability, response.error!));
      }

      return response;
    } catch (e, stack) {
      final error = 'AI processing failed: $e';
      debugPrint('$error\n$stack');
      _eventController.add(AIEvent.requestFailed(contextId, capability, error));
      return AIResponse.failure(error, contextId: contextId);
    }
  }

  AIContext _getOrCreateContext(String contextId) {
    return _activeContexts[contextId] ??= AIContext(contextId);
  }

  Map<String, dynamic> _prepareAIRequest(
    String input,
    AICapability capability,
    AIContext context,
  ) {
    final config = ProductionConfigSystem();
    final model = config.get<String>('ai.model', 'nvidia-llama-3.1-8b-instruct');
    final maxTokens = config.get<int>('ai.max_tokens', 4096);
    final temperature = config.get<double>('ai.temperature', 0.7);

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
    };
  }

  String _getSystemPrompt(AICapability capability) {
    switch (capability) {
      case AICapability.text_generation:
        return 'you are an intelligent terminal assistant. help users with terminal commands, explain concepts, and provide helpful suggestions. be concise but informative.';
      case AICapability.code_generation:
        return 'you are a programming assistant. generate high-quality, well-documented code. follow best practices and include error handling.';
      case AICapability.command_suggestion:
        return 'you are a terminal command expert. suggest safe, efficient commands. explain what each command does and warn about potentially dangerous operations.';
      case AICapability.system_analysis:
        return 'you are a system analysis expert. help diagnose issues, optimize performance, and explain system behavior. provide actionable recommendations.';
      case AICapability.documentation:
        return 'you are a technical documentation specialist. create clear, comprehensive documentation with examples and best practices.';
    }
  }

  Future<AIResponse> _makeAPIRequestWithRetry(Map<String, dynamic> request) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await _makeAPIRequest(request);
        return response;
      } catch (e) {
        if (attempt == maxRetries) {
          return AIResponse.failure('all retry attempts failed: $e');
        }
        await Future.delayed(Duration(seconds: pow(2, attempt).toInt()));
        debugPrint('AI request retry $attempt: $e');
      }
    }
    return AIResponse.failure('unexpected error in retry logic');
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

    final response = await _httpClient.post(
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

  /// send request to local gemma endpoint on android.
  Future<AIResponse> _makeLocalGemmaRequest(Map<String, dynamic> request) async {
    if (_localGemmaEndpoint == null) {
      return AIResponse.failure('no local gemma endpoint available');
    }

    final url = Uri.parse(_localGemmaEndpoint!);
    final body = {
      'model': 'gemma:4b',
      'messages': request['messages'],
      'stream': false,
    };

    final response = await _httpClient
        .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(requestTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['message']?['content'] ?? data['response'] ?? '';
      return AIResponse.success(content.toString());
    } else {
      return AIResponse.failure('local gemma request failed: ${response.statusCode}');
    }
  }

  /// get intelligent command suggestions based on current context
  Future<List<String>> getCommandSuggestions({
    required String currentInput,
    required String contextId,
    int maxSuggestions = 5,
  }) async {
    if (!_isInitialized && _localGemmaEndpoint == null) return [];

    try {
      _getOrCreateContext(contextId);
      final prompt = 'based on the current terminal session and input "$currentInput", suggest $maxSuggestions relevant terminal commands. return only the commands, one per line, no explanations.';

      final response = await processText(
        input: prompt,
        capability: AICapability.command_suggestion,
        contextId: '${contextId}_suggestions',
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
    } catch (e, stack) {
      debugPrint('command suggestion failed: $e\n$stack');
      return [];
    }
  }

  /// analyze terminal output for issues and suggestions
  Future<AnalysisResult> analyzeTerminalOutput({
    required String output,
    required String contextId,
  }) async {
    if (!_isInitialized && _localGemmaEndpoint == null) {
      return AnalysisResult.empty();
    }

    try {
      final prompt = 'analyze this terminal output for errors, warnings, or opportunities for improvement:\n\n$output\n\nprovide a JSON response with: {"errors": [], "warnings": [], "suggestions": [], "summary": ""}';

      final response = await processText(
        input: prompt,
        capability: AICapability.system_analysis,
        contextId: '${contextId}_analysis',
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
          debugPrint('failed to parse analysis response: $e');
        }
      }
      return AnalysisResult.empty();
    } catch (e, stack) {
      debugPrint('terminal analysis failed: $e\n$stack');
      return AnalysisResult.empty();
    }
  }

  /// generate code based on description
  Future<String?> generateCode({
    required String description,
    required String language,
    required String contextId,
  }) async {
    if (!_isInitialized && _localGemmaEndpoint == null) return null;

    try {
      final prompt = 'generate $language code for: $description\n\ninclude proper error handling, comments, and follow best practices.';

      final response = await processText(
        input: prompt,
        capability: AICapability.code_generation,
        contextId: '${contextId}_code',
      );

      return response.success ? response.output : null;
    } catch (e, stack) {
      debugPrint('code generation failed: $e\n$stack');
      return null;
    }
  }

  /// clear conversation context
  void clearContext(String contextId) {
    _activeContexts.remove(contextId);
    _eventController.add(AIEvent.contextCleared(contextId));
  }

  /// get AI assistant statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'totalRequests': _totalRequests,
      'successfulRequests': _successfulRequests,
      'successRate': successRate,
      'activeContexts': _activeContexts.length,
      'lastRequestTime': _lastRequestTime?.toIso8601String(),
      'localGemmaEndpoint': _localGemmaEndpoint,
    };
  }

  /// dispose resources
  void dispose() {
    _eventController.close();
    _activeContexts.clear();
    _conversations.clear();
    _httpClient.close();
    debugPrint('AI assistant disposed');
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