import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AsciicastRecorder {
  static const String _remoteHost = '192.168.4.250';
  static const String _remotePath = '/home/house/Videos';
  static const String _localFallbackDir = '/home/house/Videos';
  static const String _logsDir = '/home/house/.termisol_recordings';

  bool _isRecording = false;
  bool _isInitialized = false;
  DateTime? _recordingStart;
  String? _currentCastPath;
  IOSink? _castSink;
  double _lastEventTime = 0;
  int _eventCount = 0;

  final StreamController<RecordingEvent> _eventController =
      StreamController<RecordingEvent>.broadcast();

  Stream<RecordingEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  DateTime? get recordingStart => _recordingStart;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await Directory(_logsDir).create(recursive: true);
    await Directory(_localFallbackDir).create(recursive: true);
    _isInitialized = true;
  }

  Future<void> toggleRecording({String? title}) async {
    if (!_isInitialized) await initialize();

    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording(title: title);
    }
  }

  Future<void> startRecording({String? title}) async {
    if (_isRecording) return;

    final timestamp = DateTime.now();
    final dateStr = '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}';
    final name = title ?? 'termisol_$dateStr-$timeStr';
    final castFile = File('$_logsDir/$name.cast');

    _currentCastPath = castFile.path;
    _castSink = castFile.openWrite();
    _recordingStart = timestamp;
    _isRecording = true;
    _lastEventTime = 0;
    _eventCount = 0;

    await _writeHeader(timestamp, title: title);

    _eventController.add(RecordingEvent(
      type: RecordingEventType.started,
      message: 'Recording started: $name.cast',
    ));
  }

  Future<void> _writeHeader(DateTime timestamp, {String? title}) async {
    final header = <String, dynamic>{
      'version': 2,
      'width': 120,
      'height': 40,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'title': title ?? 'Termisol recording',
      'env': {
        'SHELL': Platform.environment['SHELL'] ?? '/bin/bash',
        'TERM': Platform.environment['TERM'] ?? 'xterm-256color',
      },
    };
    _castSink?.writeln(jsonEncode(header));
  }

  void writeOutput(String text) {
    if (!_isRecording || _castSink == null) return;

    final now = DateTime.now();
    final elapsed = _recordingStart != null
        ? now.difference(_recordingStart!).inMicroseconds / 1000000.0
        : 0.0;

    final eventTime = elapsed > _lastEventTime ? elapsed : _lastEventTime + 0.000001;
    _lastEventTime = eventTime;

    final event = [eventTime, 'o', text];
    _castSink?.writeln(jsonEncode(event));
    _eventCount++;
  }

  void writeInput(String text) {
    if (!_isRecording || _castSink == null) return;

    final now = DateTime.now();
    final elapsed = _recordingStart != null
        ? now.difference(_recordingStart!).inMicroseconds / 1000000.0
        : 0.0;

    final eventTime = elapsed > _lastEventTime ? elapsed : _lastEventTime + 0.000001;
    _lastEventTime = eventTime;

    final event = [eventTime, 'i', text];
    _castSink?.writeln(jsonEncode(event));
    _eventCount++;
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    await _castSink?.flush();
    await _castSink?.close();
    _castSink = null;

    final duration = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!)
        : Duration.zero;

    final localPath = _currentCastPath;
    _currentCastPath = null;

    if (localPath == null) return;

    _eventController.add(RecordingEvent(
      type: RecordingEventType.stopped,
      message: 'Recording stopped (${duration.inSeconds}s, $_eventCount events)',
    ));

    await _uploadToRemote(localPath, duration);
  }

  Future<void> _uploadToRemote(String localPath, Duration duration) async {
    final filename = localPath.split('/').last;
    final remoteFullPath = '$_remotePath/$filename';

    _eventController.add(RecordingEvent(
      type: RecordingEventType.uploading,
      message: 'Uploading to $_remoteHost:$remoteFullPath...',
    ));

    try {
      final result = await Process.run(
        'scp',
        [localPath, '$_remoteHost:$remoteFullPath'],
        runInShell: true,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode == 0) {
        _eventController.add(RecordingEvent(
          type: RecordingEventType.uploaded,
          message: 'Saved to $_remoteHost:$remoteFullPath',
        ));
      } else {
        throw Exception(result.stderr.toString());
      }
    } catch (e) {
      await _fallbackLocalSave(localPath);

      _eventController.add(RecordingEvent(
        type: RecordingEventType.uploadFailed,
        message: 'Remote upload failed (saved locally): $e',
      ));
    }
  }

  Future<void> _fallbackLocalSave(String sourcePath) async {
    try {
      final filename = sourcePath.split('/').last;
      final destPath = '$_localFallbackDir/$filename';
      await File(sourcePath).copy(destPath);
    } catch (e) {
      _eventController.add(RecordingEvent(
        type: RecordingEventType.saveFailed,
        message: 'Failed to save recording: $e',
      ));
    }
  }

  Future<List<RecordingInfo>> listRecordings() async {
    final recordings = <RecordingInfo>[];

    try {
      final dir = Directory(_logsDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.cast')) {
            final stat = await entity.stat();
            recordings.add(RecordingInfo(
              path: entity.path,
              filename: entity.path.split('/').last,
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load recording: $e');
    }

    recordings.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return recordings;
  }

  Future<void> deleteRecording(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _eventController.add(RecordingEvent(
        type: RecordingEventType.deleted,
        message: 'Recording deleted: ${path.split('/').last}',
      ));
    }
  }

  void dispose() {
    if (_isRecording) {
      _castSink?.close();
    }
    _eventController.close();
    _isInitialized = false;
  }
}

class RecordingInfo {
  final String path;
  final String filename;
  final int sizeBytes;
  final DateTime modifiedAt;

  RecordingInfo({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

enum RecordingEventType {
  started,
  stopped,
  uploading,
  uploaded,
  uploadFailed,
  saveFailed,
  deleted,
}

class RecordingEvent {
  final RecordingEventType type;
  final String message;
  final DateTime timestamp;

  RecordingEvent({
    required this.type,
    required this.message,
  }) : timestamp = DateTime.now();
}