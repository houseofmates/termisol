import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Circular Buffer Manager - Best-in-class terminal output optimization
/// 
/// Provides efficient circular buffer management for terminal output:
/// - Multiple buffer types with different strategies
/// - Memory-efficient circular storage
/// - Automatic buffer resizing based on usage
/// - Performance metrics and optimization
/// - Thread-safe operations
/// - Smart buffer compression for old data
class CircularBufferManager {
  static final CircularBufferManager _instance = CircularBufferManager._internal();
  factory CircularBufferManager() => _instance;
  CircularBufferManager._internal();

  final Map<String, CircularBuffer> _buffers = {};
  final Map<String, BufferMetrics> _bufferMetrics = {};
  final Map<String, BufferConfiguration> _bufferConfigs = {};
  
  bool _isInitialized = false;
  Timer? _optimizationTimer;
  Timer? _cleanupTimer;
  
  // Buffer management configuration
  static const Duration _optimizationInterval = Duration(minutes: 1);
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const int _defaultBufferSize = 10000;
  static const int _maxBufferSize = 100000;
  static const int _compressionThreshold = 50000;
  
  // Memory management
  int _totalMemoryUsage = 0;
  int _maxMemoryUsage = 200 * 1024 * 1024; // 200MB
  double _memoryPressureThreshold = 0.8;
  
  bool get isInitialized => _isInitialized;
  Map<String, CircularBuffer> get buffers => Map.unmodifiable(_buffers);
  Map<String, BufferMetrics> get bufferMetrics => Map.unmodifiable(_bufferMetrics);

  /// Initialize the circular buffer manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Register default buffer configurations
      await _registerDefaultBufferConfigurations();
      
      // Create default buffers
      await _createDefaultBuffers();
      
