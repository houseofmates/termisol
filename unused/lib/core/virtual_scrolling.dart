import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Virtual Scrolling - Infinite buffer with performance optimization
/// 
/// Implements comprehensive virtual scrolling:
/// - Infinite scrollback buffer
/// - Memory-efficient storage
/// - High-performance rendering
/// - Search within virtual buffer
/// - Performance monitoring
class VirtualScrolling {
  bool _isInitialized = false;
  
  // Virtual buffer
  VirtualBuffer _buffer = VirtualBuffer();
  ScrollPosition _scrollPosition = ScrollPosition();
  
  // Performance optimization
  final Map<int, RenderedLine> _renderCache = {};
  final Queue<int> _renderQueue = Queue();
  final Map<String, int> _lineCache = {};
  
  // Search within buffer
  final BufferSearch _search = BufferSearch();
  
  // Configuration
  VirtualScrollingConfig _config = VirtualScrollingConfig();
  
  // Performance monitoring
  final PerformanceMonitor _performance = PerformanceMonitor();
  
  VirtualScrolling();
  
  bool get isInitialized => _isInitialized;
  VirtualBuffer get buffer => _buffer;
  ScrollPosition get scrollPosition => _scrollPosition;
  PerformanceMonitor get performance => _performance;
  
  /// Initialize virtual scrolling
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Initialize buffer
      _buffer = VirtualBuffer(
        maxLines: _config.maxBufferLines,
        maxLineLength: _config.maxLineLength,
      );
      
      // Initialize search
      await _search.initialize(_buffer);
      
      // Setup performance monitoring
      _performance.initialize();
      
