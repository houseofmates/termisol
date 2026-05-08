import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// NVIDIA AI Client for Termisol with round-robin API key rotation.
///
/// Loads API keys from a `.env` file in the application documents directory
/// or from platform environment variables. Supports automatic failover when
/// keys are rate-limited.
///
/// Supported models:
/// - deepseek-ai/deepseek-v4-pro
/// - deepseek-ai/deepseek-v4-flash
/// - z-ai/glm-5.1
/// - moonshotai/kimi-k2.6
/// - minimaxai/minimax-m2.7
class NvidiaAIClient {
  static const String _baseUrl = 'https://integrate.api.nvidia.com/v1';
  static const int _maxRetries = 3;
  static const int _timeoutSeconds = 30;
  static const int _maxKeys = 24;

  // User's preferred model order - highest to lowest preference
  static const List<String> _availableModels = [
    'deepseek-ai/deepseek-v4-pro',      // #1 - Highest preference
    'deepseek-ai/deepseek-v4-flash',    // #2
    'moonshotai/kimi-k2.6',             // #3 - Multimodal fallback for images
    'z-ai/glm-5.1',                     // #4
    'minimaxai/minimax-m2.7',           // #5 - Lowest preference
  ];

  final List<String> _apiKeys = [];
  int _currentKeyIndex = 0;
  final Map<String, DateTime> _keyLastUsed = {};
  final Map<String, int> _keyUsageCount = {};
  final Map<String, DateTime> _keyRateLimitedUntil = {};

  String _currentModel = _availableModels[0];
  final Map<String, ModelPerformance> _modelPerformance = {};

  final List<RequestMetrics> _requestHistory = [];
  Timer? _metricsCleanupTimer;

  bool _isInitialized = false;

  final StreamController<AIEvent> _eventController =
      StreamController<AIEvent>.broadcast();

  Stream<AIEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  String get currentModel => _currentModel;
  List<String> get availableModels => List.unmodifiable(_availableModels);

  /// Initialize the client, loading API keys from `.env` and environment.
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('[NVIDIA AI] Initializing client...');

    await _loadApiKeys();

    if (_apiKeys.isEmpty) {
      _eventController.add(AIEvent(
        type: AIEventType.error,
        message:
            'No NVIDIA API keys found. Set NVIDIA_API_KEY_1 through NVIDIA_API_KEY_$_maxKeys in .env or environment.',
        data: {'keys_required': _maxKeys},
      ));
      return;
    }

    for (final model in _availableModels) {
      _modelPerformance[model] = ModelPerformance(model: model);
    }

