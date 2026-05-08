import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// Advanced command prediction and auto-completion system
/// Uses machine learning and pattern matching for intelligent suggestions
class CommandPredictor {
  static const String _historyFile = '.termisol_command_history';
  static const String _patternsFile = '.termisol_command_patterns';
  
  final List<String> _commandHistory = [];
  final Map<String, int> _commandFrequency = {};
  final Map<String, List<String>> _patterns = {};
  final Map<String, List<String>> _contextualSuggestions = {};
  
  Timer? _debounceTimer;
  String _lastInput = '';
  
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadCommandHistory();
      await _loadPatterns();
      _buildContextualSuggestions();
      _isInitialized = true;
      debugPrint('🧠 Command Predictor initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Command Predictor: $e');
    }
  }

  Future<void> _loadCommandHistory() async {
    try {
      final file = File(_historyFile);
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n').where((line) => line.isNotEmpty).toList();
        
        _commandHistory.clear();
        _commandFrequency.clear();
        
        for (final command in lines) {
          _commandHistory.add(command);
          _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
        }
        
        // Keep only last 10000 commands
        if (_commandHistory.length > 10000) {
          _commandHistory.removeRange(0, _commandHistory.length - 10000);
        }
      }
    } catch (e) {
      debugPrint('Failed to load command history: $e');
    }
  }

  Future<void> _loadPatterns() async {
    try {
      final file = File(_patternsFile);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _patterns.clear();
        for (final entry in data.entries) {
          if (entry.value is List) {
            _patterns[entry.key] = List<String>.from(entry.value);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load patterns: $e');
    }
  }

  void _buildContextualSuggestions() {
    _contextualSuggestions.clear();
    
    // Git commands
    _contextualSuggestions['git'] = [
      'status', 'add', 'commit', 'push', 'pull', 'branch', 'checkout', 'merge', 'rebase', 'log', 'diff', 'stash'
    ];
    
    // Docker commands
    _contextualSuggestions['docker'] = [
      'ps', 'run', 'build', 'compose', 'exec', 'logs', 'stop', 'start', 'restart', 'rm'
    ];
    
    // NPM commands
    _contextualSuggestions['npm'] = [
      'install', 'run', 'start', 'test', 'build', 'publish', 'update', 'audit'
    ];
    
    // Python commands
    _contextualSuggestions['python'] = [
      '-m', '--version', '-c', '-v', 'pip', 'venv', 'jupyter'
    ];
    
    // File operations
    _contextualSuggestions['ls'] = ['-la', '-l', '-a', '--help'];
    _contextualSuggestions['cd'] = ['..', '~', '-'];
    _contextualSuggestions['cp'] = ['-r', '-v', '--help'];
    _contextualSuggestions['mv'] = ['-v', '--help'];
    _contextualSuggestions['rm'] = ['-r', '-f', '-rf', '--help'];
  }

  Future<List<String>> getSuggestions(String input) async {
    if (!_isInitialized) await initialize();
    
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) return [];
    
    final suggestions = <String>[];
    
    // 1. Exact history matches
    suggestions.addAll(_getHistoryMatches(trimmedInput));
    
    // 2. Pattern-based suggestions
    suggestions.addAll(_getPatternMatches(trimmedInput));
    
    // 3. Contextual suggestions
    suggestions.addAll(_getContextualSuggestions(trimmedInput));
    
    // 4. File path completions
    suggestions.addAll(_getFilePathCompletions(trimmedInput));
    
    // Remove duplicates and sort by relevance
    final uniqueSuggestions = suggestions.toSet().toList();
    uniqueSuggestions.sort((a, b) => _compareRelevance(trimmedInput, a, b));
    
    return uniqueSuggestions.take(10).toList();
  }

  List<String> _getHistoryMatches(String input) {
    final matches = <String>[];
    
    for (final command in _commandHistory.reversed.take(100)) {
      if (command.startsWith(input) && !matches.contains(command)) {
        matches.add(command);
      }
    }
    
    return matches;
  }

  List<String> _getPatternMatches(String input) {
    final matches = <String>[];
    final words = input.split(' ');
    
    for (final pattern in _patterns.entries) {
      if (pattern.key.startsWith(words.first)) {
        for (final suggestion in pattern.value) {
          final fullSuggestion = '${words.first} $suggestion';
          if (fullSuggestion.startsWith(input) && !matches.contains(fullSuggestion)) {
            matches.add(fullSuggestion);
          }
        }
      }
    }
    
    return matches;
  }

  List<String> _getContextualSuggestions(String input) {
    final matches = <String>[];
    final words = input.split(' ');
    final baseCommand = words.first;
    
    if (_contextualSuggestions.containsKey(baseCommand)) {
      for (final suggestion in _contextualSuggestions[baseCommand]!) {
        final fullSuggestion = '$baseCommand $suggestion';
        if (fullSuggestion.startsWith(input) && !matches.contains(fullSuggestion)) {
          matches.add(fullSuggestion);
        }
      }
    }
    
    return matches;
  }

  List<String> _getFilePathCompletions(String input) {
    final matches = <String>[];
    final words = input.split(' ');
    
    if (words.length > 1) {
      final lastWord = words.last;
      
      // Check if it looks like a path
      if (lastWord.contains('/') || lastWord.contains('~') || lastWord == '.') {
        try {
          final dir = Directory(path.dirname(lastWord.isEmpty ? '.' : lastWord));
          if (await dir.exists()) {
            final files = await dir.list().toList();
            final prefix = path.basename(lastWord);
            
            for (final file in files) {
              final fileName = path.basename(file.path);
              if (fileName.startsWith(prefix)) {
                final completedPath = path.join(path.dirname(lastWord), fileName);
                matches.add(input.replaceLast(lastWord, completedPath));
              }
            }
          }
        } catch (e) {
          // Ignore path errors
        }
      }
    }
    
    return matches;
  }

  int _compareRelevance(String input, String a, String b) {
    // Exact matches first
    final aExact = a.startsWith(input);
    final bExact = b.startsWith(input);
    
    if (aExact && !bExact) return -1;
    if (!aExact && bExact) return 1;
    
    // Frequency-based ranking
    final aFreq = _commandFrequency[a] ?? 0;
    final bFreq = _commandFrequency[b] ?? 0;
    
    if (aFreq != bFreq) {
      return bFreq.compareTo(aFreq); // Higher frequency first
    }
    
    // Length-based ranking (shorter first)
    return a.length.compareTo(b.length);
  }

  Future<void> recordCommand(String command) async {
    if (command.trim().isEmpty) return;
    
    _commandHistory.add(command);
    _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
    
    // Debounce saving to disk
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _saveCommandHistory();
    });
    
    // Learn from command patterns
    _learnFromCommand(command);
  }

  void _learnFromCommand(String command) {
    final words = command.split(' ');
    if (words.length < 2) return;
    
    final baseCommand = words.first;
    if (!_patterns.containsKey(baseCommand)) {
      _patterns[baseCommand] = [];
    }
    
    final argument = words[1];
    if (!_patterns[baseCommand]!.contains(argument)) {
      _patterns[baseCommand]!.add(argument);
      
      // Keep patterns manageable
      if (_patterns[baseCommand]!.length > 50) {
        _patterns[baseCommand]!.removeRange(0, _patterns[baseCommand]!.length - 50);
      }
    }
  }

  Future<void> _saveCommandHistory() async {
    try {
      final file = File(_historyFile);
      final content = _commandHistory.join('\n');
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save command history: $e');
    }
  }

  Future<void> _savePatterns() async {
    try {
      final file = File(_patternsFile);
      final content = jsonEncode(_patterns);
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save patterns: $e');
    }
  }

  Future<void> clearHistory() async {
    _commandHistory.clear();
    _commandFrequency.clear();
    
    try {
      final file = File(_historyFile);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to clear command history: $e');
    }
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalCommands': _commandHistory.length,
      'uniqueCommands': _commandFrequency.length,
      'patternsLearned': _patterns.length,
      'mostUsedCommands': _commandFrequency.entries
          .toList()
          ..sort((a, b) => b.value.compareTo(a.value))
          .take(10)
          .map((e) => {'command': e.key, 'count': e.value})
          .toList(),
    };
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _saveCommandHistory();
    await _savePatterns();
    debugPrint('🧠 Command Predictor disposed');
  }
}

