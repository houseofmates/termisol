import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';

class BackgroundFileOperations {
  static const int _maxConcurrentOperations = 5;
  static const int _operationTimeout = 300000; // 5 minutes
  static const int _progressUpdateInterval = 500; // 500ms
  static const int _cleanupInterval = 60000; // 1 minute
  
  final Map<String, FileOperation> _activeOperations = {};
  final Queue<FileOperation> _operationQueue = Queue();
  final List<FileOperation> _completedOperations = [];
  final Map<String, FileOperationStats> _operationStats = {};
  
  Timer? _cleanupTimer;
  Timer? _progressTimer;
  int _totalOperations = 0;
  int _totalBytesTransferred = 0;
  
  final StreamController<FileOperationEvent> _operationEventController = 
      StreamController<FileOperationEvent>.broadcast();

  void initialize() {
    _startCleanupTimer();
    _startProgressTimer();
    developer.log('📁 Background File Operations initialized');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      Duration(milliseconds: _cleanupInterval),
      (_) => _cleanupOperations(),
    );
  }

  void _startProgressTimer() {
    _progressTimer = Timer.periodic(
      Duration(milliseconds: _progressUpdateInterval),
      (_) => _updateProgress(),
    );
  }

  String copyFile(String source, String destination, {
    FileOperationPriority priority = FileOperationPriority.normal,
    bool overwrite = false,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _enqueueFileOperation(
      FileOperationType.copy,
      source,
      destination,
      priority: priority,
      overwrite: overwrite,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String moveFile(String source, String destination, {
    FileOperationPriority priority = FileOperationPriority.normal,
    bool overwrite = false,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _enqueueFileOperation(
      FileOperationType.move,
      source,
      destination,
      priority: priority,
      overwrite: overwrite,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String deleteFile(String path, {
    FileOperationPriority priority = FileOperationPriority.normal,
    bool secure = false,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _enqueueFileOperation(
      FileOperationType.delete,
      path,
      '',
      priority: priority,
      secure: secure,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String _enqueueFileOperation(
    FileOperationType type,
    String source,
    String destination, {
    FileOperationPriority priority = FileOperationPriority.normal,
    bool overwrite = false,
    bool secure = false,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    final operationId = _generateOperationId();
    
    // Check if source exists
    final sourceFile = File(source);
    if (!sourceFile.existsSync()) {
      onError?.call('Source file does not exist: $source');
      return '';
    }
    
    // Get file size
    final fileSize = sourceFile.lengthSync();
    
    final operation = FileOperation(
      id: operationId,
      type: type,
      source: source,
      destination: destination,
      priority: priority,
      overwrite: overwrite,
      secure: secure,
      fileSize: fileSize,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      createdAt: DateTime.now(),
    );

    if (_activeOperations.length < _maxConcurrentOperations) {
      _startOperation(operation);
    } else {
      _queueOperation(operation);
    }

    _totalOperations++;
    
    _emitEvent(FileOperationEvent(
      type: FileOperationEventType.queued,
      operationId: operationId,
      operationType: type,
      source: source,
      destination: destination,
      fileSize: fileSize,
    ));

    return operationId;
  }

  void _startOperation(FileOperation operation) {
    operation.status = FileOperationStatus.running;
    operation.startedAt = DateTime.now();
    _activeOperations[operation.id] = operation;

    // Execute operation in background
    _executeOperation(operation);
  }

  void _queueOperation(FileOperation operation) {
    operation.status = FileOperationStatus.queued;
    _operationQueue.add(operation);
    
    // Sort queue by priority
    _operationQueue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    
    developer.log('📁 Queued file operation: ${operation.type} ${operation.source} (ID: ${operation.id})');
  }

  Future<void> _executeOperation(FileOperation operation) async {
    try {
      developer.log('📁 Executing: ${operation.type} ${operation.source}');
      
      _emitEvent(FileOperationEvent(
        type: FileOperationEventType.started,
        operationId: operation.id,
        operationType: operation.type,
        source: operation.source,
        destination: operation.destination,
      ));

      switch (operation.type) {
        case FileOperationType.copy:
          await _performCopy(operation);
          break;
        case FileOperationType.move:
          await _performMove(operation);
          break;
        case FileOperationType.delete:
          await _performDelete(operation);
          break;
      }

      operation.status = FileOperationStatus.completed;
      operation.completedAt = DateTime.now();
      
      _totalBytesTransferred += operation.fileSize;
      _updateOperationStats(operation);
      
      if (operation.onComplete != null) {
        operation.onComplete!();
      }
      
      developer.log('📁 Completed: ${operation.type} ${operation.source} in ${operation.duration}ms');
      
      _emitEvent(FileOperationEvent(
        type: FileOperationEventType.completed,
        operationId: operation.id,
        operationType: operation.type,
        source: operation.source,
        destination: operation.destination,
        duration: operation.duration,
        bytesTransferred: operation.fileSize,
      ));

    } catch (e) {
      operation.status = FileOperationStatus.failed;
      operation.completedAt = DateTime.now();
      operation.error = e.toString();
      
      if (operation.onError != null) {
        operation.onError!(e.toString());
      }
      
      developer.log('📁 Failed: ${operation.type} ${operation.source} - $e');
      
      _emitEvent(FileOperationEvent(
        type: FileOperationEventType.failed,
        operationId: operation.id,
        operationType: operation.type,
        source: operation.source,
        error: e.toString(),
      ));
    } finally {
      _activeOperations.remove(operation.id);
      _completedOperations.add(operation);
      
      // Start next queued operation
      if (_operationQueue.isNotEmpty) {
        final nextOperation = _operationQueue.removeFirst();
        _startOperation(nextOperation);
      }
    }
  }

  Future<void> _performCopy(FileOperation operation) async {
    final sourceFile = File(operation.source);
    final destinationFile = File(operation.destination);
    
    // Check if destination exists
    if (destinationFile.existsSync() && !operation.overwrite) {
      throw Exception('Destination file exists and overwrite is false');
    }
    
    // Ensure destination directory exists
    final destinationDir = destinationFile.parent;
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    
    // Perform copy with progress
    final source = sourceFile.openRead();
    final sink = destinationFile.openWrite();
    
    int bytesTransferred = 0;
    await for (final chunk in source) {
      sink.add(chunk);
      bytesTransferred += chunk.length;
      
      // Update progress
      final progress = bytesTransferred / operation.fileSize;
      operation.progress = progress;
      
      if (operation.onProgress != null) {
        operation.onProgress!(progress);
      }
    }
    
    await source.close();
    await sink.close();
  }

  Future<void> _performMove(FileOperation operation) async {
    final sourceFile = File(operation.source);
    final destinationFile = File(operation.destination);
    
    // Check if destination exists
    if (destinationFile.existsSync() && !operation.overwrite) {
      throw Exception('Destination file exists and overwrite is false');
    }
    
    // Ensure destination directory exists
    final destinationDir = destinationFile.parent;
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    
    // Perform move
    await sourceFile.rename(operation.destination);
    
    // Update progress
    operation.progress = 1.0;
    if (operation.onProgress != null) {
      operation.onProgress!(1.0);
    }
  }

  Future<void> _performDelete(FileOperation operation) async {
    final file = File(operation.source);
    
    if (operation.secure) {
      // Secure delete - overwrite file multiple times
      final fileSize = file.lengthSync();
      final random = Random();
      
      for (int pass = 0; pass < 3; pass++) {
        final sink = file.openWrite();
        
        // Generate random data
        final randomData = List<int>.generate(fileSize, (_) => random.nextInt(256));
        sink.add(randomData);
        
        await sink.close();
        
        // Update progress
        final progress = (pass + 1) / 3.0;
        operation.progress = progress;
        
        if (operation.onProgress != null) {
          operation.onProgress!(progress);
        }
      }
    }
    
    // Delete the file
    await file.delete();
    
    // Update progress
    operation.progress = 1.0;
    if (operation.onProgress != null) {
      operation.onProgress!(1.0);
    }
  }

  void _updateProgress() {
    for (final operation in _activeOperations.values) {
      if (operation.status == FileOperationStatus.running && operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
  }

  void _cleanupOperations() {
    final now = DateTime.now();
    final operationsToRemove = <String>[];
    
    // Clean up completed operations older than 1 hour
    for (final entry in _activeOperations.entries) {
      final operationId = entry.key;
      final operation = entry.value;
      
      if ((operation.status == FileOperationStatus.completed || 
           operation.status == FileOperationStatus.failed) &&
          operation.completedAt != null &&
          now.difference(operation.completedAt!).inMinutes > 60) {
        operationsToRemove.add(operationId);
      }
    }
    
    // Remove old operations
    for (final operationId in operationsToRemove) {
      final operation = _activeOperations.remove(operationId);
      if (operation != null) {
        developer.log('📁 Cleaned up operation: ${operation.type} ${operation.source} (ID: $operationId)');
      }
    }
    
    // Clean up completed operations history
    _completedOperations.removeWhere((operation) => 
        now.difference(operation.completedAt ?? operation.createdAt).inHours > 24);
  }

  void _updateOperationStats(FileOperation operation) {
    final statsKey = '${operation.type}_${operation.source.split('/').last}';
    final stats = _operationStats.putIfAbsent(
      statsKey,
      () => FileOperationStats(operationType: operation.type),
    );
    
    stats.recordOperation(operation);
  }

  bool cancelOperation(String operationId) {
    final operation = _activeOperations[operationId];
    if (operation == null) return false;
    
    operation.status = FileOperationStatus.cancelled;
    operation.completedAt = DateTime.now();
    
    _activeOperations.remove(operationId);
    
    developer.log('📁 Cancelled operation: ${operation.type} ${operation.source} (ID: $operationId)');
    
    _emitEvent(FileOperationEvent(
      type: FileOperationEventType.cancelled,
      operationId: operationId,
      operationType: operation.type,
      source: operation.source,
    ));
    
    return true;
  }

  FileOperation? getOperation(String operationId) {
    return _activeOperations[operationId];
  }

  List<FileOperation> getActiveOperations() {
    return _activeOperations.values.toList();
  }

  List<FileOperation> getQueuedOperations() {
    return _operationQueue.toList();
  }

  String _generateOperationId() {
    return 'op_${DateTime.now().millisecondsSinceEpoch}_$_totalOperations';
  }

  void _emitEvent(FileOperationEvent event) {
    _operationEventController.add(event);
  }

  Stream<FileOperationEvent> get operationEventStream => _operationEventController.stream;

  BackgroundFileOperationsStats getStats() {
    return BackgroundFileOperationsStats(
      totalOperations: _totalOperations,
      activeOperations: _activeOperations.length,
      queuedOperations: _operationQueue.length,
      totalBytesTransferred: _totalBytesTransferred,
      completedOperations: _completedOperations.length,
      operationStats: _operationStats.values.toList(),
    );
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _progressTimer?.cancel();
    
    // Cancel all active operations
    for (final operationId in _activeOperations.keys.toList()) {
      cancelOperation(operationId);
    }
    
    _activeOperations.clear();
    _operationQueue.clear();
    _completedOperations.clear();
    _operationStats.clear();
    _operationEventController.close();
    
    developer.log('📁 Background File Operations disposed');
  }
}

class FileOperation {
  final String id;
  final FileOperationType type;
  final String source;
  final String destination;
  final FileOperationPriority priority;
  final bool overwrite;
  final bool secure;
  final int fileSize;
  final Function(double)? onProgress;
  final Function()? onComplete;
  final Function(String)? onError;
  final DateTime createdAt;
  
  FileOperationStatus status = FileOperationStatus.created;
  DateTime? startedAt;
  DateTime? completedAt;
  double progress = 0.0;
  String? error;

  FileOperation({
    required this.id,
    required this.type,
    required this.source,
    required this.destination,
    required this.priority,
    required this.overwrite,
    required this.secure,
    required this.fileSize,
    this.onProgress,
    this.onComplete,
    this.onError,
    required this.createdAt,
  });

  int? get duration {
    if (startedAt == null || completedAt == null) return null;
    return completedAt!.difference(startedAt!).inMilliseconds;
  }
}

enum FileOperationType {
  copy,
  move,
  delete,
}

enum FileOperationPriority {
  low,
  normal,
  high,
  urgent,
}

enum FileOperationStatus {
  created,
  queued,
  running,
  completed,
  failed,
  cancelled,
}

class FileOperationStats {
  final FileOperationType operationType;
  int totalOperations = 0;
  int totalBytesTransferred = 0;
  int totalDuration = 0;
  int successCount = 0;
  int failureCount = 0;
  DateTime lastOperation = DateTime.now();

  FileOperationStats({required this.operationType});

  void recordOperation(FileOperation operation) {
    totalOperations++;
    lastOperation = operation.completedAt ?? DateTime.now();
    
    if (operation.fileSize > 0) {
      totalBytesTransferred += operation.fileSize;
    }
    
    if (operation.duration != null) {
      totalDuration += operation.duration!;
    }
    
    if (operation.status == FileOperationStatus.completed) {
      successCount++;
    } else if (operation.status == FileOperationStatus.failed) {
      failureCount++;
    }
  }

  double getAverageDuration() {
    return totalOperations > 0 ? totalDuration / totalOperations : 0.0;
  }

  double getSuccessRate() {
    return totalOperations > 0 ? successCount / totalOperations : 0.0;
  }

  double getAverageTransferRate() {
    final totalTime = totalDuration / 1000.0; // Convert to seconds
    return totalTime > 0 ? totalBytesTransferred / totalTime : 0.0;
  }
}

enum FileOperationEventType {
  queued,
  started,
  progress,
  completed,
  failed,
  cancelled,
}

class FileOperationEvent {
  final FileOperationEventType type;
  final String operationId;
  final FileOperationType operationType;
  final String source;
  final String? destination;
  final int? fileSize;
  final double? progress;
  final int? duration;
  final int? bytesTransferred;
  final String? error;

  FileOperationEvent({
    required this.type,
    required this.operationId,
    required this.operationType,
    required this.source,
    this.destination,
    this.fileSize,
    this.progress,
    this.duration,
    this.bytesTransferred,
    this.error,
  });
}

class BackgroundFileOperationsStats {
  final int totalOperations;
  final int activeOperations;
  final int queuedOperations;
  final int totalBytesTransferred;
  final int completedOperations;
  final List<FileOperationStats> operationStats;

  BackgroundFileOperationsStats({
    required this.totalOperations,
    required this.activeOperations,
    required this.queuedOperations,
    required this.totalBytesTransferred,
    required this.completedOperations,
    required this.operationStats,
  });
}
