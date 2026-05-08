import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Custom exception for optimization failures
class OptimizationException implements Exception {
  final String message;
  const OptimizationException(this.message);
  
  @override
  String toString() => 'OptimizationException: $message';
}

/// NVIDIA AI Optimization Recommendations - AI-powered performance optimization
class NVIDIAAIOptimizer {
  static final NVIDIAAIOptimizer _instance = NVIDIAAIOptimizer._internal();
  factory NVIDIAAIOptimizer() => _instance;
  NVIDIAAIOptimizer._internal();

  final String _nimEndpoint = 'https://integrate.nvidia.com/v1/chat/completions';
  String? _apiKey;
  final List<OptimizationRecommendation> _recommendations = [];
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
      final cachedRecommendations = _recommendations.where((r) => r.id == cacheKey).toList();
      if (cachedRecommendations.isNotEmpty) {
        return OptimizationResult.success(recommendations: cachedRecommendations);
      }

      // Build optimization prompt
      final prompt = _buildOptimizationPrompt(performanceMetrics, systemType, profileName);
      
      // Call NVIDIA API
      final response = await _callNVIDIA(prompt);
      final recommendations = _parseOptimizationResponse(response);
      
      // Cache results - add to list since _recommendations is now a List
      _recommendations.addAll(recommendations);
      