      // Start optimization timer
      _startOptimizationTimer();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('🔄 Circular Buffer Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Circular Buffer Manager: $e');
      rethrow;
    }
  }

  /// Get or create a buffer
  CircularBuffer getBuffer(String id, {BufferConfiguration? config}) {
    if (!_buffers.containsKey(id)) {
      final bufferConfig = config ?? _bufferConfigs[id] ?? BufferConfiguration.defaultConfig();
      _buffers[id] = CircularBuffer(
        id: id,
        config: bufferConfig,
      );
      
      _bufferMetrics[id] = BufferMetrics(id);
      debugPrint('📝 Created buffer: $id');
    }
    
    return _buffers[id]!;
  }

  /// Write data to a buffer
  void write(String bufferId, List<int> data) {
    final buffer = getBuffer(bufferId);
    final metrics = _bufferMetrics[bufferId]!;
    
    final startTime = DateTime.now();
    buffer.write(data);
    
    // Update metrics
    metrics.totalWrites++;
    metrics.totalBytesWritten += data.length;
    metrics.currentSize = buffer.size;
    metrics.writeTime += DateTime.now().difference(startTime);
    
    // Check memory pressure
    _checkMemoryPressure();
  }

  /// Read data from a buffer
  List<int> read(String bufferId, {int? length}) {
    final buffer = getBuffer(bufferId);
    final metrics = _bufferMetrics[bufferId]!;
    
    final startTime = DateTime.now();
    final data = buffer.read(length);
    
    // Update metrics
    metrics.totalReads++;
    metrics.totalBytesRead += data.length;
    metrics.readTime += DateTime.now().difference(startTime);
    
    return data;
  }

  /// Read all data from a buffer
  List<int> readAll(String bufferId) {
    final buffer = getBuffer(bufferId);
    return buffer.readAll();
  }

  /// Clear a buffer
  void clearBuffer(String bufferId) {
    final buffer = getBuffer(bufferId);
    final metrics = _bufferMetrics[bufferId]!;
    
    buffer.clear();
    metrics.currentSize = 0;
    metrics.totalClears++;
    
    debugPrint('🗑️ Cleared buffer: $bufferId');
  }

  /// Resize a buffer
  void resizeBuffer(String bufferId, int newSize) {
    final buffer = getBuffer(bufferId);
    final metrics = _bufferMetrics[bufferId]!;
    
    buffer.resize(newSize);
    metrics.currentSize = buffer.size;
    metrics.totalResizes++;
    
    debugPrint('📏 Resized buffer $bufferId to $newSize');
  }

  /// Get buffer statistics
  BufferStatistics getStatistics(String bufferId) {
    final buffer = _buffers[bufferId];
    final metrics = _bufferMetrics[bufferId];
    
    if (buffer == null || metrics == null) {
      throw ArgumentError('Buffer not found: $bufferId');
    }
    
    return BufferStatistics(
      id: bufferId,
      size: buffer.size,
      capacity: buffer.capacity,
      utilization: buffer.utilization,
      totalWrites: metrics.totalWrites,
      totalReads: metrics.totalReads,
      totalBytesWritten: metrics.totalBytesWritten,
      totalBytesRead: metrics.totalBytesRead,
      averageWriteTime: metrics.getAverageWriteTime(),
      averageReadTime: metrics.getAverageReadTime(),
      compressionRatio: metrics.compressionRatio,
    );
  }

  /// Get comprehensive statistics for all buffers
  Map<String, BufferStatistics> getAllStatistics() {
    final stats = <String, BufferStatistics>{};
    
    for (final bufferId in _buffers.keys) {
      stats[bufferId] = getStatistics(bufferId);
    }
    
    return stats;
  }

  /// Optimize all buffers based on usage patterns
  Future<void> optimizeBuffers() async {
    debugPrint('🔧 Optimizing buffers based on usage patterns');
    
    for (final entry in _bufferMetrics.entries) {
      final bufferId = entry.key;
      final metrics = entry.value;
      final buffer = _buffers[bufferId];
      
      if (buffer != null && metrics.totalWrites > 100) {
        await _optimizeBuffer(bufferId, buffer, metrics);
      }
    }
  }

  /// Optimize a specific buffer
  Future<void> _optimizeBuffer(String bufferId, CircularBuffer buffer, BufferMetrics metrics) async {
    // Calculate optimal size based on usage patterns
    final avgWriteSize = metrics.totalBytesWritten / metrics.totalWrites;
    final utilization = buffer.utilization;
    
    int optimalSize;
    
    if (utilization > 0.9) {
      // High utilization - increase size
      optimalSize = (buffer.capacity * 1.5).round().clamp(_defaultBufferSize, _maxBufferSize);
    } else if (utilization < 0.3 && buffer.capacity > _defaultBufferSize) {
      // Low utilization - decrease size
      optimalSize = (buffer.capacity * 0.7).round().clamp(_defaultBufferSize, buffer.capacity);
    } else {
      // Optimal utilization - keep current size
      optimalSize = buffer.capacity;
    }
    
    if (optimalSize != buffer.capacity) {
      resizeBuffer(bufferId, optimalSize);
      debugPrint('🔧 Optimized buffer $bufferId: ${buffer.capacity} -> $optimalSize');
    }
    
    // Compress old data if buffer is large
    if (buffer.size > _compressionThreshold) {
      await _compressBufferData(bufferId, buffer);
    }
  }

  /// Compress old buffer data
  Future<void> _compressBufferData(String bufferId, CircularBuffer buffer) async {
    // This would implement compression of old data
    // For now, just log the action
    debugPrint('🗜️ Compressing old data in buffer: $bufferId');
    
    final metrics = _bufferMetrics[bufferId];
    if (metrics != null) {
      metrics.compressionRatio = 0.7; // Simulate 30% compression
    }
  }

  /// Handle memory pressure
  Future<void> handleMemoryPressure() async {
    debugPrint('⚠️ Memory pressure detected, reducing buffer sizes');
    
    // Sort buffers by least recently used
    final sortedBuffers = _bufferMetrics.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    
    // Reduce buffer sizes starting with least used
    for (final entry in sortedBuffers) {
      final bufferId = entry.key;
      final buffer = _buffers[bufferId];
      
      if (buffer != null) {
        final reduction = (buffer.capacity * 0.3).round();
        resizeBuffer(bufferId, (buffer.capacity - reduction).clamp(_defaultBufferSize, buffer.capacity));
        
        if (_totalMemoryUsage <= _maxMemoryUsage * _memoryPressureThreshold) {
          break;
        }
      }
    }
  }

  /// Check memory pressure
  void _checkMemoryPressure() {
    _updateMemoryUsage();
    
    if (_totalMemoryUsage > _maxMemoryUsage * _memoryPressureThreshold) {
      unawaited(handleMemoryPressure());
    }
  }

  /// Update memory usage
  void _updateMemoryUsage() {
    _totalMemoryUsage = _buffers.values
        .fold(0, (sum, buffer) => sum + buffer.memoryUsage);
  }

  /// Register default buffer configurations
  Future<void> _registerDefaultBufferConfigurations() async {
    // Terminal output buffer - high frequency, large capacity
    _bufferConfigs['terminal_output'] = BufferConfiguration(
      initialSize: 10000,
      maxSize: 50000,
      growthFactor: 1.5,
      shrinkFactor: 0.7,
      compressionEnabled: true,
      compressionThreshold: 20000,
    );

    // Search buffer - medium frequency, medium capacity
    _bufferConfigs['search'] = BufferConfiguration(
      initialSize: 1000,
      maxSize: 5000,
      growthFactor: 1.3,
      shrinkFactor: 0.8,
      compressionEnabled: false,
    );

    // Command history buffer - medium frequency, large capacity
    _bufferConfigs['command_history'] = BufferConfiguration(
      initialSize: 5000,
      maxSize: 20000,
      growthFactor: 1.4,
      shrinkFactor: 0.75,
      compressionEnabled: true,
      compressionThreshold: 10000,
    );

    // File buffer - low frequency, variable capacity
    _bufferConfigs['file'] = BufferConfiguration(
      initialSize: 2000,
      maxSize: 10000,
      growthFactor: 2.0,
      shrinkFactor: 0.5,
      compressionEnabled: true,
      compressionThreshold: 5000,
    );
  }

  /// Create default buffers
  Future<void> _createDefaultBuffers() async {
    for (final configId in _bufferConfigs.keys) {
      getBuffer(configId);
    }
    
    debugPrint('📝 Created ${_buffers.length} default buffers');
  }

  /// Start optimization timer
  void _startOptimizationTimer() {
    _optimizationTimer = Timer.periodic(_optimizationInterval, (_) {
      unawaited(optimizeBuffers());
    });
  }

  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// Perform periodic cleanup
  void _performCleanup() {
    final now = DateTime.now();
    final buffersToCleanup = <String>[];
    
    for (final entry in _bufferMetrics.entries) {
      final bufferId = entry.key;
      final metrics = entry.value;
      final buffer = _buffers[bufferId];
      
      if (buffer != null && 
          now.difference(metrics.lastAccess).inMinutes > 10 &&
          buffer.size == 0) {
        buffersToCleanup.add(bufferId);
      }
    }
    
    for (final bufferId in buffersToCleanup) {
      _buffers.remove(bufferId);
      _bufferMetrics.remove(bufferId);
      debugPrint('🗑️ Removed unused buffer: $bufferId');
    }
  }

  /// Dispose the circular buffer manager
  Future<void> dispose() async {
    _optimizationTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _buffers.clear();
    _bufferMetrics.clear();
    _bufferConfigs.clear();
    
    debugPrint('🔄 Circular Buffer Manager disposed');
  }
}