    _metricsCleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupMetrics();
    });

    _isInitialized = true;
    _eventController.add(AIEvent(
      type: AIEventType.initialized,
      message: 'NVIDIA AI Client initialized with ${_apiKeys.length} API keys',
      data: {
        'keys_count': _apiKeys.length,
        'models_count': _availableModels.length,
      },
    ));

    debugPrint('[NVIDIA AI] Initialized with ${_apiKeys.length} keys');
  }

  /// Load API keys from `.env` file first, then fall back to environment.
  Future<void> _loadApiKeys() async {
    // Try .env file in app documents directory
    try {
      final dir = await getApplicationDocumentsDirectory();
      final envFile = File('${dir.path}/.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eq = trimmed.indexOf('=');
          if (eq == -1) continue;
          final key = trimmed.substring(0, eq).trim();
          final value = trimmed.substring(eq + 1).trim();
          if (key.startsWith('NVIDIA_API_KEY_') && value.isNotEmpty) {
            _addKey(value);
          }
        }
      }
    } catch (e) {
      debugPrint('[NVIDIA AI] Failed to load .env file: $e');
    }

    // Fall back to environment variables
    if (_apiKeys.isEmpty) {
      for (int i = 1; i <= _maxKeys; i++) {
        final key = Platform.environment['NVIDIA_API_KEY_$i'];
        if (key != null && key.isNotEmpty) {
          _addKey(key);
        }
      }
    }
  }

  void _addKey(String key) {
    if (_apiKeys.contains(key)) return;
    _apiKeys.add(key);
    _keyLastUsed[key] = DateTime.now().subtract(const Duration(days: 1));
    _keyUsageCount[key] = 0;
  }

  /// Send a chat completion request to the NVIDIA API.
  Future<AIResponse> chatCompletion({
    required List<ChatMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    bool? stream,
    bool requiresMultimodal = false, // Whether task involves images/videos
  }) async {
    if (!_isInitialized) {
      throw StateError('NVIDIA AI Client not initialized');
    }

    final targetModel = model ?? selectModelForTask(
      requiresMultimodal: requiresMultimodal,
      preferredModel: _currentModel,
    );
    final stopwatch = Stopwatch()..start();

    try {
      final requestBody = {
        'model': targetModel,
        'messages': messages.map((m) => m.toJson()).toList(),
        'max_tokens': maxTokens ?? 2048,
        'temperature': temperature ?? 0.7,
        'top_p': topP ?? 0.9,
        'stream': stream ?? false,
      };

      debugPrint('[NVIDIA AI] Request to $targetModel');

      final response = await _makeHttpRequest(
        url: '$_baseUrl/chat/completions',
        body: jsonEncode(requestBody),
      );

      stopwatch.stop();

      final responseData = jsonDecode(response.body);
      final aiResponse = AIResponse.fromJson(responseData);

      final apiKey = _apiKeys[_currentKeyIndex];
      _updateRequestMetrics(
        apiKey: apiKey,
        model: targetModel,
        success: true,
        responseTime: stopwatch.elapsedMilliseconds,
        tokensUsed: aiResponse.usage?.totalTokens ?? 0,
      );

      _eventController.add(AIEvent(
        type: AIEventType.response,
        message: 'AI response received',
        data: {
          'model': targetModel,
          'response_time': stopwatch.elapsedMilliseconds,
          'tokens_used': aiResponse.usage?.totalTokens,
        },
      ));

      return aiResponse;
    } catch (e) {
      stopwatch.stop();

      final apiKey =
          _apiKeys.isNotEmpty ? _apiKeys[_currentKeyIndex] : 'unknown';
      _updateRequestMetrics(
        apiKey: apiKey,
        model: targetModel,
        success: false,
        responseTime: stopwatch.elapsedMilliseconds,
        tokensUsed: 0,
      );

      _eventController.add(AIEvent(
        type: AIEventType.error,
        message: 'AI request failed: $e',
        data: {'error': e.toString(), 'model': targetModel},
      ));

      rethrow;
    }
  }

  /// Makes an HTTP request with automatic retry and key rotation on 429.
  Future<http.Response> _makeHttpRequest({
    required String url,
    required String body,
  }) async {
    int retryCount = 0;
    final attemptedKeys = <String>{};

    while (retryCount < _maxRetries) {
      final apiKey = await _getNextAvailableKey(exclude: attemptedKeys);
      if (apiKey == null) {
        throw Exception('Rate limit exceeded and no available keys');
      }
      attemptedKeys.add(apiKey);

      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: _timeoutSeconds));

        if (response.statusCode == 200) {
          return response;
        } else if (response.statusCode == 429) {
          _markKeyRateLimited(apiKey, const Duration(minutes: 1));
          retryCount++;
          if (retryCount < _maxRetries) {
            await Future.delayed(
              Duration(milliseconds: 500 * retryCount),
            );
            continue;
          }
          throw Exception('Rate limit exceeded and no available keys');
        } else if (response.statusCode >= 400) {
          final errorData =
              jsonDecode(response.body.isEmpty ? '{}' : response.body);
          final message = errorData['error']?['message'] ??
              'HTTP ${response.statusCode}';
          throw Exception('API Error: $message');
        } else {
          throw Exception('HTTP Error: ${response.statusCode}');
        }
      } on TimeoutException {
        _markKeyRateLimited(apiKey, const Duration(seconds: 30));
        retryCount++;
        if (retryCount >= _maxRetries) rethrow;
      } catch (e) {
        if (retryCount == _maxRetries - 1) rethrow;
        retryCount++;
        await Future.delayed(Duration(milliseconds: 1000 * retryCount));
      }
    }

    throw Exception('Max retries exceeded');
  }

  /// Get next available key with round-robin rotation.
  Future<String?> _getNextAvailableKey({Set<String>? exclude}) async {
    if (_apiKeys.isEmpty) return null;

    for (int i = 0; i < _apiKeys.length; i++) {
      final keyIndex = (_currentKeyIndex + i) % _apiKeys.length;
      final key = _apiKeys[keyIndex];

      if (exclude != null && exclude.contains(key)) continue;
      if (_isKeyAvailable(key)) {
        _currentKeyIndex = keyIndex;
        return key;
      }
    }

    return null;
  }

  bool _isKeyAvailable(String apiKey) {
    final rateLimitedUntil = _keyRateLimitedUntil[apiKey];
    if (rateLimitedUntil != null &&
        DateTime.now().isBefore(rateLimitedUntil)) {
      return false;
    }
    return true;
  }

  void _markKeyRateLimited(String apiKey, Duration duration) {
    _keyRateLimitedUntil[apiKey] = DateTime.now().add(duration);
    debugPrint(
        '[NVIDIA AI] Key rate limited for ${duration.inMinutes}m${duration.inSeconds % 60}s');
  }

  void _updateRequestMetrics({
    required String apiKey,
    required String model,
    required bool success,
    required int responseTime,
    required int tokensUsed,
  }) {
    _keyLastUsed[apiKey] = DateTime.now();
    _keyUsageCount[apiKey] = (_keyUsageCount[apiKey] ?? 0) + 1;

    final performance = _modelPerformance[model]!;
    performance.addRequest(
      success: success,
      responseTime: responseTime,
      tokensUsed: tokensUsed,
    );

    _requestHistory.add(RequestMetrics(
      timestamp: DateTime.now(),
      model: model,
      success: success,
      responseTime: responseTime,
      tokensUsed: tokensUsed,
    ));

    if (_requestHistory.length > 1000) {
      _requestHistory.removeAt(0);
    }
  }

  void _cleanupMetrics() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    _keyRateLimitedUntil.removeWhere((key, time) => time.isBefore(cutoff));
    _requestHistory.removeWhere((m) => m.timestamp.isBefore(cutoff));
  }

  Map<String, dynamic> getMetrics() {
    return {
      'is_initialized': _isInitialized,
      'api_keys_count': _apiKeys.length,
      'current_key_index': _currentKeyIndex,
      'current_model': _currentModel,
      'total_requests': _requestHistory.length,
      'model_performance': _modelPerformance.map((k, v) => MapEntry(k, v.toJson())),
      'key_usage': _keyUsageCount,
      'rate_limited_keys': _keyRateLimitedUntil.length,
    };
  }

  void switchModel(String model) {
    if (_availableModels.contains(model)) {
      _currentModel = model;
      _eventController.add(AIEvent(
        type: AIEventType.modelChanged,
        message: 'Switched to model: $model',
        data: {'model': model},
      ));
    } else {
      throw ArgumentError('Model not available: $model');
    }
  }

  /// Get the best available model based on user's preferred order.
  /// Uses the highest preference model that has good performance.
  String getBestModel() {
    // First, try to use the highest preference model if it has reasonable performance
    for (final model in _availableModels) {
      final performance = _modelPerformance[model]!;
      // Only skip if performance is extremely poor (< 10% success rate)
      if (performance.successRate > 0.1) {
        return model;
      }
    }

    // Fallback to highest preference model if all have poor performance
    return _availableModels[0];
  }

  /// Get the preferred model for image/video processing (always uses multimodal model).
  String getImageModel() {
    return 'moonshotai/kimi-k2.6'; // Explicitly use multimodal model for images
  }

  /// Select model based on task type and user's preference order.
  String selectModelForTask({bool requiresMultimodal = false, String? preferredModel}) {
    // If a specific model is preferred, use it if available
    if (preferredModel != null && _availableModels.contains(preferredModel)) {
      return preferredModel;
    }

    // For multimodal tasks (images, videos), always use kimi-k2.6
    if (requiresMultimodal) {
      return getImageModel();
    }

    // Otherwise, use the best model from user's preference order
    return getBestModel();
  }

  Future<void> dispose() async {
    _metricsCleanupTimer?.cancel();
    await _eventController.close();
    _isInitialized = false;
    debugPrint('[NVIDIA AI] Client disposed');
  }
}

