import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class StreamingProcessor {
  static const int _defaultChunkSize = 8192; // 8KB chunks
  static const int _maxBufferSize = 1024 * 1024; // 1MB buffer
  static const int _processingQueueSize = 100;
  
  final Map<String, StreamSession> _activeStreams = {};
  final Queue<ProcessingTask> _processingQueue = Queue();
  final Map<String, FileProcessor> _fileProcessors = {};
  
  Timer? _queueProcessor;
  int _totalBytesProcessed = 0;
  int _totalFilesProcessed = 0;
  
  final StreamController<StreamEvent> _streamController = 
      StreamController<StreamEvent>.broadcast();

  void initialize() {
    _startQueueProcessor();
    _initializeFileProcessors();
    developer.log('📡 Streaming Processor initialized');
  }

  void _startQueueProcessor() {
    _queueProcessor = Timer.periodic(
      Duration(milliseconds: 10),
      (_) => _processQueue(),
    );
  }

  void _initializeFileProcessors() {
    _fileProcessors['text'] = TextFileProcessor();
    _fileProcessors['binary'] = BinaryFileProcessor();
    _fileProcessors['json'] = JsonFileProcessor();
    _fileProcessors['csv'] = CsvFileProcessor();
    _fileProcessors['log'] = LogFileProcessor();
  }

  Future<StreamResult> processFileStreaming(String filePath, {
    int chunkSize = _defaultChunkSize,
    Function(String chunk)? onChunk,
    Function(double progress)? onProgress,
    Map<String, dynamic>? options,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File does not exist: $filePath');
    }
    
    final fileSize = file.lengthSync();
    final sessionId = _generateSessionId();
    
    // Determine file type and processor
    final fileType = _detectFileType(filePath);
    final processor = _fileProcessors[fileType] ?? _fileProcessors['binary']!;
    
    final session = StreamSession(
      id: sessionId,
      filePath: filePath,
      fileSize: fileSize,
      chunkSize: chunkSize,
      processor: processor,
      startTime: DateTime.now(),
      options: options ?? {},
    );
    
    _activeStreams[sessionId] = session;
    
    developer.log('📡 Starting stream processing: $filePath (${fileSize} bytes)');
    
    _emitEvent(StreamEvent(
      type: StreamEventType.started,
      sessionId: sessionId,
      filePath: filePath,
      fileSize: fileSize,
    ));
    
    try {
      final result = await _processFileStream(session, onChunk, onProgress);
      
      session.endTime = DateTime.now();
      session.status = StreamStatus.completed;
      
      _totalFilesProcessed++;
      _totalBytesProcessed += fileSize;
      
      developer.log('📡 Completed stream processing: $filePath');
      
      _emitEvent(StreamEvent(
        type: StreamEventType.completed,
        sessionId: sessionId,
        filePath: filePath,
        result: result,
      ));
      
      return result;
      
    } catch (e) {
      session.endTime = DateTime.now();
      session.status = StreamStatus.failed;
      session.error = e.toString();
      
      developer.log('📡 Failed stream processing: $filePath - $e');
      
      _emitEvent(StreamEvent(
        type: StreamEventType.failed,
        sessionId: sessionId,
        filePath: filePath,
        error: e.toString(),
      ));
      
      rethrow;
    } finally {
      _activeStreams.remove(sessionId);
    }
  }

  Future<StreamResult> _processFileStream(
    StreamSession session,
    Function(String chunk)? onChunk,
    Function(double progress)? onProgress,
  ) async {
    final file = File(session.filePath);
    final stream = file.openRead();
    final buffer = StringBuffer();
    int bytesProcessed = 0;
    
    await for (final chunk in stream) {
      // Process chunk
      final processedChunk = await session.processor.processChunk(
        chunk,
        buffer.toString(),
        session.options,
      );
      
      // Update buffer
      buffer.clear();
      buffer.write(processedChunk.data);
      
      // Emit chunk if callback provided
      if (onChunk != null) {
        onChunk(processedChunk.data);
      }
      
      bytesProcessed += chunk.length;
      
      // Update progress
      final progress = bytesProcessed / session.fileSize;
      if (onProgress != null) {
        onProgress(progress);
      }
      
      // Emit progress event
      _emitEvent(StreamEvent(
        type: StreamEventType.progress,
        sessionId: session.id,
        filePath: session.filePath,
        progress: progress,
        bytesProcessed: bytesProcessed,
      ));
      
      // Check if we should yield control
      if (processedChunk.shouldYield) {
        await Future.delayed(Duration.zero);
      }
    }
    
    // Finalize processing
    final finalResult = await session.processor.finalize(
      buffer.toString(),
      session.options,
    );
    
    return StreamResult(
      sessionId: session.id,
      filePath: session.filePath,
      data: finalResult.data,
      metadata: finalResult.metadata,
      processingTime: session.endTime!.difference(session.startTime).inMilliseconds,
      bytesProcessed: bytesProcessed,
    );
  }

  String _detectFileType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'txt':
      case 'md':
      case 'log':
        return 'text';
      case 'json':
        return 'json';
      case 'csv':
        return 'csv';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'pdf':
      case 'zip':
      case 'tar':
      case 'gz':
        return 'binary';
      default:
        return 'text';
    }
  }

  Future<StreamResult> processDirectoryStreaming(String directoryPath, {
    String pattern = '*',
    bool recursive = false,
    Function(String filePath, String chunk)? onFileChunk,
    Function(String filePath, double progress)? onFileProgress,
    Function(double overallProgress)? onOverallProgress,
  }) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw Exception('Directory does not exist: $directoryPath');
    }
    
    final files = await directory
        .list(recursive: recursive)
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => _matchesPattern(file.path, pattern))
        .toList();
    
    final totalFiles = files.length;
    int processedFiles = 0;
    final overallResults = <StreamResult>[];
    
    for (final file in files) {
      final result = await processFileStreaming(
        file.path,
        onChunk: (chunk) => onFileChunk?.call(file.path, chunk),
        onProgress: (progress) => onFileProgress?.call(file.path, progress),
      );
      
      overallResults.add(result);
      processedFiles++;
      
      // Update overall progress
      final overallProgress = processedFiles / totalFiles;
      if (onOverallProgress != null) {
        onOverallProgress(overallProgress);
      }
    }
    
    return StreamResult(
      sessionId: 'directory_${DateTime.now().millisecondsSinceEpoch}',
      filePath: directoryPath,
      data: jsonEncode(overallResults.map((r) => r.toJson()).toList()),
      metadata: {'totalFiles': totalFiles, 'processedFiles': processedFiles},
      processingTime: 0, // Would track total time
      bytesProcessed: overallResults.fold(0, (sum, r) => sum + r.bytesProcessed),
    );
  }

  bool _matchesPattern(String filePath, String pattern) {
    // Simple pattern matching
    if (pattern == '*') return true;
    if (pattern.contains('*')) {
      final parts = pattern.split('*');
      return filePath.contains(parts.first);
    }
    return filePath.endsWith(pattern);
  }

  Future<void> cancelStream(String sessionId) async {
    final session = _activeStreams[sessionId];
    if (session == null) return;
    
    session.status = StreamStatus.cancelled;
    session.endTime = DateTime.now();
    
    _activeStreams.remove(sessionId);
    
    developer.log('📡 Cancelled stream: $sessionId');
    
    _emitEvent(StreamEvent(
      type: StreamEventType.cancelled,
      sessionId: sessionId,
      filePath: session.filePath,
    ));
  }

  StreamSession? getStream(String sessionId) {
    return _activeStreams[sessionId];
  }

  List<StreamSession> getActiveStreams() {
    return _activeStreams.values.toList();
  }

  void pauseStream(String sessionId) {
    final session = _activeStreams[sessionId];
    if (session != null) {
      session.status = StreamStatus.paused;
      developer.log('📡 Paused stream: $sessionId');
    }
  }

  void resumeStream(String sessionId) {
    final session = _activeStreams[sessionId];
    if (session != null) {
      session.status = StreamStatus.active;
      developer.log('📡 Resumed stream: $sessionId');
    }
  }

  void _processQueue() {
    while (_processingQueue.isNotEmpty && _activeStreams.length < _processingQueueSize) {
      final task = _processingQueue.removeFirst();
      _executeTask(task);
    }
  }

  Future<void> _executeTask(ProcessingTask task) async {
    try {
      await task.execute();
    } catch (e) {
      developer.log('📡 Task execution failed: $e');
    }
  }

  void queueTask(ProcessingTask task) {
    _processingQueue.add(task);
  }

  String _generateSessionId() {
    return 'stream_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(StreamEvent event) {
    _streamController.add(event);
  }

  Stream<StreamEvent> get streamEventStream => _streamController.stream;

  StreamingProcessorStats getStats() {
    return StreamingProcessorStats(
      totalBytesProcessed: _totalBytesProcessed,
      totalFilesProcessed: _totalFilesProcessed,
      activeStreams: _activeStreams.length,
      queuedTasks: _processingQueue.length,
      supportedProcessors: _fileProcessors.length,
    );
  }

  void dispose() {
    _queueProcessor?.cancel();
    
    // Cancel all active streams
    for (final sessionId in _activeStreams.keys.toList()) {
      cancelStream(sessionId);
    }
    
    _activeStreams.clear();
    _processingQueue.clear();
    _fileProcessors.clear();
    _streamController.close();
    
    developer.log('📡 Streaming Processor disposed');
  }
}

