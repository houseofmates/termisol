import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Command suggestion with enhanced metadata
class CommandSuggestion {
  final String command;
  final String description;
  final int priority;
  final double score;
  final String category;
  final DateTime? lastUsed;

  CommandSuggestion({
    required this.command,
    required this.description,
    this.priority = 0,
    this.score = 0.0,
    this.category = 'general',
    this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
    'command': command,
    'description': description,
    'priority': priority,
    'score': score,
    'category': category,
    'lastUsed': lastUsed?.toIso8601String(),
  };

  factory CommandSuggestion.fromJson(Map<String, dynamic> json) => CommandSuggestion(
    command: json['command'] as String,
    description: json['description'] as String? ?? '',
    priority: json['priority'] as int? ?? 0,
    score: (json['score'] as num?)?.toDouble() ?? 0.0,
    category: json['category'] as String? ?? 'general',
    lastUsed: json['lastUsed'] != null 
        ? DateTime.parse(json['lastUsed'] as String) 
        : null,
  );
}

/// Professional smart auto-complete system with persistence and intelligence
class SmartAutoComplete {
  static const String _historyKey = 'command_history';
  static const String _frequencyKey = 'command_frequency';
  static const int _maxHistorySize = 1000;
  static const String _customCommandsKey = 'custom_commands';

  final List<String> _recentCommands = [];
  final Map<String, int> _commandFrequency = {};
  final Map<String, CommandSuggestion> _customCommands = {};
  final List<String> _commonCommands = [
    'ls', 'cd', 'pwd', 'mkdir', 'rm', 'cp', 'mv', 'cat', 'less', 'more',
    'grep', 'find', 'ps', 'kill', 'top', 'df', 'du', 'tar', 'zip', 'unzip',
    'git', 'docker', 'npm', 'pip', 'cargo', 'go', 'python', 'node', 'java',
    'gcc', 'make', 'cmake', 'ssh', 'scp', 'rsync', 'wget', 'curl', 'vim',
    'nano', 'emacs', 'echo', 'printf', 'export', 'source', 'alias', 'history',
    'which', 'whereis', 'man', 'help', 'exit', 'clear', 'reset', 'sudo',
  ];

  SharedPreferences? _prefs;
  Timer? _saveTimer;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadHistory();
      await _loadFrequency();
      await _loadCustomCommands();
      _initializeCommonCommands();
      _isInitialized = true;
      
