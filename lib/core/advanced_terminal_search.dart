import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class AdvancedTerminalSearch {
  static const String _indexFile = '/home/house/.termisol_search_index.json';
  static const String _historyFile = '/home/house/.termisol_search_history.json';
  static const int _maxHistoryEntries = 1000;
  static const int _maxIndexEntries = 50000;
  static const Duration _cleanupInterval = Duration(hours: 1);
  static const Duration _indexUpdateInterval = Duration(minutes: 5);
  
  final Map<String, SearchIndex> _indexes = {};
  final Map<String, List<SearchHistoryEntry>> _history = {};
  final Map<String, SearchFilter> _filters = {};
  final Map<String, SearchResult> _results = {};
  
  Timer? _cleanupTimer;
  Timer? _indexUpdateTimer;
  int _totalIndexes = 0;
  int _totalHistory = 0;
  int _totalFilters = 0;
  int _totalResults = 0;
  
  final StreamController<SearchEvent> _searchController = 
      StreamController<SearchEvent>.broadcast();

  void initialize() {
    _loadIndexes();
    _loadHistory();
    _loadFilters();
    _initializeDefaultFilters();
    _startTimers();
    developer.log('🔍 Advanced Terminal Search initialized');
  }

  void _loadIndexes() {
    try {
      final file = File(_indexFile);
      if (!file.existsSync()) {
        developer.log('🔍 No existing search indexes found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['indexes']) {
        final index = SearchIndex.fromJson(entry);
        _indexes[index.id] = index;
        _totalIndexes++;
      }
      
      developer.log('🔍 Loaded ${_indexes.length} search indexes');
      
    } catch (e) {
      developer.log('🔍 Failed to load search indexes: $e');
    }
  }

  void _loadHistory() {
    try {
      final file = File(_historyFile);
      if (!file.existsSync()) {
        developer.log('🔍 No existing search history found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['history']) {
        final history = (entry['entries'] as List)
            .map((item) => SearchHistoryEntry.fromJson(item))
            .toList();
        
        _history[entry['user_id']] = history;
        _totalHistory += history.length;
      }
      
      developer.log('🔍 Loaded search history for ${_history.length} users');
      
    } catch (e) {
      developer.log('🔍 Failed to load search history: $e');
    }
  }

  void _loadFilters() {
    try {
      final file = File('${_indexFile}.filters');
      if (!file.existsSync()) {
        developer.log('🔍 No existing search filters found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['filters']) {
        final filter = SearchFilter.fromJson(entry);
        _filters[filter.id] = filter;
        _totalFilters++;
      }
      
      developer.log('🔍 Loaded ${_filters.length} search filters');
      
    } catch (e) {
      developer.log('🔍 Failed to load search filters: $e');
    }
  }

  void _initializeDefaultFilters() {
    if (_filters.isEmpty) {
      final defaultFilters = [
        // Command filter
        SearchFilter(
          id: 'commands',
          name: 'Commands',
          description: 'Filter for command history',
          type: FilterType.content,
          patterns: [
            r'^\s*\w+\s+.*$', // Command pattern
            r'^\s*(cd|ls|pwd|mkdir|rm|cp|mv|grep|find|ssh|git|docker|kubectl)', // Common commands
          ],
          excludePatterns: [
            r'^\s*#.*$', // Comments
            r'^\s*$', // Empty lines
          ],
          enabled: true,
          priority: 1,
          createdAt: DateTime.now(),
        ),
        
        // Error filter
        SearchFilter(
          id: 'errors',
          name: 'Errors',
          description: 'Filter for error messages',
          type: FilterType.content,
          patterns: [
            r'(?i)error|exception|failed|failed|fatal|critical|panic',
            r'(?i)command not found|no such file|permission denied',
            r'(?i)connection refused|timeout|network unreachable',
          ],
          excludePatterns: [],
          enabled: true,
          priority: 2,
          createdAt: DateTime.now(),
        ),
        
        // File operations filter
        SearchFilter(
          id: 'file_operations',
          name: 'File Operations',
          description: 'Filter for file operation commands',
          type: FilterType.content,
          patterns: [
            r'\b(cd|ls|pwd|mkdir|rmdir|rm|cp|mv|chmod|chown|find|locate)\b',
            r'\b(cat|less|more|head|tail|grep|sed|awk|sort|uniq)\b',
            r'\b(tar|zip|unzip|gzip|gunzip)\b',
          ],
          excludePatterns: [],
          enabled: true,
          priority: 3,
          createdAt: DateTime.now(),
        ),
        
        // Git operations filter
        SearchFilter(
          id: 'git_operations',
          name: 'Git Operations',
          description: 'Filter for Git commands',
          type: FilterType.content,
          patterns: [
            r'\bgit\s+(status|add|commit|push|pull|fetch|checkout|branch|merge|rebase|log|diff|stash|reset|remote)\b',
            r'\bgit\s+(init|clone|rm|mv|tag|show|blame|bisect|cherry-pick|revert)\b',
          ],
          excludePatterns: [],
          enabled: true,
          priority: 4,
          createdAt: DateTime.now(),
        ),
        
        // Docker operations filter
        SearchFilter(
          id: 'docker_operations',
          name: 'Docker Operations',
          description: 'Filter for Docker commands',
          type: FilterType.content,
          patterns: [
            r'\bdocker\s+(run|build|push|pull|ps|images|rm|rmi|stop|start|restart|logs|exec|inspect)\b',
            r'\bdocker\s+(compose|network|volume|swarm|service|stack|config|login|logout)\b',
          ],
          excludePatterns: [],
          enabled: true,
          priority: 5,
          createdAt: DateTime.now(),
        ),
        
        // Time filter
        SearchFilter(
          id: 'time_based',
          name: 'Time Based',
          description: 'Filter by time ranges',
          type: FilterType.time,
          patterns: [],
          excludePatterns: [],
          timeRanges: [
            TimeRange(name: 'Last Hour', start: Duration(hours: -1), end: Duration.zero),
            TimeRange(name: 'Last 24 Hours', start: Duration(hours: -24), end: Duration.zero),
            TimeRange(name: 'Last Week', start: Duration(days: -7), end: Duration.zero),
            TimeRange(name: 'Last Month', start: Duration(days: -30), end: Duration.zero),
          ],
          enabled: true,
          priority: 6,
          createdAt: DateTime.now(),
        ),
        
        // Session filter
        SearchFilter(
          id: 'session_based',
          name: 'Session Based',
          description: 'Filter by terminal session',
          type: FilterType.session,
          patterns: [],
          excludePatterns: [],
          sessionTypes: [
            'local',
            'ssh',
            'tmux',
            'screen',
          ],
          enabled: true,
          priority: 7,
          createdAt: DateTime.now(),
        ),
      ];
      
      for (final filter in defaultFilters) {
        _filters[filter.id] = filter;
        _totalFilters++;
      }
      
      _saveFilters();
      developer.log('🔍 Initialized ${defaultFilters.length} default filters');
    }
  }

  void _startTimers() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
    
    _indexUpdateTimer = Timer.periodic(_indexUpdateInterval, (_) => _updateIndexes());
  }

  Future<SearchResult> search({
    required String query,
    SearchType? type,
    List<String>? filterIds,
    String? sessionId,
    int? limit,
    int? offset,
    bool? caseSensitive,
    bool? regex,
    bool? fuzzy,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final searchId = _generateSearchId();
    final userId = 'current_user'; // In practice, get actual user ID
    
    try {
      developer.log('🔍 Performing search: "$query"');
      
      // Record search in history
      await _recordSearchHistory(userId, query, type, filterIds);
      
      // Apply filters
      final activeFilters = _getActiveFilters(filterIds);
      
      // Perform search based on type
      final results = await _performSearch(
        query,
        type ?? SearchType.content,
        activeFilters,
        sessionId,
        limit,
        offset,
        caseSensitive ?? false,
        regex ?? false,
        fuzzy ?? false,
        startTime,
        endTime,
      );
      
      // Create search result
      final searchResult = SearchResult(
        id: searchId,
        query: query,
        type: type ?? SearchType.content,
        filters: activeFilters,
        results: results,
        totalCount: results.length,
        hasMore: false, // Simplified
        searchTime: DateTime.now(),
        executionTime: Duration(milliseconds: 100), // Simplified
      );
      
      _results[searchId] = searchResult;
      _totalResults++;
      
      developer.log('🔍 Search completed: ${results.length} results');
      
      _emitEvent(SearchEvent(
        type: SearchEventType.searchCompleted,
        searchId: searchId,
        query: query,
        resultCount: results.length,
      ));
      
      await _saveResults();
      
      return searchResult;
      
    } catch (e) {
      developer.log('🔍 Search failed: $e');
      
      _emitEvent(SearchEvent(
        type: SearchEventType.searchFailed,
        searchId: searchId,
        query: query,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<List<SearchResultItem>> _performSearch(
    String query,
    SearchType type,
    List<SearchFilter> filters,
    String? sessionId,
    int? limit,
    int? offset,
    bool caseSensitive,
    bool regex,
    bool fuzzy,
    DateTime? startTime,
    DateTime? endTime,
  ) async {
    switch (type) {
      case SearchType.content:
        return await _searchContent(
          query,
          filters,
          sessionId,
          limit,
          offset,
          caseSensitive,
          regex,
          fuzzy,
          startTime,
          endTime,
        );
      case SearchType.command:
        return await _searchCommands(
          query,
          filters,
          limit,
          offset,
          caseSensitive,
          regex,
          fuzzy,
        );
      case SearchType.file:
        return await _searchFiles(
          query,
          filters,
          limit,
          offset,
          caseSensitive,
          regex,
          fuzzy,
        );
      case SearchType.semantic:
        return await _searchSemantic(
          query,
          filters,
          limit,
          offset,
          startTime,
          endTime,
        );
    }
  }

  Future<List<SearchResultItem>> _searchContent(
    String query,
    List<SearchFilter> filters,
    String? sessionId,
    int? limit,
    int? offset,
    bool caseSensitive,
    bool regex,
    bool fuzzy,
    DateTime? startTime,
    DateTime? endTime,
  ) async {
    final results = <SearchResultItem>[];
    
    // Search through terminal content indexes
    for (final index in _indexes.values) {
      if (index.type != IndexType.content) continue;
      
      // Apply time filter
      if (startTime != null && index.timestamp.isBefore(startTime!)) continue;
      if (endTime != null && index.timestamp.isAfter(endTime!)) continue;
      
      // Apply session filter
      if (sessionId != null && index.sessionId != sessionId) continue;
      
      // Apply content filters
      if (!_passesContentFilters(index.content, filters)) continue;
      
      // Perform search
      final match = _searchInContent(
        query,
        index.content,
        caseSensitive,
        regex,
        fuzzy,
      );
      
      if (match != null) {
        results.add(SearchResultItem(
          id: _generateResultId(),
          indexId: index.id,
          type: ResultType.content,
          content: index.content,
          line: index.line,
          column: match.startIndex,
          matchText: match.matchedText,
          score: match.score,
          context: _extractContext(index.content, match.startIndex, match.endIndex),
          timestamp: index.timestamp,
          sessionId: index.sessionId,
          metadata: index.metadata,
        ));
      }
    }
    
    // Sort by score
    results.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply limit and offset
    if (offset != null && offset! > 0) {
      results.removeRange(0, math.min(offset!, results.length));
    }
    
    if (limit != null && limit! > 0) {
      return results.take(limit!).toList();
    }
    
    return results;
  }

  Future<List<SearchResultItem>> _searchCommands(
    String query,
    List<SearchFilter> filters,
    int? limit,
    int? offset,
    bool caseSensitive,
    bool regex,
    bool fuzzy,
  ) async {
    final results = <SearchResultItem>[];
    
    // Search through command history indexes
    for (final index in _indexes.values) {
      if (index.type != IndexType.command) continue;
      
      // Apply command filters
      if (!_passesCommandFilters(index.content, filters)) continue;
      
      // Perform search
      final match = _searchInContent(
        query,
        index.content,
        caseSensitive,
        regex,
        fuzzy,
      );
      
      if (match != null) {
        results.add(SearchResultItem(
          id: _generateResultId(),
          indexId: index.id,
          type: ResultType.command,
          content: index.content,
          line: index.line,
          column: match.startIndex,
          matchText: match.matchedText,
          score: match.score,
          context: _extractContext(index.content, match.startIndex, match.endIndex),
          timestamp: index.timestamp,
          sessionId: index.sessionId,
          metadata: index.metadata,
        ));
      }
    }
    
    // Sort by score
    results.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply limit and offset
    if (offset != null && offset! > 0) {
      results.removeRange(0, math.min(offset!, results.length));
    }
    
    if (limit != null && limit! > 0) {
      return results.take(limit!).toList();
    }
    
    return results;
  }

  Future<List<SearchResultItem>> _searchFiles(
    String query,
    List<SearchFilter> filters,
    int? limit,
    int? offset,
    bool caseSensitive,
    bool regex,
    bool fuzzy,
  ) async {
    final results = <SearchResultItem>[];
    
    // Search through file indexes
    for (final index in _indexes.values) {
      if (index.type != IndexType.file) continue;
      
      // Apply file filters
      if (!_passesFileFilters(index.content, filters)) continue;
      
      // Perform search
      final match = _searchInContent(
        query,
        index.content,
        caseSensitive,
        regex,
        fuzzy,
      );
      
      if (match != null) {
        results.add(SearchResultItem(
          id: _generateResultId(),
          indexId: index.id,
          type: ResultType.file,
          content: index.content,
          line: index.line,
          column: match.startIndex,
          matchText: match.matchedText,
          score: match.score,
          context: _extractContext(index.content, match.startIndex, match.endIndex),
          timestamp: index.timestamp,
          sessionId: index.sessionId,
          metadata: index.metadata,
        ));
      }
    }
    
    // Sort by score
    results.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply limit and offset
    if (offset != null && offset! > 0) {
      results.removeRange(0, math.min(offset!, results.length));
    }
    
    if (limit != null && limit! > 0) {
      return results.take(limit!).toList();
    }
    
    return results;
  }

  Future<List<SearchResultItem>> _searchSemantic(
    String query,
    List<SearchFilter> filters,
    int? limit,
    int? offset,
    DateTime? startTime,
    DateTime? endTime,
  ) async {
    final results = <SearchResultItem>[];
    
    // Semantic search using keyword analysis
    final keywords = _extractKeywords(query);
    
    for (final index in _indexes.values) {
      // Apply time filter
      if (startTime != null && index.timestamp.isBefore(startTime!)) continue;
      if (endTime != null && index.timestamp.isAfter(endTime!)) continue;
      
      // Calculate semantic similarity
      final similarity = _calculateSemanticSimilarity(keywords, index.content);
      
      if (similarity > 0.3) { // Threshold for semantic match
        results.add(SearchResultItem(
          id: _generateResultId(),
          indexId: index.id,
          type: ResultType.semantic,
          content: index.content,
          line: index.line,
          column: 0,
          matchText: query,
          score: similarity,
          context: index.content,
          timestamp: index.timestamp,
          sessionId: index.sessionId,
          metadata: index.metadata,
        ));
      }
    }
    
    // Sort by score
    results.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply limit and offset
    if (offset != null && offset! > 0) {
      results.removeRange(0, math.min(offset!, results.length));
    }
    
    if (limit != null && limit! > 0) {
      return results.take(limit!).toList();
    }
    
    return results;
  }

  SearchMatch? _searchInContent(
    String query,
    String content,
    bool caseSensitive,
    bool regex,
    bool fuzzy,
  ) {
    if (regex) {
      try {
        final pattern = RegExp(query, caseSensitive: caseSensitive);
        final match = pattern.firstMatch(content);
        
        if (match != null) {
          return SearchMatch(
            startIndex: match.start,
            endIndex: match.end,
            matchedText: match.group(0)!,
            score: 1.0,
          );
        }
      } catch (e) {
        // Invalid regex
      }
    } else if (fuzzy) {
      return _fuzzySearch(query, content, caseSensitive);
    } else {
      final searchContent = caseSensitive ? content : content.toLowerCase();
      final searchQuery = caseSensitive ? query : query.toLowerCase();
      
      final index = searchContent.indexOf(searchQuery);
      if (index >= 0) {
        return SearchMatch(
          startIndex: index,
          endIndex: index + query.length,
          matchedText: content.substring(index, index + query.length),
          score: 1.0,
        );
      }
    }
    
    return null;
  }

  SearchMatch? _fuzzySearch(String query, String content, bool caseSensitive) {
    final searchContent = caseSensitive ? content : content.toLowerCase();
    final searchQuery = caseSensitive ? query : query.toLowerCase();
    
    if (searchQuery.isEmpty) return null;
    
    // Simple fuzzy matching using Levenshtein distance
    int bestScore = 0;
    int bestIndex = -1;
    int bestLength = 0;
    
    for (int i = 0; i <= searchContent.length - searchQuery.length; i++) {
      final substring = searchContent.substring(i, i + searchQuery.length);
      final distance = _levenshteinDistance(searchQuery, substring);
      final maxLen = math.max(searchQuery.length, substring.length);
      final score = maxLen > 0 ? (maxLen - distance) / maxLen : 0.0;
      
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
        bestLength = substring.length;
      }
    }
    
    if (bestScore > 0.5) { // Threshold for fuzzy match
      return SearchMatch(
        startIndex: bestIndex,
        endIndex: bestIndex + bestLength,
        matchedText: content.substring(bestIndex, bestIndex + bestLength),
        score: bestScore,
      );
    }
    
    return null;
  }

  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    
    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(
            matrix[i - 1][j] + 1, // deletion
            matrix[i][j - 1] + 1, // insertion
          ),
          matrix[i - 1][j - 1] + cost, // substitution
        );
      }
    }
    
    return matrix[a.length][b.length];
  }

  List<String> _extractKeywords(String query) {
    // Simple keyword extraction
    final words = query.toLowerCase().split(RegExp(r'\W+'));
    final keywords = <String>[];
    
    for (final word in words) {
      if (word.length > 2) { // Ignore short words
        keywords.add(word);
      }
    }
    
    return keywords;
  }

  double _calculateSemanticSimilarity(List<String> keywords, String content) {
    if (keywords.isEmpty) return 0.0;
    
    final contentWords = content.toLowerCase().split(RegExp(r'\W+'));
    final contentSet = Set.from(contentWords);
    
    int matches = 0;
    for (final keyword in keywords) {
      if (contentSet.contains(keyword)) {
        matches++;
      }
    }
    
    return matches / keywords.length;
  }

  bool _passesContentFilters(String content, List<SearchFilter> filters) {
    for (final filter in filters) {
      if (filter.type != FilterType.content) continue;
      
      // Check include patterns
      for (final pattern in filter.patterns) {
        try {
          final regex = RegExp(pattern, caseSensitive: false);
          if (!regex.hasMatch(content)) {
            return false;
          }
        } catch (e) {
          // Invalid pattern
        }
      }
      
      // Check exclude patterns
      for (final pattern in filter.excludePatterns) {
        try {
          final regex = RegExp(pattern, caseSensitive: false);
          if (regex.hasMatch(content)) {
            return false;
          }
        } catch (e) {
          // Invalid pattern
        }
      }
    }
    
    return true;
  }

  bool _passesCommandFilters(String content, List<SearchFilter> filters) {
    for (final filter in filters) {
      if (filter.type != FilterType.content) continue;
      
      // Command-specific filtering
      if (filter.id == 'commands') {
        if (!RegExp(r'^\s*\w+\s+.*$').hasMatch(content)) {
          return false;
        }
      }
    }
    
    return true;
  }

  bool _passesFileFilters(String content, List<SearchFilter> filters) {
    for (final filter in filters) {
      if (filter.type != FilterType.content) continue;
      
      // File-specific filtering
      // Add file-specific filter logic here
    }
    
    return true;
  }

  String _extractContext(String content, int startIndex, int endIndex) {
    final contextRadius = 50; // Characters before and after match
    
    final start = math.max(0, startIndex - contextRadius);
    final end = math.min(content.length, endIndex + contextRadius);
    
    return content.substring(start, end);
  }

  List<SearchFilter> _getActiveFilters(List<String>? filterIds) {
    if (filterIds == null || filterIds.isEmpty) {
      return _filters.values.where((filter) => filter.enabled).toList();
    }
    
    return filterIds
        .map((id) => _filters[id])
        .where((filter) => filter != null && filter!.enabled)
        .cast<SearchFilter>()
        .toList();
  }

  Future<void> _recordSearchHistory(
    String userId,
    String query,
    SearchType? type,
    List<String>? filterIds,
  ) async {
    final history = _history[userId] ?? [];
    
    // Add new entry
    final entry = SearchHistoryEntry(
      id: _generateHistoryId(),
      query: query,
      type: type ?? SearchType.content,
      filterIds: filterIds ?? [],
      timestamp: DateTime.now(),
      resultCount: 0, // Will be updated after search
    );
    
    history.insert(0, entry);
    _totalHistory++;
    
    // Limit history size
    if (history.length > _maxHistoryEntries) {
      history.removeRange(_maxHistoryEntries, history.length);
    }
    
    _history[userId] = history;
    
    await _saveHistory();
  }

  Future<void> _updateIndexes() async {
    // Simulate index updates
    // In practice, this would scan terminal content and update indexes
    developer.log('🔍 Updating search indexes');
  }

  Future<void> _performCleanup() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    
    // Clean old indexes
    final toRemoveIndexes = <String>[];
    for (final entry in _indexes.entries) {
      if (entry.value.timestamp.isBefore(cutoffDate)) {
        toRemoveIndexes.add(entry.key);
      }
    }
    
    for (final key in toRemoveIndexes) {
      _indexes.remove(key);
      _totalIndexes--;
    }
    
    // Clean old search results
    final toRemoveResults = <String>[];
    for (final entry in _results.entries) {
      if (entry.value.searchTime.isBefore(cutoffDate)) {
        toRemoveResults.add(entry.key);
      }
    }
    
    for (final key in toRemoveResults) {
      _results.remove(key);
      _totalResults--;
    }
    
    // Clean old search history
    for (final entry in _history.entries) {
      final history = entry.value;
      history.removeWhere((item) => item.timestamp.isBefore(cutoffDate));
    }
    
    if (toRemoveIndexes.isNotEmpty || toRemoveResults.isNotEmpty) {
      developer.log('🔍 Cleaned ${toRemoveIndexes.length} indexes and ${toRemoveResults.length} results');
      
      await _saveIndexes();
      await _saveResults();
      await _saveHistory();
    }
  }

  Future<void> _saveIndexes() async {
    try {
      final file = File(_indexFile);
      
      final indexesData = _indexes.values.map((index) => index.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'indexes': indexesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🔍 Failed to save indexes: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final file = File(_historyFile);
      
      final historyData = _history.entries.map((entry) => {
        'user_id': entry.key,
        'entries': entry.value.map((item) => item.toJson()).toList(),
      }).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'history': historyData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🔍 Failed to save search history: $e');
    }
  }

  Future<void> _saveFilters() async {
    try {
      final file = File('${_indexFile}.filters');
      
      final filtersData = _filters.values.map((filter) => filter.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'filters': filtersData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🔍 Failed to save filters: $e');
    }
  }

  Future<void> _saveResults() async {
    try {
      final file = File('${_indexFile}.results');
      
      final resultsData = _results.values.map((result) => result.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'results': resultsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🔍 Failed to save results: $e');
    }
  }

  Future<String> createFilter({
    required String name,
    required String description,
    required FilterType type,
    List<String>? patterns,
    List<String>? excludePatterns,
    List<TimeRange>? timeRanges,
    List<String>? sessionTypes,
  }) async {
    final filterId = _generateFilterId();
    
    final filter = SearchFilter(
      id: filterId,
      name: name,
      description: description,
      type: type,
      patterns: patterns ?? [],
      excludePatterns: excludePatterns ?? [],
      timeRanges: timeRanges ?? [],
      sessionTypes: sessionTypes ?? [],
      enabled: true,
      priority: _totalFilters + 1,
      createdAt: DateTime.now(),
    );
    
    _filters[filterId] = filter;
    _totalFilters++;
    
    developer.log('🔍 Created filter: $name');
    
    _emitEvent(SearchEvent(
      type: SearchEventType.filterCreated,
      filterId: filterId,
      filterName: name,
    ));
    
    await _saveFilters();
    
    return filterId;
  }

  Future<void> addIndexEntry({
    required String content,
    required IndexType type,
    int? line,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    if (_indexes.length >= _maxIndexEntries) {
      await _performCleanup();
    }
    
    final indexId = _generateIndexId();
    
    final index = SearchIndex(
      id: indexId,
      content: content,
      type: type,
      line: line ?? 0,
      timestamp: DateTime.now(),
      sessionId: sessionId ?? 'default',
      metadata: metadata ?? {},
    );
    
    _indexes[indexId] = index;
    _totalIndexes++;
    
    // Save periodically
    if (_totalIndexes % 100 == 0) {
      await _saveIndexes();
    }
  }

  List<SearchHistoryEntry> getSearchHistory({String? userId}) {
    final userIdToUse = userId ?? 'current_user';
    return _history[userIdToUse] ?? [];
  }

  List<SearchFilter> getFilters() {
    return _filters.values.toList();
  }

  SearchResult? getSearchResult(String searchId) {
    return _results[searchId];
  }

  SearchStats getStats() {
    return SearchStats(
      totalIndexes: _totalIndexes,
      totalHistory: _totalHistory,
      totalFilters: _totalFilters,
      totalResults: _totalResults,
      activeFilters: _filters.values.where((f) => f.enabled).length,
      indexesByType: _indexes.values.fold(<IndexType, int>{}, (map, index) {
        map[index.type] = (map[index.type] ?? 0) + 1;
        return map;
      }),
      recentSearches: _getRecentSearches(),
      popularQueries: _getPopularQueries(),
    );
  }

  List<String> _getRecentSearches() {
    final allHistory = _history.values.expand((history) => history).toList();
    allHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return allHistory.take(10).map((entry) => entry.query).toList();
  }

  List<String> _getPopularQueries() {
    final queryCounts = <String, int>{};
    
    for (final history in _history.values) {
      for (final entry in history) {
        queryCounts[entry.query] = (queryCounts[entry.query] ?? 0) + 1;
      }
    }
    
    final sortedQueries = queryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedQueries.take(10).map((entry) => entry.key).toList();
  }

  String _generateSearchId() {
    return 'search_${DateTime.now().millisecondsSinceEpoch}_$_totalResults';
  }

  String _generateIndexId() {
    return 'index_${DateTime.now().millisecondsSinceEpoch}_$_totalIndexes';
  }

  String _generateFilterId() {
    return 'filter_${DateTime.now().millisecondsSinceEpoch}_$_totalFilters';
  }

  String _generateHistoryId() {
    return 'history_${DateTime.now().millisecondsSinceEpoch}_$_totalHistory';
  }

  String _generateResultId() {
    return 'result_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(SearchEvent event) {
    _searchController.add(event);
  }

  Stream<SearchEvent> get searchEventStream => _searchController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    _indexUpdateTimer?.cancel();
    
    _indexes.clear();
    _history.clear();
    _filters.clear();
    _results.clear();
    _searchController.close();
    
    developer.log('🔍 Advanced Terminal Search disposed');
  }
}

class SearchIndex {
  final String id;
  final String content;
  final IndexType type;
  final int line;
  final DateTime timestamp;
  final String sessionId;
  final Map<String, dynamic> metadata;

  SearchIndex({
    required this.id,
    required this.content,
    required this.type,
    required this.line,
    required this.timestamp,
    required this.sessionId,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type.name,
      'line': line,
      'timestamp': timestamp.toIso8601String(),
      'session_id': sessionId,
      'metadata': metadata,
    };
  }

  factory SearchIndex.fromJson(Map<String, dynamic> json) {
    return SearchIndex(
      id: json['id'],
      content: json['content'],
      type: IndexType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => IndexType.content,
      ),
      line: json['line'] ?? 0,
      timestamp: DateTime.parse(json['timestamp']),
      sessionId: json['session_id'],
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }
}

class SearchFilter {
  final String id;
  final String name;
  final String description;
  final FilterType type;
  final List<String> patterns;
  final List<String> excludePatterns;
  final List<TimeRange> timeRanges;
  final List<String> sessionTypes;
  final bool enabled;
  final int priority;
  final DateTime createdAt;

  SearchFilter({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.patterns,
    required this.excludePatterns,
    required this.timeRanges,
    required this.sessionTypes,
    required this.enabled,
    required this.priority,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'patterns': patterns,
      'exclude_patterns': excludePatterns,
      'time_ranges': timeRanges.map((range) => range.toJson()).toList(),
      'session_types': sessionTypes,
      'enabled': enabled,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SearchFilter.fromJson(Map<String, dynamic> json) {
    return SearchFilter(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: FilterType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => FilterType.content,
      ),
      patterns: List<String>.from(json['patterns'] ?? []),
      excludePatterns: List<String>.from(json['exclude_patterns'] ?? []),
      timeRanges: (json['time_ranges'] as List?)
          ?.map((range) => TimeRange.fromJson(range))
          .toList() ?? [],
      sessionTypes: List<String>.from(json['session_types'] ?? []),
      enabled: json['enabled'] ?? true,
      priority: json['priority'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class TimeRange {
  final String name;
  final Duration start;
  final Duration end;

  TimeRange({
    required this.name,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'start': start.inMilliseconds,
      'end': end.inMilliseconds,
    };
  }

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(
      name: json['name'],
      start: Duration(milliseconds: json['start']),
      end: Duration(milliseconds: json['end']),
    );
  }
}

class SearchHistoryEntry {
  final String id;
  final String query;
  final SearchType type;
  final List<String> filterIds;
  final DateTime timestamp;
  final int resultCount;

  SearchHistoryEntry({
    required this.id,
    required this.query,
    required this.type,
    required this.filterIds,
    required this.timestamp,
    required this.resultCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'query': query,
      'type': type.name,
      'filter_ids': filterIds,
      'timestamp': timestamp.toIso8601String(),
      'result_count': resultCount,
    };
  }

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SearchHistoryEntry(
      id: json['id'],
      query: json['query'],
      type: SearchType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => SearchType.content,
      ),
      filterIds: List<String>.from(json['filter_ids'] ?? []),
      timestamp: DateTime.parse(json['timestamp']),
      resultCount: json['result_count'] ?? 0,
    );
  }
}

class SearchResult {
  final String id;
  final String query;
  final SearchType type;
  final List<SearchFilter> filters;
  final List<SearchResultItem> results;
  final int totalCount;
  final bool hasMore;
  final DateTime searchTime;
  final Duration executionTime;

  SearchResult({
    required this.id,
    required this.query,
    required this.type,
    required this.filters,
    required this.results,
    required this.totalCount,
    required this.hasMore,
    required this.searchTime,
    required this.executionTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'query': query,
      'type': type.name,
      'filters': filters.map((filter) => filter.toJson()).toList(),
      'results': results.map((result) => result.toJson()).toList(),
      'total_count': totalCount,
      'has_more': hasMore,
      'search_time': searchTime.toIso8601String(),
      'execution_time': executionTime.inMilliseconds,
    };
  }

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'],
      query: json['query'],
      type: SearchType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => SearchType.content,
      ),
      filters: (json['filters'] as List?)
          ?.map((filter) => SearchFilter.fromJson(filter))
          .toList() ?? [],
      results: (json['results'] as List?)
          ?.map((result) => SearchResultItem.fromJson(result))
          .toList() ?? [],
      totalCount: json['total_count'] ?? 0,
      hasMore: json['has_more'] ?? false,
      searchTime: DateTime.parse(json['search_time']),
      executionTime: Duration(milliseconds: json['execution_time'] ?? 0),
    );
  }
}

class SearchResultItem {
  final String id;
  final String indexId;
  final ResultType type;
  final String content;
  final int line;
  final int column;
  final String matchText;
  final double score;
  final String context;
  final DateTime timestamp;
  final String sessionId;
  final Map<String, dynamic> metadata;

  SearchResultItem({
    required this.id,
    required this.indexId,
    required this.type,
    required this.content,
    required this.line,
    required this.column,
    required this.matchText,
    required this.score,
    required this.context,
    required this.timestamp,
    required this.sessionId,
    required this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index_id': indexId,
      'type': type.name,
      'content': content,
      'line': line,
      'column': column,
      'match_text': matchText,
      'score': score,
      'context': context,
      'timestamp': timestamp.toIso8601String(),
      'session_id': sessionId,
      'metadata': metadata,
    };
  }

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      id: json['id'],
      indexId: json['index_id'],
      type: ResultType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ResultType.content,
      ),
      content: json['content'],
      line: json['line'] ?? 0,
      column: json['column'] ?? 0,
      matchText: json['match_text'],
      score: (json['score'] ?? 0.0).toDouble(),
      context: json['context'],
      timestamp: DateTime.parse(json['timestamp']),
      sessionId: json['session_id'],
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }
}

class SearchMatch {
  final int startIndex;
  final int endIndex;
  final String matchedText;
  final double score;

  SearchMatch({
    required this.startIndex,
    required this.endIndex,
    required this.matchedText,
    required this.score,
  });
}

class SearchStats {
  final int totalIndexes;
  final int totalHistory;
  final int totalFilters;
  final int totalResults;
  final int activeFilters;
  final Map<IndexType, int> indexesByType;
  final List<String> recentSearches;
  final List<String> popularQueries;

  SearchStats({
    required this.totalIndexes,
    required this.totalHistory,
    required this.totalFilters,
    required this.totalResults,
    required this.activeFilters,
    required this.indexesByType,
    required this.recentSearches,
    required this.popularQueries,
  });
}

enum IndexType {
  content,
  command,
  file,
  session,
}

enum FilterType {
  content,
  time,
  session,
  file,
}

enum SearchType {
  content,
  command,
  file,
  semantic,
}

enum ResultType {
  content,
  command,
  file,
  semantic,
}

enum SearchEventType {
  searchCompleted,
  searchFailed,
  filterCreated,
  indexUpdated,
}