class StreamSession {
  final String id;
  final String filePath;
  final int fileSize;
  final int chunkSize;
  final FileProcessor processor;
  final DateTime startTime;
  final Map<String, dynamic> options;
  
  StreamStatus status = StreamStatus.active;
  DateTime? endTime;
  String? error;

  StreamSession({
    required this.id,
    required this.filePath,
    required this.fileSize,
    required this.chunkSize,
    required this.processor,
    required this.startTime,
    required this.options,
  });

  int? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inMilliseconds;
  }
}

class ProcessingTask {
  final String id;
  final Future<void> Function() execute;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  ProcessingTask({
    required this.id,
    required this.execute,
    required this.createdAt,
    this.metadata,
  });
}

class StreamResult {
  final String sessionId;
  final String filePath;
  final String data;
  final Map<String, dynamic> metadata;
  final int processingTime;
  final int bytesProcessed;

  StreamResult({
    required this.sessionId,
    required this.filePath,
    required this.data,
    required this.metadata,
    required this.processingTime,
    required this.bytesProcessed,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'filePath': filePath,
      'data': data,
      'metadata': metadata,
      'processingTime': processingTime,
      'bytesProcessed': bytesProcessed,
    };
  }
}

enum StreamStatus {
  active,
  paused,
  completed,
  failed,
  cancelled,
}

