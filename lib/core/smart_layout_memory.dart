import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Smart layout memory system that remembers user preferences
class SmartLayoutMemory {
  final Map<String, LayoutPreference> _preferences = {};
  final Map<String, ActivityPattern> _patterns = {};
  final Map<String, DateTime> _lastUsed = {};
  
  Timer? _cleanupTimer;
  StreamController<LayoutEvent> _eventController = StreamController<LayoutEvent>.broadcast();
  Stream<LayoutEvent> get events => _eventController.stream;
  
  void initialize() {
    _setupCleanup();
    _loadDefaultPreferences();
    developer.log('Smart Layout Memory initialized');
  }
  
  void _setupCleanup() {
    _cleanupTimer = Timer.periodic(Duration(hours: 1), (_) {
      _cleanupOldPreferences();
    });
  }
  
  void _loadDefaultPreferences() {
    // Load default layout preferences
    _preferences['coding'] = LayoutPreference(
      splitRatio: 0.7,
      sidebarWidth: 300,
      showMinimap: true,
      showTerminal: true,
      showFileExplorer: true,
    );
    
    _preferences['debugging'] = LayoutPreference(
      splitRatio: 0.6,
      sidebarWidth: 350,
      showMinimap: true,
      showTerminal: true,
      showFileExplorer: true,
      showDebugPanel: true,
    );
    
    _preferences['design'] = LayoutPreference(
      splitRatio: 0.8,
      sidebarWidth: 250,
      showMinimap: false,
      showTerminal: false,
      showFileExplorer: true,
      showPreviewPanel: true,
    );
    
    _preferences['monitoring'] = LayoutPreference(
      splitRatio: 0.5,
      sidebarWidth: 400,
      showMinimap: false,
      showTerminal: true,
      showFileExplorer: true,
      showLogs: true,
      showMetrics: true,
    );
  }
  
  void recordLayoutUsage(String activity, LayoutPreference layout) {
    final now = DateTime.now();
    _lastUsed[activity] = now;
    
    // Update preference based on usage
    _updatePreference(activity, layout);
    
    // Record usage pattern
    _recordUsagePattern(activity, layout);
    
    _eventController.add(LayoutEvent(
      type: LayoutEventType.usageRecorded,
      data: {
        'activity': activity,
        'layout': layout.toJson(),
        'timestamp': now.toIso8601String(),
      },
    ));
  }
  
