import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

class FuzzyCommandMatcher {
  static const double _matchThreshold = 0.7; // Conservative threshold
  static const int _maxSuggestions = 5;
  static const int _minCommandLength = 2;
  
  final List<String> _commandHistory = [];
  final Map<String, CommandFrequency> _commandFrequencies = {};
  final List<String> _commonCommands = [];
  
  void initialize() {
    _initializeCommonCommands();
    developer.log('🔍 Fuzzy Command Matcher initialized');
  }

  void _initializeCommonCommands() {
    _commonCommands.addAll([
      'ls', 'cd', 'pwd', 'mkdir', 'rm', 'cp', 'mv', 'cat', 'less', 'more',
      'grep', 'find', 'locate', 'which', 'whereis', 'man', 'help',
      'git', 'npm', 'yarn', 'pip', 'cargo', 'flutter', 'dart',
      'docker', 'docker-compose', 'kubectl', 'helm',
      'ssh', 'scp', 'rsync', 'wget', 'curl',
      'ps', 'top', 'htop', 'kill', 'killall', 'jobs', 'bg', 'fg',
      'tar', 'zip', 'unzip', 'gzip', 'gunzip',
      'chmod', 'chown', 'chgrp', 'sudo', 'su',
      'echo', 'printf', 'read', 'export', 'env', 'set',
      'vim', 'nano', 'emacs', 'code', 'vi',
      'gcc', 'g++', 'make', 'cmake', 'python', 'python3', 'node',
      'systemctl', 'service', 'journalctl', 'dmesg',
    ]);
  }

  void addToHistory(String command) {
    // Clean and normalize command
    final normalizedCommand = _normalizeCommand(command);
    
    // Add to history
    _commandHistory.add(normalizedCommand);
    if (_commandHistory.length > 1000) {
      _commandHistory.removeAt(0);
    }
    
    // Update frequency
    final frequency = _commandFrequencies.putIfAbsent(
      normalizedCommand,
      () => CommandFrequency(command: normalizedCommand),
    );
    frequency.increment();
    
    // Sort by frequency periodically
    if (_commandHistory.length % 50 == 0) {
      _updateFrequencyRankings();
    }
  }

  String _normalizeCommand(String command) {
    // Remove extra whitespace and convert to lowercase
    command = command.trim().toLowerCase();
    
    // Remove common prefixes/suffixes
    command = command.replaceAll(RegExp(r'^\s*sudo\s+'), '');
    command = command.replaceAll(RegExp(r'\s*&\s*$'), '');
    command = command.replaceAll(RegExp(r'\s*;\s*$'), '');
    
    // Normalize multiple spaces
    command = command.replaceAll(RegExp(r'\s+'), ' ');
    
    return command;
  }

  void _updateFrequencyRankings() {
    final sortedFrequencies = _commandFrequencies.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    
    for (int i = 0; i < sortedFrequencies.length; i++) {
      sortedFrequencies[i].rank = i + 1;
    }
  }

  List<FuzzyMatch> findMatches(String input, {int? maxResults}) {
    if (input.length < _minCommandLength) {
      return [];
    }
    
    final normalizedInput = _normalizeCommand(input);
    final matches = <FuzzyMatch>[];
    
    // Search in command history
    matches.addAll(_searchInHistory(normalizedInput));
    
    // Search in common commands
    matches.addAll(_searchInCommonCommands(normalizedInput));
    
    // Remove duplicates and sort by score
    final uniqueMatches = <String, FuzzyMatch>{};
    for (final match in matches) {
      if (!uniqueMatches.containsKey(match.command) || 
          match.score > uniqueMatches[match.command]!.score) {
        uniqueMatches[match.command] = match;
      }
    }
    
    final sortedMatches = uniqueMatches.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    
    // Filter by threshold and limit results
    final filteredMatches = sortedMatches
        .where((match) => match.score >= _matchThreshold)
        .take(maxResults ?? _maxSuggestions)
        .toList();
    
    return filteredMatches;
  }

  List<FuzzyMatch> _searchInHistory(String input) {
    final matches = <FuzzyMatch>[];
    
    for (final command in _commandHistory) {
      final score = _calculateFuzzyScore(input, command);
      if (score >= _matchThreshold) {
        final frequency = _commandFrequencies[command];
        matches.add(FuzzyMatch(
          command: command,
          score: score,
          type: MatchType.history,
          frequency: frequency?.count ?? 0,
        ));
      }
    }
    
    return matches;
  }

  List<FuzzyMatch> _searchInCommonCommands(String input) {
    final matches = <FuzzyMatch>[];
    
    for (final command in _commonCommands) {
      final score = _calculateFuzzyScore(input, command);
      if (score >= _matchThreshold) {
        matches.add(FuzzyMatch(
          command: command,
          score: score,
          type: MatchType.common,
          frequency: 0,
        ));
      }
    }
    
    return matches;
  }

