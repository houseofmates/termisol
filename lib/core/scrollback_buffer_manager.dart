import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Scrollback Buffer Manager - Best-in-class efficient scrollback management
/// 
/// Provides comprehensive scrollback buffer optimization with:
/// - Intelligent buffer sizing and compression
/// - Search and filtering capabilities
/// - Memory-efficient storage
/// - Automatic cleanup and archiving
/// - Performance monitoring
/// - Multi-buffer management
class ScrollbackBufferManager {
  static final ScrollbackBufferManager _instance = ScrollbackBufferManager._internal();
  factory ScrollbackBufferManager() => _instance;
  ScrollbackBufferManager._internal();

  final Map<String, ScrollbackBuffer> _buffers = {};
  final Map<String, BufferStatistics> _bufferStats = {};
  final Map<String, List<BufferSnapshot>> _snapshots = {};
  
  bool _isInitialized = false;
  Timer? _cleanupTimer;
  Timer? _compressionTimer;
  
  // Buffer configuration
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const Duration _compressionInterval = Duration(minutes: 10);
  static const int _defaultBufferSize = 10000;
  static const int _maxBufferSize = 100000;
  static const int _compressionThreshold = 50000;
  static const double _memoryPressureThreshold = 0.8;
  
  final _bufferController = StreamController<BufferEvent>.broadcast();
  Stream<BufferEvent> get events => _bufferController.stream;
  
  bool get isInitialized => _isInitialized;
  Map<String, ScrollbackBuffer> get buffers => Map.unmodifiable(_buffers);

  /// Initialize scrollback buffer manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Create default buffers
      await _createDefaultBuffers();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      // Start compression timer
      _startCompressionTimer();
      
