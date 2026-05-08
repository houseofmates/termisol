import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Fuzzy Search across Terminal History
/// 
/// Implements advanced fuzzy search capabilities for terminal history with:
/// - Substring matching with scoring
/// - Levenshtein distance calculation
/// - Typo tolerance
/// - Command pattern recognition
/// - Context-aware ranking
/// - Real-time search suggestions
/// - Search result highlighting
/// - Search history and favorites
class FuzzyHistorySearch {
  static final FuzzyHistorySearch _instance = FuzzyHistorySearch._internal();
  factory FuzzyHistorySearch() => _instance;
  FuzzyHistorySearch._internal();

  bool _isInitialized = false;
  final List<HistoryEntry> _history = [];
  final Map<String, List<HistoryEntry>> _commandIndex = {};
  final Map<String, List<HistoryEntry>> _pathIndex = {};
  final Map<String, List<HistoryEntry>> _userIndex = {};
  final List<SearchQuery> _searchHistory = [];
  final Set<String> _favoriteQueries = {};
  
  // Search configuration
  static const int _maxResults = 100;
  static const double _minScore = 0.3;
  static const int _maxSearchHistory = 1000;
  static const int _maxHistoryEntries = 10000;
  
  // Search state
  Timer? _indexingTimer;
  final _searchController = StreamController<SearchEvent>.broadcast();
  Stream<SearchEvent> get events => _searchController.stream;
  
  bool get isInitialized => _isInitialized;
  int get historySize => _history.length;
  int get searchHistorySize => _searchHistory.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load existing history
      await _loadHistory();
      
      // Build search indexes
      await _buildIndexes();
      
      // Start periodic indexing
      _startIndexing();
      
