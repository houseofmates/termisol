import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Network Bandwidth Management - Prioritize critical terminal operations
class NetworkBandwidthManager {
  static final NetworkBandwidthManager _instance = NetworkBandwidthManager._internal();
  factory NetworkBandwidthManager() => _instance;
  NetworkBandwidthManager._internal();

  final PriorityQueue<NetworkOperation> _highPriorityQueue = PriorityQueue();
  final Queue<NetworkOperation> _normalQueue = Queue();
  final Queue<NetworkOperation> _lowPriorityQueue = Queue();
  final Map<String, NetworkStream> _activeStreams = {};
  final List<NetworkMetric> _metricsHistory = [];
  
  bool _isInitialized = false;
  Timer? _processingTimer;
  Timer? _monitoringTimer;
  bool _isProcessing = false;
  
  // Bandwidth limits and configuration
  static const Duration _processingInterval = Duration(milliseconds: 50);
  static const Duration _monitoringInterval = Duration(seconds: 1);
  static const double _maxBandwidthMbps = 100.0; // 100 Mbps
  static const double _criticalBandwidthThreshold = 0.8; // 80% of max
  static const double _highBandwidthThreshold = 0.6; // 60% of max
  static const int _maxConcurrentStreams = 10;
  static const int _maxQueueSize = 500;
  
  double _currentBandwidthUsage = 0.0;
  double _totalBandwidthAllocated = 0.0;
  
  final _bandwidthController = StreamController<BandwidthEvent>.broadcast();
  Stream<BandwidthEvent> get events => _bandwidthController.stream;
  
