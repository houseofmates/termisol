import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'nvidia_ai_optimizer_classes.dart';

/// NVIDIA AI Optimization Recommendations - AI-powered performance optimization
class NVIDIAAIOptimizer {
  static final NVIDIAAIOptimizer _instance = NVIDIAAIOptimizer._internal();
  factory NVIDIAAIOptimizer() => _instance;
  NVIDIAAIOptimizer._internal();

  final String _nimEndpoint = 'https://integrate.nvidia.com/v1/chat/completions';
  String? _apiKey;
  final Map<String, OptimizationRecommendation> _recommendations = {};
  final Map<String, PerformanceProfile> _profiles = {};
  final List<OptimizationHistory> _history = [];
  
  bool _isInitialized = false;
  Timer? _analysisTimer;
  
  static const Duration _timeout = Duration(seconds: 45);
  static const Duration _analysisInterval = Duration(minutes: 5);
  
  final _optimizerController = StreamController<OptimizerEvent>.broadcast();
  Stream<OptimizerEvent> get events => _optimizerController.stream;
  
  bool get isInitialized => _isInitialized;

  Future<void> initialize(String apiKey) async {
    if (apiKey.isEmpty || !apiKey.startsWith('nvapi-')) {
      throw const OptimizationException('Invalid NVIDIA API key format');
    }
    _apiKey = apiKey;
    _isInitialized = true;
    
    // Start analysis timer
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(_analysisInterval, (_) => _analyzePerformance());
  }

  Future<OptimizationResult> getOptimizationRecommendations({
    required Map<String, dynamic> performanceMetrics,
    required String systemType,
    String? profileName,
  }) async {
    if (!_isInitialized) {
      throw const OptimizationException('Optimizer not initialized');
    }

    try {
      // Check cache first
      final cacheKey = _generateCacheKey(performanceMetrics, systemType);
      if (_recommendations.containsKey(cacheKey)) {
        return OptimizationResult.success(recommendations: _recommendations[cacheKey]);
      }

      // Build optimization prompt
      final prompt = _buildOptimizationPrompt(performanceMetrics, systemType, profileName);
      
      // Call NVIDIA API
      final response = await _callNVIDIA(prompt);
      final recommendations = _parseOptimizationResponse(response);
      
      // Cache results
      _recommendations[cacheKey] = recommendations;
      
      // Add to history
      _history.add(OptimizationHistory(
        timestamp: DateTime.now(),
        systemType: systemType,
        metrics: performanceMetrics,
        recommendations: recommendations.suggestions,
      ));
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.recommendationsGenerated,
        data: {
          'system_type': systemType,
          'recommendations_count': recommendations.suggestions.length,
          'overall_score': recommendations.overallScore,
        },
      ));
      
