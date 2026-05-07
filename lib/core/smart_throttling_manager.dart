import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Smart Throttling Manager - Best-in-class background operation management
/// 
/// Provides intelligent throttling for background operations:
/// - Adaptive throttling based on system performance
/// - Priority-based operation queuing
/// - Resource-aware scheduling
/// - Performance impact monitoring
/// - Automatic throttling adjustments
/// - Operation cancellation and retry logic
class SmartThrottlingManager {
  static final SmartThrottlingManager _instance = SmartThrottlingManager._internal();
  factory SmartThrottlingManager() => _instance;
  SmartThrottlingManager._internal();

  final Map<String, ThrottledOperation> _operations = {};
  final Queue<QueuedOperation> _operationQueue = Queue<QueuedOperation>();
  final Map<String, OperationMetrics> _operationMetrics = {};
  final Map<OperationPriority, Queue<QueuedOperation>> _priorityQueues = {};
  
  bool _isInitialized = false;
  bool _isThrottling = false;
  Timer? _processingTimer;
  Timer? _adjustmentTimer;
  
  // Throttling configuration
  static const Duration _processingInterval = Duration(milliseconds: 100);
  static const Duration _adjustmentInterval = Duration(seconds: 5);
  static const int _maxConcurrentOperations = 5;
  static const int _maxQueueSize = 1000;
  
  // Throttling state
  double _currentThrottleLevel = 0.0; // 0.0 = no throttling, 1.0 = maximum throttling
  ThrottlingStrategy _currentStrategy = ThrottlingStrategy.adaptive;
  int _activeOperations = 0;
  double _systemLoad = 0.0;
  
  final _eventController = StreamController<ThrottlingEvent>.broadcast();
  Stream<ThrottlingEvent> get events => _eventController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get isThrottling => _isThrottling;
  double get currentThrottleLevel => _currentThrottleLevel;
  int get activeOperations => _activeOperations;
  int get queuedOperations => _operationQueue.length;

  /// Initialize the smart throttling manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize priority queues
      _initializePriorityQueues();
      
      // Start processing timer
      _startProcessingTimer();
      
      // Start adjustment timer
      _startAdjustmentTimer();
      