  bool get isInitialized => _isInitialized;
  double get currentBandwidthUsage => _currentBandwidthUsage;
  int get totalQueuedOperations => _highPriorityQueue.length + _normalQueue.length + _lowPriorityQueue.length;
  int get activeStreamCount => _activeStreams.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startProcessing();
    _startMonitoring();
    _isInitialized = true;
    debugPrint('🌐 Network Bandwidth Manager initialized');
  }

  Future<NetworkOperationResult> enqueueOperation(NetworkOperation operation) async {
    // Check queue limits
    if (totalQueuedOperations >= _maxQueueSize) {
      return NetworkOperationResult.error('Queue full', operation.id);
    }
    
    // Add to appropriate queue based on priority
    switch (operation.priority) {
      case NetworkPriority.critical:
        _highPriorityQueue.add(operation);
        break;
      case NetworkPriority.high:
        _normalQueue.add(operation);
        break;
      case NetworkPriority.low:
        _lowPriorityQueue.add(operation);
        break;
    }
    
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.operationQueued,
      data: {
        'operation_id': operation.id,
        'priority': operation.priority.toString(),
        'type': operation.type.toString(),
        'size_bytes': operation.sizeBytes,
      },
    ));
    
    debugPrint('🌐 Enqueued network operation: ${operation.type}');
    return NetworkOperationResult.success(operation.id);
  }

  Future<NetworkStream> createStream({
    required String streamId,
    required NetworkType type,
    required NetworkPriority priority,
    double? minBandwidth,
    double? maxBandwidth,
  }) async {
    if (_activeStreams.length >= _maxConcurrentStreams) {
      throw StateError('Maximum concurrent streams reached');
    }
    
    final stream = NetworkStream(
      id: streamId,
      type: type,
      priority: priority,
      minBandwidth: minBandwidth ?? 1.0,
      maxBandwidth: maxBandwidth ?? 10.0,
      allocatedBandwidth: 0.0,
      currentUsage: 0.0,
      createdAt: DateTime.now(),
    );
    
    _activeStreams[streamId] = stream;
    
    // Allocate bandwidth immediately if available
    _allocateBandwidthToStream(stream);
    
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.streamCreated,
      data: {
        'stream_id': streamId,
        'type': type.toString(),
        'priority': priority.toString(),
      },
    ));
    
    return stream;
  }

  Future<void> updateStreamUsage(String streamId, double usageMbps) async {
    final stream = _activeStreams[streamId];
    if (stream == null) return;
    
    stream.currentUsage = usageMbps;
    
    // Reallocate bandwidth if needed
    if (usageMbps > stream.allocatedBandwidth) {
      await _reallocateBandwidth();
    }
    
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.usageUpdated,
      data: {
        'stream_id': streamId,
        'usage_mbps': usageMbps,
        'allocated_mbps': stream.allocatedBandwidth,
      },
    ));
  }

  Future<void> closeStream(String streamId) async {
    final stream = _activeStreams.remove(streamId);
    if (stream != null) {
      _totalBandwidthAllocated -= stream.allocatedBandwidth;
      
      _bandwidthController.add(BandwidthEvent(
        type: BandwidthEventType.streamClosed,
        data: {
          'stream_id': streamId,
          'released_bandwidth': stream.allocatedBandwidth,
        },
      ));
      
      // Reallocate bandwidth to remaining streams
      await _reallocateBandwidth();
    }
  }

  BandwidthStatistics getStatistics() {
    final recentMetrics = _metricsHistory.takeLast(60).toList(); // Last minute
    
    return BandwidthStatistics(
      currentUsage: _currentBandwidthUsage,
      totalAllocated: _totalBandwidthAllocated,
      availableBandwidth: _maxBandwidthMbps - _currentBandwidthUsage,
      activeStreams: _activeStreams.length,
      queuedOperations: totalQueuedOperations,
      averageLatency: _calculateAverageLatency(recentMetrics),
      throughput: _calculateThroughput(recentMetrics),
      packetLoss: _calculatePacketLoss(recentMetrics),
      efficiency: _calculateEfficiency(),
    );
  }

  void _startProcessing() {
    _processingTimer = Timer.periodic(_processingInterval, (_) {
      unawaited(_processQueues());
    });
  }

  void _startMonitoring() {
    _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
      _collectMetrics();
    });
  }

  Future<void> _processQueues() async {
    if (_isProcessing) return;
    
    _isProcessing = true;
    
    try {
      // Process critical priority queue first
      await _processQueue(_highPriorityQueue);
      
      // Process high priority queue if bandwidth allows
      if (_currentBandwidthUsage < _highBandwidthThreshold * _maxBandwidthMbps) {
        await _processQueue(_normalQueue);
      }
      
      // Process low priority queue if plenty of bandwidth
      if (_currentBandwidthUsage < _criticalBandwidthThreshold * _maxBandwidthMbps) {
        await _processQueue(_lowPriorityQueue);
      }
      
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processQueue(Queue<NetworkOperation> queue) async {
    if (queue.isEmpty) return;
    
    final operationsToProcess = <NetworkOperation>[];
    
    // Process as many operations as bandwidth allows
    while (queue.isNotEmpty && operationsToProcess.length < 10) {
      final operation = queue.removeFirst();
      
      // Check if we have enough bandwidth
      final requiredBandwidth = _estimateOperationBandwidth(operation);
      if (_currentBandwidthUsage + requiredBandwidth <= _maxBandwidthMbps) {
        operationsToProcess.add(operation);
      } else {
        // Put it back and stop processing
        queue.addFirst(operation);
        break;
      }
    }
    
    if (operationsToProcess.isEmpty) return;
    
    // Process operations concurrently
    final futures = operationsToProcess.map((op) => _executeOperation(op));
    await Future.wait(futures);
  }

  Future<void> _executeOperation(NetworkOperation operation) async {
    final operationStart = DateTime.now();
    final requiredBandwidth = _estimateOperationBandwidth(operation);
    
    try {
      // Reserve bandwidth
      _currentBandwidthUsage += requiredBandwidth;
      
      // Simulate network operation
      await Future.delayed(Duration(
        milliseconds: _getOperationLatency(operation),
      ));
      
      final operationEnd = DateTime.now();
      final latency = operationEnd.difference(operationStart);
      
      // Record metric
      _metricsHistory.add(NetworkMetric(
        operationId: operation.id,
        operationType: operation.type,
        bandwidthUsed: requiredBandwidth,
        latency: latency,
        timestamp: operationEnd,
        successful: true,
      ));
      
      _bandwidthController.add(BandwidthEvent(
        type: BandwidthEventType.operationCompleted,
        data: {
          'operation_id': operation.id,
          'latency_ms': latency.inMilliseconds,
          'bandwidth_mbps': requiredBandwidth,
        },
      ));
      
    } catch (e) {
      _metricsHistory.add(NetworkMetric(
        operationId: operation.id,
        operationType: operation.type,
        bandwidthUsed: requiredBandwidth,
        latency: Duration.zero,
        timestamp: DateTime.now(),
        successful: false,
      ));
      
      _bandwidthController.add(BandwidthEvent(
        type: BandwidthEventType.operationFailed,
        data: {
          'operation_id': operation.id,
          'error': e.toString(),
        },
      ));
    } finally {
      // Release bandwidth
      _currentBandwidthUsage -= requiredBandwidth;
    }
  }

  double _estimateOperationBandwidth(NetworkOperation operation) {
    switch (operation.type) {
      case NetworkType.download:
        return math.min(10.0, operation.sizeBytes / (1024.0 * 1024.0)); // Estimate based on size
      case NetworkType.upload:
        return math.min(5.0, operation.sizeBytes / (1024.0 * 1024.0));
      case NetworkType.apiCall:
        return 0.1; // Small API calls
      case NetworkType.streaming:
        return operation.priority == NetworkPriority.critical ? 5.0 : 2.0;
      case NetworkType.sync:
        return 1.0;
    }
  }

  int _getOperationLatency(NetworkOperation operation) {
    switch (operation.type) {
      case NetworkType.download:
        return 100 + math.Random().nextInt(200); // 100-300ms
      case NetworkType.upload:
        return 150 + math.Random().nextInt(250); // 150-400ms
      case NetworkType.apiCall:
        return 50 + math.Random().nextInt(100); // 50-150ms
      case NetworkType.streaming:
        return 10 + math.Random().nextInt(20); // 10-30ms
      case NetworkType.sync:
        return 200 + math.Random().nextInt(300); // 200-500ms
    }
  }

  void _allocateBandwidthToStream(NetworkStream stream) {
    final availableBandwidth = _maxBandwidthMbps - _totalBandwidthAllocated;
    
    if (availableBandwidth >= stream.minBandwidth) {
      final allocated = math.min(stream.maxBandwidth, availableBandwidth);
      stream.allocatedBandwidth = allocated;
      _totalBandwidthAllocated += allocated;
    }
  }

  Future<void> _reallocateBandwidth() async {
    // Sort streams by priority
    final sortedStreams = _activeStreams.values.toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
    
    // Reset allocations
    _totalBandwidthAllocated = 0.0;
    for (final stream in sortedStreams) {
      stream.allocatedBandwidth = 0.0;
    }
    
    // Reallocate based on priority and needs
    for (final stream in sortedStreams) {
      _allocateBandwidthToStream(stream);
    }
    
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.bandwidthReallocated,
      data: {
        'total_allocated': _totalBandwidthAllocated,
        'active_streams': _activeStreams.length,
      },
    ));
  }

  void _collectMetrics() {
    // Simulate network metrics collection
    final currentUsage = _currentBandwidthUsage + (math.Random().nextDouble() - 0.5) * 5.0;
    _currentBandwidthUsage = math.max(0.0, math.min(_maxBandwidthMbps, currentUsage));
    
    // Check for bandwidth pressure
    if (_currentBandwidthUsage > _criticalBandwidthThreshold * _maxBandwidthMbps) {
      _handleCriticalBandwidth();
    } else if (_currentBandwidthUsage > _highBandwidthThreshold * _maxBandwidthMbps) {
      _handleHighBandwidth();
    }
    
    // Clean up old metrics
    if (_metricsHistory.length > 3600) { // Keep 1 hour of metrics
      _metricsHistory.removeRange(0, _metricsHistory.length - 3600);
    }
  }

  void _handleCriticalBandwidth() {
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.criticalBandwidth,
      data: {
        'current_usage': _currentBandwidthUsage,
        'threshold': _criticalBandwidthThreshold * _maxBandwidthMbps,
      },
    ));
    
    debugPrint('🚨 CRITICAL BANDWIDTH USAGE: ${_currentBandwidthUsage.toStringAsFixed(2)} Mbps');
  }

  void _handleHighBandwidth() {
    _bandwidthController.add(BandwidthEvent(
      type: BandwidthEventType.highBandwidth,
      data: {
        'current_usage': _currentBandwidthUsage,
        'threshold': _highBandwidthThreshold * _maxBandwidthMbps,
      },
    ));
  }

  Duration _calculateAverageLatency(List<NetworkMetric> metrics) {
    if (metrics.isEmpty) return Duration.zero;
    
    final totalLatency = metrics
        .where((m) => m.successful)
        .map((m) => m.latency.inMicroseconds)
        .fold<int>(0, (sum, latency) => sum + latency);
    
    final successfulCount = metrics.where((m) => m.successful).length;
    return Duration(
      microseconds: successfulCount > 0 ? totalLatency ~/ successfulCount : 0,
    );
  }

  double _calculateThroughput(List<NetworkMetric> metrics) {
    if (metrics.length < 2) return 0.0;
    
    final totalBytes = metrics
        .where((m) => m.successful)
        .map((m) => m.bandwidthUsed * 1024 * 1024 / 8) // Convert to bytes per second
        .fold<double>(0.0, (sum, bytes) => sum + bytes);
    
    final timeSpan = metrics.last.timestamp.difference(metrics.first.timestamp).inSeconds;
    return timeSpan > 0 ? totalBytes / timeSpan : 0.0;
  }

  double _calculatePacketLoss(List<NetworkMetric> metrics) {
    if (metrics.isEmpty) return 0.0;
    
    final failedCount = metrics.where((m) => !m.successful).length;
    return failedCount / metrics.length;
  }

  double _calculateEfficiency() {
    if (_maxBandwidthMbps == 0) return 0.0;
    return _currentBandwidthUsage / _maxBandwidthMbps;
  }

  Future<void> dispose() async {
    _processingTimer?.cancel();
    _monitoringTimer?.cancel();
    _bandwidthController.close();
    
    _highPriorityQueue.clear();
    _normalQueue.clear();
    _lowPriorityQueue.clear();
    _activeStreams.clear();
    _metricsHistory.clear();
  }
}

