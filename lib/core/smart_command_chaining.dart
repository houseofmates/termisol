import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

/// Smart Command Chaining
///
/// Learns and suggests command sequences based on execution history.
/// Uses pattern recognition and frequency analysis to predict the next
/// command in a workflow chain.
class SmartCommandChaining {
  final Map<String, CommandGraph> _patterns = {};
  final Map<String, CommandStatistics> _statistics = {};
  final List<CommandSession> _recentSessions = [];
  final StreamController<ChainSuggestion> _suggestionController = StreamController<ChainSuggestion>.broadcast();
  Timer? _decayTimer;
  int _totalCommands = 0;

  static const int _maxSessions = 100;
  static const int _maxPatternDepth = 5;
  static const Duration _sessionTimeout = Duration(minutes: 5);
  static const Duration _decayInterval = Duration(hours: 1);
  static const double _decayFactor = 0.95;

  Stream<ChainSuggestion> get suggestions => _suggestionController.stream;
  int get totalCommands => _totalCommands;

  Future<void> initialize() async {
    try {
      await _loadPersistedPatterns();
      _decayTimer = Timer.periodic(_decayInterval, (_) => _applyDecay());
      debugPrint('SmartCommandChaining initialized ($_totalCommands commands tracked)');
    } catch (e) {
      debugPrint('Failed to initialize SmartCommandChaining: $e');
    }
  }

  void recordCommand(String sessionId, String command, {String? cwd, int? exitCode, Duration? duration}) {
    _totalCommands++;
    command = command.trim();
    if (command.isEmpty) return;

    final stats = _statistics.putIfAbsent(command, () => CommandStatistics(command: command));
    stats.count++;
    if (exitCode != null && exitCode == 0) stats.successCount++;
    if (duration != null) stats.totalDuration += duration;
    stats.lastUsed = DateTime.now();

    CommandSession? activeSession = _getOrCreateSession(sessionId, cwd);

    final previousCommand = activeSession.commands.isNotEmpty ? activeSession.commands.last : null;
    activeSession.commands.add(CommandEntry(
      command: command,
      timestamp: DateTime.now(),
      cwd: cwd,
      exitCode: exitCode,
    ));
    if (activeSession.commands.length > 200) {
      activeSession.commands.removeRange(0, 50);
    }

    if (previousCommand != null) {
      _updatePattern(previousCommand.command, command);
    }

    if (activeSession.commands.length >= 2) {
      for (int depth = 3; depth <= min(_maxPatternDepth, activeSession.commands.length); depth++) {
        final recent = activeSession.commands.sublist(activeSession.commands.length - depth);
        final prefix = recent.sublist(0, recent.length - 1).map((e) => e.command).join('|');
        final next = recent.last.command;
        _updatePattern(prefix, next);
      }
    }
  }

  List<ChainSuggestion> suggestNext(String currentCommand, {int maxSuggestions = 5}) {
    currentCommand = currentCommand.trim();
    if (currentCommand.isEmpty) return [];

    final graph = _patterns[currentCommand];
    if (graph == null) return [];

    final candidates = graph.transitions.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalWeight = candidates.fold(0.0, (sum, e) => sum + e.value);
    return candidates.take(maxSuggestions).map((e) {
      final stats = _statistics[e.key];
      return ChainSuggestion(
        command: e.key,
        confidence: totalWeight > 0 ? e.value / totalWeight : 0.0,
        frequency: e.value,
        totalUsage: stats?.count ?? 0,
        successRate: stats != null ? (stats.successCount / max(stats.count, 1)) : 0.0,
      );
    }).toList();
  }

  List<ChainSuggestion> suggestChain(List<String> context, {int maxDepth = 5, int topK = 3}) {
    if (context.isEmpty) return [];
    final key = context.join('|');
    final graph = _patterns[key];
    if (graph == null) return suggestNext(context.last, maxSuggestions: topK);

    final candidates = graph.transitions.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalWeight = candidates.fold(0.0, (sum, e) => sum + e.value);
    return candidates.take(topK).map((e) {
      final stats = _statistics[e.key];
      return ChainSuggestion(
        command: e.key,
        confidence: totalWeight > 0 ? e.value / totalWeight : 0.0,
        frequency: e.value,
        totalUsage: stats?.count ?? 0,
        successRate: stats != null ? (stats.successCount / max(stats.count, 1)) : 0.0,
      );
    }).toList();
  }

