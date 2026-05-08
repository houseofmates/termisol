import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// I/O Queue Optimization - Smart disk operation scheduling
class IOQueueOptimizer {
  static final IOQueueOptimizer _instance = IOQueueOptimizer._internal();
  factory IOQueueOptimizer() => _instance;
  IOQueueOptimizer._internal();

  final PriorityQueue<IOOperation> _highPriorityQueue = PriorityQueue();
  final Queue<IOOperation> _normalQueue = Queue();
  final Queue<IOOperation> _lowPriorityQueue = Queue();
  final Map<String, IOBatch> _activeBatches = {};
  final List<IOPerformanceMetric> _performanceHistory = [];
  
  bool _isInitialized = false;
  Timer? _processingTimer;
  Timer? _optimizationTimer;
  bool _isProcessing = false;
  
  static const Duration _processingInterval = Duration(milliseconds: 100);
  static const Duration _optimizationInterval = Duration(seconds: 5);
  static const int _maxBatchSize = 50;
  static const int _maxQueueSize = 1000;
  static const Duration _batchTimeout = Duration(milliseconds: 500);
  
  final _ioController = StreamController<IOEvent>.broadcast();
  Stream<IOEvent> get events => _ioController.stream;
  
  bool get isInitialized => _isInitialized;
  int get totalQueuedOperations => _highPriorityQueue.length + _normalQueue.length + _lowPriorityQueue.length;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startProcessing();
    _startOptimization();
    _isInitialized = true;
    debugPrint('💾 I/O Queue Optimizer initialized');
  }

  Future<IOOperationResult> enqueueOperation(IOOperation operation) async {
    // Check queue limits
    if (totalQueuedOperations >= _maxQueueSize) {
      return IOOperationResult.error('Queue full', operation.id);
    }
    
    // Add to appropriate queue based on priority
    switch (operation.priority) {
      case IOPriority.high:
        _highPriorityQueue.add(operation);
        break;
      case IOPriority.normal:
        _normalQueue.add(operation);
        break;
      case IOPriority.low:
        _lowPriorityQueue.add(operation);
        break;
    }
    
    _ioController.add(IOEvent(
      type: IOEventType.operationQueued,
      data: {
        'operation_id': operation.id,
        'priority': operation.priority.toString(),
        'type': operation.type.toString(),
      },
    ));
    
    debugPrint('💾 Enqueued I/O operation: ${operation.type}');
    return IOOperationResult.success(operation.id);
  }

  Future<List<IOOperationResult>> enqueueBatch(List<IOOperation> operations) async {
    final results = <IOOperationResult>[];
    
    // Try to batch compatible operations
    final batches = _createBatches(operations);
    
    for (final batch in batches) {
      final batchId = _generateBatchId();
      final ioBatch = IOBatch(
        id: batchId,
        operations: batch,
        createdAt: DateTime.now(),
        priority: _determineBatchPriority(batch),
      );
      
      _activeBatches[batchId] = ioBatch;
      
      for (final operation in batch) {
        final result = await enqueueOperation(operation);
        results.add(result);
      }
    }
    
    return results;
  }

  Future<IOOperationResult> prioritizeOperation(String operationId, IOPriority newPriority) async {
    // Find operation in queues
    IOOperation? operation = _findOperationInQueues(operationId);
    if (operation == null) {
      return IOOperationResult.error('Operation not found', operationId);
    }
    
    // Remove from current queue
    _removeOperationFromQueues(operationId);
    
    // Update priority and re-enqueue
    operation.priority = newPriority;
    return await enqueueOperation(operation);
  }

  List<IOOperation> getQueueStatus() {
    final allOperations = <IOOperation>[];
    
    allOperations.addAll(_highPriorityQueue.toList());
    allOperations.addAll(_normalQueue.toList());
    allOperations.addAll(_lowPriorityQueue.toList());
    
    return allOperations;
  }

  IOPerformanceStatistics getPerformanceStatistics() {
    if (_performanceHistory.isEmpty) {
      return IOPerformanceStatistics(
        averageLatency: Duration.zero,
        throughput: 0.0,
        queueDepth: totalQueuedOperations,
        batchEfficiency: 0.0,
        errorRate: 0.0,
      );
    }
    
    final recentMetrics = _performanceHistory.takeLast(100).toList();
    final averageLatency = Duration(
      microseconds: recentMetrics
          .map((m) => m.latency.inMicroseconds)
          .reduce((a, b) => a + b) ~/ recentMetrics.length,
    );
    
    final throughput = recentMetrics.length > 1 ? 
        1000.0 / recentMetrics.last.timestamp.difference(recentMetrics.first.timestamp).inMilliseconds : 0.0;
    
    final batchEfficiency = _calculateBatchEfficiency();
    final errorRate = _calculateErrorRate();
    
    return IOPerformanceStatistics(
      averageLatency: averageLatency,
      throughput: throughput,
      queueDepth: totalQueuedOperations,
      batchEfficiency: batchEfficiency,
      errorRate: errorRate,
    );
  }

  void _startProcessing() {
    _processingTimer = Timer.periodic(_processingInterval, (_) {
      unawaited(_processQueues());
    });
  }

  void _startOptimization() {
    _optimizationTimer = Timer.periodic(_optimizationInterval, (_) {
      unawaited(_optimizeQueues());
    });
  }

  Future<void> _processQueues() async {
    if (_isProcessing) return;
    
    _isProcessing = true;
    
    try {
      // Process high priority queue first
      await _processQueue(_highPriorityQueue);
      
      // Process normal queue
      await _processQueue(_normalQueue);
      
      // Process low priority queue if capacity allows
      if (totalQueuedOperations < _maxQueueSize * 0.8) {
        await _processQueue(_lowPriorityQueue);
      }
      
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processQueue(Queue<IOOperation> queue) async {
    if (queue.isEmpty) return;
    
    final operationsToProcess = <IOOperation>[];
    
    // Batch operations if possible
    while (queue.isNotEmpty && operationsToProcess.length < _maxBatchSize) {
      final operation = queue.removeFirst();
      operationsToProcess.add(operation);
    }
    
    if (operationsToProcess.isEmpty) return;
    
    // Group by type for batching
    final batchedOperations = _groupOperationsByType(operationsToProcess);
    
    // Process each batch
    for (final batch in batchedOperations) {
      await _processBatch(batch);
    }
  }

  Future<void> _processBatch(List<IOOperation> operations) async {
    final batchStart = DateTime.now();
    
    try {
      for (final operation in operations) {
        final operationStart = DateTime.now();
        
        // Execute the I/O operation
        await _executeOperation(operation);
        
        final operationEnd = DateTime.now();
        final latency = operationEnd.difference(operationStart);
        
        // Record performance metric
        _performanceHistory.add(IOPerformanceMetric(
          operationId: operation.id,
          operationType: operation.type,
          latency: latency,
          timestamp: operationEnd,
          successful: true,
        ));
        
        _ioController.add(IOEvent(
          type: IOEventType.operationCompleted,
          data: {
            'operation_id': operation.id,
            'latency_ms': latency.inMilliseconds,
            'type': operation.type.toString(),
          },
        ));
      }
      
      final batchEnd = DateTime.now();
      final batchTime = batchEnd.difference(batchStart);
      
      _ioController.add(IOEvent(
        type: IOEventType.batchCompleted,
        data: {
          'operations_count': operations.length,
          'batch_time_ms': batchTime.inMilliseconds,
          'avg_latency_ms': batchTime.inMilliseconds / operations.length,
        },
      ));
      
    } catch (e) {
      // Handle batch errors
      for (final operation in operations) {
        _performanceHistory.add(IOPerformanceMetric(
          operationId: operation.id,
          operationType: operation.type,
          latency: Duration.zero,
          timestamp: DateTime.now(),
          successful: false,
        ));
      }
      
      _ioController.add(IOEvent(
        type: IOEventType.batchFailed,
        data: {
          'operations_count': operations.length,
          'error': e.toString(),
        },
      ));
    }
  }

  Future<void> _executeOperation(IOOperation operation) async {
    // Simulate I/O operation execution
    await Future.delayed(Duration(
      milliseconds: _getOperationLatency(operation.type),
    ));
    
    // Different operations have different characteristics
    switch (operation.type) {
      case IOType.read:
        // Simulate read operation
        break;
      case IOType.write:
        // Simulate write operation
        break;
      case IOType.delete:
        // Simulate delete operation
        break;
      case IOType.copy:
        // Simulate copy operation
        break;
      case IOType.move:
        // Simulate move operation
        break;
    }
  }

  int _getOperationLatency(IOType type) {
    switch (type) {
      case IOType.read:
        return 5 + math.Random().nextInt(10); // 5-15ms
      case IOType.write:
        return 10 + math.Random().nextInt(20); // 10-30ms
      case IOType.delete:
        return 2 + math.Random().nextInt(5); // 2-7ms
      case IOType.copy:
        return 20 + math.Random().nextInt(30); // 20-50ms
      case IOType.move:
        return 15 + math.Random().nextInt(25); // 15-40ms
    }
  }

  List<List<IOOperation>> _groupOperationsByType(List<IOOperation> operations) {
    final grouped = <IOType, List<IOOperation>>{};
    
    for (final operation in operations) {
      grouped.putIfAbsent(operation.type, () => []).add(operation);
    }
    
    return grouped.values.toList();
  }

  List<List<IOOperation>> _createBatches(List<IOOperation> operations) {
    final batches = <List<IOOperation>>[];
    final currentBatch = <IOOperation>[];
    
    for (final operation in operations) {
      if (currentBatch.isEmpty || _canBatchWith(currentBatch.last, operation)) {
        currentBatch.add(operation);
      } else {
        if (currentBatch.isNotEmpty) {
          batches.add(List.from(currentBatch));
          currentBatch.clear();
        }
        currentBatch.add(operation);
      }
      
      if (currentBatch.length >= _maxBatchSize) {
        batches.add(List.from(currentBatch));
        currentBatch.clear();
      }
    }
    
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }
    
    return batches;
  }

  bool _canBatchWith(IOOperation first, IOOperation second) {
    // Same type operations can be batched
    if (first.type != second.type) return false;
    
    // Same priority level
    if (first.priority != second.priority) return false;
    
    // Similar file paths (same directory)
    if (!_arePathsCompatible(first.path, second.path)) return false;
    
    return true;
  }

  bool _arePathsCompatible(String path1, String path2) {
    final dir1 = path1.substring(0, path1.lastIndexOf('/'));
    final dir2 = path2.substring(0, path2.lastIndexOf('/'));
    return dir1 == dir2;
  }

  IOPriority _determineBatchPriority(List<IOOperation> operations) {
    if (operations.any((op) => op.priority == IOPriority.high)) {
      return IOPriority.high;
    } else if (operations.any((op) => op.priority == IOPriority.normal)) {
      return IOPriority.normal;
    }
    return IOPriority.low;
  }

  IOOperation? _findOperationInQueues(String operationId) {
    final allQueues = [_highPriorityQueue, _normalQueue, _lowPriorityQueue];
    
    for (final queue in allQueues) {
      for (final operation in queue) {
        if (operation.id == operationId) {
          return operation;
        }
      }
    }
    
    return null;
  }

  void _removeOperationFromQueues(String operationId) {
    _highPriorityQueue.removeWhere((op) => op.id == operationId);
    _normalQueue.removeWhere((op) => op.id == operationId);
    _lowPriorityQueue.removeWhere((op) => op.id == operationId);
  }

  Future<void> _optimizeQueues() async {
    // Reorder operations based on learned patterns
    await _reorderQueues();
    
    // Merge compatible operations
    await _mergeCompatibleOperations();
    
    // Clean up old performance metrics
    _cleanupPerformanceHistory();
    
    _ioController.add(IOEvent(
      type: IOEventType.optimizationCompleted,
      data: {
        'queue_depth': totalQueuedOperations,
        'performance_metrics': _performanceHistory.length,
      },
    ));
  }

  Future<void> _reorderQueues() async {
    // Reorder operations based on historical performance
    for (final queue in [_highPriorityQueue, _normalQueue, _lowPriorityQueue]) {
      if (queue.isEmpty) continue;
      
      final operations = queue.toList();
      queue.clear();
      
      // Sort by predicted performance
      operations.sort((a, b) => _predictOperationPerformance(a).compareTo(_predictOperationPerformance(b)));
      
      for (final operation in operations) {
        queue.add(operation);
      }
    }
  }

  Future<void> _mergeCompatibleOperations() async {
    // Look for merge opportunities in queues
    for (final queue in [_normalQueue, _lowPriorityQueue]) {
      if (queue.length < 2) continue;
      
      final operations = queue.toList();
      queue.clear();
      
      final merged = <IOOperation>[];
      final toRemove = <int>{};
      
      for (int i = 0; i < operations.length; i++) {
        if (toRemove.contains(i)) continue;
        
        final current = operations[i];
        
        // Look for merge candidates
        for (int j = i + 1; j < operations.length; j++) {
          if (toRemove.contains(j)) continue;
          
          final candidate = operations[j];
          
          if (_canMergeOperations(current, candidate)) {
            // Merge operations
            final mergedOp = _mergeOperations(current, candidate);
            merged.add(mergedOp);
            toRemove.add(i);
            toRemove.add(j);
            break;
          }
        }
        
        if (!toRemove.contains(i)) {
          merged.add(current);
        }
      }
      
      for (final operation in merged) {
        queue.add(operation);
      }
    }
  }

  bool _canMergeOperations(IOOperation op1, IOOperation op2) {
    // Can merge read operations on same file
    if (op1.type == IOType.read && op2.type == IOType.read && op1.path == op2.path) {
      return true;
    }
    
    // Can merge write operations to same file
    if (op1.type == IOType.write && op2.type == IOType.write && op1.path == op2.path) {
      return true;
    }
    
    return false;
  }

  IOOperation _mergeOperations(IOOperation op1, IOOperation op2) {
    return IOOperation(
      id: _generateOperationId(),
      type: op1.type,
      path: op1.path,
      priority: math.max(op1.priority.index, op2.priority.index) == 0 ? IOPriority.high :
              math.max(op1.priority.index, op2.priority.index) == 1 ? IOPriority.normal : IOPriority.low,
      data: {...op1.data, ...op2.data},
      createdAt: DateTime.now(),
    );
  }

  double _predictOperationPerformance(IOOperation operation) {
    // Use historical data to predict performance
    final relevantMetrics = _performanceHistory
        .where((m) => m.operationType == operation.type)
        .takeLast(20);
    
    if (relevantMetrics.isEmpty) return 0.5;
    
    final avgLatency = relevantMetrics
        .map((m) => m.latency.inMilliseconds)
        .reduce((a, b) => a + b) / relevantMetrics.length;
    
    // Lower latency = higher performance score
    return math.max(0.0, 1.0 - (avgLatency / 100.0));
  }

  void _cleanupPerformanceHistory() {
    if (_performanceHistory.length > 1000) {
      _performanceHistory.removeRange(0, _performanceHistory.length - 1000);
    }
  }

  double _calculateBatchEfficiency() {
    final recentMetrics = _performanceHistory.takeLast(100).toList();
    if (recentMetrics.isEmpty) return 0.0;
    
    // Calculate how many operations were processed in batches
    final batchedOperations = recentMetrics.where((m) => 
        m.timestamp.difference(recentMetrics.first.timestamp).inMilliseconds < _batchTimeout.inMilliseconds).length;
    
    return batchedOperations / recentMetrics.length;
  }

  double _calculateErrorRate() {
    final recentMetrics = _performanceHistory.takeLast(100).toList();
    if (recentMetrics.isEmpty) return 0.0;
    
    final failedOperations = recentMetrics.where((m) => !m.successful).length;
    return failedOperations / recentMetrics.length;
  }

  String _generateOperationId() {
    return 'io_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000)}';
  }

  String _generateBatchId() {
    return 'batch_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> dispose() async {
    _processingTimer?.cancel();
    _optimizationTimer?.cancel();
    _ioController.close();
    
    _highPriorityQueue.clear();
    _normalQueue.clear();
    _lowPriorityQueue.clear();
    _activeBatches.clear();
    _performanceHistory.clear();
  }
}

