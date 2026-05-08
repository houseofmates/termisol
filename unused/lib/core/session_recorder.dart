import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Session Recorder - Terminal session recording with Ctrl+P toggle
class SessionRecorder {
  static final SessionRecorder _instance = SessionRecorder._internal();
  factory SessionRecorder() => _instance;
  SessionRecorder._internal();

  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  IOSink? _recordingFile;
  DateTime? _recordingStartTime;
  int _recordingNumber = 0;
  final List<String> _sessionBuffer = [];
  
  static const String _remoteHost = '192.168.4.250';
  static const String _videosDir = '/home/house/Videos';
  static const String _remoteVideosDir = '$_videosDir';
  
  final _recordingController = StreamController<RecordingEvent>.broadcast();
  Stream<RecordingEvent> get events => _recordingController.stream;
  
  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;
  String? get currentRecordingPath => _currentRecordingPath;
  Duration? get recordingDuration => _recordingStartTime != null 
      ? DateTime.now().difference(_recordingStartTime!) 
      : null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Ensure remote videos directory exists
    await _ensureRemoteVideosDirectory();
    
    // Get next recording number
    _recordingNumber = await _getNextRecordingNumber();
    
    _isInitialized = true;
    debugPrint('🎥 Session Recorder initialized');
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    
    try {
      // Generate recording filename
      final filename = 'terminal-recording-${_recordingNumber + 1}.txt';
      _currentRecordingPath = path.join(_remoteVideosDir, filename);
      
      // Create recording file on remote host
      _recordingFile = await File(_currentRecordingPath!).openWrite();
      
      _recordingStartTime = DateTime.now();
      _isRecording = true;
      _sessionBuffer.clear();
      
      // Write recording header
      _writeToRecording('=== Terminal Session Recording ===');
      _writeToRecording('Started: ${_recordingStartTime!.toIso8601String()}');
      _writeToRecording('Recording Number: ${_recordingNumber + 1}');
      _writeToRecording('Host: $_remoteHost');
      _writeToRecording('================================');
      _writeToRecording('');
      
      _recordingController.add(RecordingEvent(
        type: RecordingEventType.recordingStarted,
        data: {
          'filename': filename,
          'path': _currentRecordingPath,
          'recording_number': _recordingNumber + 1,
        },
      ));
      
      debugPrint('🎥 Started recording: $filename');
      
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingFile = null;
      _recordingStartTime = null;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    try {
      final recordingEndTime = DateTime.now();
      final duration = recordingEndTime.difference(_recordingStartTime!);
      
      // Write recording footer
      _writeToRecording('');
      _writeToRecording('================================');
      _writeToRecording('Ended: ${recordingEndTime.toIso8601String()}');
      _writeToRecording('Duration: ${duration.inSeconds} seconds');
      _writeToRecording('Total Commands: ${_sessionBuffer.length}');
      _writeToRecording('=== End of Recording ===');
      
      // Close recording file
      await _recordingFile?.close();
      _recordingFile = null;
      
      // Update recording number
      _recordingNumber++;
      
      _recordingController.add(RecordingEvent(
        type: RecordingEventType.recordingStopped,
        data: {
          'filename': path.basename(_currentRecordingPath!),
          'path': _currentRecordingPath,
          'duration_seconds': duration.inSeconds,
          'commands_count': _sessionBuffer.length,
        },
      ));
      
      debugPrint('🎥 Stopped recording: ${path.basename(_currentRecordingPath!)}');
      debugPrint('📊 Duration: ${duration.inSeconds}s, Commands: ${_sessionBuffer.length}');
      
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      
    } catch (e) {
      debugPrint('❌ Failed to stop recording: $e');
    }
  }

  Future<void> recordCommand(String command, String output, {bool isError = false}) async {
    if (!_isRecording || _recordingFile == null) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final commandEntry = '[$timestamp] $command';
    final outputEntry = isError ? 'ERROR: $output' : output;
    
    // Add to buffer
    _sessionBuffer.add(commandEntry);
    
    // Write to recording file
    _writeToRecording(commandEntry);
    if (output.isNotEmpty) {
      _writeToRecording(outputEntry);
    }
    _writeToRecording('');
  }

  Future<void> recordKeystroke(String key, bool isControl, bool isShift) async {
    if (!_isRecording || _recordingFile == null) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final modifiers = [];
    if (isControl) modifiers.add('Ctrl');
    if (isShift) modifiers.add('Shift');
    
    final keystrokeEntry = modifiers.isEmpty 
        ? '[$timestamp] KEY: $key'
        : '[$timestamp] KEY: ${modifiers.join('+')}:$key';
    
    _writeToRecording(keystrokeEntry);
  }

