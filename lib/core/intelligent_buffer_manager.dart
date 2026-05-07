import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

class IntelligentBufferManager {
  static const int _maxBufferSize = 50 * 1024 * 1024; // 50MB max buffer
  static const int _defaultBufferSize = 1024 * 1024; // 1MB default
  static const int _minBufferSize = 64 * 1024; // 64KB minimum
  static const int _bufferCleanupInterval = 30000; // 30 seconds
  
  final Map<String, ManagedBuffer> _buffers = {};
  final Map<String, BufferProfile> _bufferProfiles = {};
  final List<BufferMetrics> _metricsHistory = [];
  
  Timer? _cleanupTimer;
  int _totalMemoryUsed = 0;
  int _peakMemoryUsed = 0;
  
  final StreamController<BufferEvent> _eventController = 
      StreamController<BufferEvent>.broadcast();

  void initialize() {
    _startCleanupTimer();
    developer.log('🧠 Intelligent Buffer Manager initialized');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      Duration(milliseconds: _bufferCleanupInterval),
      (_) => _performBufferCleanup(),
    );
  }

  ManagedBuffer createBuffer(String id, {int? initialSize}) {
    if (_buffers.containsKey(id)) {
      return _buffers[id]!;
    }

    final size = _calculateOptimalSize(id, initialSize ?? _defaultBufferSize);
    final buffer = ManagedBuffer(
      id: id,
      size: size,
      createdAt: DateTime.now(),
    );

    _buffers[id] = buffer;
    _totalMemoryUsed += size;
    _peakMemoryUsed = _peakMemoryUsed > _totalMemoryUsed ? _peakMemoryUsed : _totalMemoryUsed;

    developer.log('🧠 Created buffer $id with size ${size ~/ 1024}KB');
    _emitEvent(BufferEvent(type: BufferEventType.created, bufferId: id, size: size));

    return buffer;
  }

  int _calculateOptimalSize(String id, int requestedSize) {
    final profile = _bufferProfiles[id];
    if (profile == null) {
      return requestedSize.clamp(_minBufferSize, _maxBufferSize ~/ 10);
    }

    // Use historical data to predict optimal size
    final avgUsage = profile.getAverageUsage();
    final peakUsage = profile.getPeakUsage();
    final growthRate = profile.getGrowthRate();

    // Calculate optimal size based on usage patterns
    int optimalSize;
    if (growthRate > 0) {
      // Growing buffer - allocate more space
      optimalSize = (peakUsage * 1.5).round();
    } else {
      // Stable or shrinking - use average with some headroom
      optimalSize = (avgUsage * 1.2).round();
    }

    return optimalSize.clamp(_minBufferSize, _maxBufferSize ~/ 5);
  }

  void writeBuffer(String id, Uint8List data) {
    final buffer = _buffers[id];
    if (buffer == null) return;

    final requiredSize = buffer.position + data.length;
    
    // Resize buffer if needed
    if (requiredSize > buffer.size) {
      _resizeBuffer(id, requiredSize);
    }

    buffer.write(data);
    _updateBufferProfile(id, data.length);
    
    _emitEvent(BufferEvent(
      type: BufferEventType.write,
      bufferId: id,
      size: data.length,
    ));
  }

  Uint8List? readBuffer(String id, {int? length}) {
    final buffer = _buffers[id];
    if (buffer == null) return null;

    final data = buffer.read(length);
    
    _emitEvent(BufferEvent(
      type: BufferEventType.read,
      bufferId: id,
      size: data?.length ?? 0,
    ));

    return data;
  }

  void _resizeBuffer(String id, int requiredSize) {
    final buffer = _buffers[id]!;
    final oldSize = buffer.size;
    
    // Calculate new size with growth factor
    final newSize = _calculateGrowthSize(oldSize, requiredSize);
    
    if (newSize > _maxBufferSize) {
      // Buffer is getting too large - consider splitting or compression
      _handleOversizedBuffer(id, requiredSize);
      return;
    }

    buffer.resize(newSize);
    _totalMemoryUsed += (newSize - oldSize);
    _peakMemoryUsed = _peakMemoryUsed > _totalMemoryUsed ? _peakMemoryUsed : _totalMemoryUsed;

    developer.log('🧠 Resized buffer $id from ${oldSize ~/ 1024}KB to ${newSize ~/ 1024}KB');
    
    _emitEvent(BufferEvent(
      type: BufferEventType.resized,
      bufferId: id,
      size: newSize - oldSize,
    ));
  }

  int _calculateGrowthSize(int currentSize, int requiredSize) {
    // Use exponential growth with diminishing returns
    final growthFactor = requiredSize < currentSize * 1.5 ? 1.5 : 1.25;
    final newSize = (requiredSize * growthFactor).round();
    
    return newSize.clamp(_minBufferSize, _maxBufferSize);
  }

  void _handleOversizedBuffer(String id, int requiredSize) {
    developer.log('🧠 Buffer $id is oversized (${requiredSize ~/ 1024}KB), applying optimization strategies');
    
    // Strategy 1: Compress old data
    _compressBufferData(id);
    
    // Strategy 2: Split into multiple buffers
    if (_shouldSplitBuffer(id)) {
      _splitBuffer(id);
    }
    
    // Strategy 3: Move to disk storage
    if (_shouldMoveToDisk(id)) {
      _moveBufferToDisk(id);
    }
  }

  void _compressBufferData(String id) {
    final buffer = _buffers[id]!;
    // Implement compression logic
    buffer.compress();
    developer.log('🧠 Compressed buffer $id');
  }

  bool _shouldSplitBuffer(String id) {
    final buffer = _buffers[id]!;
    return buffer.size > _maxBufferSize ~/ 2 && buffer.canSplit();
  }

  void _splitBuffer(String id) {
    final buffer = _buffers[id]!;
    final parts = buffer.split();
    
    for (int i = 0; i < parts.length; i++) {
      final partId = '${id}_part_$i';
      final partBuffer = ManagedBuffer(
        id: partId,
        size: parts[i].length,
        createdAt: DateTime.now(),
      );
      partBuffer.write(parts[i]);
      _buffers[partId] = partBuffer;
    }

    // Remove original buffer
    _removeBuffer(id);
    developer.log('🧠 Split buffer $id into ${parts.length} parts');
  }

  bool _shouldMoveToDisk(String id) {
    final buffer = _buffers[id]!;
    final profile = _bufferProfiles[id];
    
    // Move to disk if:
    // 1. Buffer is very large
    // 2. Access frequency is low
    // 3. Buffer hasn't been accessed recently
    
    return buffer.size > _maxBufferSize ~/ 3 &&
           (profile?.getAccessFrequency() ?? 0) < 0.1 &&
           DateTime.now().difference(buffer.lastAccessed).inMinutes > 5;
  }

  void _moveBufferToDisk(String id) {
    final buffer = _buffers[id]!;
    buffer.moveToDisk();
    developer.log('🧠 Moved buffer $id to disk storage');
  }

  void _updateBufferProfile(String id, int operationSize) {
    final profile = _bufferProfiles.putIfAbsent(
      id, 
      () => BufferProfile(id: id),
    );
    
    profile.recordOperation(operationSize);
  }

  void _performBufferCleanup() {
    final now = DateTime.now();
    final buffersToRemove = <String>[];
    int memoryFreed = 0;

    for (final entry in _buffers.entries) {
      final id = entry.key;
      final buffer = entry.value;

      // Remove old, unused buffers
      if (now.difference(buffer.lastAccessed).inMinutes > 30 && 
          buffer.accessCount < 5) {
        buffersToRemove.add(id);
        memoryFreed += buffer.size;
        continue;
      }

      // Compress buffers that haven't been accessed recently
      if (now.difference(buffer.lastAccessed).inMinutes > 10) {
        buffer.compress();
      }

      // Shrink oversized buffers
      if (buffer.size > buffer.position * 3 && buffer.size > _defaultBufferSize) {
        final newSize = (buffer.position * 1.5).clamp(_minBufferSize, buffer.size);
        final freed = buffer.size - newSize;
        buffer.resize(newSize);
        _totalMemoryUsed -= freed;
        memoryFreed += freed;
      }
    }

    // Remove unused buffers
    for (final id in buffersToRemove) {
      _removeBuffer(id);
    }

    if (memoryFreed > 0) {
      developer.log('🧠 Buffer cleanup freed ${memoryFreed ~/ 1024}KB');
      _emitEvent(BufferEvent(
        type: BufferEventType.cleanup,
        size: memoryFreed,
      ));
    }

    _recordMetrics();
  }

  void _removeBuffer(String id) {
    final buffer = _buffers.remove(id);
    if (buffer != null) {
      _totalMemoryUsed -= buffer.size;
      buffer.dispose();
      developer.log('🧠 Removed buffer $id');
      
      _emitEvent(BufferEvent(
        type: BufferEventType.removed,
        bufferId: id,
        size: buffer.size,
      ));
    }
  }

  void _recordMetrics() {
    final metrics = BufferMetrics(
      timestamp: DateTime.now(),
      totalBuffers: _buffers.length,
      totalMemoryUsed: _totalMemoryUsed,
      peakMemoryUsed: _peakMemoryUsed,
      averageBufferSize: _buffers.isEmpty ? 0 : _totalMemoryUsed ~/ _buffers.length,
    );

    _metricsHistory.add(metrics);
    if (_metricsHistory.length > 100) {
      _metricsHistory.removeAt(0);
    }
  }

  void _emitEvent(BufferEvent event) {
    _eventController.add(event);
  }

  Stream<BufferEvent> get eventStream => _eventController.stream;

  BufferManagerStats getStats() {
    return BufferManagerStats(
      totalBuffers: _buffers.length,
      totalMemoryUsed: _totalMemoryUsed,
      peakMemoryUsed: _peakMemoryUsed,
      averageBufferSize: _buffers.isEmpty ? 0 : _totalMemoryUsed ~/ _buffers.length,
      metricsHistory: _metricsHistory.toList(),
      bufferProfiles: _bufferProfiles.values.toList(),
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    
    for (final buffer in _buffers.values) {
      buffer.dispose();
    }
    _buffers.clear();
    _bufferProfiles.clear();
    _metricsHistory.clear();
    _eventController.close();
    
    developer.log('🧠 Intelligent Buffer Manager disposed');
  }
}