class NetworkOperation {
  final String id;
  final NetworkType type;
  final NetworkPriority priority;
  final int sizeBytes;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  
  NetworkOperation({
    required this.id,
    required this.type,
    required this.priority,
    required this.sizeBytes,
    required this.data,
    required this.createdAt,
  });
}

class NetworkStream {
  final String id;
  final NetworkType type;
  final NetworkPriority priority;
  final double minBandwidth;
  final double maxBandwidth;
  double allocatedBandwidth;
  double currentUsage;
  final DateTime createdAt;
  
  NetworkStream({
    required this.id,
    required this.type,
    required this.priority,
    required this.minBandwidth,
    required this.maxBandwidth,
    required this.allocatedBandwidth,
    required this.currentUsage,
    required this.createdAt,
  });
}

class NetworkOperationResult {
  final bool success;
  final String operationId;
  final String? error;
  
  NetworkOperationResult({
    required this.success,
    required this.operationId,
    this.error,
  });
  
  factory NetworkOperationResult.success(String operationId) {
    return NetworkOperationResult(
      success: true,
      operationId: operationId,
    );
  }
  
  factory NetworkOperationResult.error(String error, String operationId) {
    return NetworkOperationResult(
      success: false,
      operationId: operationId,
      error: error,
    );
  }
}