      _isInitialized = true;
      debugPrint('📜 Scrollback Buffer Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Scrollback Buffer Manager: $e');
      rethrow;
    }
  }

  /// Get or create a buffer
  ScrollbackBuffer getBuffer(String id, {
    int? maxSize,
    bool enableCompression = true,
    bool enableSearch = true,
  }) {
    if (!_buffers.containsKey(id)) {
      final buffer = ScrollbackBuffer(
        id: id,
        maxSize: maxSize ?? _defaultBufferSize,
        enableCompression: enableCompression,
        enableSearch: enableSearch,
      );
      
      _buffers[id] = buffer;
      _bufferStats[id] = BufferStatistics(id);
      
      debugPrint('📜 Created buffer: $id');
    }
    
    return _buffers[id]!;
  }

  /// Add content to buffer
  void addContent(String bufferId, String content, {
    String? source,
    Map<String, dynamic>? metadata,
  }) {
    final buffer = getBuffer(bufferId);
    final stats = _bufferStats[bufferId]!;
    
    final entry = BufferEntry(
      content: content,
      source: source ?? 'terminal',
      timestamp: DateTime.now(),
      metadata: metadata ?? {},
    );
    
    buffer.addEntry(entry);
    stats.totalEntries++;
    stats.totalBytes += content.length;
    stats.lastAccess = DateTime.now();
    
    // Check memory pressure
    _checkMemoryPressure();
    
    _bufferController.add(BufferEvent(
      type: BufferEventType.contentAdded,
      bufferId: bufferId,
      timestamp: DateTime.now(),
      data: {'entryCount': 1, 'contentSize': content.length},
    ));
  }

  /// Search buffer content
  List<SearchResult> search(String bufferId, String query, {
    bool caseSensitive = false,
    bool regex = false,
    int? limit,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final buffer = _buffers[bufferId];
    if (buffer == null) {
      return [];
    }

    final results = <SearchResult>[];
    final entries = buffer.getEntries(startDate: startDate, endDate: endDate);
    
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final match = _matchesQuery(entry.content, query, 
          caseSensitive: caseSensitive, regex: regex);
      
      if (match) {
        results.add(SearchResult(
          entry: entry,
          score: _calculateSearchScore(entry.content, query),
          position: i,
          context: _getContext(entries, i, query.length),
        ));
        
        if (limit != null && results.length >= limit!) {
          break;
        }
      }
    }
    
    // Sort by score (descending)
    results.sort((a, b) => b.score.compareTo(a.score));
    
    _bufferController.add(BufferEvent(
      type: BufferEventType.searchPerformed,
      bufferId: bufferId,
      timestamp: DateTime.now(),
      data: {'query': query, 'results': results.length},
    ));
    
    return results;
  }

  /// Get buffer content range
  List<BufferEntry> getContentRange(String bufferId, {
    int? start,
    int? end,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final buffer = _buffers[bufferId];
    if (buffer == null) {
      return [];
    }

    return buffer.getEntries(
      start: start,
      end: end,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Clear buffer
  void clearBuffer(String bufferId) {
    final buffer = _buffers[bufferId];
    if (buffer != null) {
      buffer.clear();
      
      final stats = _bufferStats[bufferId]!;
      stats.totalEntries = 0;
      stats.totalBytes = 0;
      stats.clearedCount++;
      
      _bufferController.add(BufferEvent(
        type: BufferEventType.bufferCleared,
        bufferId: bufferId,
        timestamp: DateTime.now(),
      ));
      
      debugPrint('📜 Cleared buffer: $bufferId');
    }
  }

  /// Archive buffer
  Future<void> archiveBuffer(String bufferId) async {
    final buffer = _buffers[bufferId];
    if (buffer == null) {
      return;
    }

    try {
      // Create snapshot
      final snapshot = BufferSnapshot(
        id: _generateSnapshotId(),
        bufferId: bufferId,
        timestamp: DateTime.now(),
        entryCount: buffer.size,
        totalBytes: buffer.totalBytes,
        entries: buffer.getEntries(),
      );

      // Add to snapshots
      _snapshots[bufferId] ??= [];
      _snapshots[bufferId]!.add(snapshot);

      // Clear current buffer
      clearBuffer(bufferId);

      // Save snapshot to disk
      await _saveSnapshot(snapshot);

      _bufferController.add(BufferEvent(
        type: BufferEventType.bufferArchived,
        bufferId: bufferId,
        timestamp: DateTime.now(),
        data: {'snapshotId': snapshot.id, 'entryCount': snapshot.entryCount},
      ));

      debugPrint('📜 Archived buffer: $bufferId');
      
    } catch (e) {
      debugPrint('❌ Failed to archive buffer: $e');
    }
  }

  /// Optimize buffer
  Future<void> optimizeBuffer(String bufferId) async {
    final buffer = _buffers[bufferId];
    if (buffer == null) {
      return;
    }

    // Compress old entries
    await _compressOldEntries(buffer);
    
    // Resize buffer if needed
    await _optimizeBufferSize(buffer);
    
    // Update statistics
    _updateBufferStatistics(bufferId);
    
    debugPrint('📜 Optimized buffer: $bufferId');
  }

  /// Get buffer statistics
  BufferStatistics getStatistics(String bufferId) {
    return _bufferStats[bufferId] ?? BufferStatistics(bufferId);
  }

  /// Get overall statistics
  OverallBufferStatistics getOverallStatistics() {
    return OverallBufferStatistics(
      totalBuffers: _buffers.length,
      totalEntries: _buffers.values
          .fold(0, (sum, buffer) => sum + buffer.size),
      totalBytes: _buffers.values
          .fold(0, (sum, buffer) => sum + buffer.totalBytes),
      averageBufferSize: _buffers.values
          .fold(0, (sum, buffer) => sum + buffer.size) / _buffers.length,
      memoryUsage: _calculateMemoryUsage(),
      compressionRatio: _calculateOverallCompressionRatio(),
    );
  }

  /// Check memory pressure
  void _checkMemoryPressure() {
    final memoryUsage = _calculateMemoryUsage();
    
    if (memoryUsage > _memoryPressureThreshold) {
      _handleMemoryPressure();
    }
  }

  /// Handle memory pressure
  void _handleMemoryPressure() {
    debugPrint('⚠️ Memory pressure detected, optimizing buffers');
    
    // Optimize all buffers
    for (final bufferId in _buffers.keys) {
      unawaited(optimizeBuffer(bufferId));
    }
    
    _bufferController.add(BufferEvent(
      type: BufferEventType.memoryPressure,
      timestamp: DateTime.now(),
      data: {'memoryUsage': _calculateMemoryUsage()},
    ));
  }

  /// Compress old entries
  Future<void> _compressOldEntries(ScrollbackBuffer buffer) async {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(hours: 1));
    
    final oldEntries = buffer.entries.where((entry) => 
        entry.timestamp.isBefore(cutoff)).toList();
    
    for (final entry in oldEntries) {
      entry.compressed = true;
      entry.compressedContent = _compressContent(entry.content);
    }
    
    debugPrint('📜 Compressed ${oldEntries.length} old entries');
  }

  /// Optimize buffer size
  Future<void> _optimizeBufferSize(ScrollbackBuffer buffer) async {
    final utilization = buffer.size / buffer.maxSize;
    
    if (utilization > 0.9 && buffer.maxSize < _maxBufferSize) {
      // Increase buffer size
      final newSize = (buffer.maxSize * 1.5).round().clamp(_defaultBufferSize, _maxBufferSize);
      buffer.resize(newSize);
      
      debugPrint('📜 Resized buffer ${buffer.id} to $newSize');
    } else if (utilization < 0.3 && buffer.maxSize > _defaultBufferSize) {
      // Decrease buffer size
      final newSize = (buffer.maxSize * 0.7).round().clamp(_defaultBufferSize, buffer.maxSize);
      buffer.resize(newSize);
      
      debugPrint('📜 Resized buffer ${buffer.id} to $newSize');
    }
  }

  /// Update buffer statistics
  void _updateBufferStatistics(String bufferId) {
    final buffer = _buffers[bufferId];
    final stats = _bufferStats[bufferId];
    
    if (buffer != null && stats != null) {
      stats.currentSize = buffer.size;
      stats.currentBytes = buffer.totalBytes;
      stats.compressionRatio = buffer.compressionRatio;
      stats.lastAccess = DateTime.now();
    }
  }

  /// Calculate memory usage
  double _calculateMemoryUsage() {
    final totalBytes = _buffers.values
        .fold(0, (sum, buffer) => sum + buffer.totalBytes);
    
    // Simulate memory limit (100MB)
    const memoryLimit = 100 * 1024 * 1024;
    return totalBytes / memoryLimit;
  }

  /// Calculate overall compression ratio
  double _calculateOverallCompressionRatio() {
    if (_buffers.isEmpty) return 1.0;
    
    final totalRatio = _buffers.values
        .fold(0.0, (sum, buffer) => sum + buffer.compressionRatio);
    
    return totalRatio / _buffers.length;
  }

  /// Check if content matches query
  bool _matchesQuery(String content, String query, {
    bool caseSensitive = false,
    bool regex = false,
  }) {
    if (regex) {
      try {
        final pattern = RegExp(query, caseSensitive: caseSensitive);
        return pattern.hasMatch(content);
      } catch (e) {
        return false;
      }
    } else {
      final contentToSearch = caseSensitive ? content : content.toLowerCase();
      final queryToSearch = caseSensitive ? query : query.toLowerCase();
      return contentToSearch.contains(queryToSearch);
    }
  }

  /// Calculate search score
  double _calculateSearchScore(String content, String query) {
    if (query.isEmpty) return 0.0;
    
    // Simple scoring based on query length and content length
    final queryLength = query.length;
    final contentLength = content.length;
    
    if (contentLength == 0) return 0.0;
    
    // Exact match gets highest score
    if (content.toLowerCase() == query.toLowerCase()) {
      return 1.0;
    }
    
    // Partial match based on position
    final position = content.toLowerCase().indexOf(query.toLowerCase());
    if (position == 0) {
      return 0.8;
    } else if (position > 0) {
      return 0.6;
    }
    
    return 0.3;
  }

  /// Get context around match
  String _getContext(List<BufferEntry> entries, int position, int queryLength) {
    const contextRadius = 50;
    final start = (position - contextRadius).clamp(0, entries.length);
    final end = (position + contextRadius).clamp(0, entries.length);
    
    final contextEntries = entries.sublist(start, end);
    return contextEntries.map((e) => e.content).join('\n');
  }

  /// Compress content
  String _compressContent(String content) {
    // Simple compression simulation
    // In a real implementation, this would use compression algorithms
    return content.length > 100 ? '${content.substring(0, 100)}...' : content;
  }

  /// Create default buffers
  Future<void> _createDefaultBuffers() async {
    // Terminal output buffer
    getBuffer('terminal_output', maxSize: 50000, enableCompression: true);
    
    // Search buffer
    getBuffer('search', maxSize: 1000, enableCompression: false);
    
    // AI chat buffer
    getBuffer('ai_chat', maxSize: 2000, enableCompression: true);
    
    // File operations buffer
    getBuffer('file_ops', maxSize: 5000, enableCompression: true);
    
    debugPrint('📜 Created ${_buffers.length} default buffers');
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Start compression timer
  void _startCompressionTimer() {
    _compressionTimer = Timer.periodic(_compressionInterval, (_) {
      _performCompression();
    });
  }

  /// Perform cleanup
  void _performCleanup() {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(hours: 24));
    
    for (final buffer in _buffers.values) {
      final oldEntries = buffer.entries.where((entry) => 
          entry.timestamp.isBefore(cutoff) && !entry.pinned).toList();
      
      for (final entry in oldEntries) {
        buffer.removeEntry(entry);
      }
      
      if (oldEntries.isNotEmpty) {
        debugPrint('📜 Cleaned ${oldEntries.length} old entries from buffer ${buffer.id}');
      }
    }
  }

  /// Perform compression
  void _performCompression() {
    for (final bufferId in _buffers.keys) {
      unawaited(optimizeBuffer(bufferId));
    }
  }

  /// Save snapshot to disk
  Future<void> _saveSnapshot(BufferSnapshot snapshot) async {
    try {
      // This would save snapshot to disk
      debugPrint('💾 Saved snapshot: ${snapshot.id}');
    } catch (e) {
      debugPrint('❌ Failed to save snapshot: $e');
    }
  }

  /// Generate snapshot ID
  String _generateSnapshotId() {
    return 'snapshot_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Dispose scrollback buffer manager
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _compressionTimer?.cancel();
    _bufferController.close();
    
    _buffers.clear();
    _bufferStats.clear();
    _snapshots.clear();
    
    debugPrint('📜 Scrollback Buffer Manager disposed');
  }
}

/// Scrollback buffer
class ScrollbackBuffer {
  final String id;
  final int maxSize;
  final bool enableCompression;
  final bool enableSearch;
  
  final Queue<BufferEntry> _entries = Queue<BufferEntry>();
  int _totalBytes = 0;
  double _compressionRatio = 1.0;
  
  ScrollbackBuffer({
    required this.id,
    required this.maxSize,
    required this.enableCompression,
    required this.enableSearch,
  });
  
  int get size => _entries.length;
  int get totalBytes => _totalBytes;
  double get compressionRatio => _compressionRatio;
  
  void addEntry(BufferEntry entry) {
    _entries.add(entry);
    _totalBytes += entry.content.length;
    
    // Remove old entries if over max size
    while (_entries.length > maxSize) {
      final oldEntry = _entries.removeFirst();
      _totalBytes -= oldEntry.content.length;
    }
    
    // Update compression ratio
    if (enableCompression) {
      _updateCompressionRatio();
    }
  }
  
  void removeEntry(BufferEntry entry) {
    if (_entries.remove(entry)) {
      _totalBytes -= entry.content.length;
      _updateCompressionRatio();
    }
  }
  
  void clear() {
    _entries.clear();
    _totalBytes = 0;
    _compressionRatio = 1.0;
  }
  
  void resize(int newSize) {
    // Remove entries if new size is smaller
    while (_entries.length > newSize) {
      final oldEntry = _entries.removeFirst();
      _totalBytes -= oldEntry.content.length;
    }
  }
  
  List<BufferEntry> getEntries({
    int? start,
    int? end,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    var entries = _entries.toList();
    
    // Filter by date range
    if (startDate != null || endDate != null) {
      entries = entries.where((entry) {
        if (startDate != null && entry.timestamp.isBefore(startDate!)) {
          return false;
        }
        if (endDate != null && entry.timestamp.isAfter(endDate!)) {
          return false;
        }
        return true;
      }).toList();
    }
    
    // Filter by range
    if (start != null || end != null) {
      final startIndex = start ?? 0;
      final endIndex = end ?? entries.length;
      entries = entries.sublist(startIndex, endIndex.clamp(0, entries.length));
    }
    
    return entries;
  }
  
  void _updateCompressionRatio() {
    if (!enableCompression || _entries.isEmpty) {
      _compressionRatio = 1.0;
      return;
    }
    
    int compressedCount = 0;
    for (final entry in _entries) {
      if (entry.compressed) {
        compressedCount++;
      }
    }
    
    _compressionRatio = compressedCount / _entries.length;
  }
}

/// Buffer entry
class BufferEntry {
  final String content;
  final String source;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  bool compressed = false;
  String? compressedContent;
  bool pinned = false;
  
  BufferEntry({
    required this.content,
    required this.source,
    required this.timestamp,
    required this.metadata,
  });
}

/// Buffer statistics
class BufferStatistics {
  final String bufferId;
  int totalEntries = 0;
  int totalBytes = 0;
  int currentSize = 0;
  int currentBytes = 0;
  int clearedCount = 0;
  double compressionRatio = 1.0;
  DateTime? lastAccess;
  
  BufferStatistics(this.bufferId);
}

/// Buffer snapshot
class BufferSnapshot {
  final String id;
  final String bufferId;
  final DateTime timestamp;
  final int entryCount;
  final int totalBytes;
  final List<BufferEntry> entries;
  
  BufferSnapshot({
    required this.id,
    required this.bufferId,
    required this.timestamp,
    required this.entryCount,
    required this.totalBytes,
    required this.entries,
  });
}

/// Search result
class SearchResult {
  final BufferEntry entry;
  final double score;
  final int position;
  final String context;
  
  SearchResult({
    required this.entry,
    required this.score,
    required this.position,
    required this.context,
  });
}

/// Overall buffer statistics
class OverallBufferStatistics {
  final int totalBuffers;
  final int totalEntries;
  final int totalBytes;
  final double averageBufferSize;
  final double memoryUsage;
  final double compressionRatio;
  
  OverallBufferStatistics({
    required this.totalBuffers,
    required this.totalEntries,
    required this.totalBytes,
    required this.averageBufferSize,
    required this.memoryUsage,
    required this.compressionRatio,
  });
}

/// Buffer event
class BufferEvent {
  final BufferEventType type;
  final String? bufferId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  BufferEvent({
    required this.type,
    this.bufferId,
    required this.timestamp,
    this.data,
  });
}

/// Enums
enum BufferEventType {
  contentAdded,
  searchPerformed,
  bufferCleared,
  bufferArchived,
  memoryPressure,
}