// ─── Data Classes ───

class ChatMessage {
  final String role;
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AIResponse {
  final String id;
  final String object;
  final int created;
  final String model;
  final List<Choice> choices;
  final Usage? usage;

  AIResponse({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    required this.choices,
    this.usage,
  });

  factory AIResponse.fromJson(Map<String, dynamic> json) {
    return AIResponse(
      id: json['id'] ?? '',
      object: json['object'] ?? '',
      created: json['created'] ?? 0,
      model: json['model'] ?? '',
      choices: (json['choices'] as List? ?? [])
          .map((c) => Choice.fromJson(c))
          .toList(),
      usage: json['usage'] != null ? Usage.fromJson(json['usage']) : null,
    );
  }

  String get content =>
      choices.isNotEmpty ? choices.first.message.content : '';
}

class Choice {
  final int index;
  final Message message;
  final String finishReason;

  Choice({
    required this.index,
    required this.message,
    required this.finishReason,
  });

  factory Choice.fromJson(Map<String, dynamic> json) {
    return Choice(
      index: json['index'] ?? 0,
      message: Message.fromJson(json['message'] ?? {}),
      finishReason: json['finish_reason'] ?? '',
    );
  }
}

class Message {
  final String role;
  final String content;

  Message({required this.role, required this.content});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'] ?? '',
      content: json['content'] ?? '',
    );
  }
}