      _isInitialized = true;
      debugPrint('🚦 Smart Throttling Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Smart Throttling Manager: $e');
      rethrow;
    }
  }

  /// Submit an operation for throttled execution
  Future<T> submitOperation<T>(
    String id,
    Future<T> Function() operation, {
    OperationPriority priority = OperationPriority.normal,
    Duration? timeout,
    int? maxRetries,
    String? category,
  }) async {
    if (_operations.containsKey(id)) {
      throw ArgumentError('Operation with ID $id already exists');
    }

    final completer = Completer<T>();
    final queuedOp = QueuedOperation(
      id: id,
      operation: operation,
      priority: priority,
      timeout: timeout ?? Duration(seconds: 30),
      maxRetries: maxRetries ?? 3,
      category: category ?? 'default',
      completer: completer,
      submittedAt: DateTime.now(),
    );

    // Add to appropriate priority queue
    _priorityQueues[priority]!.add(queuedOp);
    
    // Track operation metrics
    _operationMetrics[id] = OperationMetrics(id, category ?? 'default');
    
    debugPrint('🚦 Submitted operation: $id (priority: $priority)');

    return completer.future;
  }

  /// Cancel an operation
  bool cancelOperation(String id) {
    // Check if operation is in queue
    for (final queue in _priorityQueues.values) {
      final operation = queue.cast<QueuedOperation?>().firstWhere(
        (op) => op?.id == id,
        orElse: () => null,
      );
      
      if (operation != null) {
        queue.remove(operation);
        operation.completer.completeError(OperationCancelledException(id));
        _operationMetrics.remove(id);
        debugPrint('🚦 Cancelled operation: $id');
        return true;
      }
    }
    
    return false;
  }

  /// Set throttling strategy
  void setThrottlingStrategy(ThrottlingStrategy strategy) {
    _currentStrategy = strategy;
    debugPrint('🚦 Set throttling strategy: $strategy');
    
    _eventController.add(ThrottlingEvent(
      type: ThrottlingEventType.strategyChanged,
      message: 'Throttling strategy changed to $strategy',
      timestamp: DateTime.now(),
      data: {'strategy': strategy.toString()},
    ));
  }

  /// Set manual throttle level
  void setThrottleLevel(double level) {
    _currentThrottleLevel = level.clamp(0.0, 1.0);
    debugPrint('🚦 Set throttle level: ${(_currentThrottleLevel * 100).toStringAsFixed(0)}%');
  }

  /// Get throttling statistics
  ThrottlingStatistics getStatistics() {
    return ThrottlingStatistics(
      activeOperations: _activeOperations,
      queuedOperations: _operationQueue.length,
      throttleLevel: _currentThrottleLevel,
      strategy: _currentStrategy,
      systemLoad: _systemLoad,
      totalOperations: _operationMetrics.length,
      averageExecutionTime: _calculateAverageExecutionTime(),
      successRate: _calculateSuccessRate(),
    );
  }

  /// Initialize priority queues
  void _initializePriorityQueues() {
    for (final priority in OperationPriority.values) {
      _priorityQueues[priority] = Queue<QueuedOperation>();
    }
  }

  /// Start processing timer
  void _startProcessingTimer() {
    _processingTimer = Timer.periodic(_processingInterval, (_) {
      _processOperations();
    });
  }

  /// Start adjustment timer
  void _startAdjustmentTimer() {
    _adjustmentTimer = Timer.periodic(_adjustmentInterval, (_) {
      _adjustThrottling();
    });
  }

  /// Process queued operations
  void _processOperations() {
    if (_activeOperations >= _maxConcurrentOperations) return;
    
    // Get next operation based on priority and throttling
    final operation = _getNextOperation();
    if (operation == null) return;
    
    // Check if we should execute based on throttling
    if (!_shouldExecuteOperation(operation)) {
      return;
    }
    
    _activeOperations++;
    
    // Execute operation
    _executeOperation(operation).then((_) {
      _activeOperations--;
    }).catchError((e) {
      _activeOperations--;
      debugPrint('❌ Operation failed: ${operation.id} - $e');
    });
  }

  /// Get next operation to execute
  QueuedOperation? _getNextOperation() {
    // Check queues in priority order
    for (final priority in OperationPriority.values) {
      final queue = _priorityQueues[priority]!;
      if (queue.isNotEmpty) {
        return queue.removeFirst();
      }
    }
    return null;
  }

  /// Check if operation should be executed based on throttling
  bool _shouldExecuteOperation(QueuedOperation operation) {
    switch (_currentStrategy) {
      case ThrottlingStrategy.none:
        return true;
        
      case ThrottlingStrategy.fixed:
        return math.Random().nextDouble() > _currentThrottleLevel;
        
      case ThrottlingStrategy.adaptive:
        return _adaptiveShouldExecute(operation);
        
      case ThrottlingStrategy.priorityBased:
        return _priorityBasedShouldExecute(operation);
        
      case ThrottlingStrategy.loadBased:
        return _loadBasedShouldExecute(operation);
    }
  }

  /// Adaptive throttling decision
  bool _adaptiveShouldExecute(QueuedOperation operation) {
    // Consider system load, operation priority, and current throttle level
    final priorityFactor = _getPriorityFactor(operation.priority);
    final loadFactor = 1.0 - _systemLoad;
    final throttleFactor = 1.0 - _currentThrottleLevel;
    
    final executionProbability = priorityFactor * loadFactor * throttleFactor;
    return math.Random().nextDouble() < executionProbability;
  }

  /// Priority-based throttling decision
  bool _priorityBasedShouldExecute(QueuedOperation operation) {
    switch (operation.priority) {
      case OperationPriority.critical:
        return true;
      case OperationPriority.high:
        return _currentThrottleLevel < 0.7;
      case OperationPriority.normal:
        return _currentThrottleLevel < 0.5;
      case OperationPriority.low:
        return _currentThrottleLevel < 0.3;
      case OperationPriority.background:
        return _currentThrottleLevel < 0.1;
    }
  }

  /// Load-based throttling decision
  bool _loadBasedShouldExecute(QueuedOperation operation) {
    if (_systemLoad < 0.5) return true;
    if (_systemLoad > 0.8) return false;
    
    // Moderate load - throttle based on priority
    return _priorityBasedShouldExecute(operation);
  }

  /// Get priority factor for adaptive throttling
  double _getPriorityFactor(OperationPriority priority) {
    switch (priority) {
      case OperationPriority.critical: return 1.0;
      case OperationPriority.high: return 0.8;
      case OperationPriority.normal: return 0.6;
      case OperationPriority.low: return 0.4;
      case OperationPriority.background: return 0.2;
    }
  }

  /// Execute an operation
  Future<void> _executeOperation(QueuedOperation operation) async {
    final metrics = _operationMetrics[operation.id]!;
    metrics.executionAttempts++;
    
    debugPrint('🚦 Executing operation: ${operation.id}');
    
    try {
      // Execute with timeout
      final result = await operation.operation().timeout(operation.timeout);
      
      // Update metrics
      metrics.executionTime = DateTime.now().difference(operation.submittedAt);
      metrics.successfulExecutions++;
      
      // Complete successfully
      operation.completer.complete(result);
      
      debugPrint('✅ Operation completed: ${operation.id}');
      
    } catch (e) {
      metrics.failedExecutions++;
      
      // Check if we should retry
      if (metrics.executionAttempts <= operation.maxRetries) {
        debugPrint('🔄 Retrying operation: ${operation.id} (attempt ${metrics.executionAttempts}/${operation.maxRetries})');
        
        // Add back to queue with delay
        Future.delayed(Duration(seconds: metrics.executionAttempts * 2), () {
          _priorityQueues[operation.priority]!.add(operation);
        });
      } else {
        debugPrint('❌ Operation failed permanently: ${operation.id}');
        operation.completer.completeError(e);
      }
    }
  }

  /// Adjust throttling based on system conditions
  void _adjustThrottling() {
    // Update system load
    _systemLoad = _getSystemLoad();
    
    switch (_currentStrategy) {
      case ThrottlingStrategy.adaptive:
        _adjustAdaptiveThrottling();
        break;
      case ThrottlingStrategy.loadBased:
        _adjustLoadBasedThrottling();
        break;
      default:
        break;
    }
    
    // Check queue sizes and adjust if necessary
    _adjustForQueueSize();
  }

  /// Adaptive throttling adjustment
  void _adjustAdaptiveThrottling() {
    final targetLevel = _systemLoad;
    final currentLevel = _currentThrottleLevel;
    
    // Gradually adjust towards target
    final adjustment = (targetLevel - currentLevel) * 0.1;
    _currentThrottleLevel = (currentLevel + adjustment).clamp(0.0, 1.0);
  }

  /// Load-based throttling adjustment
  void _adjustLoadBasedThrottling() {
    if (_systemLoad > 0.8) {
      _currentThrottleLevel = 1.0;
    } else if (_systemLoad > 0.6) {
      _currentThrottleLevel = 0.7;
    } else if (_systemLoad > 0.4) {
      _currentThrottleLevel = 0.4;
    } else {
      _currentThrottleLevel = 0.0;
    }
  }

  /// Adjust throttling based on queue size
  void _adjustForQueueSize() {
    final totalQueued = _priorityQueues.values.fold(0, (sum, queue) => sum + queue.length);
    
    if (totalQueued > _maxQueueSize * 0.8) {
      // Queue is getting full, increase throttling
      _currentThrottleLevel = (_currentThrottleLevel + 0.1).clamp(0.0, 1.0);
    } else if (totalQueued < _maxQueueSize * 0.2 && _currentThrottleLevel > 0.1) {
      // Queue is mostly empty, decrease throttling
      _currentThrottleLevel = (_currentThrottleLevel - 0.1).clamp(0.0, 1.0);
    }
  }

  /// Get current system load (simulated)
  double _getSystemLoad() {
    // This would typically use platform channels to get actual system metrics
    // For now, simulate based on active operations
    final operationLoad = _activeOperations / _maxConcurrentOperations;
    final queueLoad = _operationQueue.length / _maxQueueSize;
    
    return (operationLoad * 0.7 + queueLoad * 0.3).clamp(0.0, 1.0);
  }

  /// Calculate average execution time
  Duration _calculateAverageExecutionTime() {
    if (_operationMetrics.isEmpty) return Duration.zero;
    
    final completedMetrics = _operationMetrics.values
        .where((m) => m.executionTime != null)
        .toList();
    
    if (completedMetrics.isEmpty) return Duration.zero;
    
    final totalMs = completedMetrics
        .map((m) => m.executionTime!.inMilliseconds)
        .reduce((a, b) => a + b);
    
    return Duration(milliseconds: totalMs ~/ completedMetrics.length);
  }

  /// Calculate success rate
  double _calculateSuccessRate() {
    if (_operationMetrics.isEmpty) return 1.0;
    
    final totalExecutions = _operationMetrics.values
        .map((m) => m.executionAttempts)
        .reduce((a, b) => a + b);
    
    final totalSuccesses = _operationMetrics.values
        .map((m) => m.successfulExecutions)
        .reduce((a, b) => a + b);
    
    return totalExecutions > 0 ? totalSuccesses / totalExecutions : 1.0;
  }

  /// Dispose the smart throttling manager
  Future<void> dispose() async {
    _processingTimer?.cancel();
    _adjustmentTimer?.cancel();
    _eventController.close();
    
    // Cancel all pending operations
    for (final queue in _priorityQueues.values) {
      for (final operation in queue) {
        operation.completer.completeError(OperationCancelledException('System shutting down'));
      }
    }
    
    _operations.clear();
    _operationQueue.clear();
    _operationMetrics.clear();
    _priorityQueues.clear();
    
    debugPrint('🚦 Smart Throttling Manager disposed');
  }
}