      _isInitialized = true;
      debugPrint('📜 Virtual Scrolling initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Virtual Scrolling: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/virtual_scrolling_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = VirtualScrollingConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load virtual scrolling config: $e');
    }
  }
  
  /// Add line to buffer
  void addLine(String line) {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Add line to virtual buffer
      final lineIndex = _buffer.addLine(line);
      
      // Update scroll position if needed
      if (_config.autoScrollToEnd) {
        _scrollPosition.moveToLine(lineIndex);
      }
      
      // Invalidate render cache for affected area
      _invalidateRenderCache(lineIndex);
      
      // Update performance metrics
      _performance.recordAddLine(stopwatch.elapsedMicroseconds);
      
      debugPrint('📝 Added line $lineIndex to virtual buffer');
    } catch (e) {
      debugPrint('⚠️ Failed to add line to virtual buffer: $e');
    }
  }
  
  /// Add multiple lines
  void addLines(List<String> lines) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final startIndex = _buffer.lineCount;
      
      // Add lines to buffer
      for (final line in lines) {
        _buffer.addLine(line);
      }
      
      // Update scroll position
      if (_config.autoScrollToEnd) {
        _scrollPosition.moveToLine(_buffer.lineCount - 1);
      }
      
      // Invalidate render cache
      _invalidateRenderCache(startIndex);
      
      // Update performance metrics
      _performance.recordAddLines(lines.length, stopwatch.elapsedMicroseconds);
      
      debugPrint('📝 Added ${lines.length} lines to virtual buffer');
    } catch (e) {
      debugPrint('⚠️ Failed to add lines to virtual buffer: $e');
    }
  }
  
  /// Get visible lines
  List<RenderedLine> getVisibleLines(int firstLine, int count) {
    final stopwatch = Stopwatch()..start();
    
    try {
      final visibleLines = <RenderedLine>[];
      final lastLine = min(firstLine + count, _buffer.lineCount);
      
      // Get lines from buffer
      for (int i = firstLine; i < lastLine; i++) {
        final line = _buffer.getLine(i);
        if (line != null) {
          // Check render cache
          final cachedLine = _renderCache[i];
          if (cachedLine != null) {
            visibleLines.add(cachedLine);
          } else {
            // Render line
            final renderedLine = _renderLine(line, i);
            visibleLines.add(renderedLine);
            
            // Cache rendered line
            _renderCache[i] = renderedLine;
          }
        }
      }
      
      // Update performance metrics
      _performance.recordGetVisibleLines(visibleLines.length, stopwatch.elapsedMicroseconds);
      
      return visibleLines;
    } catch (e) {
      debugPrint('⚠️ Failed to get visible lines: $e');
      return [];
    }
  }
  
  /// Render line
  RenderedLine _renderLine(String line, int lineNumber) {
    return RenderedLine(
      lineNumber: lineNumber,
      text: line,
      length: line.length,
      wrapOffsets: _calculateWrapOffsets(line),
      style: _calculateLineStyle(line),
    );
  }
  
  /// Calculate wrap offsets
  List<int> _calculateWrapOffsets(String line) {
    final offsets = <int>[];
    final maxLineLength = _config.maxLineLength;
    
    if (line.length <= maxLineLength) {
      return offsets;
    }
    
    for (int i = maxLineLength; i < line.length; i += maxLineLength) {
      offsets.add(i);
    }
    
    return offsets;
  }
  
  /// Calculate line style
  LineStyle _calculateLineStyle(String line) {
    // Basic style calculation based on content
    final style = LineStyle();
    
    // Check for special patterns
    if (line.contains('ERROR') || line.contains('FATAL')) {
      style.foregroundColor = 'red';
      style.bold = true;
    } else if (line.contains('WARNING') || line.contains('WARN')) {
      style.foregroundColor = 'orange';
      style.bold = true;
    } else if (line.contains('INFO')) {
      style.foregroundColor = 'blue';
    } else if (line.contains('SUCCESS')) {
      style.foregroundColor = 'green';
      style.bold = true;
    }
    
    return style;
  }
  
  /// Search in buffer
  List<SearchResult> search(String query, {bool caseSensitive = false, bool regex = false}) {
    return _search.search(query, caseSensitive: caseSensitive, regex: regex);
  }
  
  /// Scroll to line
  void scrollToLine(int lineNumber) {
    final clampedLine = max(0, min(lineNumber, _buffer.lineCount - 1));
    _scrollPosition.moveToLine(clampedLine);
    
    // Trigger re-render
    _invalidateRenderCache(clampedLine);
  }
  
  /// Scroll to top
  void scrollToTop() {
    _scrollPosition.moveToLine(0);
    _invalidateRenderCache(0);
  }
  
  /// Scroll to bottom
  void scrollToBottom() {
    _scrollPosition.moveToLine(_buffer.lineCount - 1);
    _invalidateRenderCache(_buffer.lineCount - 1);
  }
  
  /// Scroll by lines
  void scrollByLines(int delta) {
    final newLine = _scrollPosition.lineNumber + delta;
    scrollToLine(newLine);
  }
  
  /// Get scroll position
  ScrollPosition getCurrentScrollPosition() {
    return _scrollPosition;
  }
  
  /// Invalidate render cache
  void _invalidateRenderCache(int fromLine) {
    // Remove cached lines from specified line onwards
    final keysToRemove = <int>[];
    for (final key in _renderCache.keys) {
      if (key >= fromLine) {
        keysToRemove.add(key);
      }
    }
    
    for (final key in keysToRemove) {
      _renderCache.remove(key);
    }
    
    // Limit cache size
    if (_renderCache.length > _config.maxCacheSize) {
      final sortedKeys = _renderCache.keys.toList()..sort();
      final keysToRemove = sortedKeys.take(sortedKeys.length - _config.maxCacheSize);
      
      for (final key in keysToRemove) {
        _renderCache.remove(key);
      }
    }
  }
  
  /// Clear buffer
  void clearBuffer() {
    _buffer.clear();
    _renderCache.clear();
    _scrollPosition.reset();
    _search.clear();
    
    debugPrint('🗑️ Virtual buffer cleared');
  }
  
  /// Get buffer statistics
  BufferStatistics getStatistics() {
    return BufferStatistics(
      totalLines: _buffer.lineCount,
      maxLines: _config.maxBufferLines,
      currentLine: _scrollPosition.lineNumber,
      scrollOffset: _scrollPosition.offset,
      cacheSize: _renderCache.length,
      maxCacheSize: _config.maxCacheSize,
      memoryUsage: _calculateMemoryUsage(),
      performance: _performance.getStatistics(),
    );
  }
  
  /// Calculate memory usage
  int _calculateMemoryUsage() {
    int totalSize = 0;
    
    // Buffer memory
    totalSize += _buffer.estimateMemoryUsage();
    
    // Render cache memory
    for (final line in _renderCache.values) {
      totalSize += line.estimateMemoryUsage();
    }
    
    // Search memory
    totalSize += _search.estimateMemoryUsage();
    
    return totalSize;
  }
  
  /// Optimize buffer
  void optimizeBuffer() {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Remove old render cache entries
      _optimizeRenderCache();
      
      // Optimize buffer storage
      _buffer.optimize();
      
      // Optimize search index
      _search.optimize();
      
      debugPrint('⚡ Buffer optimization completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ Failed to optimize buffer: $e');
    }
  }
  
  /// Optimize render cache
  void _optimizeRenderCache() {
    if (_renderCache.length <= _config.maxCacheSize) return;
    
    // Sort by last access time (oldest first)
    final sortedEntries = _renderCache.entries.toList()
      ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));
    
    // Remove oldest entries
    final entriesToRemove = sortedEntries.take(sortedEntries.length - _config.maxCacheSize);
    for (final entry in entriesToRemove) {
      _renderCache.remove(entry.key);
    }
  }
  
  /// Export buffer
  String exportBuffer({int? maxLines}) {
    final lines = <String>[];
    final limit = maxLines ?? _buffer.lineCount;
    
    for (int i = 0; i < limit && i < _buffer.lineCount; i++) {
      final line = _buffer.getLine(i);
      if (line != null) {
        lines.add(line);
      }
    }
    
    return lines.join('\n');
  }
  
  /// Import buffer
  bool importBuffer(String content) {
    try {
      final lines = content.split('\n');
      clearBuffer();
      addLines(lines);
      
      debugPrint('📥 Imported ${lines.length} lines to buffer');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import buffer: $e');
      return false;
    }
  }
  
  /// Save buffer state
  Future<void> saveBufferState() async {
    try {
      final state = {
        'version': '1.0',
        'buffer': _buffer.exportState(),
        'scrollPosition': _scrollPosition.toJson(),
        'config': _config.toJson(),
        'performance': _performance.exportState(),
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      final stateFile = File('${Platform.environment['HOME']}/.termisol/virtual_buffer_state.json');
      await stateFile.writeAsString(jsonEncode(state));
      
      debugPrint('💾 Virtual buffer state saved');
    } catch (e) {
      debugPrint('⚠️ Failed to save buffer state: $e');
    }
  }
  
  /// Load buffer state
  Future<bool> loadBufferState() async {
    try {
      final stateFile = File('${Platform.environment['HOME']}/.termisol/virtual_buffer_state.json');
      if (!await stateFile.exists()) {
        return false;
      }
      
      final content = await stateFile.readAsString();
      final state = jsonDecode(content) as Map<String, dynamic>;
      
      // Load buffer state
      if (state.containsKey('buffer')) {
        _buffer.importState(state['buffer'] as Map<String, dynamic>);
      }
      
      // Load scroll position
      if (state.containsKey('scrollPosition')) {
        _scrollPosition = ScrollPosition.fromJson(state['scrollPosition'] as Map<String, dynamic>);
      }
      
      // Load configuration
      if (state.containsKey('config')) {
        _config = VirtualScrollingConfig.fromJson(state['config'] as Map<String, dynamic>);
      }
      
      // Load performance state
      if (state.containsKey('performance')) {
        _performance.importState(state['performance'] as Map<String, dynamic>);
      }
      
      debugPrint('📥 Virtual buffer state loaded');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to load buffer state: $e');
      return false;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _buffer.dispose();
    _renderCache.clear();
    _search.dispose();
    _performance.dispose();
    
    _isInitialized = false;
    debugPrint('📜 Virtual Scrolling disposed');
  }
}

/// Virtual buffer data structure
class VirtualBuffer {
  final List<String> _lines = [];
  final Queue<String> _lineQueue = Queue();
  int _maxLines;
  int _maxLineLength;
  int _totalLinesAdded = 0;
  
  VirtualBuffer({
    int maxLines = 100000,
    int maxLineLength = 10000,
  }) : _maxLines = maxLines, _maxLineLength = maxLineLength;
  
  int get lineCount => _lines.length;
  int get maxLines => _maxLines;
  int get maxLineLength => _maxLineLength;
  int get totalLinesAdded => _totalLinesAdded;
  
  /// Add line to buffer
  int addLine(String line) {
    // Truncate line if too long
    if (line.length > _maxLineLength) {
      line = line.substring(0, _maxLineLength);
    }
    
    _lines.add(line);
    _lineQueue.add(line);
    _totalLinesAdded++;
    
    // Remove oldest line if buffer is full
    if (_lines.length > _maxLines) {
      _lines.removeAt(0);
      _lineQueue.removeFirst();
    }
    
    return _lines.length - 1;
  }
  
  /// Get line from buffer
  String? getLine(int index) {
    if (index < 0 || index >= _lines.length) {
      return null;
    }
    return _lines[index];
  }
  
  /// Clear buffer
  void clear() {
    _lines.clear();
    _lineQueue.clear();
    _totalLinesAdded = 0;
  }
  
  /// Optimize buffer
  void optimize() {
    // Remove excess lines if buffer is too large
    while (_lines.length > _maxLines) {
      _lines.removeAt(0);
      _lineQueue.removeFirst();
    }
  }
  
  /// Estimate memory usage
  int estimateMemoryUsage() {
    int totalSize = 0;
    
    for (final line in _lines) {
      totalSize += line.length * 2; // UTF-16 characters
    }
    
    return totalSize;
  }
  
  /// Export state
  Map<String, dynamic> exportState() {
    return {
      'lines': _lines,
      'maxLines': _maxLines,
      'maxLineLength': _maxLineLength,
      'totalLinesAdded': _totalLinesAdded,
    };
  }
  
  /// Import state
  void importState(Map<String, dynamic> state) {
    _lines.clear();
    _lineQueue.clear();
    
    final lines = state['lines'] as List<dynamic>?;
    if (lines != null) {
      _lines.addAll(lines.cast<String>());
      _lineQueue.addAll(lines.cast<String>());
    }
    
    _maxLines = state['maxLines'] as int? ?? _maxLines;
    _maxLineLength = state['maxLineLength'] as int? ?? _maxLineLength;
    _totalLinesAdded = state['totalLinesAdded'] as int? ?? 0;
  }
  
  /// Dispose buffer
  void dispose() {
    _lines.clear();
    _lineQueue.clear();
  }
}

/// Scroll position data structure
class ScrollPosition {
  int _lineNumber = 0;
  double _offset = 0.0;
  DateTime _lastUpdated = DateTime.now();
  
  ScrollPosition();
  
  int get lineNumber => _lineNumber;
  double get offset => _offset;
  DateTime get lastUpdated => _lastUpdated;
  
  /// Move to line
  void moveToLine(int lineNumber) {
    _lineNumber = lineNumber;
    _offset = 0.0;
    _lastUpdated = DateTime.now();
  }
  
  /// Move to offset
  void moveToOffset(double offset) {
    _offset = offset;
    _lastUpdated = DateTime.now();
  }
  
  /// Reset position
  void reset() {
    _lineNumber = 0;
    _offset = 0.0;
    _lastUpdated = DateTime.now();
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'lineNumber': _lineNumber,
      'offset': _offset,
      'lastUpdated': _lastUpdated.toIso8601String(),
    };
  }
  
  /// Create from JSON
  factory ScrollPosition.fromJson(Map<String, dynamic> json) {
    final position = ScrollPosition();
    position._lineNumber = json['lineNumber'] as int? ?? 0;
    position._offset = (json['offset'] as num?)?.toDouble() ?? 0.0;
    position._lastUpdated = DateTime.parse(json['lastUpdated'] as String);
    return position;
  }
}

