import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Universal Search System
/// 
/// Comprehensive search across all Termisol data including:
/// - Terminal history and commands
/// - Files and directories
/// - Sessions and bookmarks
/// - Git repositories and commits
/// - Configuration and settings
/// - Code symbols and documentation
class UniversalSearch {
  static final UniversalSearch _instance = UniversalSearch._internal();
  factory UniversalSearch() => _instance;
  UniversalSearch._internal();

  bool _isInitialized = false;
  
  // Search indices
  final Map<String, SearchIndex> _indices = {};
  final List<SearchResult> _recentSearches = [];
  final Map<String, SearchQuery> _searchHistory = {};
  
  // Search providers
  final List<SearchProvider> _providers = [];
  
  // Configuration
  final SearchConfig _config = SearchConfig();
  
  // Event system
  final _searchController = StreamController<SearchEvent>.broadcast();
  Stream<SearchEvent> get events => _searchController.stream;
  
  // Search cache
  final Map<String, List<SearchResult>> _searchCache = {};
  Timer? _cacheCleanupTimer;
  
  bool get isInitialized => _isInitialized;
  int get indexedItems => _indices.values.fold(0, (sum, index) => sum + index.itemCount);
  int get recentSearches => _recentSearches.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize search providers
      await _initializeProviders();
      
      // Build search indices
      await _buildIndices();
      
      // Load search history
      await _loadSearchHistory();
      
      // Start cache cleanup
      _startCacheCleanup();
      
