import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keyboard macro reader and recorder for future expansion.
///
/// Stores macros as JSON files with recorded key sequences and timing.
/// This is a foundation for macro recording, playback, and sharing.
class KeyboardMacroReader {
  final Map<String, KeyboardMacro> _macros = {};
  final StreamController<MacroEvent> _eventController =
      StreamController<MacroEvent>.broadcast();

  Stream<MacroEvent> get events => _eventController.stream;

  bool _isInitialized = false;
  bool _isRecording = false;
  String? _currentRecordingId;
  final List<KeyEvent> _recordingBuffer = [];
  DateTime? _recordingStartTime;

  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  List<KeyboardMacro> get macros => _macros.values.toList();

  /// Initialize the macro reader
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadMacros();
    _isInitialized = true;
    debugPrint('🎹 Keyboard Macro Reader initialized');
  }

  /// Load macros from storage
  Future<void> _loadMacros() async {
    try {
      final dir = await _getMacroDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return;
      }

      final files = dir.listSync().where((f) => f.path.endsWith('.macro')).cast<File>();

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          final macro = KeyboardMacro.fromJson(data);
          _macros[macro.id] = macro;
        } catch (e) {
          debugPrint('⚠️ Failed to load macro ${file.path}: $e');
        }
      }

      debugPrint('📂 Loaded ${_macros.length} macros');
    } catch (e) {
      debugPrint('⚠️ Failed to load macros: $e');
    }
  }

  /// Get macro storage directory
  Future<Directory> _getMacroDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/macros');
  }

  /// Start recording a new macro
  Future<String> startRecording(String name, {String? description}) async {
    if (!_isInitialized) throw Exception('Macro reader not initialized');
    if (_isRecording) throw Exception('Already recording a macro');

    _isRecording = true;
    _currentRecordingId = 'macro_${DateTime.now().millisecondsSinceEpoch}';
    _recordingBuffer.clear();
    _recordingStartTime = DateTime.now();

    _eventController.add(MacroEvent(
      type: MacroEventType.recordingStarted,
      message: 'Recording started: $name',
    ));

    debugPrint('🎹 Recording started: $name');
    return _currentRecordingId!;
  }

  /// Record a key event during recording
  void recordKeyEvent(KeyEvent event) {
    if (!_isRecording || _currentRecordingId == null) return;
    _recordingBuffer.add(event);
  }

  /// Stop recording and save the macro
  Future<KeyboardMacro?> stopRecording(String name, {String? description}) async {
    if (!_isRecording || _currentRecordingId == null) {
      throw Exception('Not currently recording');
    }

    if (_recordingBuffer.isEmpty) {
      _isRecording = false;
      _currentRecordingId = null;
      return null;
    }

    final macro = KeyboardMacro(
      id: _currentRecordingId!,
      name: name,
      description: description ?? '',
      keys: _recordingBuffer.toList(),
      totalDuration: _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero,
      createdAt: DateTime.now(),
      keyCount: _recordingBuffer.length,
    );

    // Save to storage
    await _saveMacro(macro);
    _macros[macro.id] = macro;

    // Reset recording state
    _isRecording = false;
    _currentRecordingId = null;
    _recordingBuffer.clear();
    _recordingStartTime = null;

    _eventController.add(MacroEvent(
      type: MacroEventType.recordingStopped,
      message: 'Recording saved: $name (${macro.keyCount} keys)',
      macroId: macro.id,
    ));

    debugPrint('🎹 Recording saved: $name (${macro.keyCount} keys)');
    return macro;
  }

  /// Cancel recording without saving
  void cancelRecording() {
    _isRecording = false;
    _currentRecordingId = null;
    _recordingBuffer.clear();
    _recordingStartTime = null;

    _eventController.add(MacroEvent(
      type: MacroEventType.recordingCancelled,
      message: 'Recording cancelled',
    ));

    debugPrint('🎹 Recording cancelled');
  }

  /// Play back a macro
  Future<bool> playMacro(String macroId, {Function(KeyEvent)? onKeyPlayed}) async {
    final macro = _macros[macroId];
    if (macro == null) {
      throw Exception('Macro not found: $macroId');
    }

    _eventController.add(MacroEvent(
      type: MacroEventType.playbackStarted,
      message: 'Playing macro: ${macro.name}',
      macroId: macroId,
    ));

    debugPrint('🎹 Playing macro: ${macro.name} (${macro.keys.length} keys)');

    // Play each key event with timing
    for (int i = 0; i < macro.keys.length; i++) {
      final keyEvent = macro.keys[i];
      onKeyPlayed?.call(keyEvent);

      // Simulate delay between events
      if (i < macro.keys.length - 1) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    _eventController.add(MacroEvent(
      type: MacroEventType.playbackCompleted,
      message: 'Macro playback completed: ${macro.name}',
      macroId: macroId,
    ));

    return true;
  }

  /// Save a macro to storage
  Future<void> _saveMacro(KeyboardMacro macro) async {
    final dir = await _getMacroDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('${dir.path}/${macro.id}.macro');
    await file.writeAsString(jsonEncode(macro.toJson()));
  }

  /// Delete a macro
  Future<bool> deleteMacro(String macroId) async {
    final macro = _macros.remove(macroId);
    if (macro == null) return false;

    final dir = await _getMacroDirectory();
    final file = File('${dir.path}/$macroId.macro');
    if (await file.exists()) {
      await file.delete();
    }

    _eventController.add(MacroEvent(
      type: MacroEventType.macroDeleted,
      message: 'Macro deleted: ${macro.name}',
      macroId: macroId,
    ));

    return true;
  }

  /// Get macro by ID
  KeyboardMacro? getMacro(String macroId) {
    return _macros[macroId];
  }

  /// Export as JSON (for cloud sync)
  String exportAll() {
    final data = _macros.values.map((m) => m.toJson()).toList();
    return jsonEncode(data);
  }

  /// Import from JSON (for cloud sync)
  Future<void> importAll(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as List;
      for (final item in data) {
        final macro = KeyboardMacro.fromJson(item);
        _macros[macro.id] = macro;
        await _saveMacro(macro);
      }
      debugPrint('📥 Imported ${data.length} macros');
    } catch (e) {
      debugPrint('⚠️ Failed to import macros: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _eventController.close();
    _isInitialized = false;
  }
}

/// Keyboard macro data structure
class KeyboardMacro {
  final String id;
  final String name;
  final String description;
  final List<KeyEvent> keys;
  final Duration totalDuration;
  final DateTime createdAt;
  final int keyCount;

  KeyboardMacro({
    required this.id,
    required this.name,
    required this.description,
    required this.keys,
    required this.totalDuration,
    required this.createdAt,
    required this.keyCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'keyCount': keyCount,
      'totalDurationMs': totalDuration.inMilliseconds,
      'createdAt': createdAt.toIso8601String(),
      'keys': keys.map((k) => k.toJson()).toList(),
    };
  }

  factory KeyboardMacro.fromJson(Map<String, dynamic> json) {
    return KeyboardMacro(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      keyCount: json['keyCount'] ?? 0,
      totalDuration: Duration(milliseconds: json['totalDurationMs'] ?? 0),
      createdAt: DateTime.parse(json['createdAt']),
      keys: (json['keys'] as List?)
          ?.map((k) => KeyEvent.fromJson(k))
          .toList() ?? [],
    );
  }
}

/// Key event record
class KeyEvent {
  final String key;
  final String type; // 'down', 'up', 'repeat'
  final int timestampOffset; // milliseconds from recording start
  final String? character;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  KeyEvent({
    required this.key,
    required this.type,
    required this.timestampOffset,
    this.character,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'type': type,
      'timestampOffset': timestampOffset,
      'character': character,
      'ctrl': ctrl,
      'alt': alt,
      'shift': shift,
      'meta': meta,
    };
  }

  factory KeyEvent.fromJson(Map<String, dynamic> json) {
    return KeyEvent(
      key: json['key'] ?? '',
      type: json['type'] ?? 'down',
      timestampOffset: json['timestampOffset'] ?? 0,
      character: json['character'],
      ctrl: json['ctrl'] ?? false,
      alt: json['alt'] ?? false,
      shift: json['shift'] ?? false,
      meta: json['meta'] ?? false,
    );
  }
}

/// Macro events
enum MacroEventType {
  recordingStarted,
  recordingStopped,
  recordingCancelled,
  playbackStarted,
  playbackCompleted,
  macroDeleted,
}

class MacroEvent {
  final MacroEventType type;
  final String message;
  final String? macroId;

  MacroEvent({
    required this.type,
    required this.message,
    this.macroId,
  });
}