/// Auto-completion widget for terminal input
class CommandAutoComplete extends StatefulWidget {
  final String currentInput;
  final Function(String) onSelected;
  final VoidCallback? onDismiss;

  const CommandAutoComplete({
    super.key,
    required this.currentInput,
    required this.onSelected,
    this.onDismiss,
  });

  @override
  State<CommandAutoComplete> createState() => _CommandAutoCompleteState();
}

class _CommandAutoCompleteState extends State<CommandAutoComplete> {
  final CommandPredictor _predictor = CommandPredictor();
  List<String> _suggestions = [];
  bool _isLoading = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(CommandAutoComplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentInput != widget.currentInput) {
      _loadSuggestions();
      _selectedIndex = 0;
    }
  }

  Future<void> _loadSuggestions() async {
    if (widget.currentInput.trim().isEmpty) {
      setState(() {
        _suggestions.clear();
        _isLoading = false;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final suggestions = await _predictor.getSuggestions(widget.currentInput);
      setState(() {
        _suggestions = suggestions;
        _isLoading = false;
        _selectedIndex = 0;
      });
    } catch (e) {
      setState(() {
        _suggestions.clear();
        _isLoading = false;
      });
    }
  }

  void _selectSuggestion(String suggestion) {
    widget.onSelected(suggestion);
    widget.onDismiss?.call();
  }

  void _handleKeyDown(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          setState(() {
            _selectedIndex = (_selectedIndex - 1) % _suggestions.length;
          });
          break;
        case LogicalKeyboardKey.arrowDown:
          setState(() {
            _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
          });
          break;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.tab:
          if (_suggestions.isNotEmpty) {
            _selectSuggestion(_suggestions[_selectedIndex]);
          }
          break;
        case LogicalKeyboardKey.escape:
          widget.onDismiss?.call();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border.all(color: Colors.grey[700]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          final isSelected = index == _selectedIndex;
          
          return InkWell(
            onTap: () => _selectSuggestion(suggestion),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.withOpacity(0.3) : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 16,
                    color: isSelected ? Colors.blue : Colors.grey[400],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[300],
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