enum StreamEventType {
  started,
  progress,
  completed,
  failed,
  cancelled,
}

class StreamEvent {
  final StreamEventType type;
  final String sessionId;
  final String filePath;
  final double? progress;
  final int? bytesProcessed;
  final StreamResult? result;
  final String? error;

  StreamEvent({
    required this.type,
    required this.sessionId,
    required this.filePath,
    this.progress,
    this.bytesProcessed,
    this.result,
    this.error,
  });
}

class StreamingProcessorStats {
  final int totalBytesProcessed;
  final int totalFilesProcessed;
  final int activeStreams;
  final int queuedTasks;
  final int supportedProcessors;

  StreamingProcessorStats({
    required this.totalBytesProcessed,
    required this.totalFilesProcessed,
    required this.activeStreams,
    required this.queuedTasks,
    required this.supportedProcessors,
  });
}

abstract class FileProcessor {
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  );
  
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  );
}

class ProcessedChunk {
  final String data;
  final bool shouldYield;
  final Map<String, dynamic>? metadata;

  ProcessedChunk({
    required this.data,
    required this.shouldYield,
    this.metadata,
  });
}

class TextFileProcessor implements FileProcessor {
  @override
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  ) async {
    final chunkText = utf8.decode(chunk);
    final combinedText = currentBuffer + chunkText;
    
    return ProcessedChunk(
      data: chunkText,
      shouldYield: false,
      metadata: {'length': chunkText.length},
    );
  }

  @override
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  ) async {
    return ProcessedChunk(
      data: buffer,
      shouldYield: false,
      metadata: {'totalLength': buffer.length},
    );
  }
}