class IOOperation {
  final String id;
  final IOType type;
  final String path;
  IOPriority priority;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  
  IOOperation({
    required this.id,
    required this.type,
    required this.path,
    required this.priority,
    required this.data,
    required this.createdAt,
  });
}

class IOBatch {
  final String id;
  final List<IOOperation> operations;
  final DateTime createdAt;
  final IOPriority priority;
  
  IOBatch({
    required this.id,
    required this.operations,
    required this.createdAt,
    required this.priority,
  });
}

class IOOperationResult {
  final bool success;
  final String operationId;
  final String? error;
  
  IOOperationResult({
    required this.success,
    required this.operationId,
    this.error,
  });
  
  factory IOOperationResult.success(String operationId) {
    return IOOperationResult(
      success: true,
      operationId: operationId,
    );
  }
  
  factory IOOperationResult.error(String error, String operationId) {
    return IOOperationResult(
      success: false,
      operationId: operationId,
      error: error,
    );
  }
}

class IOPerformanceMetric {
  final String operationId;
  final IOType operationType;
  final Duration latency;
  final DateTime timestamp;
  final bool successful;
  
  IOPerformanceMetric({
    required this.operationId,
    required this.operationType,
    required this.latency,
    required this.timestamp,
    required this.successful,
  });
}

class IOPerformanceStatistics {
  final Duration averageLatency;
  final double throughput;
  final int queueDepth;
  final double batchEfficiency;
  final double errorRate;
  
  IOPerformanceStatistics({
    required this.averageLatency,
    required this.throughput,
    required this.queueDepth,
    required this.batchEfficiency,
    required this.errorRate,
  });
}

class IOEvent {
  final IOEventType type;
  final Map<String, dynamic>? data;
  
  IOEvent({
    required this.type,
    this.data,
  });
}

enum IOType {
  read,
  write,
  delete,
  copy,
  move,
}

enum IOPriority {
  high,
  normal,
  low,
}

enum IOEventType {
  operationQueued,
  operationCompleted,
  batchCompleted,
  batchFailed,
  optimizationCompleted,
}

/// Priority queue implementation
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
  
  bool removeWhere(bool Function(T) test) {
    final initialLength = _heap.length;
    _heap.removeWhere(test);
    
    // Rebuild heap if items were removed
    if (_heap.length != initialLength) {
      final items = List.from(_heap);
      _heap.clear();
      for (final item in items) {
        add(item);
      }
    }
    
    return _heap.length != initialLength;
  }
}