class Usage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  Usage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory Usage.fromJson(Map<String, dynamic> json) {
    return Usage(
      promptTokens: json['prompt_tokens'] ?? 0,
      completionTokens: json['completion_tokens'] ?? 0,
      totalTokens: json['total_tokens'] ?? 0,
    );
  }
}

class ModelPerformance {
  final String model;
  int totalRequests = 0;
  int successfulRequests = 0;
  int totalResponseTime = 0;
  int totalTokensUsed = 0;

  ModelPerformance({required this.model});

  void addRequest({
    required bool success,
    required int responseTime,
    required int tokensUsed,
  }) {
    totalRequests++;
    if (success) successfulRequests++;
    totalResponseTime += responseTime;
    totalTokensUsed += tokensUsed;
  }

  double get successRate =>
      totalRequests > 0 ? successfulRequests / totalRequests : 0.0;
  double get avgResponseTime =>
      totalRequests > 0 ? totalResponseTime / totalRequests : 0.0;
  double get avgTokensUsed =>
      totalRequests > 0 ? totalTokensUsed / totalRequests : 0.0;

  /// Higher score = better performance.
  /// We reward high success rate, low latency, and low token usage.
  double getScore() {
    if (totalRequests == 0) return 0.0;
    return (successRate * 0.5) +
        ((1.0 / (avgResponseTime / 1000.0 + 1.0)) * 0.35) +
        ((1.0 / (avgTokensUsed / 100.0 + 1.0)) * 0.15);
  }

  Map<String, dynamic> toJson() => {
    'model': model,
    'total_requests': totalRequests,
    'success_rate': successRate,
    'avg_response_time': avgResponseTime,
    'avg_tokens_used': avgTokensUsed,
    'score': getScore(),
  };
}

class RequestMetrics {
  final DateTime timestamp;
  final String model;
  final bool success;
  final int responseTime;
  final int tokensUsed;

  RequestMetrics({
    required this.timestamp,
    required this.model,
    required this.success,
    required this.responseTime,
    required this.tokensUsed,
  });
}

enum AIEventType {
  initialized,
  response,
  error,
  modelChanged,
  rateLimit,
}

class AIEvent {
  final AIEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  AIEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
