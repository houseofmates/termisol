import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';
import 'dart:io';
import 'dart:convert';

class SmartCommandHistory {
  static const int _maxHistorySize = 10000;
  static const int _maxSemanticResults = 50;
  static const int _searchCacheSize = 1000;
  static const String _historyFile = '/home/house/.termisol_history';
  
  final List<CommandEntry> _history = [];
  final Map<String, List<CommandEntry>> _semanticIndex = {};
  final Map<String, SearchCache> _searchCache = {};
  final Map<String, CommandPattern> _patterns = {};
  
  int _currentHistoryIndex = -1;
  String? _currentSearchQuery;
  List<CommandEntry> _currentSearchResults = [];
  int _currentSearchIndex = -1;
  
  Timer? _saveTimer;
  int _totalCommands = 0;
  int _totalSearches = 0;
  
  final StreamController<HistoryEvent> _historyController = 
      StreamController<HistoryEvent>.broadcast();

  void initialize() {
    _loadHistory();
    _buildSemanticIndex();
    _startAutoSave();
    developer.log('📚 Smart Command History initialized');
  }

  void _loadHistory() {
    try {
      final file = File(_historyFile);
      if (!file.existsSync()) {
        developer.log('📚 No history file found, starting fresh');
        return;
      }
      
      final content = file.readAsStringSync();
      final lines = content.split('\n');
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final data = jsonDecode(line);
          final entry = CommandEntry.fromJson(data);
          _history.add(entry);
          _totalCommands++;
        } catch (e) {
          developer.log('📚 Failed to parse history line: $e');
        }
      }
      
      _currentHistoryIndex = _history.length - 1;
      
