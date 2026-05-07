import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Smart auto-complete with context awareness
/// 
/// Features:
/// - Context-aware suggestions
/// - Command history analysis
/// - Directory-based completion
/// - Fuzzy matching
/// - Performance optimized
class SmartAutoComplete {
  final List<CommandSuggestion> _suggestions = [];
  final Map<String, int> _commandFrequency = {};
  final List<String> _recentCommands = [];
  final String _currentDirectory;
  Timer? _debounceTimer;

  SmartAutoComplete() {
    _updateCurrentDirectory();
  }

  /// Update current working directory
  void _updateCurrentDirectory() {
    _currentDirectory = Directory.current.path;
  }

  /// Get suggestions for command
  Future<List<CommandSuggestion>> getSuggestions(String partialCommand) async {
    _suggestions.clear();
    
    // Cancel previous debounce timer
    _debounceTimer?.cancel();
    
    // Debounce suggestions
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _generateSuggestions(partialCommand);
    });
    
    return _suggestions;
  }

  /// Generate suggestions based on context
  void _generateSuggestions(String partialCommand) {
    final lowerPartial = partialCommand.toLowerCase();
    
    // File/directory completions
    if (lowerPartial.startsWith('./') || lowerPartial.startsWith('/') || lowerPartial.startsWith('~')) {
      _generatePathSuggestions(partialCommand);
      return;
    }
    
    // Command completions
    _generateCommandSuggestions(partialCommand);
    
    // Fuzzy matching from history
    _generateFuzzySuggestions(partialCommand);
  }

  /// Generate path suggestions
  void _generatePathSuggestions(String partialPath) async {
    try {
      final dir = partialPath.startsWith('~') 
          ? Directory(partialPath.replaceFirst('~', Platform.environment['HOME'] ?? ''))
          : Directory(partialPath);
      
      if (await dir.exists()) {
        final entities = await dir.list().timeout(const Duration(seconds: 1));
        
        for (final entity in entities) {
          final name = entity.path.split('/').last;
          final fullPath = '${partialPath.substring(0, partialPath.length - name.length)}$name';
          
          _suggestions.add(CommandSuggestion(
            type: SuggestionType.file,
            text: fullPath,
            description: 'File: $name',
            priority: _calculateFilePriority(entity),
          ));
        }
      }
    } catch (e) {
      // Silently fail on directory access
    }
  }

  /// Generate command suggestions
  void _generateCommandSuggestions(String partialCommand) {
    final commonCommands = [
      'ls', 'cd', 'mkdir', 'rm', 'cp', 'mv', 'cat', 'grep', 'find',
      'git', 'docker', 'edit', 'ssh', 'scp', 'ping', 'curl', 'wget', 'nano',
      'vim', 'emacs', 'python', 'node', 'npm', 'yarn', 'cargo', 'go', 'java',
      'make', 'cmake', 'gcc', 'g++', 'python3', 'pip3', 'apt', 'yum', 'systemctl',
    ];
    
    for (final command in commonCommands) {
      if (command.startsWith(partialCommand)) {
        _suggestions.add(CommandSuggestion(
          type: SuggestionType.command,
          text: command,
          description: 'Command: $command',
          priority: _calculateCommandPriority(command),
        ));
      }
    }
    
    // Add recent commands
    for (final recent in _recentCommands.take(5)) {
      if (recent.toLowerCase().startsWith(partialCommand)) {
        _suggestions.add(CommandSuggestion(
          type: SuggestionType.history,
          text: recent,
          description: 'Recent: $recent',
          priority: 0.8,
        ));
      }
    }
  }

  /// Generate fuzzy suggestions from history
  void _generateFuzzySuggestions(String partialCommand) {
    for (final recent in _recentCommands) {
      final similarity = _calculateSimilarity(partialCommand, recent);
      if (similarity > 0.6) {
        _suggestions.add(CommandSuggestion(
          type: SuggestionType.fuzzy,
          text: recent,
          description: 'Did you mean: $recent?',
          priority: similarity,
        ));
      }
    }
  }

  /// Calculate file priority based on type and modification time
  double _calculateFilePriority(FileSystemEntity entity) {
    final now = DateTime.now();
    final modified = entity.statSync().modified;
    final hoursOld = now.difference(modified).inHours;
    
    if (entity is Directory) {
      return hoursOld < 24 ? 1.0 : 0.7;
    } else {
      final extension = entity.path.split('.').last.toLowerCase();
      final priority = switch (extension) {
        'dart' || 'py' || 'js' || 'ts' => 1.0,
        'md' || 'txt' || 'json' || 'yaml' => 0.9,
        'jpg' || 'png' || 'gif' => 0.6,
        _ => 0.8,
      };
      
      // Adjust based on how old the file is
      return hoursOld < 1 ? priority + 0.2 : priority - (hoursOld / 24 * 0.3);
    }
  }

  /// Calculate command priority based on frequency
  double _calculateCommandPriority(String command) {
    final frequency = _commandFrequency[command] ?? 0;
    return 1.0 - (frequency / 10).clamp(0.0, 0.5);
  }

  /// Calculate string similarity
  double _calculateSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    
    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;
    
    // Levenshtein distance approximation
    int matches = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (longer.contains(shorter[i])) {
        matches++;
      }
    }
    
    return matches / shorter.length;
  }

  /// Add command to history
  void addToHistory(String command) {
    _recentCommands.remove(command);
    _recentCommands.insert(0, command);
    
    // Update frequency
    _commandFrequency[command] = (_commandFrequency[command] ?? 0) + 1;
    
    // Keep only recent 50 commands
    if (_recentCommands.length > 50) {
      _recentCommands.removeRange(50, _recentCommands.length);
    }
  }

  /// Clear command history
  void clearHistory() {
    _recentCommands.clear();
    _commandFrequency.clear();
  }
}

/// Command suggestion for auto-complete
class CommandSuggestion {
  final SuggestionType type;
  final String text;
  final String description;
  final double priority;

  const CommandSuggestion({
    required this.type,
    required this.text,
    required this.description,
    required this.priority,
  });
}

/// Suggestion types
enum SuggestionType {
  command,
  file,
  directory,
  history,
  fuzzy,
}