class BinaryFileProcessor implements FileProcessor {
  @override
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  ) async {
    // For binary files, just pass through
    return ProcessedChunk(
      data: base64Encode(chunk),
      shouldYield: true,
      metadata: {'binary': true, 'size': chunk.length},
    );
  }

  @override
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  ) async {
    return ProcessedChunk(
      data: buffer,
      shouldYield: false,
      metadata: {'binary': true},
    );
  }
}

class JsonFileProcessor implements FileProcessor {
  @override
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  ) async {
    final chunkText = utf8.decode(chunk);
    final combinedText = currentBuffer + chunkText;
    
    // Try to parse as JSON (may fail on partial chunks)
    try {
      final parsed = jsonDecode(combinedText);
      return ProcessedChunk(
        data: chunkText,
        shouldYield: false,
        metadata: {'validJson': true, 'parsed': parsed},
      );
    } catch (e) {
      return ProcessedChunk(
        data: chunkText,
        shouldYield: false,
        metadata: {'validJson': false, 'error': e.toString()},
      );
    }
  }

  @override
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  ) async {
    try {
      final parsed = jsonDecode(buffer);
      return ProcessedChunk(
        data: buffer,
        shouldYield: false,
        metadata: {'validJson': true, 'parsed': parsed},
      );
    } catch (e) {
      throw Exception('Invalid JSON: $e');
    }
  }
}

class CsvFileProcessor implements FileProcessor {
  @override
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  ) async {
    final chunkText = utf8.decode(chunk);
    final combinedText = currentBuffer + chunkText;
    
    // Count lines in CSV
    final lines = combinedText.split('\n');
    final rowCount = lines.length - 1; // Last line might be incomplete
    
    return ProcessedChunk(
      data: chunkText,
      shouldYield: false,
      metadata: {'rowCount': rowCount, 'lines': lines.length},
    );
  }

  @override
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  ) async {
    final lines = buffer.split('\n');
    final rowCount = lines.where((line) => line.isNotEmpty).length;
    
    return ProcessedChunk(
      data: buffer,
      shouldYield: false,
      metadata: {'rowCount': rowCount, 'totalLines': lines.length},
    );
  }
}

class LogFileProcessor implements FileProcessor {
  @override
  Future<ProcessedChunk> processChunk(
    List<int> chunk,
    String currentBuffer,
    Map<String, dynamic> options,
  ) async {
    final chunkText = utf8.decode(chunk);
    final combinedText = currentBuffer + chunkText;
    
    // Parse log entries
    final lines = combinedText.split('\n');
    final logEntries = lines.where((line) => line.isNotEmpty).length;
    
    return ProcessedChunk(
      data: chunkText,
      shouldYield: false,
      metadata: {'logEntries': logEntries, 'lines': lines.length},
    );
  }

  @override
  Future<ProcessedChunk> finalize(
    String buffer,
    Map<String, dynamic> options,
  ) async {
    final lines = buffer.split('\n');
    final logEntries = lines.where((line) => line.isNotEmpty).length;
    
    return ProcessedChunk(
      data: buffer,
      shouldYield: false,
      metadata: {'logEntries': logEntries, 'totalLines': lines.length},
    );
  }
}
