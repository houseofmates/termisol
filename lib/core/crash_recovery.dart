import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Crash recovery system for terminal sessions.
/// Tracks command health, detects hangs, and can suggest recovery actions.
class CrashRecovery {
  final _commandHistory = Queue<_CommandRecord>();
  static const int _maxHistory = 100;
  Timer? _healthTimer;
  final Map<String, _SessionHealth> _sessionHealth = {};

  /// Initialize the recovery system for a session.
  Future<void> initialize(String sessionId) async {
    _sessionHealth[sessionId] = _SessionHealth(
      startTime: DateTime.now(),
      commandCount: 0,
      lastActivity: DateTime.now(),
    );
  }

  /// Record a command execution for health monitoring.
  void onCommand(String sessionId, String command) {
    final now = DateTime.now();
    _commandHistory.add(_CommandRecord(
      sessionId: sessionId,
      command: command,
      timestamp: now,
    ));

    if (_commandHistory.length > _maxHistory) {
      _commandHistory.removeFirst();
    }

    final health = _sessionHealth[sessionId];
    if (health != null) {
      health.commandCount++;
      health.lastActivity = now;
    }
  }

  /// Mark a session as ended.
  void onSessionEnd(String sessionId) {
    _sessionHealth.remove(sessionId);
  }

  /// Start periodic health monitoring.
  void startHealthMonitoring(String sessionId) {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkHealth(sessionId);
    });
  }

  void _checkHealth(String sessionId) {
    final health = _sessionHealth[sessionId];
    if (health == null) return;

    final inactiveDuration = DateTime.now().difference(health.lastActivity);
    if (inactiveDuration > const Duration(minutes: 5)) {
      if (kDebugMode) {
        debugPrint('[CrashRecovery] Session $sessionId inactive for $inactiveDuration');
      }
    }
  }

  /// Get recent commands for a session.
  List<String> getRecentCommands(String sessionId, {int limit = 20}) {
    return _commandHistory
        .where((r) => r.sessionId == sessionId)
        .take(limit)
        .map((r) => r.command)
        .toList();
  }

  /// Dispose and clean up resources.
  void dispose() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _commandHistory.clear();
    _sessionHealth.clear();
  }
}

class _CommandRecord {
  final String sessionId;
  final String command;
  final DateTime timestamp;

  _CommandRecord({
    required this.sessionId,
    required this.command,
    required this.timestamp,
  });
}

class _SessionHealth {
  DateTime startTime;
  int commandCount;
  DateTime lastActivity;

  _SessionHealth({
    required this.startTime,
    required this.commandCount,
    required this.lastActivity,
  });
}