  List<CommandStatistics> getPopularCommands({int limit = 20}) {
    return _statistics.values
        .where((s) => s.count > 0)
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<String> findSimilarCommands(String command, {double threshold = 0.6}) {
    return _statistics.keys
        .where((k) => _levenshteinSimilarity(k.toLowerCase(), command.toLowerCase()) >= threshold)
        .toList()
      ..sort((a, b) {
        final sa = _statistics[a]?.count ?? 0;
        final sb = _statistics[b]?.count ?? 0;
        return sb.compareTo(sa);
      });
  }

  Future<bool> forgetCommand(String command) async {
    _patterns.remove(command);
    _statistics.remove(command);
    for (final graph in _patterns.values) {
      graph.transitions.remove(command);
    }
    return true;
  }

  Future<void> reset() async {
    _patterns.clear();
    _statistics.clear();
    _recentSessions.clear();
    _totalCommands = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cmd_chaining_patterns');
    await prefs.remove('cmd_chaining_stats');
  }

  void _updatePattern(String from, String to) {
    _patterns.putIfAbsent(from, () => CommandGraph(command: from));
    final graph = _patterns[from]!;
    graph.transitions.update(to, (v) => v + 1, ifAbsent: () => 1);
    graph.lastUsed = DateTime.now();
  }

  CommandSession _getOrCreateSession(String sessionId, String? cwd) {
    CommandSession? session = _recentSessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session != null) {
      session.lastActivity = DateTime.now();
      if (cwd != null) session.cwd = cwd;
      return session;
    }
    session = CommandSession(id: sessionId, cwd: cwd ?? '/', lastActivity: DateTime.now());
    _recentSessions.add(session);
    if (_recentSessions.length > _maxSessions) {
      _recentSessions.removeRange(0, _recentSessions.length - _maxSessions);
    }
    return session;
  }

  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final distances = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (int i = 0; i <= a.length; i++) distances[i][0] = i;
    for (int j = 0; j <= b.length; j++) distances[0][j] = j;
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        distances[i][j] = min(distances[i - 1][j] + 1, min(distances[i][j - 1] + 1, distances[i - 1][j - 1] + cost));
      }
    }
    final distance = distances[a.length][b.length];
    return 1.0 - (distance / max(a.length, b.length));
  }

  void _applyDecay() {
    for (final graph in _patterns.values) {
      for (final key in graph.transitions.keys.toList()) {
        graph.transitions[key] = (graph.transitions[key]! * _decayFactor).round();
        if (graph.transitions[key]! <= 0) {
          graph.transitions.remove(key);
        }
      }
    }
  }

  Future<void> _loadPersistedPatterns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patternsData = prefs.getString('cmd_chaining_patterns');
      if (patternsData != null) {
        final data = json.decode(patternsData) as Map<String, dynamic>;
        for (final entry in data.entries) {
          final graph = CommandGraph.fromJson(entry.key, Map<String, dynamic>.from(entry.value as Map));
          _patterns[entry.key] = graph;
        }
      }
      final statsData = prefs.getString('cmd_chaining_stats');
      if (statsData != null) {
        final data = json.decode(statsData) as Map<String, dynamic>;
        for (final entry in data.entries) {
          _statistics[entry.key] = CommandStatistics.fromJson(Map<String, dynamic>.from(entry.value as Map));
        }
      }
    } catch (e) {
      debugPrint('Failed to load persisted patterns: $e');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patternsData = _patterns.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString('cmd_chaining_patterns', json.encode(patternsData));
      final statsData = _statistics.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString('cmd_chaining_stats', json.encode(statsData));
    } catch (e) {
      debugPrint('Failed to persist patterns: $e');
    }
  }

  Future<void> dispose() async {
    _decayTimer?.cancel();
    await persist();
    await _suggestionController.close();
  }
}

class CommandGraph {
  final String command;
  final Map<String, int> transitions;
  DateTime lastUsed;

  CommandGraph({required this.command, Map<String, int>? transitions})
      : transitions = transitions ?? {},
        lastUsed = DateTime.now();

  Map<String, dynamic> toJson() => {
    'command': command,
    'transitions': transitions,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory CommandGraph.fromJson(String command, Map<String, dynamic> json) {
    return CommandGraph(
      command: command,
      transitions: Map<String, int>.from(json['transitions'] ?? {}),
    )..lastUsed = DateTime.tryParse(json['lastUsed'] ?? '') ?? DateTime.now();
  }
}

class CommandStatistics {
  final String command;
  int count;
  int successCount;
  Duration totalDuration;
  DateTime lastUsed;

  CommandStatistics({
    required this.command,
    this.count = 0,
    this.successCount = 0,
    this.totalDuration = Duration.zero,
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  double get successRate => count > 0 ? successCount / count : 0.0;
  Duration get averageDuration => count > 0 ? totalDuration ~/ count : Duration.zero;

  Map<String, dynamic> toJson() => {
    'command': command,
    'count': count,
    'successCount': successCount,
    'totalDurationMs': totalDuration.inMilliseconds,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory CommandStatistics.fromJson(Map<String, dynamic> json) {
    return CommandStatistics(
      command: json['command'] as String,
      count: json['count'] as int? ?? 0,
      successCount: json['successCount'] as int? ?? 0,
      totalDuration: Duration(milliseconds: json['totalDurationMs'] as int? ?? 0),
      lastUsed: DateTime.tryParse(json['lastUsed'] ?? '') ?? DateTime.now(),
    );
  }
}

class CommandSession {
  final String id;
  String cwd;
  DateTime lastActivity;
  final List<CommandEntry> commands;

  CommandSession({required this.id, this.cwd = '/', required this.lastActivity, List<CommandEntry>? commands})
      : commands = commands ?? [];
}

class CommandEntry {
  final String command;
  final DateTime timestamp;
  final String? cwd;
  final int? exitCode;

  CommandEntry({required this.command, required this.timestamp, this.cwd, this.exitCode});
}

class ChainSuggestion {
  final String command;
  final double confidence;
  final int frequency;
  final int totalUsage;
  final double successRate;

  ChainSuggestion({
    required this.command,
    required this.confidence,
    required this.frequency,
    required this.totalUsage,
    required this.successRate,
  });
}