  double _calculateFuzzyScore(String input, String command) {
    // Exact match gets highest score
    if (input == command) {
      return 1.0;
    }
    
    // Prefix match gets high score
    if (command.startsWith(input)) {
      return 0.9;
    }
    
    // Contains match gets good score
    if (command.contains(input)) {
      return 0.8;
    }
    
    // Calculate Levenshtein distance for fuzzy matching
    final distance = _levenshteinDistance(input, command);
    final maxLength = max(input.length, command.length);
    final similarity = 1.0 - (distance / maxLength);
    
    // Boost score based on command frequency
    final frequency = _commandFrequencies[command];
    final frequencyBoost = frequency != null ? min(0.2, frequency.count / 100.0) : 0.0;
    
    // Boost score based on length similarity
    final lengthRatio = min(input.length, command.length) / max(input.length, command.length);
    final lengthBoost = lengthRatio * 0.1;
    
    final finalScore = similarity + frequencyBoost + lengthBoost;
    
    // Apply conservative threshold
    return finalScore.clamp(0.0, 1.0);
  }

  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    
    if (len1 == 0) return len2;
    if (len2 == 0) return len1;
    
    final matrix = List.generate(
      len1 + 1,
      (i) => List.generate(len2 + 1, (j) => 0),
    );
    
    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        
        matrix[i][j] = min(
          matrix[i - 1][j] + 1, // deletion
          min(
            matrix[i][j - 1] + 1, // insertion
            matrix[i - 1][j - 1] + cost, // substitution
          ),
        );
      }
    }
    
    return matrix[len1][len2];
  }

  List<String> getCommandCompletions(String partialCommand) {
    if (partialCommand.isEmpty) {
      return _commonCommands.take(10).toList();
    }
    
    final matches = findMatches(partialCommand);
    return matches.map((match) => match.command).toList();
  }

  bool isCommandValid(String command) {
    final normalizedCommand = _normalizeCommand(command);
    
    // Check if it's in common commands
    if (_commonCommands.contains(normalizedCommand)) {
      return true;
    }
    
    // Check if it's in history
    if (_commandHistory.contains(normalizedCommand)) {
      return true;
    }
    
    // Check if it's a valid path command
    if (RegExp(r'^[a-zA-Z0-9_/.-]+$').hasMatch(normalizedCommand)) {
      return true;
    }
    
    return false;
  }

  List<String> getSimilarCommands(String command, {int maxResults = 5}) {
    final matches = findMatches(command, maxResults: maxResults);
    return matches.map((match) => match.command).toList();
  }

  void clearHistory() {
    _commandHistory.clear();
    _commandFrequencies.clear();
    developer.log('🔍 Command history cleared');
  }

  FuzzyMatcherStats getStats() {
    return FuzzyMatcherStats(
      historySize: _commandHistory.length,
      uniqueCommands: _commandFrequencies.length,
      commonCommandsCount: _commonCommands.length,
      topCommands: _getTopCommands(),
    );
  }

  List<CommandFrequency> _getTopCommands() {
    return _commandFrequencies.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count))
      ..take(10);
  }

  void dispose() {
    _commandHistory.clear();
    _commandFrequencies.clear();
    _commonCommands.clear();
    developer.log('🔍 Fuzzy Command Matcher disposed');
  }
}

class FuzzyMatch {
  final String command;
  final double score;
  final MatchType type;
  final int frequency;

  FuzzyMatch({
    required this.command,
    required this.score,
    required this.type,
    required this.frequency,
  });

  @override
  String toString() {
    return 'FuzzyMatch(command: $command, score: ${score.toStringAsFixed(2)}, type: $type)';
  }
}

enum MatchType {
  exact,
  prefix,
  contains,
  fuzzy,
  history,
  common,
}

class CommandFrequency {
  final String command;
  int count = 0;
  int rank = 0;
  DateTime lastUsed = DateTime.now();

  CommandFrequency({required this.command});

  void increment() {
    count++;
    lastUsed = DateTime.now();
  }

  double getFrequencyScore() {
    // Higher count and more recent usage = higher score
    final ageInHours = DateTime.now().difference(lastUsed).inHours;
    final ageFactor = max(0.1, 1.0 - (ageInHours / 24.0)); // Decay over 24 hours
    return count * ageFactor;
  }
}

class FuzzyMatcherStats {
  final int historySize;
  final int uniqueCommands;
  final int commonCommandsCount;
  final List<CommandFrequency> topCommands;

  FuzzyMatcherStats({
    required this.historySize,
    required this.uniqueCommands,
    required this.commonCommandsCount,
    required this.topCommands,
  });
}