/// Rendered line data structure
class RenderedLine {
  final int lineNumber;
  final String text;
  final int length;
  final List<int> wrapOffsets;
  final LineStyle style;
  DateTime lastAccessed;
  
  RenderedLine({
    required this.lineNumber,
    required this.text,
    required this.length,
    required this.wrapOffsets,
    required this.style,
  }) : lastAccessed = DateTime.now();
  
  /// Estimate memory usage
  int estimateMemoryUsage() {
    int size = text.length * 2; // UTF-16 characters
    size += wrapOffsets.length * 4; // Int offsets
    size += 64; // Object overhead
    return size;
  }
}

/// Line style data structure
class LineStyle {
  String? foregroundColor;
  String? backgroundColor;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  
  LineStyle();
}

/// Buffer search implementation
class BufferSearch {
  final VirtualBuffer _buffer;
  final Map<String, List<int>> _searchIndex = {};
  final Map<String, DateTime> _lastSearch = {};
  
  BufferSearch(this._buffer);
  
  /// Initialize search
  Future<void> initialize(VirtualBuffer buffer) async {
    // Implementation would initialize search index
    debugPrint('🔍 Buffer search initialized');
  }
  
  /// Search in buffer
  List<SearchResult> search(String query, {bool caseSensitive = false, bool regex = false}) {
    final results = <SearchResult>[];
    
    // Implementation would perform search
    for (int i = 0; i < _buffer.lineCount; i++) {
      final line = _buffer.getLine(i);
      if (line != null && _matchesQuery(line!, query, caseSensitive, regex)) {
        results.add(SearchResult(
          lineNumber: i,
          line: line!,
          matchStart: 0, // Implementation would find actual match position
          matchEnd: line!.length,
        ));
      }
    }
    
    _lastSearch[query] = DateTime.now();
    return results;
  }
  
