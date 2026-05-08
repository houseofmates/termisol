import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

class BatchFileOperations {
  static const int _maxBatchSize = 1000;
  static const int _batchTimeout = 600000; // 10 minutes
  static const int _progressUpdateInterval = 1000; // 1 second
  
  final Map<String, BatchOperation> _activeBatches = {};
  final List<BatchOperation> _completedBatches = [];
  final Map<String, BatchOperationStats> _batchStats = {};
  
  Timer? _progressTimer;
  int _totalBatches = 0;
  int _totalFilesProcessed = 0;
  
  final StreamController<BatchEvent> _batchEventController = 
      StreamController<BatchEvent>.broadcast();

  void initialize() {
    _startProgressTimer();
    developer.log('📦 Batch File Operations initialized');
  }

  void _startProgressTimer() {
    _progressTimer = Timer.periodic(
      Duration(milliseconds: _progressUpdateInterval),
      (_) => _updateBatchProgress(),
    );
  }

  String createBatchCopy(List<String> sources, String destinationDir, {
    BatchOperationPriority priority = BatchOperationPriority.normal,
    bool overwrite = false,
    bool preserveStructure = true,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _createBatchOperation(
      BatchOperationType.copy,
      sources,
      destinationDir,
      priority: priority,
      overwrite: overwrite,
      preserveStructure: preserveStructure,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String createBatchMove(List<String> sources, String destinationDir, {
    BatchOperationPriority priority = BatchOperationPriority.normal,
    bool overwrite = false,
    bool preserveStructure = true,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _createBatchOperation(
      BatchOperationType.move,
      sources,
      destinationDir,
      priority: priority,
      overwrite: overwrite,
      preserveStructure: preserveStructure,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String createBatchDelete(List<String> paths, {
    BatchOperationPriority priority = BatchOperationPriority.normal,
    bool secure = false,
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    return _createBatchOperation(
      BatchOperationType.delete,
      paths,
      '',
      priority: priority,
      overwrite: false,
      preserveStructure: false,
      secure: secure,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  String createBatchCompress(List<String> sources, String archivePath, {
    BatchOperationPriority priority = BatchOperationPriority.normal,
    String compressionLevel = 'normal',
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    final operationId = _generateBatchId();
    
    final operation = BatchOperation(
      id: operationId,
      type: BatchOperationType.compress,
      sources: sources,
      destination: archivePath,
      priority: priority,
      compressionLevel: compressionLevel,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      createdAt: DateTime.now(),
    );

    _startBatchOperation(operation);
    _totalBatches++;
    
    _emitEvent(BatchEvent(
      type: BatchEventType.created,
      batchId: operationId,
      operationType: BatchOperationType.compress,
      sourceCount: sources.length,
    ));

    return operationId;
  }

  String _createBatchOperation(
    BatchOperationType type,
    List<String> sources,
    String destination, {
    BatchOperationPriority priority = BatchOperationPriority.normal,
    bool overwrite = false,
    bool preserveStructure = true,
    bool secure = false,
    String compressionLevel = 'normal',
    Function(double)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) {
    final operationId = _generateBatchId();
    
    // Validate batch size
    if (sources.length > _maxBatchSize) {
      onError?.call('Batch size exceeds maximum of $_maxBatchSize files');
      return '';
    }
    
    // Validate sources exist
    final validSources = <String>[];
    for (final source in sources) {
      if (FileSystemEntity.isDirectorySync(source) || File(source).existsSync()) {
        validSources.add(source);
      }
    }
    
    if (validSources.isEmpty) {
      onError?.call('No valid sources found');
      return '';
    }
    
    final operation = BatchOperation(
      id: operationId,
      type: type,
      sources: validSources,
      destination: destination,
      priority: priority,
      overwrite: overwrite,
      preserveStructure: preserveStructure,
      secure: secure,
      compressionLevel: compressionLevel,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      createdAt: DateTime.now(),
    );

    _startBatchOperation(operation);
    _totalBatches++;
    
    _emitEvent(BatchEvent(
      type: BatchEventType.created,
      batchId: operationId,
      operationType: type,
      sourceCount: validSources.length,
    ));

    return operationId;
  }

  void _startBatchOperation(BatchOperation operation) {
    operation.status = BatchStatus.running;
    operation.startedAt = DateTime.now();
    _activeBatches[operation.id] = operation;

    // Execute batch operation
    _executeBatchOperation(operation);
  }

  Future<void> _executeBatchOperation(BatchOperation operation) async {
    try {
      developer.log('📦 Executing batch ${operation.type} with ${operation.sources.length} items');
      
      _emitEvent(BatchEvent(
        type: BatchEventType.started,
        batchId: operation.id,
        operationType: operation.type,
        sourceCount: operation.sources.length,
      ));

      switch (operation.type) {
        case BatchOperationType.copy:
          await _performBatchCopy(operation);
          break;
        case BatchOperationType.move:
          await _performBatchMove(operation);
          break;
        case BatchOperationType.delete:
          await _performBatchDelete(operation);
          break;
        case BatchOperationType.compress:
          await _performBatchCompress(operation);
          break;
      }

      operation.status = BatchStatus.completed;
      operation.completedAt = DateTime.now();
      
      _totalFilesProcessed += operation.sources.length;
      _updateBatchStats(operation);
      
      if (operation.onComplete != null) {
        operation.onComplete!();
      }
      
      developer.log('📦 Completed batch ${operation.type} in ${operation.duration}ms');
      
      _emitEvent(BatchEvent(
        type: BatchEventType.completed,
        batchId: operation.id,
        operationType: operation.type,
        sourceCount: operation.sources.length,
        duration: operation.duration,
        filesProcessed: operation.sources.length,
      ));

    } catch (e) {
      operation.status = BatchStatus.failed;
      operation.completedAt = DateTime.now();
      operation.error = e.toString();
      
      if (operation.onError != null) {
        operation.onError!(e.toString());
      }
      
      developer.log('📦 Failed batch ${operation.type}: $e');
      
      _emitEvent(BatchEvent(
        type: BatchEventType.failed,
        batchId: operation.id,
        operationType: operation.type,
        error: e.toString(),
      ));
    } finally {
      _activeBatches.remove(operation.id);
      _completedBatches.add(operation);
    }
  }

  Future<void> _performBatchCopy(BatchOperation operation) async {
    final destinationDir = Directory(operation.destination);
    
    // Ensure destination directory exists
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    
    int completed = 0;
    
    for (final source in operation.sources) {
      final sourceEntity = FileSystemEntity.isDirectorySync(source) 
          ? Directory(source) 
          : File(source);
      
      final destination = operation.preserveStructure
          ? '${operation.destination}/${path.basename(source)}'
          : operation.destination;
      
      if (sourceEntity is Directory) {
        await _copyDirectory(sourceEntity, Directory(destination), operation.overwrite);
      } else {
        await _copyFile(sourceEntity, File(destination), operation.overwrite);
      }
      
      completed++;
      operation.progress = completed / operation.sources.length;
      
      if (operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
  }

  Future<void> _performBatchMove(BatchOperation operation) async {
    final destinationDir = Directory(operation.destination);
    
    // Ensure destination directory exists
    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }
    
    int completed = 0;
    
    for (final source in operation.sources) {
      final sourceEntity = FileSystemEntity.isDirectorySync(source) 
          ? Directory(source) 
          : File(source);
      
      final destination = operation.preserveStructure
          ? '${operation.destination}/${path.basename(source)}'
          : operation.destination;
      
      if (sourceEntity is Directory) {
        await sourceEntity.rename(destination);
      } else {
        await sourceEntity.rename(destination);
      }
      
      completed++;
      operation.progress = completed / operation.sources.length;
      
      if (operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
  }

  Future<void> _performBatchDelete(BatchOperation operation) async {
    int completed = 0;
    
    // Sort by path length (delete deepest first)
    final sortedPaths = List<String>.from(operation.sources)
      ..sort((a, b) => b.length.compareTo(a.length));
    
    for (final sourcePath in sortedPaths) {
      final entity = FileSystemEntity.isDirectorySync(sourcePath) 
          ? Directory(sourcePath) 
          : File(sourcePath);
      
      if (operation.secure && entity is File) {
        await _secureDeleteFile(entity);
      } else {
        await entity.delete(recursive: true);
      }
      
      completed++;
      operation.progress = completed / operation.sources.length;
      
      if (operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
  }

  Future<void> _performBatchCompress(BatchOperation operation) async {
    // Simplified compression - in practice, use proper compression library
    final archiveFile = File(operation.destination);
    final sink = archiveFile.openWrite();
    
    int completed = 0;
    
    for (final source in operation.sources) {
      final entity = FileSystemEntity.isDirectorySync(source) 
          ? Directory(source) 
          : File(source);
      
      // Write file info to archive
      final relativePath = path.basename(source);
      final fileInfo = '$relativePath|${entity.statSync().size}\n';
      sink.write(utf8.encode(fileInfo));
      
      if (entity is File) {
        final content = await entity.readAsBytes();
        sink.add(content);
      }
      
      completed++;
      operation.progress = completed / operation.sources.length;
      
      if (operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
    
    await sink.close();
  }

  Future<void> _copyDirectory(Directory source, Directory destination, bool overwrite) async {
    if (!destination.existsSync()) {
      destination.createSync(recursive: true);
    }
    
    await for (final entity in source.list()) {
      final targetPath = '${destination.path}/${path.basename(entity.path)}';
      
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath), overwrite);
      } else {
        await _copyFile(entity, File(targetPath), overwrite);
      }
    }
  }

  Future<void> _copyFile(File source, File destination, bool overwrite) async {
    if (destination.existsSync() && !overwrite) {
      throw Exception('Destination file exists and overwrite is false');
    }
    
    await source.copy(destination.path);
  }

  Future<void> _secureDeleteFile(File file) async {
    final fileSize = file.lengthSync();
    final random = Random();
    
    // Overwrite file multiple times
    for (int pass = 0; pass < 3; pass++) {
      final sink = file.openWrite();
      
      // Generate random data
      final randomData = List<int>.generate(fileSize, (_) => random.nextInt(256));
      sink.add(randomData);
      
      await sink.close();
    }
    
    // Delete the file
    await file.delete();
  }

  void _updateBatchProgress() {
    for (final operation in _activeBatches.values) {
      if (operation.status == BatchStatus.running && operation.onProgress != null) {
        operation.onProgress!(operation.progress);
      }
    }
  }

  void _updateBatchStats(BatchOperation operation) {
    final statsKey = '${operation.type}_${operation.sources.length}';
    final stats = _batchStats.putIfAbsent(
      statsKey,
      () => BatchOperationStats(operationType: operation.type),
    );
    
    stats.recordOperation(operation);
  }

  bool cancelBatch(String batchId) {
    final operation = _activeBatches[batchId];
    if (operation == null) return false;
    
    operation.status = BatchStatus.cancelled;
    operation.completedAt = DateTime.now();
    
    _activeBatches.remove(batchId);
    
    developer.log('📦 Cancelled batch operation: ${operation.type} (ID: $batchId)');
    
    _emitEvent(BatchEvent(
      type: BatchEventType.cancelled,
      batchId: batchId,
      operationType: operation.type,
    ));
    
    return true;
  }

  BatchOperation? getBatch(String batchId) {
    return _activeBatches[batchId];
  }

  List<BatchOperation> getActiveBatches() {
    return _activeBatches.values.toList();
  }

  List<BatchOperation> getCompletedBatches() {
    return _completedBatches.toList();
  }

  String _generateBatchId() {
    return 'batch_${DateTime.now().millisecondsSinceEpoch}_$_totalBatches';
  }

  void _emitEvent(BatchEvent event) {
    _batchEventController.add(event);
  }

  Stream<BatchEvent> get batchEventStream => _batchEventController.stream;

  BatchFileOperationsStats getStats() {
    return BatchFileOperationsStats(
      totalBatches: _totalBatches,
      activeBatches: _activeBatches.length,
      completedBatches: _completedBatches.length,
      totalFilesProcessed: _totalFilesProcessed,
      batchStats: _batchStats.values.toList(),
    );
  }

  void dispose() {
    _progressTimer?.cancel();
    
    // Cancel all active batches
    for (final batchId in _activeBatches.keys.toList()) {
      cancelBatch(batchId);
    }
    
    _activeBatches.clear();
    _completedBatches.clear();
    _batchStats.clear();
    _batchEventController.close();
    
    developer.log('📦 Batch File Operations disposed');
  }
}

class BatchOperation {
  final String id;
  final BatchOperationType type;
  final List<String> sources;
  final String destination;
  final BatchOperationPriority priority;
  final bool overwrite;
  final bool preserveStructure;
  final bool secure;
  final String compressionLevel;
  final Function(double)? onProgress;
  final Function()? onComplete;
  final Function(String)? onError;
  final DateTime createdAt;
  
  BatchStatus status = BatchStatus.created;
  DateTime? startedAt;
  DateTime? completedAt;
  double progress = 0.0;
  String? error;

  BatchOperation({
    required this.id,
    required this.type,
    required this.sources,
    required this.destination,
    required this.priority,
    required this.overwrite,
    required this.preserveStructure,
    required this.secure,
    required this.compressionLevel,
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

enum BatchOperationType {
  copy,
  move,
  delete,
  compress,
}

enum BatchOperationPriority {
  low,
  normal,
  high,
  urgent,
}

enum BatchStatus {
  created,
  running,
  completed,
  failed,
  cancelled,
}

class BatchOperationStats {
  final BatchOperationType operationType;
  int totalOperations = 0;
  int totalFilesProcessed = 0;
  int totalDuration = 0;
  int successCount = 0;
  int failureCount = 0;
  DateTime lastOperation = DateTime.now();

  BatchOperationStats({required this.operationType});

  void recordOperation(BatchOperation operation) {
    totalOperations++;
    lastOperation = operation.completedAt ?? DateTime.now();
    
    totalFilesProcessed += operation.sources.length;
    
    if (operation.duration != null) {
      totalDuration += operation.duration!;
    }
    
    if (operation.status == BatchStatus.completed) {
      successCount++;
    } else if (operation.status == BatchStatus.failed) {
      failureCount++;
    }
  }

  double getAverageDuration() {
    return totalOperations > 0 ? totalDuration / totalOperations : 0.0;
  }

  double getSuccessRate() {
    return totalOperations > 0 ? successCount / totalOperations : 0.0;
  }

  double getAverageFilesPerOperation() {
    return totalOperations > 0 ? totalFilesProcessed / totalOperations : 0.0;
  }
}

enum BatchEventType {
  created,
  started,
  progress,
  completed,
  failed,
  cancelled,
}

class BatchEvent {
  final BatchEventType type;
  final String batchId;
  final BatchOperationType operationType;
  final int? sourceCount;
  final int? filesProcessed;
  final int? duration;
  final String? error;

  BatchEvent({
    required this.type,
    required this.batchId,
    required this.operationType,
    this.sourceCount,
    this.filesProcessed,
    this.duration,
    this.error,
  });
}

class BatchFileOperationsStats {
  final int totalBatches;
  final int activeBatches;
  final int completedBatches;
  final int totalFilesProcessed;
  final List<BatchOperationStats> batchStats;

  BatchFileOperationsStats({
    required this.totalBatches,
    required this.activeBatches,
    required this.completedBatches,
    required this.totalFilesProcessed,
    required this.batchStats,
  });
}