      developer.log('📚 Loaded ${_history.length} commands from history');
      
    } catch (e) {
      developer.log('📚 Failed to load history: $e');
    }
  }

  void _buildSemanticIndex() {
    _semanticIndex.clear();
    _patterns.clear();
    
    for (int i = 0; i < _history.length; i++) {
      final entry = _history[i];
      _indexCommand(entry, i);
    }
    
    developer.log('📚 Built semantic index with ${_semanticIndex.length} terms');
  }

  void _indexCommand(CommandEntry entry, int index) {
    final words = _extractWords(entry.command);
    final normalizedCommand = entry.command.toLowerCase();
    
    // Index individual words
    for (final word in words) {
      _semanticIndex.putIfAbsent(
        word,
        () => <CommandEntry>[],
      ).add(entry);
    }
    
    // Index command patterns
    _indexPatterns(entry, index);
    
    // Index semantic features
    _indexSemanticFeatures(entry, index);
  }

  List<String> _extractWords(String command) {
    // Extract meaningful words from command
    final words = <String>[];
    final parts = command.split(RegExp(r'\s+'));
    
    for (final part in parts) {
      // Remove common prefixes and suffixes
      final cleanPart = part
          .replaceAll(RegExp(r'^[./]*'), '')
          .replaceAll(RegExp(r'[&;|><]*$'), '')
          .toLowerCase();
      
      if (cleanPart.length > 2) {
        words.add(cleanPart);
      }
    }
    
    return words.toSet().toList();
  }

  void _indexPatterns(CommandEntry entry, int index) {
    // Index command patterns like file paths, URLs, etc.
    final command = entry.command;
    
    // File paths
    final pathPattern = RegExp(r'[~/\.\w][~/\.\w]*\.\w+');
    final paths = pathPattern.allMatches(command);
    for (final match in paths) {
      _patterns.putIfAbsent(
        'path_${match.group(0)}',
        () => CommandPattern(type: PatternType.path, entries: []),
      ).entries.add(entry);
    }
    
    // URLs
    final urlPattern = RegExp(r'https?://[^\s]+');
    final urls = urlPattern.allMatches(command);
    for (final match in urls) {
      _patterns.putIfAbsent(
        'url_${match.group(0)}',
        () => CommandPattern(type: PatternType.url, entries: []),
      ).entries.add(entry);
    }
    
    // Git commands
    if (command.startsWith('git ')) {
      final gitCommand = command.substring(4);
      _patterns.putIfAbsent(
        'git_$gitCommand',
        () => CommandPattern(type: PatternType.git, entries: []),
      ).entries.add(entry);
    }
    
    // Docker commands
    if (command.startsWith('docker ')) {
      final dockerCommand = command.substring(7);
      _patterns.putIfAbsent(
        'docker_$dockerCommand',
        () => CommandPattern(type: PatternType.docker, entries: []),
      ).entries.add(entry);
    }
  }

  void _indexSemanticFeatures(CommandEntry entry, int index) {
    final command = entry.command;
    
    // Index by working directory
    final workingDir = entry.workingDirectory ?? 'default';
    _semanticIndex.putIfAbsent(
      'wd_$workingDir',
      () => <CommandEntry>[],
    ).add(entry);
    
    // Index by command type
    final commandType = _detectCommandType(command);
    _semanticIndex.putIfAbsent(
      'type_$commandType',
      () => <CommandEntry>[],
    ).add(entry);
    
    // Index by time of day
    final hour = entry.timestamp.hour;
    _semanticIndex.putIfAbsent(
      'hour_$hour',
      () => <CommandEntry>[],
    ).add(entry);
    
    // Index by day of week
    final day = entry.timestamp.weekday;
    _semanticIndex.putIfAbsent(
      'day_$day',
      () => <CommandEntry>[],
    ).add(entry);
  }

  String _detectCommandType(String command) {
    if (command.startsWith('git ')) return 'git';
    if (command.startsWith('docker ')) return 'docker';
    if (command.startsWith('npm ')) return 'npm';
    if (command.startsWith('yarn ')) return 'yarn';
    if (command.startsWith('python ')) return 'python';
    if (command.startsWith('node ')) return 'node';
    if (command.startsWith('java ')) return 'java';
    if (command.startsWith('javac ')) return 'javac';
    if (command.startsWith('gcc ')) return 'gcc';
    if (command.startsWith('make ')) return 'make';
    if (command.startsWith('cmake ')) return 'cmake';
    if (command.startsWith('cargo ')) return 'cargo';
    if (command.startsWith('flutter ')) return 'flutter';
    if (command.startsWith('dart ')) return 'dart';
    if (RegExp(r'^\s*cd\s+').hasMatch(command)) return 'cd';
    if (RegExp(r'^\s*ls\s').hasMatch(command)) return 'ls';
    if (RegExp(r'^\s*cat\s+').hasMatch(command)) return 'cat';
    if (RegExp(r'^\s*vim?\s+').hasMatch(command)) return 'editor';
    if (RegExp(r'^\s*nano\s+').hasMatch(command)) return 'editor';
    if (RegExp(r'^\s*ssh\s+').hasMatch(command)) return 'ssh';
    if (RegExp(r'^\s*scp\s+').hasMatch(command)) return 'scp';
    if (RegExp(r'^\s*rsync\s+').hasMatch(command)) return 'rsync';
    
    return 'other';
  }

  void _startAutoSave() {
    _saveTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _saveHistory(),
    );
  }

  void addCommand(String command, {
    String? workingDirectory,
    int? exitCode,
    Duration? executionTime,
    Map<String, dynamic>? metadata,
  }) {
    final entry = CommandEntry(
      id: _generateCommandId(),
      command: command,
      timestamp: DateTime.now(),
      workingDirectory: workingDirectory ?? Directory.current.path,
      exitCode: exitCode,
      executionTime: executionTime,
      metadata: metadata ?? {},
    );
    
    _history.add(entry);
    _totalCommands++;
    
    // Update semantic index
    _indexCommand(entry, _history.length - 1);
    
    // Update current index
    _currentHistoryIndex = _history.length - 1;
    
    developer.log('📚 Added command: $command');
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.commandAdded,
      entry: entry,
    ));
    
    // Trigger save
    _saveHistory();
  }

  List<CommandEntry> searchCommands(String query, {
    SearchType searchType = SearchType.semantic,
    int? limit,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    _totalSearches++;
    _currentSearchQuery = query;
    
    // Check cache first
    final cacheKey = _generateCacheKey(query, searchType, workingDirectory, startDate, endDate);
    final cached = _searchCache[cacheKey];
    
    if (cached != null && !cached.isExpired()) {
      _currentSearchResults = cached.results;
      _currentSearchIndex = -1;
      
      developer.log('📚 Search cache hit: $query (${cached.results.length} results)');
      
      return cached.results.take(limit ?? _maxSemanticResults).toList();
    }
    
    final results = _performSearch(query, searchType, workingDirectory, startDate, endDate);
    
    // Cache results
    _searchCache[cacheKey] = SearchCache(
      query: query,
      searchType: searchType,
      workingDirectory: workingDirectory,
      startDate: startDate,
      endDate: endDate,
      results: results,
      createdAt: DateTime.now(),
    );
    
    // Keep cache size limited
    if (_searchCache.length > _searchCacheSize) {
      final oldestKey = _searchCache.keys.first;
      _searchCache.remove(oldestKey);
    }
    
    _currentSearchResults = results;
    _currentSearchIndex = -1;
    
    developer.log('📚 Searched: $query (${results.length} results)');
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.searched,
      query: query,
      searchType: searchType,
      results: results,
    ));
    
    return results.take(limit ?? _maxSemanticResults).toList();
  }

  List<CommandEntry> _performSearch(
    String query,
    SearchType searchType,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final normalizedQuery = query.toLowerCase();
    final results = <CommandEntry>[];
    
    switch (searchType) {
      case SearchType.exact:
        return _exactSearch(normalizedQuery, workingDirectory, startDate, endDate);
      
      case SearchType.fuzzy:
        return _fuzzySearch(normalizedQuery, workingDirectory, startDate, endDate);
      
      case SearchType.semantic:
        return _semanticSearch(normalizedQuery, workingDirectory, startDate, endDate);
      
      case SearchType.pattern:
        return _patternSearch(normalizedQuery, workingDirectory, startDate, endDate);
      
      case SearchType.combined:
        return _combinedSearch(normalizedQuery, workingDirectory, startDate, endDate);
    }
  }

  List<CommandEntry> _exactSearch(
    String query,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    return _history.where((entry) {
      if (workingDirectory != null && entry.workingDirectory != workingDirectory) {
        return false;
      }
      
      if (startDate != null && entry.timestamp.isBefore(startDate!)) {
        return false;
      }
      
      if (endDate != null && entry.timestamp.isAfter(endDate!)) {
        return false;
      }
      
      return entry.command.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<CommandEntry> _fuzzySearch(
    String query,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final scoredResults = <ScoredResult>[];
    
    for (final entry in _history) {
      if (workingDirectory != null && entry.workingDirectory != workingDirectory) {
        continue;
      }
      
      if (startDate != null && entry.timestamp.isBefore(startDate!)) {
        continue;
      }
      
      if (endDate != null && entry.timestamp.isAfter(endDate!)) {
        continue;
      }
      
      final score = _calculateFuzzyScore(query, entry.command.toLowerCase());
      if (score > 0.3) {
        scoredResults.add(ScoredResult(entry: entry, score: score));
      }
    }
    
    scoredResults.sort((a, b) => b.score.compareTo(a.score));
    
    return scoredResults.map((result) => result.entry).toList();
  }

  double _calculateFuzzyScore(String query, String command) {
    // Simple fuzzy matching using Levenshtein distance
    final distance = _levenshteinDistance(query, command);
    final maxLength = max(query.length, command.length);
    
    if (maxLength == 0) return 0.0;
    
    final similarity = 1.0 - (distance / maxLength);
    
    // Boost score for exact matches
    if (command.contains(query)) {
      return similarity + 0.3;
    }
    
    return similarity;
  }

  int _levenshteinDistance(String s1, String s2) {
    final matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );
    
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = min(
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    
    return matrix[s1.length][s2.length];
  }

  List<CommandEntry> _semanticSearch(
    String query,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final queryWords = _extractWords(query);
    final scoredResults = <ScoredResult>[];
    
    for (final entry in _history) {
      if (workingDirectory != null && entry.workingDirectory != workingDirectory) {
        continue;
      }
      
      if (startDate != null && entry.timestamp.isBefore(startDate!)) {
        continue;
      }
      
      if (endDate != null && entry.timestamp.isAfter(endDate!)) {
        continue;
      }
      
      final score = _calculateSemanticScore(queryWords, entry);
      if (score > 0.2) {
        scoredResults.add(ScoredResult(entry: entry, score: score));
      }
    }
    
    scoredResults.sort((a, b) => b.score.compareTo(a.score));
    
    return scoredResults.map((result) => result.entry).toList();
  }

  double _calculateSemanticScore(List<String> queryWords, CommandEntry entry) {
    final entryWords = _extractWords(entry.command);
    final commandWords = _extractWords(entry.command);
    
    double score = 0.0;
    
    // Word matching score
    int matchingWords = 0;
    for (final queryWord in queryWords) {
      for (final entryWord in entryWords) {
        if (entryWord.contains(queryWord) || queryWord.contains(entryWord)) {
          matchingWords++;
          score += 0.4;
        }
      }
    }
    
    // Semantic feature matching
    for (final queryWord in queryWords) {
      final semanticEntries = _semanticIndex[queryWord];
      if (semanticEntries != null && semanticEntries.contains(entry)) {
        score += 0.6;
      }
    }
    
    // Pattern matching
    for (final pattern in _patterns.values) {
      if (pattern.entries.contains(entry)) {
        score += 0.3;
      }
    }
    
    // Recency boost
    final hoursSince = DateTime.now().difference(entry.timestamp).inHours;
    if (hoursSince < 24) {
      score += 0.2;
    } else if (hoursSince < 168) { // 1 week
      score += 0.1;
    }
    
    // Frequency boost
    final commandType = _detectCommandType(entry.command);
    final typeEntries = _semanticIndex['type_$commandType'];
    if (typeEntries != null) {
      final frequency = typeEntries!.length;
      if (frequency > 10) {
        score += 0.1;
      }
    }
    
    return score;
  }

  List<CommandEntry> _patternSearch(
    String query,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final regex = RegExp(query, caseSensitive: false);
    
    return _history.where((entry) {
      if (workingDirectory != null && entry.workingDirectory != workingDirectory) {
        return false;
      }
      
      if (startDate != null && entry.timestamp.isBefore(startDate!)) {
        return false;
      }
      
      if (endDate != null && entry.timestamp.isAfter(endDate!)) {
        return false;
      }
      
      return regex.hasMatch(entry.command);
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<CommandEntry> _combinedSearch(
    String query,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final exactResults = _exactSearch(query, workingDirectory, startDate, endDate);
    final fuzzyResults = _fuzzySearch(query, workingDirectory, startDate, endDate);
    final semanticResults = _semanticSearch(query, workingDirectory, startDate, endDate);
    
    // Combine and deduplicate
    final allResults = <CommandEntry>{};
    
    for (final result in exactResults) {
      allResults[result.id] = result;
    }
    
    for (final result in fuzzyResults) {
      allResults[result.id] = result;
    }
    
    for (final result in semanticResults) {
      allResults[result.id] = result;
    }
    
    return allResults.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  CommandEntry? navigateHistory(NavigationDirection direction) {
    if (_history.isEmpty) return null;
    
    switch (direction) {
      case NavigationDirection.up:
        if (_currentHistoryIndex > 0) {
          _currentHistoryIndex--;
        }
        break;
      
      case NavigationDirection.down:
        if (_currentHistoryIndex < _history.length - 1) {
          _currentHistoryIndex++;
        }
        break;
      
      case NavigationDirection.first:
        _currentHistoryIndex = 0;
        break;
      
      case NavigationDirection.last:
        _currentHistoryIndex = _history.length - 1;
        break;
    }
    
    final entry = _history[_currentHistoryIndex];
    
    developer.log('📚 Navigated history: ${direction.name} -> ${entry.command}');
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.navigated,
      direction: direction,
      entry: entry,
      index: _currentHistoryIndex,
    ));
    
    return entry;
  }

  CommandEntry? navigateSearchResults(NavigationDirection direction) {
    if (_currentSearchResults.isEmpty) return null;
    
    switch (direction) {
      case NavigationDirection.up:
        if (_currentSearchIndex > 0) {
          _currentSearchIndex--;
        }
        break;
      
      case NavigationDirection.down:
        if (_currentSearchIndex < _currentSearchResults.length - 1) {
          _currentSearchIndex++;
        }
        break;
      
      case NavigationDirection.first:
        _currentSearchIndex = 0;
        break;
      
      case NavigationDirection.last:
        _currentSearchIndex = _currentSearchResults.length - 1;
        break;
    }
    
    final entry = _currentSearchResults[_currentSearchIndex];
    
    developer.log('📚 Navigated search: ${direction.name} -> ${entry.command}');
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.searchNavigated,
      direction: direction,
      entry: entry,
      index: _currentSearchIndex,
      query: _currentSearchQuery,
    ));
    
    return entry;
  }

  void clearHistory() {
    _history.clear();
    _semanticIndex.clear();
    _patterns.clear();
    _searchCache.clear();
    _currentHistoryIndex = -1;
    _currentSearchQuery = null;
    _currentSearchResults = [];
    _currentSearchIndex = -1;
    
    developer.log('📚 Cleared command history');
    
    _emitEvent(HistoryEvent(
      type: HistoryEventType.cleared,
    ));
    
    _saveHistory();
  }

  void _saveHistory() {
    try {
      final file = File(_historyFile);
      final content = _history
          .map((entry) => jsonEncode(entry.toJson()))
          .join('\n');
      
      file.writeAsStringSync(content);
      
      developer.log('📚 Saved ${_history.length} commands to history');
      
    } catch (e) {
      developer.log('📚 Failed to save history: $e');
    }
  }

  String _generateCacheKey(
    String query,
    SearchType searchType,
    String? workingDirectory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    return '${query}_${searchType.name}_${workingDirectory ?? 'all'}_${startDate?.toIso8601String() ?? 'all'}_${endDate?.toIso8601String() ?? 'all'}';
  }

  String _generateCommandId() {
    return 'cmd_${DateTime.now().millisecondsSinceEpoch}_$_totalCommands';
  }

  void _emitEvent(HistoryEvent event) {
    _historyController.add(event);
  }

  Stream<HistoryEvent> get historyEventStream => _historyController.stream;

  CommandHistoryStats getStats() {
    return CommandHistoryStats(
      totalCommands: _totalCommands,
      historySize: _history.length,
      semanticIndexSize: _semanticIndex.length,
      searchCacheSize: _searchCache.length,
      totalSearches: _totalSearches,
      currentHistoryIndex: _currentHistoryIndex,
      currentSearchIndex: _currentSearchIndex,
      currentSearchResults: _currentSearchResults.length,
    );
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveHistory();
    
    _history.clear();
    _semanticIndex.clear();
    _patterns.clear();
    _searchCache.clear();
    _historyController.close();
    
    developer.log('📚 Smart Command History disposed');
  }
}

class CommandEntry {
  final String id;
  final String command;
  final DateTime timestamp;
  final String? workingDirectory;
  final int? exitCode;
  final Duration? executionTime;
  final Map<String, dynamic> metadata;

  CommandEntry({
    required this.id,
    required this.command,
    required this.timestamp,
    this.workingDirectory,
    this.exitCode,
    this.executionTime,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'command': command,
      'timestamp': timestamp.toIso8601String(),
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'execution_time': executionTime?.inMilliseconds,
      'metadata': metadata,
    };
  }

  factory CommandEntry.fromJson(Map<String, dynamic> json) {
    return CommandEntry(
      id: json['id'],
      command: json['command'],
      timestamp: DateTime.parse(json['timestamp']),
      workingDirectory: json['working_directory'],
      exitCode: json['exit_code'],
      executionTime: json['execution_time'] != null 
          ? Duration(milliseconds: json['execution_time'])
          : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }
}

class SearchCache {
  final String query;
  final SearchType searchType;
  final String? workingDirectory;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<CommandEntry> results;
  final DateTime createdAt;

  SearchCache({
    required this.query,
    required this.searchType,
    this.workingDirectory,
    this.startDate,
    this.endDate,
    required this.results,
    required this.createdAt,
  });

  bool isExpired() {
    return DateTime.now().difference(createdAt).inMinutes > 30;
  }
}

class CommandPattern {
  final PatternType type;
  final List<CommandEntry> entries;

  CommandPattern({
    required this.type,
    required this.entries,
  });
}

class ScoredResult {
  final CommandEntry entry;
  final double score;

  ScoredResult({
    required this.entry,
    required this.score,
  });
}

enum SearchType {
  exact,
  fuzzy,
  semantic,
  pattern,
  combined,
}

enum PatternType {
  path,
  url,
  git,
  docker,
}

enum NavigationDirection {
  up,
  down,
  first,
  last,
}

enum HistoryEventType {
  commandAdded,
  searched,
  navigated,
  searchNavigated,
  cleared,
}

class HistoryEvent {
  final HistoryEventType type;
  final CommandEntry? entry;
  final String? query;
  final SearchType? searchType;
  final List<CommandEntry>? results;
  final NavigationDirection? direction;
  final int? index;

  HistoryEvent({
    required this.type,
    this.entry,
    this.query,
    this.searchType,
    this.results,
    this.direction,
    this.index,
  });
}

class CommandHistoryStats {
  final int totalCommands;
  final int historySize;
  final int semanticIndexSize;
  final int searchCacheSize;
  final int totalSearches;
  final int currentHistoryIndex;
  final int currentSearchIndex;
  final int currentSearchResults;

  CommandHistoryStats({
    required this.totalCommands,
    required this.historySize,
    required this.semanticIndexSize,
    required this.searchCacheSize,
    required this.totalSearches,
    required this.currentHistoryIndex,
    required this.currentSearchIndex,
    required this.currentSearchResults,
  });
}
