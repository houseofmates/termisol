import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Streaming AI response system for perceived responsiveness
/// Provides real-time token streaming and request deduplication
class StreamingAiFallback {
  static const Duration _streamingDelay = Duration(milliseconds: 50);
  static const Duration _deduplicationWindow = Duration(milliseconds: 500);
  static const int _maxConcurrentRequests = 3;
  
  final Map<String, _ActiveRequest> _activeRequests = {};
  final Map<String, DateTime> _recentRequests = {};
  Timer? _cleanupTimer;
  
  // Performance metrics
  int _totalRequests = 0;
  int _deduplicatedRequests = 0;
  int _streamedResponses = 0;
  final _metricsController = StreamController<AiMetrics>.broadcast();

  /// Stream of AI performance metrics
  Stream<AiMetrics> get metrics => _metricsController.stream;

  StreamingAiFallback() {
    _startCleanupTimer();
  }

  /// Process a query with streaming response
  Stream<String> processQueryStreaming({
    required String query,
    String? sessionId,
    Map<String, dynamic>? context,
  }) async* {
    final requestId = _generateRequestId(query, sessionId);
    final startTime = DateTime.now();
    
    // Check for deduplication
    if (_isDuplicateRequest(requestId)) {
      _deduplicatedRequests++;
      debugPrint('[streaming_ai] Deduplicated request: $requestId');
      return;
    }
    
    _totalRequests++;
    _recentRequests[requestId] = startTime;
    
    // Check concurrent request limit
    if (_activeRequests.length >= _maxConcurrentRequests) {
      yield* _handleRateLimit(query);
      return;
    }
    
    final activeRequest = _ActiveRequest(
      id: requestId,
      query: query,
      startTime: startTime,
      context: context,
    );
    
    _activeRequests[requestId] = activeRequest;
    
    try {
      // Generate streaming response
      yield* _generateStreamingResponse(activeRequest);
      _streamedResponses++;
    } catch (e) {
      debugPrint('[streaming_ai] Error generating response: $e');
      yield 'Error: $e';
    } finally {
      _activeRequests.remove(requestId);
      _emitMetrics();
    }
  }

  /// Generate streaming response with realistic token timing
  Stream<String> _generateStreamingResponse(_ActiveRequest request) async* {
    final response = await _generateResponse(request.query, request.context);
    final words = response.split(' ');
    
    // Stream words with realistic timing
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isLastWord = i == words.length - 1;
      
      yield word;
      
      // Add space except for last word
      if (!isLastWord {
        yield ' ';
      }
      
      // Variable delay for natural pacing
      final delay = _calculateWordDelay(word, i, words.length);
      await Future.delayed(delay);
    }
  }

  /// Calculate realistic delay between words
  Duration _calculateWordDelay(String word, int index, int totalWords) {
    // Base delay with variation
    final baseDelay = _streamingDelay.inMilliseconds;
    
    // Longer words take slightly longer to "process"
    final wordDelay = (word.length * 2).clamp(0, 100);
    
    // Punctuation pauses
    final punctuationDelay = _getPunctuationDelay(word);
    
    // Sentence-ending pauses
    final sentenceDelay = (word.endsWith('.') || word.endsWith('!') || word.endsWith('?')) ? 150 : 0;
    
    // Start/end of response delays
    final positionDelay = (index == 0) ? 100 : (index == totalWords - 1) ? 200 : 0;
    
    final totalDelay = baseDelay + wordDelay + punctuationDelay + sentenceDelay + positionDelay;
    
    // Add random variation for naturalness
    final variation = (math.Random().nextDouble() * 50 - 25).round();
    
    return Duration(milliseconds: (totalDelay + variation).clamp(10, 500));
  }

  /// Get delay for punctuation
  int _getPunctuationDelay(String word) {
    if (word.contains(',')) return 50;
    if (word.contains(';') || word.contains(':')) return 75;
    if (word.contains('-')) return 25;
    return 0;
  }

