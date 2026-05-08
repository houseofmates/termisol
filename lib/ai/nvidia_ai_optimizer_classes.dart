import 'dart:async';
import 'dart:convert';
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

/// Data classes
class OptimizationRecommendation {
  final DateTime timestamp;
  final double overallScore;
  final List<OptimizationSuggestion> suggestions;
  final String predictedImprovement;
  final String implementationTime;
  final String riskLevel;
  
  OptimizationRecommendation({
    required this.timestamp,
    required this.overallScore,
    required this.suggestions,
    required this.predictedImprovement,
    required this.implementationTime,
    required this.riskLevel,
  });
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
