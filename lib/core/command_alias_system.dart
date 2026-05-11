import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// stores and expands command aliases.
///
/// aliases are persisted via sharedpreferences and expand the first word
/// of user input into a longer command string.
class CommandAliasSystem {
  static const String _prefsKey = 'termisol_command_aliases';

  static final CommandAliasSystem _instance = CommandAliasSystem._internal();

  /// Singleton instance.
  static CommandAliasSystem get instance => _instance;

  final Map<String, String> _aliases = {};
  bool _loaded = false;

  CommandAliasSystem._internal() {
    _setupDefaults();
  }

  void _setupDefaults() {
    _aliases.addAll({
      'g': 'git',
      'gs': 'git status',
      'ga': 'git add',
      'gc': 'git commit',
      'gp': 'git push',
      'll': 'ls -la',
      '..': 'cd ..',
    });
  }

  /// All aliases as a sorted list of map entries.
  List<MapEntry<String, String>> get aliases {
    final entries = _aliases.entries.toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  /// Load aliases from persistent storage. Defaults are kept for any keys
  /// not present in storage, and user-defined keys override defaults.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _aliases[entry.key] = entry.value as String;
        }
      }
      _loaded = true;
    } catch (e, stack) {
      debugPrint('failed to load command aliases: $e\n$stack');
    }
  }

  /// Persist aliases to SharedPreferences.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_aliases));
    } catch (e, stack) {
      debugPrint('failed to save command aliases: $e\n$stack');
    }
  }

  /// Add or update an alias.
  void addAlias(String alias, String expansion) {
    if (alias.trim().isEmpty || expansion.trim().isEmpty) return;
    _aliases[alias.trim()] = expansion.trim();
  }

  /// Remove an alias.
  void removeAlias(String alias) {
    _aliases.remove(alias);
  }

  /// If [input] starts with an alias key (first word), returns the expanded
  /// command. Otherwise returns [input] unchanged.
  String expand(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;

    // Find the first word boundary
    final spaceIndex = trimmed.indexOf(' ');
    final firstWord = spaceIndex == -1
        ? trimmed
        : trimmed.substring(0, spaceIndex);
    final rest = spaceIndex == -1 ? '' : trimmed.substring(spaceIndex);

    final expansion = _aliases[firstWord];
    if (expansion == null) return input;

    return '$expansion$rest';
  }
}