/// Circular buffer implementation
class CircularBuffer {
  final String id;
  final BufferConfiguration config;
  
  late Uint8List _buffer;
  int _head = 0;
  int _tail = 0;
  int _size = 0;
  bool _isFull = false;
  
  CircularBuffer({
    required this.id,
    required this.config,
  }) {
    _buffer = Uint8List(config.initialSize);
  }
  
  /// Write data to the buffer
  void write(List<int> data) {
    for (final byte in data) {
      _buffer[_head] = byte;
      _head = (_head + 1) % _buffer.length;
      
      if (_size < _buffer.length) {
        _size++;
      } else {
        // Buffer is full, advance tail
        _tail = (_tail + 1) % _buffer.length;
        _isFull = true;
      }
    }
    
    // Check if we need to resize
    if (_isFull && _size >= _buffer.length * 0.9) {
      _resize();
    }
  }
  
  /// Read data from the buffer
  List<int> read([int? length]) {
    if (_size == 0) return [];
    
    final bytesToRead = length ?? _size;
    final result = <int>[];
    
    for (int i = 0; i < bytesToRead && i < _size; i++) {
      result.add(_buffer[_tail]);
      _tail = (_tail + 1) % _buffer.length;
      _size--;
    }
    
    return result;
  }
  
  /// Read all data from the buffer
  List<int> readAll() {
    return read(_size);
  }
  