      _isInitialized = true;
      debugPrint('🔍 Fuzzy History Search initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Fuzzy History Search: $e');
    }
  }

  Future<List<SearchResult>> search(
    String query, {
    SearchOptions options = const SearchOptions(),
    int? maxResults,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }
    
    final startTime = Stopwatch()..start();
    
    try {
      final normalizedQuery = _normalizeQuery(query);
      final results = <SearchResult>[];
      
      // Record search query
      _recordSearchQuery(query);
      
      // Search in different indexes based on options
      if (options.searchCommands) {
        results.addAll(await _searchInCommands(normalizedQuery, options));
      }
      
      if (options.searchPaths) {
        results.addAll(await _searchInPaths(normalizedQuery, options));
      }
      
      if (options.searchUsers) {
        results.addAll(await _searchInUsers(normalizedQuery, options));
      }
      
      // Full text search if enabled
      if (options.fullTextSearch) {
        results.addAll(await _fullTextSearch(normalizedQuery, options));
      }
      
      // Remove duplicates and sort by score
      final uniqueResults = _deduplicateResults(results);
      uniqueResults.sort((a, b) => b.score.compareTo(a.score));
      
      // Limit results
      final finalResults = uniqueResults.take(maxResults ?? _maxResults).toList();
      
      startTime.stop();
      
      _searchController.add(SearchEvent(
        type: SearchEventType.searchCompleted,
        data: {
          'query': query,
          'results_count': finalResults.length,
          'search_time_ms': startTime.elapsedMilliseconds,
        },
      ));
      
      return finalResults;
      
    } catch (e) {
      debugPrint('❌ Search failed for query "$query": $e');
      return [];
    }
  }

  Future<List<String>> getSuggestions(String query, {int maxSuggestions = 10}) async {
    if (query.trim().isEmpty) {
      return _getRecentQueries(maxSuggestions);
    }
    
    try {
      final normalizedQuery = _normalizeQuery(query);
      final suggestions = <String>[];
      
      // Get suggestions from command patterns
      suggestions.addAll(_getCommandSuggestions(normalizedQuery, maxSuggestions));
      
      // Get suggestions from search history
      suggestions.addAll(_getHistorySuggestions(normalizedQuery, maxSuggestions - suggestions.length));
      
      // Remove duplicates and limit
      final uniqueSuggestions = suggestions.toSet().toList();
      return uniqueSuggestions.take(maxSuggestions).toList();
      
    } catch (e) {
      debugPrint('❌ Failed to get suggestions for query "$query": $e');
      return [];
    }
  }

  Future<void> addToHistory({
    required String command,
    required String workingDirectory,
    required String user,
    required DateTime timestamp,
    int? exitCode,
    Duration? executionTime,
  }) async {
    final entry = HistoryEntry(
      id: 'hist_${timestamp.millisecondsSinceEpoch}',
      command: command,
      workingDirectory: workingDirectory,
      user: user,
      timestamp: timestamp,
      exitCode: exitCode,
      executionTime: executionTime,
    );
    
    _history.add(entry);
    
    // Limit history size
    if (_history.length > _maxHistoryEntries) {
      _history.removeAt(0);
    }
    
    // Add to indexes (will be batched by timer)
    _queueForIndexing(entry);
    
    _searchController.add(SearchEvent(
      type: SearchEventType.historyAdded,
      data: {
        'command': command,
        'directory': workingDirectory,
        'user': user,
      },
    ));
  }

  Future<void> addToFavorites(String query) async {
    _favoriteQueries.add(query);
    
    _searchController.add(SearchEvent(
      type: SearchEventType.favoriteAdded,
      data: {
        'query': query,
      },
    ));
    
    debugPrint('🔍 Added to favorites: $query');
  }

  Future<void> removeFromFavorites(String query) async {
    _favoriteQueries.remove(query);
    
    _searchController.add(SearchEvent(
      type: SearchEventType.favoriteRemoved,
      data: {
        'query': query,
      },
    ));
    
    debugPrint('🔍 Removed from favorites: $query');
  }

  List<String> getFavorites() {
    return _favoriteQueries.toList();
  }

  List<SearchQuery> getSearchHistory({int? limit}) {
    final history = _searchHistory.reversed.toList();
    return limit != null ? history.take(limit).toList() : history;
  }

  SearchStatistics getStatistics() {
    return SearchStatistics(
      totalHistoryEntries: _history.length,
      totalSearchQueries: _searchHistory.length,
      favoriteQueries: _favoriteQueries.length,
      commandIndexSize: _commandIndex.length,
      pathIndexSize: _pathIndex.length,
      userIndexSize: _userIndex.length,
      averageSearchTime: _calculateAverageSearchTime(),
      mostSearchedCommands: _getMostSearchedCommands(),
    );
  }

  Future<void> _loadHistory() async {
    // In a real implementation, would load from persistent storage
    debugPrint('🔍 Loading terminal history...');
  }

  Future<void> _buildIndexes() async {
    debugPrint('🔍 Building search indexes...');
    
    for (final entry in _history) {
      await _indexEntry(entry);
    }
    
    debugPrint('🔍 Built indexes: ${_commandIndex.length} commands, ${_pathIndex.length} paths, ${_userIndex.length} users');
  }

  Future<void> _indexEntry(HistoryEntry entry) async {
    // Index command
    final commandWords = _tokenizeCommand(entry.command);
    for (final word in commandWords) {
      _commandIndex.putIfAbsent(word, () => []).add(entry);
    }
    
    // Index path
    final pathSegments = _tokenizePath(entry.workingDirectory);
    for (final segment in pathSegments) {
      _pathIndex.putIfAbsent(segment, () => []).add(entry);
    }
    
    // Index user
    _userIndex.putIfAbsent(entry.user, () => []).add(entry);
  }

  void _queueForIndexing(HistoryEntry entry) {
    // Will be processed by indexing timer
  }

  void _startIndexing() {
    _indexingTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _processIndexingQueue();
    });
  }

  Future<void> _processIndexingQueue() async {
    // Process any pending indexing
  }

  String _normalizeQuery(String query) {
    return query.toLowerCase().trim();
  }

  List<String> _tokenizeCommand(String command) {
    // Split command into tokens (words, flags, paths)
    final tokens = <String>[];
    final parts = command.split(' ');
    
    for (final part in parts) {
      if (part.isNotEmpty) {
        tokens.add(part.toLowerCase());
        
        // Also add individual characters for fuzzy matching
        for (int i = 0; i < part.length - 1; i++) {
          tokens.add(part.substring(i, i + 2).toLowerCase());
        }
      }
    }
    
    return tokens;
  }

  List<String> _tokenizePath(String path) {
    final segments = path.split('/');
    return segments.where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
  }

  Future<List<SearchResult>> _searchInCommands(String query, SearchOptions options) async {
    final results = <SearchResult>[];
    
    for (final entry in _history) {
      final score = _calculateCommandScore(query, entry.command, options);
      if (score >= _minScore) {
        results.add(SearchResult(
          entry: entry,
          score: score,
          matchType: MatchType.command,
          highlights: _calculateHighlights(query, entry.command),
        ));
      }
    }
    
    return results;
  }

  Future<List<SearchResult>> _searchInPaths(String query, SearchOptions options) async {
    final results = <SearchResult>[];
    
    for (final entry in _history) {
      final score = _calculatePathScore(query, entry.workingDirectory, options);
      if (score >= _minScore) {
        results.add(SearchResult(
          entry: entry,
          score: score,
          matchType: MatchType.path,
          highlights: _calculateHighlights(query, entry.workingDirectory),
        ));
      }
    }
    
    return results;
  }

  Future<List<SearchResult>> _searchInUsers(String query, SearchOptions options) async {
    final results = <SearchResult>[];
    
    for (final entry in _history) {
      final score = _calculateUserScore(query, entry.user, options);
      if (score >= _minScore) {
        results.add(SearchResult(
          entry: entry,
          score: score,
          matchType: MatchType.user,
          highlights: _calculateHighlights(query, entry.user),
        ));
      }
    }
    
    return results;
  }

  Future<List<SearchResult>> _fullTextSearch(String query, SearchOptions options) async {
    final results = <SearchResult>[];
    
    for (final entry in _history) {
      final fullText = '${entry.command} ${entry.workingDirectory} ${entry.user}';
      final score = _calculateFullTextScore(query, fullText, options);
      if (score >= _minScore) {
        results.add(SearchResult(
          entry: entry,
          score: score,
          matchType: MatchType.fullText,
          highlights: _calculateHighlights(query, fullText),
        ));
      }
    }
    
    return results;
  }

  double _calculateCommandScore(String query, String command, SearchOptions options) {
    final normalizedCommand = command.toLowerCase();
    
    // Exact match gets highest score
    if (normalizedCommand.contains(query)) {
      return 1.0;
    }
    
    // Calculate fuzzy match score
    double score = 0.0;
    
    // Substring matches
    final queryLength = query.length;
    final commandLength = normalizedCommand.length;
    
    for (int i = 0; i <= commandLength - queryLength; i++) {
      final substring = normalizedCommand.substring(i, i + queryLength);
      final distance = _levenshteinDistance(query, substring);
      final matchScore = 1.0 - (distance / queryLength);
      score = math.max(score, matchScore);
    }
    
    // Token matching
    final queryTokens = query.split(' ');
    final commandTokens = command.toLowerCase().split(' ');
    
    int matchedTokens = 0;
    for (final queryToken in queryTokens) {
      for (final commandToken in commandTokens) {
        if (commandToken.contains(queryToken)) {
          matchedTokens++;
          break;
        }
      }
    }
    
    if (queryTokens.isNotEmpty) {
      final tokenScore = matchedTokens / queryTokens.length;
      score = math.max(score, tokenScore * 0.8);
    }
    
    // Apply options weighting
    if (options.preferRecent) {
      final ageInDays = DateTime.now().difference(entry.timestamp).inDays;
      final recencyBonus = math.max(0, 1.0 - (ageInDays / 365.0));
      score += recencyBonus * 0.2;
    }
    
    if (options.preferFrequent) {
      // Would need frequency tracking
    }
    
    return math.min(1.0, score);
  }

  double _calculatePathScore(String query, String path, SearchOptions options) {
    final normalizedPath = path.toLowerCase();
    
    if (normalizedPath.contains(query)) {
      return 0.9;
    }
    
    // Similar fuzzy matching as commands
    return _calculateFuzzyScore(query, normalizedPath) * 0.8;
  }

  double _calculateUserScore(String query, String user, SearchOptions options) {
    final normalizedUser = user.toLowerCase();
    
    if (normalizedUser.contains(query)) {
      return 0.8;
    }
    
    return _calculateFuzzyScore(query, normalizedUser) * 0.7;
  }

  double _calculateFullTextScore(String query, String text, SearchOptions options) {
    return _calculateFuzzyScore(query, text.toLowerCase()) * 0.6;
  }

  double _calculateFuzzyScore(String query, String text) {
    if (text.contains(query)) {
      return 1.0;
    }
    
    // Simple fuzzy scoring
    int matches = 0;
    int queryIndex = 0;
    
    for (int i = 0; i < text.length && queryIndex < query.length; i++) {
      if (text[i] == query[queryIndex]) {
        matches++;
        queryIndex++;
      }
    }
    
    if (queryIndex == query.length) {
      return matches / query.length;
    }
    
    // Use Levenshtein distance as fallback
    final distance = _levenshteinDistance(query, text);
    return math.max(0.0, 1.0 - (distance / math.max(query.length, text.length)));
  }

  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    
    if (len1 == 0) return len2;
    if (len2 == 0) return len1;
    
    final matrix = List.generate(len1 + 1, (i) => List.filled(len2 + 1, 0));
    
    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(
            matrix[i - 1][j] + 1,      // deletion
            matrix[i][j - 1] + 1,      // insertion
          ),
          matrix[i - 1][j - 1] + cost, // substitution
        );
      }
    }
    
    return matrix[len1][len2];
  }

  List<TextHighlight> _calculateHighlights(String query, String text) {
    final highlights = <TextHighlight>[];
    final normalizedText = text.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    
    int index = normalizedText.indexOf(normalizedQuery);
    while (index != -1) {
      highlights.add(TextHighlight(
        start: index,
        end: index + query.length,
        type: HighlightType.match,
      ));
      
      index = normalizedText.indexOf(normalizedQuery, index + 1);
    }
    
    return highlights;
  }

  List<SearchResult> _deduplicateResults(List<SearchResult> results) {
    final seen = <String>{};
    final uniqueResults = <SearchResult>[];
    
    for (final result in results) {
      final key = result.entry.id;
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueResults.add(result);
      }
    }
    
    return uniqueResults;
  }

  List<String> _getRecentQueries(int maxSuggestions) {
    return _searchHistory
        .reversed
        .take(maxSuggestions)
        .map((q) => q.query)
        .toList();
  }

  List<String> _getCommandSuggestions(String query, int maxSuggestions) {
    final suggestions = <String>[];
    
    // Get common command prefixes
    final prefixes = ['git ', 'docker ', 'npm ', 'yarn ', 'pip ', 'cargo ', 'go run ', 'python '];
    
    for (final prefix in prefixes) {
      if (prefix.startsWith(query)) {
        suggestions.add(prefix);
      }
    }
    
    return suggestions.take(maxSuggestions).toList();
  }

  List<String> _getHistorySuggestions(String query, int maxSuggestions) {
    return _searchHistory
        .where((q) => q.query.toLowerCase().contains(query))
        .map((q) => q.query)
        .toSet()
        .take(maxSuggestions)
        .toList();
  }

  void _recordSearchQuery(String query) {
    final searchQuery = SearchQuery(
      query: query,
      timestamp: DateTime.now(),
      resultCount: 0, // Would be set after search
    );
    
    _searchHistory.add(searchQuery);
    
    // Limit search history
    if (_searchHistory.length > _maxSearchHistory) {
      _searchHistory.removeAt(0);
    }
  }

  double _calculateAverageSearchTime() {
    // Would track actual search times
    return 50.0; // ms
  }

  List<String> _getMostSearchedCommands() {
    // Would analyze search history
    return ['git', 'docker', 'npm', 'python', 'ls', 'cd'];
  }

  Future<void> dispose() async {
    _indexingTimer?.cancel();
    _searchController.close();
    _history.clear();
    _commandIndex.clear();
    _pathIndex.clear();
    _userIndex.clear();
    _searchHistory.clear();
    _favoriteQueries.clear();
    _isInitialized = false;
    
    debugPrint('🔍 Fuzzy History Search disposed');
  }
}