      // Schedule periodic saves
      _saveTimer = Timer.periodic(const Duration(minutes: 5), (_) => _saveData());
    } catch (e) {
      // Fallback to in-memory storage if persistence fails
      debugPrint('Warning: Failed to initialize auto-complete persistence: $e');
      _isInitialized = true;
    }
  }

  Future<List<CommandSuggestion>> getSuggestions(String partialCommand) async {
    if (!_isInitialized) await initialize();
    
    if (partialCommand.isEmpty) {
      return _getRecentSuggestions().take(10).toList();
    }

    final suggestions = <CommandSuggestion>[];
    final partialLower = partialCommand.toLowerCase();

    // Exact matches first
    suggestions.addAll(_getExactMatches(partialLower));
    
    // Prefix matches
    suggestions.addAll(_getPrefixMatches(partialLower));
    
    // Fuzzy matches
    suggestions.addAll(_getFuzzyMatches(partialLower));

    // Remove duplicates and sort by score
    final uniqueSuggestions = <String, CommandSuggestion>{};
    for (final suggestion in suggestions) {
      final existing = uniqueSuggestions[suggestion.command];
      if (existing == null || suggestion.score > existing.score) {
        uniqueSuggestions[suggestion.command] = suggestion;
      }
    }

    return uniqueSuggestions.values
        .toList()
        ..sort((a, b) => b.score.compareTo(a.score))
        ..take(20);
  }

  void addToHistory(String command) {
    if (!_isInitialized) return;
    
    final trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty) return;

    // Remove from recent if it exists and add to front
    _recentCommands.remove(trimmedCommand);
    _recentCommands.insert(0, trimmedCommand);

    // Limit history size
    if (_recentCommands.length > _maxHistorySize) {
      _recentCommands.removeRange(_maxHistorySize, _recentCommands.length);
    }

    // Update frequency
    _commandFrequency[trimmedCommand] = (_commandFrequency[trimmedCommand] ?? 0) + 1;

    // Debounced save
    _scheduleSave();
  }

  List<String> get recentCommands => List.unmodifiable(_recentCommands);
  Map<String, int> get commandFrequency => Map.unmodifiable(_commandFrequency);

  void clearHistory() {
    _recentCommands.clear();
    _commandFrequency.clear();
    _customCommands.clear();
    _scheduleSave();
  }

  Future<void> addCustomCommand(CommandSuggestion suggestion) async {
    _customCommands[suggestion.command] = suggestion;
    await _saveCustomCommands();
  }

  Future<void> removeCustomCommand(String command) async {
    _customCommands.remove(command);
    await _saveCustomCommands();
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveData();
  }

  // Private methods

  void _initializeCommonCommands() {
    for (final command in _commonCommands) {
      _commandFrequency[command] = _commandFrequency[command] ?? 0;
    }
  }

  List<CommandSuggestion> _getRecentSuggestions() {
    return _recentCommands.take(20).map((cmd) => CommandSuggestion(
      command: cmd,
      description: 'Recently used command',
      priority: 1,
      score: 10.0,
      category: 'history',
      lastUsed: DateTime.now(),
    )).toList();
  }

  List<CommandSuggestion> _getExactMatches(String partialLower) {
    final matches = <CommandSuggestion>[];
    
    // Check custom commands first
    for (final entry in _customCommands.entries) {
      if (entry.key.toLowerCase() == partialLower) {
        matches.add(entry.value);
      }
    }
    
    // Check history
    for (final command in _recentCommands) {
      if (command.toLowerCase() == partialLower) {
        final frequency = _commandFrequency[command] ?? 0;
        matches.add(CommandSuggestion(
          command: command,
          description: 'Command from history',
          priority: 2,
          score: 50.0 + frequency.toDouble(),
          category: 'history',
        ));
      }
    }
    
    return matches;
  }

  List<CommandSuggestion> _getPrefixMatches(String partialLower) {
    final matches = <CommandSuggestion>[];
    final seen = <String>{};
    
    // Custom commands
    for (final entry in _customCommands.entries) {
      if (entry.key.toLowerCase().startsWith(partialLower) && !seen.contains(entry.key)) {
        matches.add(entry.value);
        seen.add(entry.key);
      }
    }
    
    // History commands
    for (final command in _recentCommands) {
      if (command.toLowerCase().startsWith(partialLower) && !seen.contains(command)) {
        final frequency = _commandFrequency[command] ?? 0;
        matches.add(CommandSuggestion(
          command: command,
          description: 'Command from history',
          priority: 1,
          score: 30.0 + frequency.toDouble(),
          category: 'history',
        ));
        seen.add(command);
      }
    }
    
    // Common commands
    for (final command in _commonCommands) {
      if (command.startsWith(partialLower) && !seen.contains(command)) {
        matches.add(CommandSuggestion(
          command: command,
          description: 'Common shell command',
          score: 20.0,
          category: 'system',
        ));
        seen.add(command);
      }
    }
    
    return matches;
  }

  List<CommandSuggestion> _getFuzzyMatches(String partialLower) {
    final matches = <CommandSuggestion>[];
    final seen = <String>{};
    
    // Simple fuzzy matching - check if all characters of partial appear in order
    for (final command in _recentCommands) {
      if (_isFuzzyMatch(command.toLowerCase(), partialLower) && !seen.contains(command)) {
        final frequency = _commandFrequency[command] ?? 0;
        matches.add(CommandSuggestion(
          command: command,
          description: 'Fuzzy match from history',
          score: 10.0 + frequency.toDouble() * 0.5,
          category: 'fuzzy',
        ));
        seen.add(command);
      }
    }
    
    return matches.take(10).toList();
  }

  bool _isFuzzyMatch(String text, String pattern) {
    if (pattern.isEmpty) return true;
    if (text.isEmpty) return false;
    
    int patternIndex = 0;
    for (int i = 0; i < text.length && patternIndex < pattern.length; i++) {
      if (text[i] == pattern[patternIndex]) {
        patternIndex++;
      }
    }
    
    return patternIndex == pattern.length;
  }

  Future<void> _loadHistory() async {
    try {
      final historyJson = _prefs?.getStringList(_historyKey) ?? [];
      _recentCommands.clear();
      _recentCommands.addAll(historyJson);
    } catch (e) {
      debugPrint('Warning: Failed to load command history: $e');
    }
  }

  Future<void> _loadFrequency() async {
    try {
      final frequencyJson = _prefs?.getString(_frequencyKey) ?? '{}';
      final frequencyMap = jsonDecode(frequencyJson) as Map<String, dynamic>;
      _commandFrequency.clear();
      frequencyMap.forEach((key, value) {
        _commandFrequency[key] = (value as num).toInt();
      });
    } catch (e) {
      debugPrint('Warning: Failed to load command frequency: $e');
    }
  }

  Future<void> _loadCustomCommands() async {
    try {
      final customJson = _prefs?.getString(_customCommandsKey) ?? '{}';
      final customMap = jsonDecode(customJson) as Map<String, dynamic>;
      _customCommands.clear();
      customMap.forEach((key, value) {
        _customCommands[key] = CommandSuggestion.fromJson(value as Map<String, dynamic>);
      });
    } catch (e) {
      debugPrint('Warning: Failed to load custom commands: $e');
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveData);
  }

  Future<void> _saveData() async {
    if (_prefs == null) return;
    
    try {
      await _prefs?.setStringList(_historyKey, _recentCommands.take(_maxHistorySize).toList());
      await _prefs?.setString(_frequencyKey, jsonEncode(_commandFrequency));
    } catch (e) {
      debugPrint('Warning: Failed to save auto-complete data: $e');
    }
  }

  Future<void> _saveCustomCommands() async {
    if (_prefs == null) return;
    
    try {
      final customMap = <String, dynamic>{};
      _customCommands.forEach((key, value) {
        customMap[key] = value.toJson();
      });
      await _prefs?.setString(_customCommandsKey, jsonEncode(customMap));
    } catch (e) {
      debugPrint('Warning: Failed to save custom commands: $e');
    }
  }
}