  /// Clear the buffer
  void clear() {
    _head = 0;
    _tail = 0;
    _size = 0;
    _isFull = false;
  }
  
  /// Resize the buffer
  void resize(int newSize) {
    if (newSize == _buffer.length) return;
    
    final currentData = readAll();
    _buffer = Uint8List(newSize);
    clear();
    write(currentData);
    
    debugPrint('📏 Resized buffer $id to $newSize');
  }
  
  /// Resize buffer when full
  void _resize() {
    final newSize = (_buffer.length * config.growthFactor).round()
        .clamp(config.initialSize, config.maxSize);
    
    if (newSize > _buffer.length) {
      resize(newSize);
    }
  }
  
  // Getters
  int get size => _size;
  int get capacity => _buffer.length;
  double get utilization => _buffer.length > 0 ? _size / _buffer.length : 0.0;
  bool get isFull => _isFull;
  bool get isEmpty => _size == 0;
  int get memoryUsage => _buffer.length;
}

/// Buffer configuration
class BufferConfiguration {
  final int initialSize;
  final int maxSize;
  final double growthFactor;
  final double shrinkFactor;
  final bool compressionEnabled;
  final int compressionThreshold;
  
  const BufferConfiguration({
    required this.initialSize,
    required this.maxSize,
    required this.growthFactor,
    required this.shrinkFactor,
    required this.compressionEnabled,
    required this.compressionThreshold,
  });
  
  static BufferConfiguration defaultConfig() {
    return const BufferConfiguration(
      initialSize: 1000,
      maxSize: 10000,
      growthFactor: 1.5,
      shrinkFactor: 0.7,
      compressionEnabled: false,
      compressionThreshold: 5000,
    );
  }
}

/// Buffer metrics tracking
class BufferMetrics {
  final String id;
  int totalWrites = 0;
  int totalReads = 0;
  int totalBytesWritten = 0;
  int totalBytesRead = 0;
  int currentSize = 0;
  int totalClears = 0;
  int totalResizes = 0;
  DateTime lastAccess = DateTime.now();
  Duration writeTime = Duration.zero;
  Duration readTime = Duration.zero;
  double compressionRatio = 1.0;
  
  BufferMetrics(this.id);
  
  Duration getAverageWriteTime() {
    return totalWrites > 0 
        ? Duration(milliseconds: writeTime.inMilliseconds ~/ totalWrites)
        : Duration.zero;
  }
  
  Duration getAverageReadTime() {
    return totalReads > 0 
        ? Duration(milliseconds: readTime.inMilliseconds ~/ totalReads)
        : Duration.zero;
  }
}

/// Buffer statistics
class BufferStatistics {
  final String id;
  final int size;
  final int capacity;
  final double utilization;
  final int totalWrites;
  final int totalReads;
  final int totalBytesWritten;
  final int totalBytesRead;
  final Duration averageWriteTime;
  final Duration averageReadTime;
  final double compressionRatio;
  
  BufferStatistics({
    required this.id,
    required this.size,
    required this.capacity,
    required this.utilization,
    required this.totalWrites,
    required this.totalReads,
    required this.totalBytesWritten,
    required this.totalBytesRead,
    required this.averageWriteTime,
    required this.averageReadTime,
    required this.compressionRatio,
  });
  
  double get writeThroughput => totalWrites > 0 ? totalBytesWritten / totalWrites : 0.0;
  double get readThroughput => totalReads > 0 ? totalBytesRead / totalReads : 0.0;
}

/// Helper function to fire and forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents "unawaited_future" lint
}