class NetworkMetric {
  final String operationId;
  final NetworkType operationType;
  final double bandwidthUsed;
  final Duration latency;
  final DateTime timestamp;
  final bool successful;
  
  NetworkMetric({
    required this.operationId,
    required this.operationType,
    required this.bandwidthUsed,
    required this.latency,
    required this.timestamp,
    required this.successful,
  });
}

class BandwidthStatistics {
  final double currentUsage;
  final double totalAllocated;
  final double availableBandwidth;
  final int activeStreams;
  final int queuedOperations;
  final Duration averageLatency;
  final double throughput;
  final double packetLoss;
  final double efficiency;
  
  BandwidthStatistics({
    required this.currentUsage,
    required this.totalAllocated,
    required this.availableBandwidth,
    required this.activeStreams,
    required this.queuedOperations,
    required this.averageLatency,
    required this.throughput,
    required this.packetLoss,
    required this.efficiency,
  });
}

class BandwidthEvent {
  final BandwidthEventType type;
  final Map<String, dynamic>? data;
  
  BandwidthEvent({
    required this.type,
    this.data,
  });
}

enum NetworkType {
  download,
  upload,
  apiCall,
  streaming,
  sync,
}

enum NetworkPriority {
  critical,
  high,
  low,
}

enum BandwidthEventType {
  operationQueued,
  operationCompleted,
  operationFailed,
  streamCreated,
  streamClosed,
  usageUpdated,
  bandwidthReallocated,
  criticalBandwidth,
  highBandwidth,
}

/// Priority queue implementation for network operations
class PriorityQueue<T> {
  final List<T> _heap = [];
  final Comparator<T> _comparator;
  
  PriorityQueue({Comparator<T>? comparator}) 
      : _comparator = comparator ?? ((a, b) => 0);
  
  bool get isEmpty => _heap.isEmpty;
  int get length => _heap.length;
  
  void add(T item) {
    _heap.add(item);
    _bubbleUp(_heap.length - 1);
  }
  
  T removeFirst() {
    if (isEmpty) throw StateError('Cannot remove from empty queue');
    
    final first = _heap.first;
    final last = _heap.removeLast();
    
    if (!isEmpty) {
      _heap[0] = last;
      _bubbleDown(0);
    }
    
    return first;
  }
  
  T get first => _heap.first;
  
  void _bubbleUp(int index) {
    while (index > 0) {
      final parentIndex = (index - 1) ~/ 2;
      if (_comparator(_heap[index], _heap[parentIndex]) >= 0) break;
      
      _swap(index, parentIndex);
      index = parentIndex;
    }
  }
  
  void _bubbleDown(int index) {
    while (true) {
      final leftChild = 2 * index + 1;
      final rightChild = 2 * index + 2;
      var smallest = index;
      
      if (leftChild < _heap.length && 
          _comparator(_heap[leftChild], _heap[smallest]) < 0) {
        smallest = leftChild;
      }
      
      if (rightChild < _heap.length && 
          _comparator(_heap[rightChild], _heap[smallest]) < 0) {
        smallest = rightChild;
      }
      
      if (smallest == index) break;
      
      _swap(index, smallest);
      index = smallest;
    }
  }
  
  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
  
  List<T> toList() => List.from(_heap);
}