      return OptimizationResult.success(recommendations: recommendations);
      
    } catch (e) {
      return OptimizationResult.error(e.toString());
    }
  }

  String _buildOptimizationPrompt(Map<String, dynamic> metrics, String systemType, String? profileName) {
    return '''
Analyze these performance metrics and provide optimization recommendations:

System Type: $systemType
Profile: ${profileName ?? 'default'}
Metrics: ${jsonEncode(metrics)}

Provide 3-5 optimization suggestions. Format each as:
OPTIMIZATION: [suggestion]
IMPACT: [high/medium/low]
EFFORT: [easy/medium/hard]
PRIORITY: [1-10]
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
    if (_apiKey == null) {
      throw const OptimizationException('NVIDIA API key not initialized');
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
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 1000,
        'temperature': 0.7,
        'stream': false,
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
        throw OptimizationException('Failed to parse NVIDIA API response: $e');
      }
    } else {
      throw OptimizationException('NVIDIA API error: ${response.statusCode} - ${response.reasonPhrase}');
    }
  }

  OptimizationRecommendation _parseOptimizationResponse(String response) {
    final lines = response.split('\n');
    double overallScore = 0.5;
    final suggestions = <OptimizationSuggestion>[];
    String? predictedImprovement;
    String? implementationTime;
    String? riskLevel;

    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('OPTIMIZATION:') && 
          lines[i + 1].startsWith('IMPACT:') && 
          lines[i + 2].startsWith('EFFORT:')) {
        
        final optimization = lines[i].substring(13).trim();
        final impact = lines[i + 1].substring(8).trim();
        final effort = lines[i + 2].substring(7).trim();
        
        suggestions.add(OptimizationSuggestion(
          id: 'opt_${DateTime.now().millisecondsSinceEpoch}_$i',
          title: optimization,
          description: optimization,
          impact: impact,
          effort: effort,
          category: 'performance',
          command: '',
          priority: 5,
        ));
        
        overallScore += 0.1;
      }
    }

    return OptimizationRecommendation(
      timestamp: DateTime.now(),
      overallScore: math.min(overallScore, 1.0),
      suggestions: suggestions,
      predictedImprovement: predictedImprovement ?? 'Unknown',
      implementationTime: implementationTime ?? 'Unknown',
      riskLevel: riskLevel ?? 'Unknown',
    );
  }

  String _generateCacheKey(Map<String, dynamic> metrics, String systemType) {
    final metricsHash = metrics.toString().hashCode;
    return '${systemType}_$metricsHash';
  }

  void _analyzePerformance() {
    // This would typically monitor system performance
    // For now, it's a placeholder for periodic analysis
    debugPrint('🔍 Performance analysis triggered');
  }

  Map<String, dynamic> getStatistics() {
    return {
      'recommendations_count': _recommendations.length,
      'profiles_count': _profiles.length,
      'history_count': _history.length,
      'applied_optimizations': _history.where((h) => h.applied).length,
    };
  }

  Future<void> dispose() async {
    _analysisTimer?.cancel();
    await _optimizerController.close();
    _recommendations.clear();
    _profiles.clear();
    _history.clear();
  }

  /// Generate cache key for optimization recommendations
  String _generateCacheKey(Map<String, dynamic> metrics, String systemType) {
    final metricsHash = metrics.toString().hashCode;
    return '${systemType}_$metricsHash';
  }

  /// Load default performance profiles
  void _loadDefaultProfiles() {
    _profiles['default'] = PerformanceProfile(
      name: 'default',
      description: 'Default performance profile',
      parameters: {
        'cpu_threshold': 0.8,
        'memory_threshold': 0.85,
        'disk_threshold': 0.9,
        'network_threshold': 0.8,
      },
      createdAt: DateTime.now(),
    );
    
    _profiles['high_performance'] = PerformanceProfile(
      name: 'high_performance',
      description: 'High performance profile',
      parameters: {
        'cpu_threshold': 0.6,
        'memory_threshold': 0.7,
        'disk_threshold': 0.8,
        'network_threshold': 0.7,
      },
      createdAt: DateTime.now(),
    );
  }

  /// Parse NVIDIA optimization response
  OptimizationRecommendation _parseOptimizationResponse(String response) {
    final lines = response.split('\n');
    double overallScore = 0.5;
    final suggestions = <OptimizationSuggestion>[];
    String? predictedImprovement;
    String? implementationTime;
    String? riskLevel;
    String? currentSection;

    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('OPTIMIZATION:') && 
          lines[i + 1].startsWith('IMPACT:') && 
          lines[i + 2].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(13).trim();
        final impact = lines[i + 1].substring(8).trim();
        final confidence = double.tryParse(lines[i + 2].substring(12)) ?? 0.5;
        final time = lines[i + 3].split(':')[1].trim();
        final risk = lines.length > i + 4 ? lines[i + 4].split(':')[1].trim() : null;
        
        suggestions.add(OptimizationSuggestion(
          text: text,
          impact: impact,
          confidence: confidence,
          implementationTime: time,
          riskLevel: risk,
        ));
      }
    }
    
    return OptimizationRecommendation(
      overallScore: overallScore,
      suggestions: suggestions,
      predictedImprovement: predictedImprovement,
      implementationTime: implementationTime,
      riskLevel: riskLevel,
    );
  }

  /// Parse system optimization response
  OptimizationRecommendation _parseSystemOptimizationResponse(String response) {
    final lines = response.split('\n');
    double overallScore = 0.5;
    final suggestions = <OptimizationSuggestion>[];
    String? predictedImprovement;
    String? implementationTime;
    String? riskLevel;
    String? currentSection;

    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('OPTIMIZATION:') && 
          lines[i + 1].startsWith('IMPACT:') && 
          lines[i + 2].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(13).trim();
        final impact = lines[i + 1].substring(8).trim();
        final confidence = double.tryParse(lines[i + 2].substring(12)) ?? 0.5;
        final time = lines[i + 3].split(':')[1].trim();
        final risk = lines.length > i + 4 ? lines[i + 4].split(':')[1].trim() : null;
        
        suggestions.add(OptimizationSuggestion(
          text: text,
          impact: impact,
          confidence: confidence,
          implementationTime: time,
          riskLevel: riskLevel,
        ));
      }
    }
    
    return OptimizationRecommendation(
      overallScore: overallScore,
      suggestions: suggestions,
      predictedImprovement: predictedImprovement,
      implementationTime: implementationTime,
      riskLevel: riskLevel,
    );
  }

  /// Parse predictive optimization response
  OptimizationRecommendation _parsePredictiveOptimizationResponse(String response) {
    final lines = response.split('\n');
    double overallScore = 0.5;
    final suggestions = <OptimizationSuggestion>[];
    String? predictedImprovement;
    String? implementationTime;
    String? riskLevel;
    String? currentSection;

    for (int i = 0; i < lines.length - 2; i += 3) {
      if (lines[i].startsWith('OPTIMIZATION:') && 
          lines[i + 1].startsWith('IMPACT:') && 
          lines[i + 2].startsWith('CONFIDENCE:')) {
        
        final text = lines[i].substring(13).trim();
        final impact = lines[i + 1].substring(8).trim();
        final confidence = double.tryParse(lines[i + 2].substring(12)) ?? 0.5;
        final time = lines[i + 3].split(':')[1].trim();
        final risk = lines.length > i + 4 ? lines[i + 4].split(':')[1].trim() : null;
        
        suggestions.add(OptimizationSuggestion(
          text: text,
          impact: impact,
          confidence: confidence,
          implementationTime: time,
          riskLevel: riskLevel,
        ));
      }
    }
    
    return OptimizationRecommendation(
      overallScore: overallScore,
      suggestions: suggestions,
      predictedImprovement: predictedImprovement,
      implementationTime: implementationTime,
      riskLevel: riskLevel,
    );
  }

  /// Execute optimization with monitoring
  Future<void> _executeOptimization(Optimization) async {
    try {
      // Apply optimization
      debugPrint('🚀 Applying optimization: ${optimization.text}');
      
      // Track execution
      _history.add(OptimizationHistory(
        timestamp: DateTime.now(),
        systemType: optimization.systemType,
        metrics: optimization.metrics,
        recommendations: [optimization],
        applied: true,
      ));
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.optimizationApplied,
        data: {
          'optimization': optimization.text,
          'impact': optimization.impact,
        },
      ));
      
    } catch (e) {
      debugPrint('❌ Failed to apply optimization: $e');
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.optimizationFailed,
        data: {
          'error': e.toString(),
          'optimization': optimization.text,
        },
      ));
    }
  }

  /// Format metrics for display
  String _formatMetrics(Map<String, dynamic> metrics) {
    final buffer = StringBuffer();
    metrics.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }

  /// Format context for display
  String _formatContext(Map<String, dynamic> context) {
    final buffer = StringBuffer();
    context.forEach((key, value) {
      if (value is List) {
        buffer.writeln('$key: ${(value as List).join(', ')}');
      } else {
        buffer.writeln('$key: $value');
      }
    });
    return buffer.toString();
  }

  /// Format configuration for display
  String _formatConfig(Map<String, dynamic> config) {
    final buffer = StringBuffer();
    config.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }

  /// Format constraints for display
  String _formatConstraints(Map<String, dynamic> constraints) {
    final buffer = StringBuffer();
    constraints.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    return buffer.toString();
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'recommendations_count': _recommendations.length,
      'profiles_count': _profiles.length,
      'history_count': _history.length,
      'applied_optimizations': _history.where((h) => h.applied).length,
    };
  }
}