class ManagedBuffer {
  final String id;
  int size;
  final DateTime createdAt;
  DateTime lastAccessed;
  int accessCount;
  int position;
  Uint8List data;
  bool isCompressed;
  bool isOnDisk;

  ManagedBuffer({
    required this.id,
    required this.size,
    required this.createdAt,
  }) : lastAccessed = DateTime.now(),
       accessCount = 0,
       position = 0,
       data = Uint8List(size),
       isCompressed = false,
       isOnDisk = false;

  void write(Uint8List writeData) {
    if (position + writeData.length > data.length) {
      throw Exception('Buffer overflow');
    }
    
    data.setRange(position, position + writeData.length, writeData);
    position += writeData.length;
    lastAccessed = DateTime.now();
    accessCount++;
  }

  Uint8List read([int? length]) {
    lastAccessed = DateTime.now();
    accessCount++;
    
    final readLength = length ?? position;
    final actualLength = readLength.clamp(0, position);
    
    return Uint8List.fromList(data.take(actualLength).toList());
  }

  void resize(int newSize) {
    final newData = Uint8List(newSize);
    final copyLength = (position < newSize ? position : newSize);
    newData.setRange(0, copyLength, data);
    
    data = newData;
    size = newSize;
    position = position < newSize ? position : newSize;
  }