  void _updatePreference(String activity, LayoutPreference layout) {
    final existing = _preferences[activity];
    if (existing != null) {
      // Weighted average based on frequency
      final frequency = _getUsageFrequency(activity);
      final weight = math.min(1.0, frequency * 0.1);
      
      _preferences[activity] = LayoutPreference(
        splitRatio: (existing.splitRatio * (1 - weight)) + (layout.splitRatio * weight),
        sidebarWidth: (existing.sidebarWidth * (1 - weight)) + (layout.sidebarWidth * weight),
        showMinimap: layout.showMinimap,
        showTerminal: layout.showTerminal,
        showFileExplorer: layout.showFileExplorer,
        showDebugPanel: layout.showDebugPanel ?? false,
        showPreviewPanel: layout.showPreviewPanel ?? false,
        showLogs: layout.showLogs ?? false,
        showMetrics: layout.showMetrics ?? false,
      );
      
      _eventController.add(LayoutEvent(
        type: LayoutEventType.preferenceUpdated,
        data: {
          'activity': activity,
          'oldPreference': existing.toJson(),
          'newPreference': _preferences[activity]!.toJson(),
          'weight': weight,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }
  }
  
  void _recordUsagePattern(String activity, LayoutPreference layout) {
    final pattern = ActivityPattern(
      activity: activity,
      layout: layout,
      timestamp: DateTime.now(),
    );
    
    // Store pattern (simplified for this example)
    _patterns[activity] = pattern;
  }
  
  double _getUsageFrequency(String activity) {
    // Calculate how often this activity is used
    final usageHistory = _getUsageHistory(activity);
    if (usageHistory.isEmpty) return 0.1;
    
    // Count recent usage
    final recentUsage = usageHistory.where((record) =>
        record.timestamp.isAfter(DateTime.now().subtract(Duration(days: 7)))).length;
    
    return recentUsage / usageHistory.length;
  }
  
  List<UsageRecord> _getUsageHistory(String activity) {
    // Simulate getting usage history
    // In real implementation, this would read from persistent storage
    final now = DateTime.now();
    final history = <UsageRecord>[];
    
    // Generate some sample history
    for (int i = 0; i < 10; i++) {
      final daysAgo = i * 3;
      final timestamp = now.subtract(Duration(days: daysAgo));
      
      history.add(UsageRecord(
        activity: activity,
        layout: _preferences[activity],
        timestamp: timestamp,
      ));
    }
    
    return history;
  }
  
  LayoutPreference? getOptimalLayout(String activity) {
    // Get the best layout for this activity based on patterns
    final pattern = _patterns[activity];
    if (pattern == null) {
      return _preferences[activity]; // Return default
    }
    
    return pattern.layout;
  }
  
  Map<String, dynamic> getActivityStats() {
    final stats = <String, dynamic>{};
    
    for (final activity in _preferences.keys) {
      final preference = _preferences[activity];
      final lastUsed = _lastUsed[activity];
      
      stats[activity] = {
        'currentPreference': preference.toJson(),
        'lastUsed': lastUsed?.toIso8601String(),
        'frequency': _getUsageFrequency(activity),
      'patterns': _getUsageHistory(activity).length,
      };
    }
    
    return stats;
  }
  
  void _cleanupOldPreferences() {
    final cutoff = DateTime.now().subtract(Duration(days: 30));
    int cleaned = 0;
    
    // Remove old usage patterns
    final expiredPatterns = <String>[];
    for (final activity in _patterns.keys) {
      final pattern = _patterns[activity];
      if (pattern.timestamp.isBefore(cutoff)) {
        expiredPatterns.add(activity);
        _patterns.remove(activity);
        cleaned++;
      }
    }
    
    if (cleaned > 0) {
      _eventController.add(LayoutEvent(
        type: LayoutEventType.cleanup,
        data: {
          'cleanedPatterns': cleaned,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }
  }
  
  void dispose() {
    _cleanupTimer?.cancel();
    _eventController.close();
  }
}

class LayoutPreference {
  final double splitRatio;
  final int sidebarWidth;
  final bool showMinimap;
  final bool showTerminal;
  final bool showFileExplorer;
  final bool showDebugPanel;
  final bool showPreviewPanel;
  final bool showLogs;
  final bool showMetrics;
  
  LayoutPreference({
    required this.splitRatio,
    required this.sidebarWidth,
    required this.showMinimap,
    required this.showTerminal,
    required this.showFileExplorer,
    this.showDebugPanel = false,
    this.showPreviewPanel = false,
    this.showLogs = false,
    this.showMetrics = false,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'splitRatio': splitRatio,
      'sidebarWidth': sidebarWidth,
      'showMinimap': showMinimap,
      'showTerminal': showTerminal,
      'showFileExplorer': showFileExplorer,
      'showDebugPanel': showDebugPanel,
      'showPreviewPanel': showPreviewPanel,
      'showLogs': showLogs,
      'showMetrics': showMetrics,
    };
  }
}

class ActivityPattern {
  final String activity;
  final LayoutPreference layout;
  final DateTime timestamp;
  
  ActivityPattern({
    required this.activity,
    required this.layout,
    required this.timestamp,
  });
}

class UsageRecord {
  final String activity;
  final LayoutPreference layout;
  final DateTime timestamp;
  
  UsageRecord({
    required this.activity,
    required this.layout,
    required this.timestamp,
  });
}

enum LayoutEventType {
  usageRecorded,
  preferenceUpdated,
  cleanup,
}

class LayoutEvent {
  final LayoutEventType type;
  final Map<String, dynamic> data;
  
  LayoutEvent({
    required this.type,
    required this.data,
  });
}
