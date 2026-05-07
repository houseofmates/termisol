import 'dart:async';
import 'dart:developer' as developer;
import 'dart:collection';
import 'dart:math';

class LazyLoading {
  static const int _viewportBufferSize = 100; // Lines to buffer beyond viewport
  static const int _preloadDistance = 50; // Lines to preload ahead
  static const int _maxCacheSize = 10000; // Maximum cached lines
  static const Duration _cacheCleanupInterval = Duration(minutes: 5);
  
  final Map<String, LazyContentCache> _contentCaches = {};
  final Map<String, ViewportState> _viewports = {};
  final Queue<CacheCleanupTask> _cleanupQueue = Queue();
  
  Timer? _cleanupTimer;
  int _totalLinesLoaded = 0;
  int _totalCacheHits = 0;
  int _totalCacheMisses = 0;
  
  final StreamController<LazyLoadEvent> _loadController = 
      StreamController<LazyLoadEvent>.broadcast();

  void initialize() {
    _startCleanupTimer();
    developer.log('🔄 Lazy Loading initialized');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cacheCleanupInterval, (_) => _cleanupCaches());
  }

  Future<LazyLoadResult> loadContent(String contentId, {
    required int startLine,
    required int endLine,
    required int viewportHeight,
    required Function(List<String>) onContentLoaded,
    Map<String, dynamic>? metadata,
  }) async {
    final cache = _contentCaches.putIfAbsent(
      contentId,
      () => LazyContentCache(id: contentId),
    );
    
    // Update viewport state
    final viewport = ViewportState(
      startLine: startLine,
      endLine: endLine,
      height: viewportHeight,
      lastUpdated: DateTime.now(),
    );
    _viewports[contentId] = viewport;
    
    developer.log('🔄 Loading content: $contentId (lines $startLine-$endLine)');
    
    _emitEvent(LazyLoadEvent(
      type: LazyLoadEventType.started,
      contentId: contentId,
      startLine: startLine,
      endLine: endLine,
    ));
    
    try {
      // Check cache first
      final cachedLines = _getCachedLines(cache, startLine, endLine);
      if (cachedLines != null) {
        _totalCacheHits++;
        onContentLoaded(cachedLines);
        
        _emitEvent(LazyLoadEvent(
          type: LazyLoadEventType.cacheHit,
          contentId: contentId,
          linesLoaded: cachedLines.length,
        ));
        
        return LazyLoadResult(
          contentId: contentId,
          linesLoaded: cachedLines.length,
          fromCache: true,
          loadTime: Duration.zero,
        );
      }
      
      // Load from source
      final loadedLines = await _loadLinesFromSource(contentId, startLine, endLine, metadata);
      
      // Cache loaded lines
      _cacheLines(cache, loadedLines, startLine, endLine);
      _totalLinesLoaded += loadedLines.length;
      _totalCacheMisses++;
      
      onContentLoaded(loadedLines);
      
      _emitEvent(LazyLoadEvent(
        type: LazyLoadEventType.loaded,
        contentId: contentId,
        linesLoaded: loadedLines.length,
        fromCache: false,
      ));
      
      // Preload content ahead
      _preloadContent(contentId, endLine + 1, endLine + _preloadDistance, metadata);
      
      return LazyLoadResult(
        contentId: contentId,
        linesLoaded: loadedLines.length,
        fromCache: false,
        loadTime: Duration(milliseconds: _estimateLoadTime(loadedLines.length)),
      );
      
    } catch (e) {
      developer.log('🔄 Failed to load content: $contentId - $e');
      
      _emitEvent(LazyLoadEvent(
        type: LazyLoadEventType.error,
        contentId: contentId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  List<String>? _getCachedLines(LazyContentCache cache, int startLine, int endLine) {
    final lines = <String>[];
    
    for (int i = startLine; i <= endLine; i++) {
      final line = cache.getLine(i);
      if (line != null) {
        lines.add(line);
      } else {
        // Cache miss for this line
        return null;
      }
    }
    
    return lines;
  }

  Future<List<String>> _loadLinesFromSource(
    String contentId,
    int startLine,
    int endLine,
    Map<String, dynamic>? metadata,
  ) async {
    // Simulate loading from file or other source
    final lines = <String>[];
    
    for (int i = startLine; i <= endLine; i++) {
      // Simulate line generation
      final line = _generateLine(contentId, i, metadata);
      lines.add(line);
      
      // Simulate I/O delay
      if (i % 100 == 0) {
        await Future.delayed(Duration(milliseconds: 1));
      }
    }
    
    return lines;
  }

  String _generateLine(String contentId, int lineNumber, Map<String, dynamic>? metadata) {
    // Generate realistic line content based on content type
    switch (contentId) {
      case 'terminal':
        return 'Line $lineNumber: ${_generateTerminalContent(lineNumber)}';
      case 'log':
        return '${DateTime.now().toIso8601String()} [INFO] Log message line $lineNumber';
      case 'code':
        return _generateCodeLine(lineNumber, metadata);
      default:
        return 'Content line $lineNumber for $contentId';
    }
  }

  String _generateTerminalContent(int lineNumber) {
    final commands = [
      'ls -la',
      'cd /home/user',
      'git status',
      'npm run dev',
      'docker ps',
      'python script.py',
      'cargo build',
      'flutter run',
      'vim file.txt',
    ];
    
    final command = commands[lineNumber % commands.length];
    final prompt = 'user@hostname:~$ ';
    return '$prompt$command';
  }

  String _generateCodeLine(int lineNumber, Map<String, dynamic>? metadata) {
    final language = metadata?['language'] ?? 'dart';
    final indent = '  ' * (lineNumber ~/ 10);
    
    switch (language) {
      case 'dart':
        return '${indent}void function$lineNumber() {\\n${indent}  // TODO: implement\\n${indent}}';
      case 'python':
        return '${indent}def function$lineNumber():\\n${indent}    # TODO: implement\\n${indent}';
      case 'javascript':
        return '${indent}function function$lineNumber() {\\n${indent}  // TODO: implement\\n${indent}}';
      default:
        return '${indent}// Line $lineNumber';
    }
  }

  void _cacheLines(
    LazyContentCache cache,
    List<String> lines,
    int startLine,
    int endLine,
  ) {
    for (int i = 0; i < lines.length; i++) {
      final lineNumber = startLine + i;
      cache.setLine(lineNumber, lines[i]);
    }
    
    // Update cache metadata
    cache.lastAccessed = DateTime.now();
    cache.lineCount = max(cache.lineCount, endLine + 1);
    
    // Check cache size limit
    _enforceCacheSizeLimit(cache);
  }

  void _enforceCacheSizeLimit(LazyContentCache cache) {
    if (cache.lineCount > _maxCacheSize) {
      // Remove oldest lines (LRU eviction)
      final linesToRemove = cache.lineCount - _maxCacheSize;
      
      for (int i = 0; i < linesToRemove; i++) {
        cache.removeOldestLine();
      }
      
      developer.log('🔄 Evicted $linesToRemove old lines from cache');
    }
  }

  Future<void> _preloadContent(
    String contentId,
    int startLine,
    int endLine,
    Map<String, dynamic>? metadata,
  ) async {
    if (startLine >= endLine) return;
    
    // Check if already cached
    final cache = _contentCaches[contentId];
    if (cache == null) return;
    
    final uncachedLines = <int>[];
    for (int i = startLine; i < endLine; i++) {
      if (cache.getLine(i) == null) {
        uncachedLines.add(i);
      }
    }
    
    if (uncachedLines.isEmpty) return;
    
    // Load uncached lines in background
    Future.microtask(() async {
      try {
        final lines = await _loadLinesFromSource(contentId, startLine, endLine, metadata);
        _cacheLines(cache, lines, startLine, endLine);
        
        developer.log('🔄 Preloaded ${lines.length} lines for $contentId');
        
        _emitEvent(LazyLoadEvent(
          type: LazyLoadEventType.preloaded,
          contentId: contentId,
          linesLoaded: lines.length,
        ));
      } catch (e) {
        developer.log('🔄 Failed to preload content: $e');
      }
    });
  }

  Future<void> updateViewport(String contentId, {
    required int startLine,
    required int endLine,
    required int viewportHeight,
  }) async {
    final viewport = _viewports[contentId];
    if (viewport == null) return;
    
    final oldStart = viewport.startLine;
    final oldEnd = viewport.endLine;
    
    // Update viewport
    viewport.startLine = startLine;
    viewport.endLine = endLine;
    viewport.height = viewportHeight;
    viewport.lastUpdated = DateTime.now();
    
    // Load new content if viewport moved significantly
    if ((startLine - oldStart).abs() > _viewportBufferSize ||
        (endLine - oldEnd).abs() > _viewportBufferSize) {
      
      // Unload old content (outside buffer)
      _unloadContent(contentId, oldStart - _viewportBufferSize, oldEnd + _viewportBufferSize);
      
      // Load new content
      await loadContent(
        contentId,
        startLine: startLine - _preloadDistance,
        endLine: endLine + _preloadDistance,
        viewportHeight: viewportHeight,
        onContentLoaded: (lines) {}, // Callback handled by caller
      );
    }
  }

  void _unloadContent(String contentId, int startLine, int endLine) {
    final cache = _contentCaches[contentId];
    if (cache == null) return;
    
    // Remove lines outside the new viewport range
    for (int i = startLine; i <= endLine; i++) {
      cache.removeLine(i);
    }
    
    developer.log('🔄 Unloaded lines $startLine-$endLine for $contentId');
  }

  void clearCache(String contentId) {
    final cache = _contentCaches.remove(contentId);
    if (cache != null) {
      cache.clear();
      developer.log('🔄 Cleared cache for $contentId');
    }
  }

  void clearAllCaches() {
    for (final cache in _contentCaches.values) {
      cache.clear();
    }
    _contentCaches.clear();
    _viewports.clear();
    developer.log('🔄 Cleared all caches');
  }

  void _cleanupCaches() {
    final now = DateTime.now();
    final cachesToCleanup = <String>[];
    
    for (final entry in _contentCaches.entries) {
      final cache = entry.value;
      
      // Remove caches not accessed recently
      if (now.difference(cache.lastAccessed).inMinutes > 10) {
        cachesToCleanup.add(entry.key);
      }
      
      // Remove old lines from cache
      _removeOldLines(cache, now);
    }
    
    for (final contentId in cachesToCleanup) {
      clearCache(contentId);
    }
  }

  void _removeOldLines(LazyContentCache cache, DateTime now) {
    final maxAge = Duration(minutes: 5);
    final linesToRemove = <int>[];
    
    for (final entry in cache.lines.entries) {
      if (now.difference(entry.value.lastAccessed).compareTo(maxAge) > 0) {
        linesToRemove.add(entry.key);
      }
    }
    
    for (final lineNumber in linesToRemove) {
      cache.removeLine(lineNumber);
    }
    
    if (linesToRemove.isNotEmpty) {
      developer.log('🔄 Removed ${linesToRemove.length} old lines from cache');
    }
  }

  LazyLoadingStats getStats() {
    return LazyLoadingStats(
      totalLinesLoaded: _totalLinesLoaded,
      totalCacheHits: _totalCacheHits,
      totalCacheMisses: _totalCacheMisses,
      cacheHitRate: _totalCacheHits + _totalCacheMisses > 0 
          ? _totalCacheHits / (_totalCacheHits + _totalCacheMisses) 
          : 0.0,
      activeCaches: _contentCaches.length,
      totalCachedLines: _contentCaches.values
          .fold(0, (sum, cache) => sum + cache.lineCount),
      activeViewports: _viewports.length,
    );
  }

  ViewportState? getViewport(String contentId) {
    return _viewports[contentId];
  }

  LazyContentCache? getCache(String contentId) {
    return _contentCaches[contentId];
  }

  String _generateEventId() {
    return 'lazy_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(LazyLoadEvent event) {
    _loadController.add(event);
  }

  Stream<LazyLoadEvent> get loadEventStream => _loadController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    clearAllCaches();
    _cleanupQueue.clear();
    _loadController.close();
    developer.log('🔄 Lazy Loading disposed');
  }
}

class LazyContentCache {
  final String id;
  final Map<int, CachedLine> lines = {};
  int lineCount = 0;
  DateTime lastAccessed = DateTime.now();

  LazyContentCache({required this.id});

  String? getLine(int lineNumber) {
    final line = lines[lineNumber];
    if (line != null) {
      line.lastAccessed = DateTime.now();
      lastAccessed = DateTime.now();
    }
    return line?.content;
  }

  void setLine(int lineNumber, String content) {
    lines[lineNumber] = CachedLine(
      content: content,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
    );
    lineCount = max(lineCount, lineNumber + 1);
  }

  void removeLine(int lineNumber) {
    lines.remove(lineNumber);
  }

  void removeOldestLine() {
    if (lines.isEmpty) return;
    
    int oldestLine = lines.keys.first;
    DateTime oldestTime = lines[oldestLine]!.createdAt;
    
    for (final entry in lines.entries) {
      if (entry.value.createdAt.isBefore(oldestTime)) {
        oldestLine = entry.key;
        oldestTime = entry.value.createdAt;
      }
    }
    
    lines.remove(oldestLine);
  }

  void clear() {
    lines.clear();
    lineCount = 0;
  }
}

class CachedLine {
  final String content;
  final DateTime createdAt;
  DateTime lastAccessed;

  CachedLine({
    required this.content,
    required this.createdAt,
    required this.lastAccessed,
  });
}

class ViewportState {
  int startLine;
  int endLine;
  int height;
  DateTime lastUpdated;

  ViewportState({
    required this.startLine,
    required this.endLine,
    required this.height,
    required this.lastUpdated,
  });
}

class LazyLoadResult {
  final String contentId;
  final int linesLoaded;
  final bool fromCache;
  final Duration loadTime;

  LazyLoadResult({
    required this.contentId,
    required this.linesLoaded,
    required this.fromCache,
    required this.loadTime,
  });
}

enum LazyLoadEventType {
  started,
  loaded,
  cacheHit,
  preloaded,
  error,
  viewportUpdated,
}

class LazyLoadEvent {
  final LazyLoadEventType type;
  final String contentId;
  final int? startLine;
  final int? endLine;
  final int? linesLoaded;
  final bool? fromCache;
  final String? error;

  LazyLoadEvent({
    required this.type,
    required this.contentId,
    this.startLine,
    this.endLine,
    this.linesLoaded,
    this.fromCache,
    this.error,
  });
}

class CacheCleanupTask {
  final String contentId;
  final DateTime scheduledAt;
  final int linesToRemove;

  CacheCleanupTask({
    required this.contentId,
    required this.scheduledAt,
    required this.linesToRemove,
  });
}

class LazyLoadingStats {
  final int totalLinesLoaded;
  final int totalCacheHits;
  final int totalCacheMisses;
  final double cacheHitRate;
  final int activeCaches;
  final int totalCachedLines;
  final int activeViewports;

  LazyLoadingStats({
    required this.totalLinesLoaded,
    required this.totalCacheHits,
    required this.totalCacheMisses,
    required this.cacheHitRate,
    required this.activeCaches,
    required this.totalCachedLines,
    required this.activeViewports,
  });
}

int _estimateLoadTime(int lineCount) {
  // Estimate load time based on line count
  return (lineCount * 0.1).round(); // 0.1ms per line
}