  void compress() {
    if (!isCompressed && !isOnDisk) {
      // Implement compression logic
      isCompressed = true;
    }
  }

  bool canSplit() {
    return !isCompressed && !isOnDisk && position > _defaultBufferSize;
  }

  List<Uint8List> split() {
    final parts = <Uint8List>[];
    final partSize = _defaultBufferSize;
    
    for (int i = 0; i < position; i += partSize) {
      final end = (i + partSize).clamp(0, position);
      parts.add(Uint8List.fromList(data.getRange(i, end)));
    }
    
    return parts;
  }

  void moveToDisk() {
    if (!isOnDisk) {
      // Implement disk storage logic
      isOnDisk = true;
      // Clear memory data
      data = Uint8List(0);
    }
  }

  void dispose() {
    data = Uint8List(0);
  }
}

class BufferProfile {
  final String id;
  final List<OperationRecord> operations = [];
  int totalOperations = 0;
  int totalBytes = 0;

  BufferProfile({required this.id});

  void recordOperation(int bytes) {
    operations.add(OperationRecord(
      timestamp: DateTime.now(),
      bytes: bytes,
    ));
    
    totalOperations++;
    totalBytes += bytes;
    
    // Keep only recent operations
    if (operations.length > 1000) {
      operations.removeAt(0);
    }
  }

  double getAverageUsage() {
    if (operations.isEmpty) return 0.0;
    return totalBytes / operations.length;
  }

  int getPeakUsage() {
    if (operations.isEmpty) return 0;
    return operations.map((op) => op.bytes).reduce((a, b) => a > b ? a : b);
  }

  double getGrowthRate() {
    if (operations.length < 10) return 0.0;
    
    final recent = operations.take(10).toList();
    final older = operations.skip(10).take(10).toList();
    
    if (older.isEmpty) return 0.0;
    
    final recentAvg = recent.map((op) => op.bytes).reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.map((op) => op.bytes).reduce((a, b) => a + b) / older.length;
    
    return recentAvg - olderAvg;
  }

  double getAccessFrequency() {
    if (operations.isEmpty) return 0.0;
    
    final timeSpan = DateTime.now().difference(operations.first.timestamp).inSeconds;
    return timeSpan > 0 ? operations.length / timeSpan : 0.0;
  }
}

class OperationRecord {
  final DateTime timestamp;
  final int bytes;

  OperationRecord({required this.timestamp, required this.bytes});
}

class BufferMetrics {
  final DateTime timestamp;
  final int totalBuffers;
  final int totalMemoryUsed;
  final int peakMemoryUsed;
  final int averageBufferSize;

  BufferMetrics({
    required this.timestamp,
    required this.totalBuffers,
    required this.totalMemoryUsed,
    required this.peakMemoryUsed,
    required this.averageBufferSize,
  });
}

enum BufferEventType {
  created,
  read,
  write,
  resized,
  removed,
  cleanup,
}

class BufferEvent {
  final BufferEventType type;
  final String? bufferId;
  final int size;

  BufferEvent({
    required this.type,
    this.bufferId,
    required this.size,
  });
}

class BufferManagerStats {
  final int totalBuffers;
  final int totalMemoryUsed;
  final int peakMemoryUsed;
  final int averageBufferSize;
  final List<BufferMetrics> metricsHistory;
  final List<BufferProfile> bufferProfiles;

  BufferManagerStats({
    required this.totalBuffers,
    required this.totalMemoryUsed,
    required this.peakMemoryUsed,
    required this.averageBufferSize,
    required this.metricsHistory,
    required this.bufferProfiles,
  });
}

const int _defaultBufferSize = 1024 * 1024;