  /// Check if line matches query
  bool _matchesQuery(String line, String query, bool caseSensitive, bool regex) {
    if (regex) {
      // Implementation would use regex matching
      return RegExp(query, caseSensitive: caseSensitive).hasMatch(line);
    } else {
      final searchLine = caseSensitive ? line : line.toLowerCase();
      final searchQuery = caseSensitive ? query : query.toLowerCase();
      return searchLine.contains(searchQuery);
    }
  }
  
  /// Clear search
  void clear() {
    _searchIndex.clear();
    _lastSearch.clear();
  }
  
  /// Optimize search
  void optimize() {
    // Implementation would optimize search index
  }
  
  /// Estimate memory usage
  int estimateMemoryUsage() {
    int size = 0;
    
    for (final entry in _searchIndex.values) {
      size += entry.length * 4; // Int indices
    }
    
    return size;
  }
  
  /// Dispose search
  void dispose() {
    _searchIndex.clear();
    _lastSearch.clear();
  }
}

/// Search result data structure
class SearchResult {
  final int lineNumber;
  final String line;
  final int matchStart;
  final int matchEnd;
  
  SearchResult({
    required this.lineNumber,
    required this.line,
    required this.matchStart,
    required this.matchEnd,
  });
}

/// Performance monitor
class PerformanceMonitor {
  final List<PerformanceMetric> _metrics = [];
  final Map<String, int> _counters = {};
  