/// Queued operation
class QueuedOperation {
  final String id;
  final Future<dynamic> Function() operation;
  final OperationPriority priority;
  final Duration timeout;
  final int maxRetries;
  final String category;
  final Completer<dynamic> completer;
  final DateTime submittedAt;
  
  QueuedOperation({
    required this.id,
    required this.operation,
    required this.priority,
    required this.timeout,
    required this.maxRetries,
    required this.category,
    required this.completer,
    required this.submittedAt,
  });
}

/// Operation metrics
class OperationMetrics {
  final String id;
  final String category;
  int executionAttempts = 0;
  int successfulExecutions = 0;
  int failedExecutions = 0;
  Duration? executionTime;
  
  OperationMetrics(this.id, this.category);
  
  double get successRate => executionAttempts > 0 ? successfulExecutions / executionAttempts : 0.0;
}

/// Throttling event
class ThrottlingEvent {
  final ThrottlingEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  
  ThrottlingEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

/// Throttling statistics
class ThrottlingStatistics {
  final int activeOperations;
  final int queuedOperations;
  final double throttleLevel;
  final ThrottlingStrategy strategy;
  final double systemLoad;
  final int totalOperations;
  final Duration averageExecutionTime;
  final double successRate;
  
  ThrottlingStatistics({
    required this.activeOperations,
    required this.queuedOperations,
    required this.throttleLevel,
    required this.strategy,
    required this.systemLoad,
    required this.totalOperations,
    required this.averageExecutionTime,
    required this.successRate,
  });
}

/// Enums
enum OperationPriority { critical, high, normal, low, background }
enum ThrottlingStrategy { none, fixed, adaptive, priorityBased, loadBased }
enum ThrottlingEventType { strategyChanged, operationCompleted, operationFailed, queueFull }

/// Exceptions
class OperationCancelledException implements Exception {
  final String operationId;
  
  OperationCancelledException(this.operationId);
  
  @override
  String toString() => 'Operation cancelled: $operationId';
}