  Future<void> recordClipboardAction(String action, String content) async {
    if (!_isRecording || _recordingFile == null) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final clipboardEntry = '[$timestamp] CLIPBOARD $action: ${content.length > 100 ? '${content.substring(0, 100)}...' : content}';
    
    _writeToRecording(clipboardEntry);
  }

  Future<void> recordSessionEvent(String eventType, Map<String, dynamic> data) async {
    if (!_isRecording || _recordingFile == null) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final eventEntry = '[$timestamp] EVENT: $eventType - ${data.toString()}';
    
    _writeToRecording(eventEntry);
  }

  Future<List<RecordingInfo>> getRecordingsList() async {
    final recordings = <RecordingInfo>[];
    
    try {
      final videosDir = Directory(_remoteVideosDir);
      if (!await videosDir.exists()) {
        return recordings;
      }
      
      final files = await videosDir.list().toList();
      
      for (final file in files) {
        if (file is File && path.basename(file.path).startsWith('terminal-recording-')) {
          final stat = await file.stat();
          final filename = path.basename(file.path);
          
          // Extract recording number from filename
          final match = RegExp(r'terminal-recording-(\d+)\.txt').firstMatch(filename);
          final recordingNumber = match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
          
          recordings.add(RecordingInfo(
            filename: filename,
            path: file.path,
            recordingNumber: recordingNumber,
            createdAt: stat.modified,
            size: stat.size,
          ));
        }
      }
      
      // Sort by recording number
      recordings.sort((a, b) => a.recordingNumber.compareTo(b.recordingNumber));
      
    } catch (e) {
      debugPrint('❌ Failed to get recordings list: $e');
    }
    
    return recordings;
  }

  Future<String?> getRecordingContent(String filename) async {
    try {
      final filePath = path.join(_remoteVideosDir, filename);
      final file = File(filePath);
      
      if (!await file.exists()) {
        return null;
      }
      
      return await file.readAsString();
      
    } catch (e) {
      debugPrint('❌ Failed to read recording content: $e');
      return null;
    }
  }

  Future<bool> deleteRecording(String filename) async {
    try {
      final filePath = path.join(_remoteVideosDir, filename);
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
        
        _recordingController.add(RecordingEvent(
          type: RecordingEventType.recordingDeleted,
          data: {'filename': filename},
        ));
        
        debugPrint('🗑️ Deleted recording: $filename');
        return true;
      }
      
      return false;
      
    } catch (e) {
      debugPrint('❌ Failed to delete recording: $e');
      return false;
    }
  }

  RecordingStatistics getStatistics() {
    return RecordingStatistics(
      isRecording: _isRecording,
      currentRecordingPath: _currentRecordingPath,
      recordingDuration: recordingDuration,
      commandsRecorded: _sessionBuffer.length,
      recordingNumber: _recordingNumber,
    );
  }

  void _writeToRecording(String content) {
    if (_recordingFile != null) {
      _recordingFile!.writeln(content);
    }
  }

  Future<void> _ensureRemoteVideosDirectory() async {
    try {
      final videosDir = Directory(_remoteVideosDir);
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
        debugPrint('📁 Created videos directory: $_remoteVideosDir');
      }
    } catch (e) {
      debugPrint('❌ Failed to create videos directory: $e');
    }
  }

  Future<int> _getNextRecordingNumber() async {
    try {
      final recordings = await getRecordingsList();
      return recordings.isEmpty ? 0 : recordings.last.recordingNumber;
    } catch (e) {
      debugPrint('❌ Failed to get next recording number: $e');
      return 0;
    }
  }

  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    
    _recordingController.close();
    _sessionBuffer.clear();
  }
}

class RecordingInfo {
  final String filename;
  final String path;
  final int recordingNumber;
  final DateTime createdAt;
  final int size;
  
  RecordingInfo({
    required this.filename,
    required this.path,
    required this.recordingNumber,
    required this.createdAt,
    required this.size,
  });
  
  String get formattedSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class RecordingStatistics {
  final bool isRecording;
  final String? currentRecordingPath;
  final Duration? recordingDuration;
  final int commandsRecorded;
  final int recordingNumber;
  
  RecordingStatistics({
    required this.isRecording,
    this.currentRecordingPath,
    this.recordingDuration,
    required this.commandsRecorded,
    required this.recordingNumber,
  });
}

class RecordingEvent {
  final RecordingEventType type;
  final Map<String, dynamic>? data;
  
  RecordingEvent({
    required this.type,
    this.data,
  });
}

enum RecordingEventType {
  recordingStarted,
  recordingStopped,
  recordingDeleted,
}
