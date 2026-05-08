import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'nvidia_ai_optimizer_classes.dart';

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
    List<String>? optimizationGoals,
    Map<String, dynamic>? context,
  }) async {
    try {
      final prompt = _buildOptimizationPrompt(
        performanceMetrics: performanceMetrics,
        systemType: systemType,
        optimizationGoals: optimizationGoals ?? ['performance', 'efficiency'],
        context: context ?? {},
      );
      
      final response = await _callNVIDIA(prompt);
      final recommendations = _parseOptimizationResponse(response);
      
      // Cache recommendations
      final cacheKey = _generateCacheKey(performanceMetrics, systemType);
      _recommendations[cacheKey] = recommendations;
      
      // Add to history
      _history.add(OptimizationHistory(
        timestamp: DateTime.now(),
        systemType: systemType,
        metrics: performanceMetrics,
        recommendations: recommendations.suggestions,
        applied: false,
      ));
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.recommendationsGenerated,
        data: {
          'system_type': systemType,
          'recommendations_count': recommendations.suggestions.length,
          'overall_score': recommendations.overallScore,
        },
      ));
      
      return OptimizationResult(
        success: true,
        recommendations: recommendations,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to get optimization recommendations: $e');
      return OptimizationResult.error(e.toString());
    }
  }

  Future<OptimizationResult> getSystemOptimization({
    required String systemType,
    required Map<String, dynamic> currentConfig,
    Map<String, dynamic>? constraints,
  }) async {
    try {
      final prompt = _buildSystemOptimizationPrompt(
        systemType: systemType,
        currentConfig: currentConfig,
        constraints: constraints ?? {},
      );
      
      final response = await _callNVIDIA(prompt);
      final systemOpt = _parseSystemOptimizationResponse(response);
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.systemOptimizationGenerated,
        data: {
          'system_type': systemType,
          'optimizations_count': systemOpt.optimizations.length,
        },
      ));
      
      return OptimizationResult(
        success: true,
        systemOptimization: systemOpt,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to get system optimization: $e');
      return OptimizationResult.error(e.toString());
    }
  }

  Future<OptimizationResult> getApplicationOptimization({
    required String applicationType,
    required Map<String, dynamic> appMetrics,
    List<String>? focusAreas,
  }) async {
    try {
      final prompt = _buildApplicationOptimizationPrompt(
        applicationType: applicationType,
        appMetrics: appMetrics,
        focusAreas: focusAreas ?? ['performance', 'memory', 'cpu'],
      );
      
      final response = await _callNVIDIA(prompt);
      final appOpt = _parseApplicationOptimizationResponse(response);
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.applicationOptimizationGenerated,
        data: {
          'application_type': applicationType,
          'optimizations_count': appOpt.optimizations.length,
        },
      ));
      
      return OptimizationResult(
        success: true,
        applicationOptimization: appOpt,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to get application optimization: $e');
      return OptimizationResult.error(e.toString());
    }
  }

  Future<OptimizationResult> getPredictiveOptimization({
    required Map<String, dynamic> currentMetrics,
    required Map<String, dynamic> workloadPattern,
    int predictionHorizon = 60, // minutes
  }) async {
    try {
      final prompt = _buildPredictiveOptimizationPrompt(
        currentMetrics: currentMetrics,
        workloadPattern: workloadPattern,
        predictionHorizon: predictionHorizon,
      );
      
      final response = await _callNVIDIA(prompt);
      final predictiveOpt = _parsePredictiveOptimizationResponse(response);
      
      _optimizerController.add(OptimizerEvent(
        type: OptimizerEventType.predictiveOptimizationGenerated,
        data: {
          'prediction_horizon': predictionHorizon,
          'predictions_count': predictiveOpt.predictions.length,
        },
      ));
      
      return OptimizationResult(
        success: true,
        predictiveOptimization: predictiveOpt,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to get predictive optimization: $e');
      return OptimizationResult.error(e.toString());
    }
  }

  Future<bool> applyOptimization(String optimizationId) async {
    final recommendation = _recommendations.values
        .where((rec) => rec.suggestions.any((s) => s.id == optimizationId))
        .firstOrNull;
    
    if (recommendation == null) {
      debugPrint('❌ Optimization not found: $optimizationId');
      return false;
    }
    
    final suggestion = recommendation.suggestions
        .where((s) => s.id == optimizationId)
        .first;
    
    try {
      // Apply the optimization
      final success = await _executeOptimization(suggestion);
      
      if (success) {
        suggestion.applied = true;
        suggestion.appliedAt = DateTime.now();
        
        // Update history
        if (_history.isNotEmpty) {
          final historyEntry = _history.last;
          historyEntry.applied = true;
          historyEntry.appliedAt = DateTime.now();
        }
        
        _optimizerController.add(OptimizerEvent(
          type: OptimizerEventType.optimizationApplied,
          data: {
            'optimization_id': optimizationId,
            'title': suggestion.title,
          },
        ));
        
        debugPrint('✅ Applied optimization: ${suggestion.title}');
        return true;
      }
      
      return false;
      
    } catch (e) {
      debugPrint('❌ Failed to apply optimization: $e');
      return false;
    }
  }

  List<OptimizationRecommendation> getRecommendationHistory() {
    return _recommendations.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<OptimizationHistory> getOptimizationHistory() {
    return _history.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  PerformanceProfile? getProfile(String profileName) {
    return _profiles[profileName];
  }

  Future<void> saveProfile(String profileName, PerformanceProfile profile) async {
    _profiles[profileName] = profile;
    
    _optimizerController.add(OptimizerEvent(
      type: OptimizerEventType.profileSaved,
      data: {
        'profile_name': profileName,
        'parameters': profile.parameters.length,
      },
    ));
  }

  String _buildOptimizationPrompt({
    required Map<String, dynamic> performanceMetrics,
    required String systemType,
    required List<String> optimizationGoals,
    required Map<String, dynamic> context,
  }) {
    return '''
You are an expert system optimization engineer specializing in performance tuning. Analyze the following system metrics and provide optimization recommendations.

SYSTEM TYPE: $systemType
OPTIMIZATION GOALS: ${optimizationGoals.join(', ')}

CURRENT PERFORMANCE METRICS:
${_formatMetrics(performanceMetrics)}

SYSTEM CONTEXT:
${_formatContext(context)}

Provide comprehensive optimization recommendations in this format:

OVERALL_SCORE: [0.0-1.0 overall performance score]

RECOMMENDATIONS: [List 3-5 specific recommendations]
- REC_1: [Title]
  DESCRIPTION: [Detailed description]
  IMPACT: [high/medium/low]
  EFFORT: [easy/medium/hard]
  CATEGORY: [cpu/memory/disk/network/application]
  COMMAND: [Specific command or action]
  PRIORITY: [1-10]
  
- REC_2: [Title]
  DESCRIPTION: [Detailed description]
  IMPACT: [high/medium/low]
  EFFORT: [easy/medium/hard]
  CATEGORY: [cpu/memory/disk/network/application]
  COMMAND: [Specific command or action]
  PRIORITY: [1-10]

PREDICTED_IMPROVEMENT: [Expected performance improvement percentage]
IMPLEMENTATION_TIME: [Estimated time to implement]
RISK_LEVEL: [low/medium/high]

Focus on practical, actionable optimizations that can be implemented immediately. Consider the specific system type and optimization goals.
''';
  }

  String _buildSystemOptimizationPrompt({
    required String systemType,
    required Map<String, dynamic> currentConfig,
    required Map<String, dynamic> constraints,
  }) {
    return '''
You are a system configuration expert. Optimize the system configuration for better performance.

SYSTEM TYPE: $systemType

CURRENT CONFIGURATION:
${_formatConfig(currentConfig)}

CONSTRAINTS:
${_formatConstraints(constraints)}

Provide system optimization recommendations:

OPTIMIZATIONS: [List configuration changes]
- OPT_1: [Configuration change]
  PARAMETER: [Parameter name]
  CURRENT_VALUE: [Current value]
  RECOMMENDED_VALUE: [Recommended value]
  REASON: [Why this change]
  IMPACT: [Expected impact]
  RISK: [Risk level]

- OPT_2: [Configuration change]
  PARAMETER: [Parameter name]
  CURRENT_VALUE: [Current value]
  RECOMMENDED_VALUE: [Recommended value]
  REASON: [Why this change]
  IMPACT: [Expected impact]
  RISK: [Risk level]

IMPLEMENTATION_PLAN: [Step-by-step implementation plan]
ROLLBACK_PLAN: [Rollback strategy if needed]
''';
  }

  String _buildApplicationOptimizationPrompt({
    required String applicationType,
    required Map<String, dynamic> appMetrics,
    required List<String> focusAreas,
  }) {
    return '''
You are an application performance optimization expert. Optimize the application for better performance.

APPLICATION TYPE: $applicationType
FOCUS AREAS: ${focusAreas.join(', ')}

APPLICATION METRICS:
${_formatMetrics(appMetrics)}

Provide application optimization recommendations:

OPTIMIZATIONS: [List application optimizations]
- APP_OPT_1: [Optimization title]
  AREA: [Performance area]
  DESCRIPTION: [What to optimize]
  IMPLEMENTATION: [How to implement]
  IMPACT: [Expected performance gain]
  EFFORT: [Implementation effort]

- APP_OPT_2: [Optimization title]
  AREA: [Performance area]
  DESCRIPTION: [What to optimize]
  IMPLEMENTATION: [How to implement]
  IMPACT: [Expected performance gain]
  EFFORT: [Implementation effort]

CODE_CHANGES: [Specific code optimizations if applicable]
MONITORING: [How to monitor improvements]
''';
  }

  String _buildPredictiveOptimizationPrompt({
    required Map<String, dynamic> currentMetrics,
    required Map<String, dynamic> workloadPattern,
    required int predictionHorizon,
  }) {
    return '''
You are a predictive performance analyst. Predict future performance issues and recommend preemptive optimizations.

CURRENT METRICS:
${_formatMetrics(currentMetrics)}

WORKLOAD PATTERN:
${_formatWorkloadPattern(workloadPattern)}

PREDICTION HORIZON: $predictionHorizon minutes

Provide predictive optimization recommendations:

PREDICTIONS: [List performance predictions]
- PRED_1: [Performance issue]
  PREDICTED_TIME: [When issue will occur]
  PROBABILITY: [0.0-1.0]
  IMPACT: [Severity of impact]
  METRICS_AFFECTED: [Which metrics]

- PRED_2: [Performance issue]
  PREDICTED_TIME: [When issue will occur]
  PROBABILITY: [0.0-1.0]
  IMPACT: [Severity of impact]
  METRICS_AFFECTED: [Which metrics]

PREEMPTIVE_ACTIONS: [List preemptive optimizations]
- ACTION_1: [Preemptive action]
  TARGET_PREDICTION: [Which prediction this addresses]
  TIMING: [When to implement]
  EFFECTIVENESS: [How effective]
  EFFORT: [Implementation effort]

- ACTION_2: [Preemptive action]
  TARGET_PREDICTION: [Which prediction this addresses]
  TIMING: [When to implement]
  EFFECTIVENESS: [How effective]
  EFFORT: [Implementation effort]

MONITORING_PLAN: [How to monitor for predicted issues]
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
          {'role': 'system', 'content': 'You are an expert system performance optimizer with deep knowledge of hardware, software, and application tuning. Provide specific, actionable recommendations with clear implementation steps.'},
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 3000,
        'temperature': 0.2,
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
    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('OVERALL_SCORE:')) {
        overallScore = double.tryParse(line.substring(14).trim()) ?? 0.5;
      } else if (line.startsWith('RECOMMENDATIONS:')) {
        currentSection = 'recommendations';
      } else if (line.startsWith('PREDICTED_IMPROVEMENT:')) {
        predictedImprovement = line.substring(21).trim();
      } else if (line.startsWith('IMPLEMENTATION_TIME:')) {
        implementationTime = line.substring(19).trim();
      } else if (line.startsWith('RISK_LEVEL:')) {
        riskLevel = line.substring(11).trim();
      } else if (currentSection == 'recommendations' && line.startsWith('- REC_')) {
        suggestions.add(_parseRecommendation(lines, lines.indexOf(line)));
      }
    }
    
    return OptimizationRecommendation(
      timestamp: DateTime.now(),
      overallScore: overallScore,
      suggestions: suggestions,
      predictedImprovement: predictedImprovement ?? 'Unknown',
      implementationTime: implementationTime ?? 'Unknown',
      riskLevel: riskLevel ?? 'medium',
    );
  }

  OptimizationSuggestion _parseRecommendation(List<String> lines, int startIndex) {
    String? title;
    String? description;
    String? impact;
    String? effort;
    String? category;
    String? command;
    int priority = 5;
    
    for (int i = startIndex; i < math.min(startIndex + 10, lines.length); i++) {
      final line = lines[i];
      if (line.startsWith('DESCRIPTION:')) {
        description = line.substring(13).trim();
      } else if (line.startsWith('IMPACT:')) {
        impact = line.substring(8).trim();
      } else if (line.startsWith('EFFORT:')) {
        effort = line.substring(8).trim();
      } else if (line.startsWith('CATEGORY:')) {
        category = line.substring(10).trim();
      } else if (line.startsWith('COMMAND:')) {
        command = line.substring(9).trim();
      } else if (line.startsWith('PRIORITY:')) {
        priority = int.tryParse(line.substring(10).trim()) ?? 5;
      } else if (line.startsWith('- REC_')) {
        title = line.substring(7).split(':').first.trim();
      }
    }
    
    return OptimizationSuggestion(
      id: 'opt_${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Unknown',
      description: description ?? 'No description',
      impact: impact ?? 'medium',
      effort: effort ?? 'medium',
      category: category ?? 'general',
      command: command ?? '',
      priority: priority,
      applied: false,
    );

  SystemOptimization _parseSystemOptimizationResponse(String response) {
    final lines = response.split('\n');
    final optimizations = <SystemConfigChange>[];
    String? implementationPlan;
    String? rollbackPlan;
    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('OPTIMIZATIONS:')) {
        currentSection = 'optimizations';
      } else if (line.startsWith('IMPLEMENTATION_PLAN:')) {
        implementationPlan = line.substring(19).trim();
        currentSection = 'implementation';
      } else if (line.startsWith('ROLLBACK_PLAN:')) {
        rollbackPlan = line.substring(14).trim();
        currentSection = 'rollback';
      } else if (currentSection == 'optimizations' && line.startsWith('- OPT_')) {
        optimizations.add(_parseSystemOptimization(lines, lines.indexOf(line)));
      }
    }
    
    return SystemOptimization(
      optimizations: optimizations,
      implementationPlan: implementationPlan ?? 'No plan provided',
      rollbackPlan: rollbackPlan ?? 'No rollback plan',
      timestamp: DateTime.now(),
    );
  }

  SystemConfigChange _parseSystemOptimization(List<String> lines, int startIndex) {
    String? title;
    String? parameter;
    String? currentValue;
    String? recommendedValue;
    String? reason;
    String? impact;
    String? risk;
    
    for (int i = startIndex; i < math.min(startIndex + 10, lines.length); i++) {
      final line = lines[i];
      if (line.startsWith('PARAMETER:')) {
        parameter = line.substring(11).trim();
      } else if (line.startsWith('CURRENT_VALUE:')) {
        currentValue = line.substring(15).trim();
      } else if (line.startsWith('RECOMMENDED_VALUE:')) {
        recommendedValue = line.substring(18).trim();
      } else if (line.startsWith('REASON:')) {
        reason = line.substring(8).trim();
      } else if (line.startsWith('IMPACT:')) {
        impact = line.substring(8).trim();
      } else if (line.startsWith('RISK:')) {
        risk = line.substring(6).trim();
      } else if (line.startsWith('- OPT_')) {
        title = line.substring(7).split(':').first.trim();
      }
    }
    
    return SystemConfigChange(
      title: title ?? 'Unknown',
      parameter: parameter ?? 'Unknown',
      currentValue: currentValue ?? 'Unknown',
      recommendedValue: recommendedValue ?? 'Unknown',
      reason: reason ?? 'No reason',
      impact: impact ?? 'medium',
      risk: risk ?? 'low',
    );
  }

  ApplicationOptimization _parseApplicationOptimizationResponse(String response) {
    final lines = response.split('\n');
    final optimizations = <ApplicationOptimizationChange>[];
    String? codeChanges;
    String? monitoring;
    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('OPTIMIZATIONS:')) {
        currentSection = 'optimizations';
      } else if (line.startsWith('CODE_CHANGES:')) {
        codeChanges = line.substring(13).trim();
        currentSection = 'code';
      } else if (line.startsWith('MONITORING:')) {
        monitoring = line.substring(12).trim();
        currentSection = 'monitoring';
      } else if (currentSection == 'optimizations' && line.startsWith('- APP_OPT_')) {
        optimizations.add(_parseApplicationOptimization(lines, lines.indexOf(line)));
      }
    }
    
    return ApplicationOptimization(
      optimizations: optimizations,
      codeChanges: codeChanges ?? 'No code changes',
      monitoring: monitoring ?? 'No monitoring plan',
      timestamp: DateTime.now(),
    );
  }

  ApplicationOptimizationChange _parseApplicationOptimization(List<String> lines, int startIndex) {
    String? title;
    String? area;
    String? description;
    String? implementation;
    String? impact;
    String? effort;
    
    for (int i = startIndex; i < math.min(startIndex + 10, lines.length); i++) {
      final line = lines[i];
      if (line.startsWith('AREA:')) {
        area = line.substring(6).trim();
      } else if (line.startsWith('DESCRIPTION:')) {
        description = line.substring(13).trim();
      } else if (line.startsWith('IMPLEMENTATION:')) {
        implementation = line.substring(15).trim();
      } else if (line.startsWith('IMPACT:')) {
        impact = line.substring(8).trim();
      } else if (line.startsWith('EFFORT:')) {
        effort = line.substring(7).trim();
      } else if (line.startsWith('- APP_OPT_')) {
        title = line.substring(10).split(':').first.trim();
      }
    }
    
    return ApplicationOptimizationChange(
      title: title ?? 'Unknown',
      area: area ?? 'general',
      description: description ?? 'No description',
      implementation: implementation ?? 'No implementation',
      impact: impact ?? 'medium',
      effort: effort ?? 'medium',
    );
  }

  PredictiveOptimization _parsePredictiveOptimizationResponse(String response) {
    final lines = response.split('\n');
    final predictions = <PerformancePrediction>[];
    final preemptiveActions = <PreemptiveAction>[];
    String? monitoringPlan;
    String? currentSection;
    
    for (final line in lines) {
      if (line.startsWith('PREDICTIONS:')) {
        currentSection = 'predictions';
      } else if (line.startsWith('PREEMPTIVE_ACTIONS:')) {
        currentSection = 'actions';
      } else if (line.startsWith('MONITORING_PLAN:')) {
        monitoringPlan = line.substring(16).trim();
        currentSection = 'monitoring';
      } else if (currentSection == 'predictions' && line.startsWith('- PRED_')) {
        predictions.add(_parsePrediction(lines, lines.indexOf(line)));
      } else if (currentSection == 'actions' && line.startsWith('- ACTION_')) {
        preemptiveActions.add(_parsePreemptiveAction(lines, lines.indexOf(line)));
      }
    }
    
    return PredictiveOptimization(
      predictions: predictions,
      preemptiveActions: preemptiveActions,
      monitoringPlan: monitoringPlan ?? 'No monitoring plan',
      timestamp: DateTime.now(),
    );
  }

  PerformancePrediction _parsePrediction(List<String> lines, int startIndex) {
    String? issue;
    String? predictedTime;
    double probability = 0.5;
    String? impact;
    List<String> metricsAffected = [];
    
    for (int i = startIndex; i < math.min(startIndex + 10, lines.length); i++) {
      final line = lines[i];
      if (line.startsWith('PREDICTED_TIME:')) {
        predictedTime = line.substring(15).trim();
      } else if (line.startsWith('PROBABILITY:')) {
        probability = double.tryParse(line.substring(12).trim()) ?? 0.5;
      } else if (line.startsWith('IMPACT:')) {
        impact = line.substring(8).trim();
      } else if (line.startsWith('METRICS_AFFECTED:')) {
        metricsAffected = line.substring(17).trim().split(',').map((m) => m.trim()).toList();
      } else if (line.startsWith('- PRED_')) {
        issue = line.substring(8).split(':').first.trim();
      }
    }
    
    return PerformancePrediction(
      issue: issue ?? 'Unknown',
      predictedTime: predictedTime ?? 'Unknown',
      probability: probability,
      impact: impact ?? 'medium',
      metricsAffected: metricsAffected,
    );
  }

  PreemptiveAction _parsePreemptiveAction(List<String> lines, int startIndex) {
    String? action;
    String? targetPrediction;
    String? timing;
    String? effectiveness;
    String? effort;
    
    for (int i = startIndex; i < math.min(startIndex + 10, lines.length); i++) {
      final line = lines[i];
      if (line.startsWith('TARGET_PREDICTION:')) {
        targetPrediction = line.substring(19).trim();
      } else if (line.startsWith('TIMING:')) {
        timing = line.substring(8).trim();
      } else if (line.startsWith('EFFECTIVENESS:')) {
        effectiveness = line.substring(14).trim();
      } else if (line.startsWith('EFFORT:')) {
        effort = line.substring(7).trim();
      } else if (line.startsWith('- ACTION_')) {
        action = line.substring(10).split(':').first.trim();
      }
    }
    
    return PreemptiveAction(
      action: action ?? 'Unknown',
      targetPrediction: targetPrediction ?? 'Unknown',
      timing: timing ?? 'Unknown',
      effectiveness: effectiveness ?? 'medium',
      effort: effort ?? 'medium',
    );
  }

  Future<bool> _executeOptimization(OptimizationSuggestion suggestion) async {
    // Simulate optimization execution
    await Future.delayed(Duration(milliseconds: 100));
    
    // In a real implementation, this would execute the actual optimization
    debugPrint('🔧 Executing optimization: ${suggestion.title}');
    debugPrint('📝 Command: ${suggestion.command}');
    
    return true;
  }

  String _formatMetrics(Map<String, dynamic> metrics) {
    final buffer = StringBuffer();
    for (final entry in metrics.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }

  String _formatContext(Map<String, dynamic> context) {
    final buffer = StringBuffer();
    for (final entry in context.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }

  String _formatConfig(Map<String, dynamic> config) {
    final buffer = StringBuffer();
    for (final entry in config.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }

  String _formatConstraints(Map<String, dynamic> constraints) {
    final buffer = StringBuffer();
    for (final entry in constraints.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }

  String _formatWorkloadPattern(Map<String, dynamic> pattern) {
    final buffer = StringBuffer();
    for (final entry in pattern.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }

  String _generateCacheKey(Map<String, dynamic> metrics, String systemType) {
    final metricsHash = metrics.toString().hashCode;
    return '${systemType}_$metricsHash';
  }



  /// Analyze current performance metrics
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
    _optimizerController.close();
    _recommendations.clear();
    _profiles.clear();
    _history.clear();
  }
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
  systemOptimizationGenerated,
  applicationOptimizationGenerated,
  predictiveOptimizationGenerated,
  optimizationApplied,
  profileSaved,
}