      _isInitialized = true;
      debugPrint('🔍 Universal Search initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Universal Search: $e');
    }
  }

  Future<void> _initializeProviders() async {
    _providers.addAll([
      TerminalHistoryProvider(),
      FileSystemProvider(),
      SessionProvider(),
      GitProvider(),
      ConfigurationProvider(),
      CodeSymbolProvider(),
      BookmarkProvider(),
      CommandProvider(),
    ]);
    
    for (final provider in _providers) {
      await provider.initialize();
    }
    
    debugPrint('🔍 Initialized ${_providers.length} search providers');
  }

  Future<void> _buildIndices() async {
    for (final provider in _providers) {
      try {
        final index = await provider.buildIndex();
        _indices[provider.id] = index;
        debugPrint('🔍 Built index for ${provider.id}: ${index.itemCount} items');
      } catch (e) {
        debugPrint('⚠️ Failed to build index for ${provider.id}: $e');
      }
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/search_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in (data['history'] as List)) {
          final query = SearchQuery.fromJson(entry);
          _searchHistory[query.id] = query;
        }
        
        debugPrint('🔍 Loaded ${_searchHistory.length} search queries');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load search history: $e');
    }
  }

  void _startCacheCleanup() {
    _cacheCleanupTimer = Timer.periodic(Duration(hours: 1), (_) {
      _cleanupCache();
    });
  }

  Future<List<SearchResult>> search(String query, {
    SearchType type = SearchType.all,
    int maxResults = 50,
    bool includeHistory = true,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final startTime = DateTime.now();
      
      // Check cache first
      final cacheKey = _generateCacheKey(query, type, maxResults, filters);
      if (_searchCache.containsKey(cacheKey)) {
        return _searchCache[cacheKey]!;
      }
      
      // Build search request
      final searchRequest = SearchRequest(
        query: query,
        type: type,
        maxResults: maxResults,
        filters: filters ?? {},
        timestamp: startTime,
      );
      
      // Execute search
      final results = await _executeSearch(searchRequest);
      
      // Add to recent searches
      _addToRecentSearches(query, results);
      
      // Cache results
      _searchCache[cacheKey] = results;
      
      // Record search query
      await _recordSearchQuery(searchRequest, results);
      
      // Emit search event
      _searchController.add(SearchEvent(
        type: SearchEventType.searchCompleted,
        query: query,
        results: results,
        duration: DateTime.now().difference(startTime),
      ));
      
      debugPrint('🔍 Search completed: "$query" -> ${results.length} results');
      return results;
      
    } catch (e) {
      debugPrint('❌ Search failed: $e');
      
      _searchController.add(SearchEvent(
        type: SearchEventType.searchFailed,
        query: query,
        error: e.toString(),
      ));
      
      return [];
    }
  }

  Future<List<SearchResult>> _executeSearch(SearchRequest request) async {
    final allResults = <SearchResult>[];
    
    // Determine which providers to search
    final targetProviders = request.type == SearchType.all 
        ? _providers 
        : _providers.where((p) => p.supportedTypes.contains(request.type)).toList();
    
    // Search in parallel
    final futures = targetProviders.map((provider) => 
        _searchProvider(provider, request)
    ).toList();
    
    final results = await Future.wait(futures);
    
    // Combine and rank results
    for (final providerResults in results) {
      allResults.addAll(providerResults);
    }
    
    // Rank results by relevance
    allResults.sort((a, b) => b.relevance.compareTo(a.relevance));
    
    // Limit results
    return allResults.take(request.maxResults).toList();
  }

  Future<List<SearchResult>> _searchProvider(SearchProvider provider, SearchRequest request) async {
    try {
      final index = _indices[provider.id];
      if (index == null) return [];
      
      return provider.search(index, request);
    } catch (e) {
      debugPrint('⚠️ Provider ${provider.id} search failed: $e');
      return [];
    }
  }

  void _addToRecentSearches(String query, List<SearchResult> results) {
    final searchResult = SearchResult(
      id: 'search_${DateTime.now().millisecondsSinceEpoch}',
      type: SearchType.search,
      title: query,
      description: '${results.length} results found',
      relevance: 1.0,
      timestamp: DateTime.now(),
      metadata: {
        'query': query,
        'result_count': results.length,
      },
    );
    
    _recentSearches.insert(0, searchResult);
    
    // Limit recent searches
    if (_recentSearches.length > 20) {
      _recentSearches.removeRange(20, _recentSearches.length);
    }
  }

  Future<void> _recordSearchQuery(SearchRequest request, List<SearchResult> results) async {
    try {
      final query = SearchQuery(
        id: 'query_${DateTime.now().millisecondsSinceEpoch}',
        query: request.query,
        type: request.type,
        resultCount: results.length,
        timestamp: request.timestamp,
        filters: request.filters,
      );
      
      _searchHistory[query.id] = query;
      
      // Limit history size
      if (_searchHistory.length > 1000) {
        final oldest = _searchHistory.keys.first;
        _searchHistory.remove(oldest);
      }
      
      // Save to disk periodically
      if (_searchHistory.length % 10 == 0) {
        await _saveSearchHistory();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to record search query: $e');
    }
  }

  Future<void> _saveSearchHistory() async {
    try {
      final historyFile = File('${Platform.environment['HOME']}/.termisol/search_history.json');
      await historyFile.parent.create(recursive: true);
      
      final data = {
        'history': _searchHistory.values.map((q) => q.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await historyFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save search history: $e');
    }
  }

  String _generateCacheKey(String query, SearchType type, int maxResults, Map<String, dynamic>? filters) {
    final filterStr = filters?.toString() ?? '';
    return '${query.toLowerCase()}_${type.name}_$maxResults_${filterStr.hashCode}';
  }

  void _cleanupCache() {
    if (_searchCache.length > 100) {
      // Remove oldest entries
      final keys = _searchCache.keys.toList();
      keys.sort();
      
      final toRemove = keys.take(_searchCache.length - 50);
      for (final key in toRemove) {
        _searchCache.remove(key);
      }
      
      debugPrint('🧹 Cleaned search cache: ${toRemove.length} entries removed');
    }
  }

  Future<List<String>> getSuggestions(String partialQuery) async {
    final suggestions = <String>[];
    
    // Get suggestions from search history
    for (final query in _searchHistory.values) {
      if (query.query.toLowerCase().contains(partialQuery.toLowerCase())) {
        suggestions.add(query.query);
      }
    }
    
    // Get suggestions from recent searches
    for (final result in _recentSearches) {
      final query = result.metadata['query'] as String?;
      if (query != null && query.toLowerCase().contains(partialQuery.toLowerCase())) {
        suggestions.add(query);
      }
    }
    
    // Remove duplicates and limit
    return suggestions.toSet().take(10).toList();
  }

  Future<void> addToIndex(SearchItem item) async {
    try {
      // Find appropriate provider
      final provider = _providers.firstWhere(
        (p) => p.canIndex(item),
        orElse: () => throw Exception('No provider found for item type'),
      );
      
      final index = _indices[provider.id];
      if (index != null) {
        await provider.addToIndex(index, item);
        debugPrint('🔍 Added item to ${provider.id} index: ${item.title}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to add item to index: $e');
    }
  }

  Future<void> removeFromIndex(String itemId) async {
    try {
      for (final provider in _providers) {
        final index = _indices[provider.id];
        if (index != null && index.contains(itemId)) {
          await provider.removeFromIndex(index, itemId);
          debugPrint('🔍 Removed item from ${provider.id} index: $itemId');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to remove item from index: $e');
    }
  }

  Future<void> rebuildIndex() async {
    try {
      debugPrint('🔍 Rebuilding search indices...');
      
      _indices.clear();
      await _buildIndices();
      
      _searchController.add(SearchEvent(
        type: SearchEventType.indexRebuilt,
        data: {'total_items': indexedItems},
      ));
      
      debugPrint('🔍 Search indices rebuilt');
    } catch (e) {
      debugPrint('❌ Failed to rebuild indices: $e');
    }
  }

  SearchStatistics getStatistics() {
    return SearchStatistics(
      totalProviders: _providers.length,
      indexedItems: indexedItems,
      recentSearches: _recentSearches.length,
      searchHistory: _searchHistory.length,
      cacheSize: _searchCache.length,
      providerStats: _getProviderStats(),
    );
  }

  Map<String, ProviderStatistics> _getProviderStats() {
    final stats = <String, ProviderStatistics>{};
    
    for (final provider in _providers) {
      final index = _indices[provider.id];
      stats[provider.id] = ProviderStatistics(
        itemCount: index?.itemCount ?? 0,
        supportedTypes: provider.supportedTypes,
        lastIndexed: index?.lastUpdated,
      );
    }
    
    return stats;
  }

  Future<void> dispose() async {
    // Save search history
    await _saveSearchHistory();
    
    // Cancel timers
    _cacheCleanupTimer?.cancel();
    
    // Dispose providers
    for (final provider in _providers) {
      await provider.dispose();
    }
    
    // Clear data
    _indices.clear();
    _recentSearches.clear();
    _searchHistory.clear();
    _searchCache.clear();
    _providers.clear();
    
    // Close event controller
    _searchController.close();
    
    _isInitialized = false;
    debugPrint('🔍 Universal Search disposed');
  }
}

/// Search configuration
class SearchConfig {
  final int maxResults;
  final Duration cacheTimeout;
  final bool enableFuzzySearch;
  final bool enableSemanticSearch;
  final double minRelevance;
  
  SearchConfig({
    this.maxResults = 50,
    this.cacheTimeout = Duration(minutes: 10),
    this.enableFuzzySearch = true,
    this.enableSemanticSearch = true,
    this.minRelevance = 0.1,
  });
}

/// Search request
class SearchRequest {
  final String query;
  final SearchType type;
  final int maxResults;
  final Map<String, dynamic> filters;
  final DateTime timestamp;
  
  SearchRequest({
    required this.query,
    required this.type,
    required this.maxResults,
    required this.filters,
    required this.timestamp,
  });
}

/// Search result
class SearchResult {
  final String id;
  final SearchType type;
  final String title;
  final String description;
  final double relevance;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  
  SearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.relevance,
    required this.timestamp,
    required this.metadata,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'title': title,
      'description': description,
      'relevance': relevance,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
  
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'],
      type: SearchType.values.firstWhere((t) => t.toString() == json['type']),
      title: json['title'],
      description: json['description'],
      relevance: json['relevance'],
      timestamp: DateTime.parse(json['timestamp']),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }
}

/// Search index
class SearchIndex {
  final String providerId;
  final Map<String, SearchItem> items;
  final Map<String, List<String>> invertedIndex;
  int itemCount;
  DateTime lastUpdated;
  
  SearchIndex({
    required this.providerId,
    required this.items,
    required this.invertedIndex,
    this.itemCount = 0,
    required this.lastUpdated,
  });
  
  bool contains(String itemId) => items.containsKey(itemId);
  
  void addItem(SearchItem item) {
    items[item.id] = item;
    itemCount++;
    lastUpdated = DateTime.now();
    
    // Update inverted index
    final words = _extractWords(item.title + ' ' + item.description);
    for (final word in words) {
      invertedIndex.putIfAbsent(word, () => []).add(item.id);
    }
  }
  
  void removeItem(String itemId) {
    final item = items.remove(itemId);
    if (item != null) {
      itemCount--;
      lastUpdated = DateTime.now();
      
      // Update inverted index
      final words = _extractWords(item.title + ' ' + item.description);
      for (final word in words) {
        invertedIndex[word]?.remove(itemId);
        if (invertedIndex[word]?.isEmpty == true) {
          invertedIndex.remove(word);
        }
      }
    }
  }
  
  List<String> _extractWords(String text) {
    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    
    return words;
  }
}

/// Search item
class SearchItem {
  final String id;
  final String title;
  final String description;
  final SearchType type;
  final Map<String, dynamic> metadata;
  
  SearchItem({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.metadata,
  });
}

/// Search query
class SearchQuery {
  final String id;
  final String query;
  final SearchType type;
  final int resultCount;
  final DateTime timestamp;
  final Map<String, dynamic> filters;
  
  SearchQuery({
    required this.id,
    required this.query,
    required this.type,
    required this.resultCount,
    required this.timestamp,
    required this.filters,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'query': query,
      'type': type.toString(),
      'result_count': resultCount,
      'timestamp': timestamp.toIso8601String(),
      'filters': filters,
    };
  }
  
  factory SearchQuery.fromJson(Map<String, dynamic> json) {
    return SearchQuery(
      id: json['id'],
      query: json['query'],
      type: SearchType.values.firstWhere((t) => t.toString() == json['type']),
      resultCount: json['result_count'],
      timestamp: DateTime.parse(json['timestamp']),
      filters: Map<String, dynamic>.from(json['filters'] ?? {}),
    );
  }
}

/// Search event
class SearchEvent {
  final SearchEventType type;
  final String? query;
  final List<SearchResult>? results;
  final Duration? duration;
  final String? error;
  final Map<String, dynamic>? data;
  
  SearchEvent({
    required this.type,
    this.query,
    this.results,
    this.duration,
    this.error,
    this.data,
  });
}

/// Search statistics
class SearchStatistics {
  final int totalProviders;
  final int indexedItems;
  final int recentSearches;
  final int searchHistory;
  final int cacheSize;
  final Map<String, ProviderStatistics> providerStats;
  
  SearchStatistics({
    required this.totalProviders,
    required this.indexedItems,
    required this.recentSearches,
    required this.searchHistory,
    required this.cacheSize,
    required this.providerStats,
  });
}

/// Provider statistics
class ProviderStatistics {
  final int itemCount;
  final List<SearchType> supportedTypes;
  final DateTime? lastIndexed;
  
  ProviderStatistics({
    required this.itemCount,
    required this.supportedTypes,
    this.lastIndexed,
  });
}

/// Search types
enum SearchType {
  all,
  command,
  file,
  session,
  git,
  config,
  symbol,
  bookmark,
  search,
}

/// Search event types
enum SearchEventType {
  searchStarted,
  searchCompleted,
  searchFailed,
  indexUpdated,
  indexRebuilt,
}

/// Abstract search provider
abstract class SearchProvider {
  String get id;
  List<SearchType> get supportedTypes;
  
  Future<void> initialize();
  Future<SearchIndex> buildIndex();
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request);
  Future<void> addToIndex(SearchIndex index, SearchItem item);
  Future<void> removeFromIndex(SearchIndex index, String itemId);
  bool canIndex(SearchItem item);
  Future<void> dispose();
}

/// Terminal history search provider
class TerminalHistoryProvider extends SearchProvider {
  @override
  String get id => 'terminal_history';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.command, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate loading terminal history
    final commands = [
      'git status',
      'npm install',
      'docker run -it ubuntu',
      'flutter run',
      'cargo build',
      'python main.py',
      'ls -la',
      'cd /home/user',
      'vim config.yaml',
    ];
    
    for (int i = 0; i < commands.length; i++) {
      final item = SearchItem(
        id: 'cmd_$i',
        title: commands[i],
        description: 'Terminal command',
        type: SearchType.command,
        metadata: {'source': 'terminal_history'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = commands[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.command && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      // Calculate relevance based on query matches
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.command;
  }
  
  @override
  Future<void> dispose() async {}
}

/// File system search provider
class FileSystemProvider extends SearchProvider {
  @override
  String get id => 'filesystem';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.file, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing files in current directory
    final files = [
      'main.dart',
      'pubspec.yaml',
      'README.md',
      'config.json',
      'src/app.dart',
      'lib/utils.dart',
      'test/main_test.dart',
      'docs/guide.md',
    ];
    
    for (int i = 0; i < files.length; i++) {
      final item = SearchItem(
        id: 'file_$i',
        title: files[i],
        description: 'File in project',
        type: SearchType.file,
        metadata: {'path': files[i]},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = files[i].toLowerCase().split(RegExp(r'[\/\._-]'));
      for (final word in words) {
        if (word.isNotEmpty) {
          invertedIndex.putIfAbsent(word, () => []).add(item.id);
        }
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(RegExp(r'\s+'));
    
    for (final item in index.items.values) {
      if (item.type != SearchType.file && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.file;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Session search provider
class SessionProvider extends SearchProvider {
  @override
  String get id => 'sessions';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.session, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing sessions
    final sessions = [
      'Development Session',
      'Testing Session',
      'Deployment Session',
      'Debug Session',
    ];
    
    for (int i = 0; i < sessions.length; i++) {
      final item = SearchItem(
        id: 'session_$i',
        title: sessions[i],
        description: 'Terminal session',
        type: SearchType.session,
        metadata: {'created_at': DateTime.now().toIso8601String()},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = sessions[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.session && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.session;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Git search provider
class GitProvider extends SearchProvider {
  @override
  String get id => 'git';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.git, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing git data
    final gitItems = [
      'commit: Add new feature',
      'branch: feature/login',
      'tag: v1.0.0',
      'file: src/main.dart',
    ];
    
    for (int i = 0; i < gitItems.length; i++) {
      final item = SearchItem(
        id: 'git_$i',
        title: gitItems[i],
        description: 'Git repository item',
        type: SearchType.git,
        metadata: {'repo': 'termisol'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = gitItems[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.git && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.git;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Configuration search provider
class ConfigurationProvider extends SearchProvider {
  @override
  String get id => 'config';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.config, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing configuration
    final configItems = [
      'theme: dark',
      'font_size: 14',
      'shell: bash',
      'keybindings: default',
    ];
    
    for (int i = 0; i < configItems.length; i++) {
      final item = SearchItem(
        id: 'config_$i',
        title: configItems[i],
        description: 'Configuration setting',
        type: SearchType.config,
        metadata: {'section': 'terminal'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = configItems[i].toLowerCase().split(':');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.config && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.config;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Code symbol search provider
class CodeSymbolProvider extends SearchProvider {
  @override
  String get id => 'symbols';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.symbol, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing code symbols
    final symbols = [
      'class TerminalSession',
      'function executeCommand',
      'variable currentDirectory',
      'enum SearchType',
    ];
    
    for (int i = 0; i < symbols.length; i++) {
      final item = SearchItem(
        id: 'symbol_$i',
        title: symbols[i],
        description: 'Code symbol',
        type: SearchType.symbol,
        metadata: {'file': 'lib/main.dart'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = symbols[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.symbol && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.symbol;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Bookmark search provider
class BookmarkProvider extends SearchProvider {
  @override
  String get id => 'bookmarks';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.bookmark, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing bookmarks
    final bookmarks = [
      'Project Root',
      'Configuration File',
      'Documentation',
      'Test Directory',
    ];
    
    for (int i = 0; i < bookmarks.length; i++) {
      final item = SearchItem(
        id: 'bookmark_$i',
        title: bookmarks[i],
        description: 'Bookmark location',
        type: SearchType.bookmark,
        metadata: {'path': '/path/to/location'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = bookmarks[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.bookmark && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.bookmark;
  }
  
  @override
  Future<void> dispose() async {}
}

/// Command search provider
class CommandProvider extends SearchProvider {
  @override
  String get id => 'commands';
  
  @override
  List<SearchType> get supportedTypes => [SearchType.command, SearchType.all];
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<SearchIndex> buildIndex() async {
    final items = <String, SearchItem>{};
    final invertedIndex = <String, List<String>>{};
    
    // Simulate indexing available commands
    final commands = [
      'git status',
      'npm install',
      'docker run',
      'flutter build',
      'cargo test',
      'python -m venv venv',
      'vim ~/.bashrc',
      'systemctl restart nginx',
    ];
    
    for (int i = 0; i < commands.length; i++) {
      final item = SearchItem(
        id: 'cmd_$i',
        title: commands[i],
        description: 'Available command',
        type: SearchType.command,
        metadata: {'source': 'command_palette'},
      );
      
      items[item.id] = item;
      
      // Update inverted index
      final words = commands[i].toLowerCase().split(' ');
      for (final word in words) {
        invertedIndex.putIfAbsent(word, () => []).add(item.id);
      }
    }
    
    return SearchIndex(
      providerId: id,
      items: items,
      invertedIndex: invertedIndex,
      itemCount: items.length,
      lastUpdated: DateTime.now(),
    );
  }
  
  @override
  Future<List<SearchResult>> search(SearchIndex index, SearchRequest request) async {
    final results = <SearchResult>[];
    final queryWords = request.query.toLowerCase().split(' ');
    
    for (final item in index.items.values) {
      if (item.type != SearchType.command && request.type != SearchType.all) {
        continue;
      }
      
      double relevance = 0.0;
      final itemText = (item.title + ' ' + item.description).toLowerCase();
      
      for (final word in queryWords) {
        if (itemText.contains(word)) {
          relevance += 1.0 / queryWords.length;
        }
      }
      
      if (relevance > 0.1) {
        results.add(SearchResult(
          id: item.id,
          type: item.type,
          title: item.title,
          description: item.description,
          relevance: relevance,
          timestamp: DateTime.now(),
          metadata: item.metadata,
        ));
      }
    }
    
    return results;
  }
  
  @override
  Future<void> addToIndex(SearchIndex index, SearchItem item) async {
    index.addItem(item);
  }
  
  @override
  Future<void> removeFromIndex(SearchIndex index, String itemId) async {
    index.removeItem(itemId);
  }
  
  @override
  bool canIndex(SearchItem item) {
    return item.type == SearchType.command;
  }
  
  @override
  Future<void> dispose() async {}
}
