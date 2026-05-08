import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and searches terminal command history.
///
/// Commands are persisted via SharedPreferences and deduplicated.
/// Provides fuzzy substring search for quick recall.
class CommandHistory {
  static const String _prefsKey = 'termisol_command_history';
  static const int _maxHistory = 500;

  final List<String> _commands = [];
  bool _loaded = false;

  /// All stored commands in reverse chronological order (newest first).
  List<String> get commands => List.unmodifiable(_commands);

  /// Number of commands in history.
  int get length => _commands.length;

  /// Load history from persistent storage.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>;
        _commands.addAll(list.cast<String>());
      }
      _loaded = true;
    } catch (e, stack) {
      debugPrint('failed to load command history: $e\n$stack');
    }
  }

  /// Add a command to history if it's non-empty and not a duplicate of the most recent.
  Future<void> add(String command) async {
    await load();
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    if (_commands.isNotEmpty && _commands.first == trimmed) return;

    _commands.insert(0, trimmed);
    if (_commands.length > _maxHistory) {
      _commands.removeLast();
    }
    await _persist();
  }

  /// Search history with fuzzy substring matching.
  /// Returns matches sorted by relevance (exact prefix matches first, then substring).
  List<String> search(String query) {
    if (query.isEmpty) return _commands.take(20).toList();

    final lowerQuery = query.toLowerCase();
    final exact = <String>[];
    final substring = <String>[];

    for (final cmd in _commands) {
      final lowerCmd = cmd.toLowerCase();
      if (lowerCmd.startsWith(lowerQuery)) {
        exact.add(cmd);
      } else if (lowerCmd.contains(lowerQuery)) {
        substring.add(cmd);
      }
    }

    return [...exact, ...substring].take(20).toList();
  }

  /// Clear all history.
  Future<void> clear() async {
    _commands.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_commands));
    } catch (e, stack) {
      debugPrint('failed to persist command history: $e\n$stack');
    }
  }
}