      // Add to history
      _history.add(OptimizationHistory(
        timestamp: DateTime.now(),
        systemType: systemType,
        metrics: performanceMetrics,
        recommendations: recommendations,
      ));
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.recommendationsGenerated,
        data: {
          'system_type': systemType,
          'recommendations_count': recommendations.length,
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

  Future<void> _analyzePerformance() async {
    try {
      debugPrint('🔍 Starting performance analysis...');
      
      // Monitor CPU usage
      final cpuUsage = await _getCpuUsage();
      
      // Monitor memory usage
      final memoryUsage = await _getMemoryUsage();
      
      // Monitor GPU usage if available
      final gpuUsage = _getGpuUsage();
      
      // Analyze terminal performance metrics
      final terminalMetrics = _getTerminalMetrics();
      
      // Generate optimization recommendations based on analysis
      final recommendations = _generateRecommendations(
        cpuUsage: cpuUsage,
        memoryUsage: memoryUsage,
        gpuUsage: gpuUsage,
        terminalMetrics: terminalMetrics,
      );
      
      // Add new recommendations to the list
      for (final recommendation in recommendations) {
        if (!_recommendations.any((r) => r.description == recommendation.description)) {
          _recommendations.add(recommendation);
          _optimizerController.add(OptimizerEvent(
          type: OptimizerEventType.recommendationGenerated,
          data: recommendation.toJson(),
        ));
        }
      }
      
      // Keep recommendations list bounded
      if (_recommendations.length > 50) {
        _recommendations.removeRange(0, _recommendations.length - 50);
      }
      
      debugPrint('✅ Performance analysis completed - ${recommendations.length} recommendations generated');
    } catch (e) {
      debugPrint('❌ Error during performance analysis: $e');
    }
  }

  Future<double> _getCpuUsage() async {
    try {
      // Simple CPU usage calculation using /proc/stat on Linux
      final statFile = File('/proc/stat');
      if (await statFile.exists()) {
        final lines = await statFile.readAsLines();
        if (lines.isNotEmpty) {
          final cpuLine = lines.first;
          final parts = cpuLine.split(RegExp(r'\s+'));
          if (parts.length > 4) {
            final idle = int.parse(parts[4]);
            final total = parts.skip(1).take(7).map(int.parse).reduce((a, b) => a + b);
            return total > 0 ? (total - idle) / total : 0.0;
          }
        }
      }
    } catch (e) {
      // Fallback for non-Linux systems or errors
    }
    return 0.0; // Default fallback
  }

  Future<double> _getMemoryUsage() async {
    try {
      final meminfoFile = File('/proc/meminfo');
      if (await meminfoFile.exists()) {
        final lines = await meminfoFile.readAsLines();
        int totalMem = 0;
        int availableMem = 0;
        
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            totalMem = int.parse(line.split(RegExp(r'\s+'))[1]);
          } else if (line.startsWith('MemAvailable:')) {
            availableMem = int.parse(line.split(RegExp(r'\s+'))[1]);
          }
        }
        
        if (totalMem > 0) {
          return (totalMem - availableMem) / totalMem;
        }
      }
    } catch (e) {
      // Fallback for non-Linux systems or errors
    }
    return 0.0; // Default fallback
  }

  double _getGpuUsage() {
    try {
      // Try to read NVIDIA GPU usage from nvidia-smi
      final result = Process.runSync('nvidia-smi', [
        '--query-gpu=utilization.gpu',
        '--format=csv,noheader,nounits'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return double.tryParse(output) ?? 0.0;
        }
      }
      
      // Fallback: try reading from /proc/driver/nvidia/gpus/0/ utilization
      final gpuUtilFile = File('/proc/driver/nvidia/gpus/0/utilization');
      if (gpuUtilFile.existsSync()) {
        final utilization = gpuUtilFile.readAsStringSync().trim();
        return double.tryParse(utilization) ?? 0.0;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get GPU usage: $e');
    }
    return 0.0;
  }

  Map<String, dynamic> _getTerminalMetrics() {
    return {
      'active_sessions': 1, // Would be dynamically determined
      'rendering_fps': 60.0, // Would be measured
      'memory_per_session': 50.0, // MB, would be measured
    };
  }

  List<OptimizationRecommendation> _generateRecommendations({
    required double cpuUsage,
    required double memoryUsage,
    required double gpuUsage,
    required Map<String, dynamic> terminalMetrics,
  }) {
    final recommendations = <OptimizationRecommendation>[];
    
    // CPU-based recommendations
    if (cpuUsage > 0.8) {
      recommendations.add(OptimizationRecommendation(
        id: 'cpu_opt_1',
        timestamp: DateTime.now(),
        overallScore: 0.7,
        suggestions: [OptimizationSuggestion(
          id: 'cpu_opt_1',
          title: 'Reduce Terminal Animations',
          description: 'Disable visual effects to lower CPU usage',
          impact: 'medium',
          effort: 'low',
          category: 'performance',
          command: 'termisol --set animations=off',
          priority: 2,
        )],
        predictedImprovement: '15-25% CPU reduction',
        implementationTime: '5 minutes',
        riskLevel: 'low',
      ));
    }
    
    // Memory-based recommendations
    if (memoryUsage > 0.85) {
      recommendations.add(OptimizationRecommendation(
        id: 'mem_opt_1',
        timestamp: DateTime.now(),
        overallScore: 0.8,
        suggestions: [OptimizationSuggestion(
          id: 'mem_opt_1',
          title: 'Clear Terminal History',
          description: 'Reduce scrollback buffer size to free memory',
          impact: 'medium',
          effort: 'low',
          category: 'memory',
          command: 'termisol --clear-history',
          priority: 3,
        )],
        predictedImprovement: '10-20% memory reduction',
        implementationTime: '2 minutes',
        riskLevel: 'low',
        ));
    }
    
    // Terminal-specific recommendations
    final fps = terminalMetrics['rendering_fps'] as double? ?? 60.0;
    if (fps < 30.0) {
      recommendations.add(OptimizationRecommendation(
        id: 'gpu_opt_1',
        timestamp: DateTime.now(),
        overallScore: 0.6,
        suggestions: [OptimizationSuggestion(
          id: 'gpu_opt_1',
          title: 'Enable Hardware Acceleration',
          description: 'Use GPU rendering for better performance',
          impact: 'high',
          effort: 'medium',
          category: 'rendering',
          command: 'termisol --enable-gpu',
          priority: 1,
        )],
        predictedImprovement: '30-50% FPS improvement',
        implementationTime: '10 minutes',
        riskLevel: 'medium',
        ));
    }
    
    return recommendations;
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
}

// Data classes
class OptimizationRecommendation {
  final String id;
  final DateTime timestamp;
  final double overallScore;
  final List<OptimizationSuggestion> suggestions;
  final String predictedImprovement;
  final String implementationTime;
  final String riskLevel;
  
  OptimizationRecommendation({
    required this.id,
    required this.timestamp,
    required this.overallScore,
    required this.suggestions,
    required this.predictedImprovement,
    required this.implementationTime,
    required this.riskLevel,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'overallScore': overallScore,
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
    'predictedImprovement': predictedImprovement,
    'implementationTime': implementationTime,
    'riskLevel': riskLevel,
  };
}

class OptimizationSuggestion {
  final String id;
  final String title;
  final String description;
  final String impact;
  final String effort;
  final String category;
  final String command;
  final int priority;
  bool applied;
  DateTime? appliedAt;
  
  OptimizationSuggestion({
    required this.id,
    required this.title,
    required this.description,
    required this.impact,
    required this.effort,
    required this.category,
    required this.command,
    required this.priority,
    this.applied = false,
    this.appliedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'impact': impact,
    'effort': effort,
    'category': category,
    'command': command,
    'priority': priority,
    'applied': applied,
    'appliedAt': appliedAt?.toIso8601String(),
  };
}

class PerformanceProfile {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final DateTime createdAt;
  
  PerformanceProfile({
    required this.name,
    required this.description,
    required this.parameters,
    required this.createdAt,
  });
}

class OptimizationHistory {
  final DateTime timestamp;
  final String systemType;
  final Map<String, dynamic> metrics;
  final List<OptimizationSuggestion> recommendations;
  bool applied;
  DateTime? appliedAt;
  
  OptimizationHistory({
    required this.timestamp,
    required this.systemType,
    required this.metrics,
    required this.recommendations,
    this.applied = false,
    this.appliedAt,
  });
}

class OptimizationResult {
  final bool success;
  final OptimizationRecommendation? recommendations;
  final SystemOptimization? systemOptimization;
  final ApplicationOptimization? applicationOptimization;
  final PredictiveOptimization? predictiveOptimization;
  final String? error;
  
  OptimizationResult({
    required this.success,
    this.recommendations,
    this.systemOptimization,
    this.applicationOptimization,
    this.predictiveOptimization,
    this.error,
  });
  
  factory OptimizationResult.success({OptimizationRecommendation? recommendations, SystemOptimization? systemOptimization, ApplicationOptimization? applicationOptimization, PredictiveOptimization? predictiveOptimization}) {
    return OptimizationResult(
      success: true,
      recommendations: recommendations,
      systemOptimization: systemOptimization,
      applicationOptimization: applicationOptimization,
      predictiveOptimization: predictiveOptimization,
    );
  }
  
  factory OptimizationResult.error(String error) {
    return OptimizationResult(
      success: false,
      error: error,
    );
  }
}

class OptimizerEvent {
  final OptimizerEventType type;
  final Map<String, dynamic>? data;
  
  OptimizerEvent({
    required this.type,
    this.data,
  });
}

enum OptimizerEventType {
  recommendationsGenerated,
  recommendationGenerated,
  systemOptimizationGenerated,
  applicationOptimizationGenerated,
  predictiveOptimizationGenerated,
  optimizationApplied,
  profileSaved,
}

class SystemOptimization {
  final List<SystemConfigChange> optimizations;
  final String implementationPlan;
  final String rollbackPlan;
  final DateTime timestamp;
  
  SystemOptimization({
    required this.optimizations,
    required this.implementationPlan,
    required this.rollbackPlan,
    required this.timestamp,
  });
}

class SystemConfigChange {
  final String title;
  final String parameter;
  final String currentValue;
  final String recommendedValue;
  final String reason;
  final String impact;
  final String risk;
  
  SystemConfigChange({
    required this.title,
    required this.parameter,
    required this.currentValue,
    required this.recommendedValue,
    required this.reason,
    required this.impact,
    required this.risk,
  });
}

class ApplicationOptimization {
  final List<ApplicationOptimizationChange> optimizations;
  final String codeChanges;
  final String monitoring;
  final DateTime timestamp;
  
  ApplicationOptimization({
    required this.optimizations,
    required this.codeChanges,
    required this.monitoring,
    required this.timestamp,
  });
}

class ApplicationOptimizationChange {
  final String title;
  final String area;
  final String description;
  final String implementation;
  final String impact;
  final String effort;
  
  ApplicationOptimizationChange({
    required this.title,
    required this.area,
    required this.description,
    required this.implementation,
    required this.impact,
    required this.effort,
  });
}

class PredictiveOptimization {
  final List<PerformancePrediction> predictions;
  final List<PreemptiveAction> preemptiveActions;
  final String monitoringPlan;
  final DateTime timestamp;
  
  PredictiveOptimization({
    required this.predictions,
    required this.preemptiveActions,
    required this.monitoringPlan,
    required this.timestamp,
  });
}

class PerformancePrediction {
  final String issue;
  final String predictedTime;
  final double probability;
  final String impact;
  final List<String> metricsAffected;
  
  PerformancePrediction({
    required this.issue,
    required this.predictedTime,
    required this.probability,
    required this.impact,
    required this.metricsAffected,
  });
}

class PreemptiveAction {
  final String action;
  final String targetPrediction;
  final String timing;
  final String effectiveness;
  final String effort;
  
  PreemptiveAction({
    required this.action,
    required this.targetPrediction,
    required this.timing,
    required this.effectiveness,
    required this.effort,
  });
}