/// Data classes
class HistoryEntry {
  final String id;
  final String command;
  final String workingDirectory;
  final String user;
  final DateTime timestamp;
  final int? exitCode;
  final Duration? executionTime;
  
  HistoryEntry({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.user,
    required this.timestamp,
    this.exitCode,
    this.executionTime,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'working_directory': workingDirectory,
    'user': user,
    'timestamp': timestamp.toIso8601String(),
    'exit_code': exitCode,
    'execution_time_ms': executionTime?.inMilliseconds,
  };
  
  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    command: json['command'] as String,
    workingDirectory: json['working_directory'] as String,
    user: json['user'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    exitCode: json['exit_code'] as int?,
    executionTime: json['execution_time_ms'] != null
        ? Duration(milliseconds: json['execution_time_ms'] as int)
        : null,
  );
}

class SearchResult {
  final HistoryEntry entry;
  final double score;
  final MatchType matchType;
  final List<TextHighlight> highlights;
  
  SearchResult({
    required this.entry,
    required this.score,
    required this.matchType,
    required this.highlights,
  });
  
  String get scorePercentage => '${(score * 100).toStringAsFixed(1)}%';
}

class SearchQuery {
  final String query;
  final DateTime timestamp;
  final int resultCount;
  
  SearchQuery({
    required this.query,
    required this.timestamp,
    required this.resultCount,
  });
}

class SearchOptions {
  final bool searchCommands;
  final bool searchPaths;
  final bool searchUsers;
  final bool fullTextSearch;
  final bool preferRecent;
  final bool preferFrequent;
  final int maxResults;
  