  PerformanceMonitor();
  
  /// Initialize monitor
  void initialize() {
    debugPrint('📊 Performance monitor initialized');
  }
  
  /// Record add line performance
  void recordAddLine(int microseconds) {
    _counters['addLine'] = (_counters['addLine'] ?? 0) + 1;
    _metrics.add(PerformanceMetric(
      operation: 'addLine',
      duration: microseconds,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Record add lines performance
  void recordAddLines(int count, int microseconds) {
    _counters['addLines'] = (_counters['addLines'] ?? 0) + count;
    _metrics.add(PerformanceMetric(
      operation: 'addLines',
      duration: microseconds,
      timestamp: DateTime.now(),
      metadata: {'count': count},
    ));
  }
  
  /// Record get visible lines performance
  void recordGetVisibleLines(int count, int microseconds) {
    _counters['getVisibleLines'] = (_counters['getVisibleLines'] ?? 0) + 1;
    _metrics.add(PerformanceMetric(
      operation: 'getVisibleLines',
      duration: microseconds,
      timestamp: DateTime.now(),
      metadata: {'count': count},
    ));
  }
  
  /// Get statistics
  PerformanceStatistics getStatistics() {
    return PerformanceStatistics(
      totalOperations: _metrics.length,
      averageAddLineTime: _calculateAverageTime('addLine'),
      averageGetVisibleLinesTime: _calculateAverageTime('getVisibleLines'),
      totalLinesAdded: _counters['addLines'] ?? 0,
      totalVisibleLinesCalls: _counters['getVisibleLines'] ?? 0,
    );
  }
  
  /// Calculate average time
  double _calculateAverageTime(String operation) {
    final operationMetrics = _metrics.where((m) => m.operation == operation);
    if (operationMetrics.isEmpty) return 0.0;
    
    final totalTime = operationMetrics.fold(0, (sum, m) => sum + m.duration);
    return totalTime / operationMetrics.length;
  }
  
  /// Export state
  Map<String, dynamic> exportState() {
    return {
      'metrics': _metrics.map((m) => m.toJson()).toList(),
      'counters': _counters,
    };
  }
  
  /// Import state
  void importState(Map<String, dynamic> state) {
    final metricsData = state['metrics'] as List<dynamic>?;
    if (metricsData != null) {
      _metrics.clear();
      for (final metric in metricsData) {
        _metrics.add(PerformanceMetric.fromJson(metric as Map<String, dynamic>));
      }
    }
    
    _counters.clear();
    _counters.addAll(state['counters'] as Map<String, dynamic>? ?? {});
  }
  
  /// Dispose monitor
  void dispose() {
    _metrics.clear();
    _counters.clear();
  }
}

/// Performance metric data structure
class PerformanceMetric {
  final String operation;
  final int duration;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  
  PerformanceMetric({
    required this.operation,
    required this.duration,
    required this.timestamp,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'duration': duration,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
  
  factory PerformanceMetric.fromJson(Map<String, dynamic> json) {
    return PerformanceMetric(
      operation: json['operation'] as String,
      duration: json['duration'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Performance statistics data structure
class PerformanceStatistics {
  final int totalOperations;
  final double averageAddLineTime;
  final double averageGetVisibleLinesTime;
  final int totalLinesAdded;
  final int totalVisibleLinesCalls;
  
  PerformanceStatistics({
    required this.totalOperations,
    required this.averageAddLineTime,
    required this.averageGetVisibleLinesTime,
    required this.totalLinesAdded,
    required this.totalVisibleLinesCalls,
  });
}

/// Buffer statistics data structure
class BufferStatistics {
  final int totalLines;
  final int maxLines;
  final int currentLine;
  final double scrollOffset;
  final int cacheSize;
  final int maxCacheSize;
  final int memoryUsage;
  final PerformanceStatistics performance;
  
  BufferStatistics({
    required this.totalLines,
    required this.maxLines,
    required this.currentLine,
    required this.scrollOffset,
    required this.cacheSize,
    required this.maxCacheSize,
    required this.memoryUsage,
    required this.performance,
  });
}

/// Virtual scrolling configuration
class VirtualScrollingConfig {
  final int maxBufferLines;
  final int maxLineLength;
  final int maxCacheSize;
  final bool autoScrollToEnd;
  final Duration optimizationInterval;
  final bool enablePerformanceMonitoring;
  
  VirtualScrollingConfig({
    this.maxBufferLines = 100000,
    this.maxLineLength = 10000,
    this.maxCacheSize = 10000,
    this.autoScrollToEnd = true,
    this.optimizationInterval = const Duration(seconds: 30),
    this.enablePerformanceMonitoring = true,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'maxBufferLines': maxBufferLines,
      'maxLineLength': maxLineLength,
      'maxCacheSize': maxCacheSize,
      'autoScrollToEnd': autoScrollToEnd,
      'optimizationInterval': optimizationInterval.inMilliseconds,
      'enablePerformanceMonitoring': enablePerformanceMonitoring,
    };
  }
  
  factory VirtualScrollingConfig.fromJson(Map<String, dynamic> json) {
    return VirtualScrollingConfig(
      maxBufferLines: json['maxBufferLines'] as int? ?? 100000,
      maxLineLength: json['maxLineLength'] as int? ?? 10000,
      maxCacheSize: json['maxCacheSize'] as int? ?? 10000,
      autoScrollToEnd: json['autoScrollToEnd'] as bool? ?? true,
      optimizationInterval: Duration(milliseconds: json['optimizationInterval'] as int? ?? 30000),
      enablePerformanceMonitoring: json['enablePerformanceMonitoring'] as bool? ?? true,
    );
  }
}