  /// Generate response content
  Future<String> _generateResponse(String query, Map<String, dynamic>? context) async {
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 100 + math.Random().nextInt(200)));
    
    // Generate contextual response
    final lowerQuery = query.toLowerCase();
    
    if (lowerQuery.contains('error') || lowerQuery.contains('failed')) {
      return _generateErrorResponse(query);
    } else if (lowerQuery.contains('explain') || lowerQuery.contains('what is')) {
      return _generateExplanationResponse(query);
    } else if (lowerQuery.contains('how to') || lowerQuery.contains('help')) {
      return _generateHelpResponse(query);
    } else {
      return _generateGeneralResponse(query);
    }
  }

  /// Generate error-related response
  String _generateErrorResponse(String query) {
    final responses = [
      "I see you're encountering an error. Let me help you troubleshoot this issue.",
      "That error looks like it might be related to permissions or missing dependencies.",
      "This type of error often occurs when the command isn't found or there's a syntax issue.",
      "Based on the error message, you might want to check the command syntax or verify file paths.",
    ];
    
    return responses[math.Random().nextInt(responses.length)] + 
           " Try checking the command syntax, permissions, or whether the required software is installed.";
  }

  /// Generate explanation response
  String _generateExplanationResponse(String query) {
    return "This command is used for system operations and file management. " +
           "It provides essential functionality for working with files, processes, and system resources. " +
           "The command accepts various options and arguments to customize its behavior.";
  }

  /// Generate help response
  String _generateHelpResponse(String query) {
    return "I can help you with terminal commands and troubleshooting. " +
           "For detailed help, you can use the man pages (man command) or the --help flag. " +
           "Common issues include permission problems, missing dependencies, and incorrect syntax.";
  }

  /// Generate general response
  String _generateGeneralResponse(String query) {
    final responses = [
      "I understand you're looking for assistance with terminal operations.",
      "That's an interesting query about system administration and command-line tools.",
      "I can provide guidance on terminal commands and system management tasks.",
      "Let me help you understand this aspect of command-line interface usage.",
    ];
    
    return responses[math.Random().nextInt(responses.length)] + 
           " Feel free to ask for more specific information about any particular command or issue.";
  }

  /// Handle rate limiting
  Stream<String> _handleRateLimit(String query) async* {
    yield "System is currently processing multiple requests. Please wait a moment...";
    await Future.delayed(Duration(milliseconds: 500));
    yield "I can help you with: " + _getQuickHelp(query);
  }

  /// Get quick help for common queries
  String _getQuickHelp(String query) {
    final lowerQuery = query.toLowerCase();
    
    if (lowerQuery.contains('git')) return "git status, git add, git commit";
    if (lowerQuery.contains('docker')) return "docker ps, docker run, docker build";
    if (lowerQuery.contains('file')) return "ls, cd, mkdir, rm, cp, mv";
    if (lowerQuery.contains('permission')) return "chmod, chown, sudo";
    if (lowerQuery.contains('network')) return "ping, curl, wget, ssh";
    
    return "basic commands, file operations, system tools";
  }

  /// Check if request is a duplicate
  bool _isDuplicateRequest(String requestId) {
    final now = DateTime.now();
    final recent = _recentRequests[requestId];
    
    if (recent == null) return false;
    
    final timeDiff = now.difference(recent);
    return timeDiff < _deduplicationWindow;
  }

  /// Generate unique request ID
  String _generateRequestId(String query, String? sessionId) {
    final hash = query.hashCode ^ (sessionId?.hashCode ?? 0);
    return '${sessionId ?? "global"}_${hash.abs()}';
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _cleanupOldRequests();
    });
  }

  /// Clean up old requests
  void _cleanupOldRequests() {
    final now = DateTime.now();
    final expiredRequests = <String>[];
    
    for (final entry in _recentRequests.entries) {
      if (now.difference(entry.value) > Duration(minutes: 1)) {
        expiredRequests.add(entry.key);
      }
    }
    
    for (final key in expiredRequests) {
      _recentRequests.remove(key);
    }
    
    if (expiredRequests.isNotEmpty) {
      debugPrint('[streaming_ai] Cleaned up ${expiredRequests.length} expired requests');
    }
  }

  /// Emit performance metrics
  void _emitMetrics() {
    final metrics = AiMetrics(
      totalRequests: _totalRequests,
      deduplicatedRequests: _deduplicatedRequests,
      streamedResponses: _streamedResponses,
      activeRequests: _activeRequests.length,
      deduplicationRate: _totalRequests > 0 ? _deduplicatedRequests / _totalRequests : 0,
      averageResponseTime: _calculateAverageResponseTime(),
      timestamp: DateTime.now(),
    );
    
    _metricsController.add(metrics);
  }

  /// Calculate average response time
  Duration _calculateAverageResponseTime() {
    if (_activeRequests.isEmpty) return Duration.zero;
    
    final now = DateTime.now();
    final totalTime = _activeRequests.values
        .map((req) => now.difference(req.startTime))
        .reduce((a, b) => a + b);
    
    return Duration(microseconds: totalTime.inMicroseconds ~/ _activeRequests.length);
  }

  /// Get current statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalRequests': _totalRequests,
      'deduplicatedRequests': _deduplicatedRequests,
      'streamedResponses': _streamedResponses,
      'activeRequests': _activeRequests.length,
      'recentRequests': _recentRequests.length,
      'deduplicationRate': _totalRequests > 0 ? _deduplicatedRequests / _totalRequests : 0,
    };
  }

  /// Dispose resources
  void dispose() {
    _cleanupTimer?.cancel();
    _metricsController.close();
    _activeRequests.clear();
    _recentRequests.clear();
  }
}

/// Active request tracking
class _ActiveRequest {
  final String id;
  final String query;
  final DateTime startTime;
  final Map<String, dynamic>? context;

  _ActiveRequest({
    required this.id,
    required this.query,
    required this.startTime,
    this.context,
  });
}

/// AI performance metrics
class AiMetrics {
  final int totalRequests;
  final int deduplicatedRequests;
  final int streamedResponses;
  final int activeRequests;
  final double deduplicationRate;
  final Duration averageResponseTime;
  final DateTime timestamp;

  AiMetrics({
    required this.totalRequests,
    required this.deduplicatedRequests,
    required this.streamedResponses,
    required this.activeRequests,
    required this.deduplicationRate,
    required this.averageResponseTime,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'deduplicatedRequests': deduplicatedRequests,
    'streamedResponses': streamedResponses,
    'activeRequests': activeRequests,
    'deduplicationRate': deduplicationRate,
    'averageResponseTimeMs': averageResponseTime.inMilliseconds,
    'timestamp': timestamp.toIso8601String(),
  };
}