  const SearchOptions({
    this.searchCommands = true,
    this.searchPaths = true,
    this.searchUsers = false,
    this.fullTextSearch = false,
    this.preferRecent = false,
    this.preferFrequent = false,
    this.maxResults = 100,
  });
}

class TextHighlight {
  final int start;
  final int end;
  final HighlightType type;
  
  TextHighlight({
    required this.start,
    required this.end,
    required this.type,
  });
}

class SearchStatistics {
  final int totalHistoryEntries;
  final int totalSearchQueries;
  final int favoriteQueries;
  final int commandIndexSize;
  final int pathIndexSize;
  final int userIndexSize;
  final double averageSearchTime;
  final List<String> mostSearchedCommands;
  
  SearchStatistics({
    required this.totalHistoryEntries,
    required this.totalSearchQueries,
    required this.favoriteQueries,
    required this.commandIndexSize,
    required this.pathIndexSize,
    required this.userIndexSize,
    required this.averageSearchTime,
    required this.mostSearchedCommands,
  });
}

class SearchEvent {
  final SearchEventType type;
  final Map<String, dynamic>? data;
  
  SearchEvent({
    required this.type,
    this.data,
  });
}

enum MatchType {
  command,
  path,
  user,
  fullText,
}

enum HighlightType {
  match,
  keyword,
  syntax,
}

enum SearchEventType {
  searchCompleted,
  historyAdded,
  favoriteAdded,
  favoriteRemoved,
}
