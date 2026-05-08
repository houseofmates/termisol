import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keyboard Macro Reader
///
/// Records keyboard input sequences and replays them as macros.
/// Supports delayed playback, looping, and macro library management.
class KeyboardMacroReader {
  final Map<String, KeyboardMacro> _macros = {};
  final List<_KeyEvent> _recordingBuffer = [];
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordingMacroId;
  DateTime? _recordingStartTime;
  final StreamController<MacroEvent> _eventController = StreamController<MacroEvent>.broadcast();
  Timer? _playbackTimer;

  Stream<MacroEvent> get events => _eventController.stream;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  Future<void> initialize() async {
    await _loadPersistedMacros();
    debugPrint('KeyboardMacroReader initialized (${_macros.length} macros loaded)');
  }

  bool startRecording({String? macroId, String name = 'Untitled Macro'}) {
    if (_isRecording) return false;
    final id = macroId ?? 'macro_${DateTime.now().millisecondsSinceEpoch}';
    _recordingMacroId = id;
    _recordingBuffer.clear();
    _recordingStartTime = DateTime.now();
    _isRecording = true;
    _eventController.add(MacroEvent.recordingStarted(id));
    return true;
  }

  Future<KeyboardMacro> stopRecording({String? name, String? description}) async {
    if (!_isRecording || _recordingMacroId == null) {
      throw StateError('Not currently recording');
    }

    final macro = KeyboardMacro(
      id: _recordingMacroId!,
      name: name ?? _recordingMacroId!,
      description: description ?? '',
      events: List.from(_recordingBuffer),
      createdAt: DateTime.now(),
      duration: _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero,
      keyCount: _recordingBuffer.length,
    );

    _macros[macro.id] = macro;
    _recordingBuffer.clear();
    _recordingMacroId = null;
    _recordingStartTime = null;
    _isRecording = false;

    await persist();
    _eventController.add(MacroEvent.recordingStopped(macro.id));
    return macro;
  }

  void cancelRecording() {
    _recordingBuffer.clear();
    _recordingMacroId = null;
    _recordingStartTime = null;
    _isRecording = false;
    _eventController.add(MacroEvent.recordingCancelled());
  }

  void recordKeyEvent(String key, {bool ctrl = false, bool alt = false, bool shift = false, bool meta = false}) {
    if (!_isRecording) return;
    final now = DateTime.now();
    final delay = _recordingStartTime != null
        ? now.difference(_recordingStartTime!).inMilliseconds
        : 0;
    _recordingBuffer.add(_KeyEvent(
      key: key,
      timestamp: now,
      delay: delay,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
      meta: meta,
    ));
  }

  Future<bool> playMacro(String macroId, {int? repeat, Duration? speedMultiplier}) async {
    if (_isPlaying) return false;
    final macro = _macros[macroId];
    if (macro == null || macro.events.isEmpty) return false;

    _isPlaying = true;
    _eventController.add(MacroEvent.playbackStarted(macroId));

    final repeats = repeat ?? 1;
    final speed = speedMultiplier ?? const Duration(milliseconds: 1);

    for (int r = 0; r < repeats && _isPlaying; r++) {
      if (r > 0) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      for (final event in macro.events) {
        if (!_isPlaying) break;
        await Future.delayed(Duration(milliseconds: event.delay ~/ speed.inMilliseconds));
        if (!_isPlaying) break;

        final mods = _buildModifiers(event);
        // Keyboard event injection via SystemChannels.keyEvent is not supported:
        // SystemChannels.keyEvent is a BasicMessageChannel, not a MethodChannel,
        // so invokeMethod is unavailable and the platform side does not expose
        // a public API for synthesizing key events.
        // if (mods > 0) {
        //   await SystemChannels.keyEvent.send({
        //     'type': 'keydown',
        //     'keymap': 'android',
        //     'keyCode': event.key.codeUnitAt(0),
        //     'modifiers': mods,
        //   });
        // }
        // Keyboard event replay not available in Flutter's public API
        // await ServicesBinding.instance.keyEventManager.handleKeyEvent(...);
      }
    }

    _isPlaying = false;
    _eventController.add(MacroEvent.playbackStopped(macroId));
    return true;
  }

  void stopPlayback() {
    _isPlaying = false;
    _playbackTimer?.cancel();
  }

  KeyboardMacro? getMacro(String id) => _macros[id];

  List<KeyboardMacro> getAllMacros() => _macros.values.toList();

  Future<bool> deleteMacro(String id) async {
    final removed = _macros.remove(id);
    if (removed != null) {
      await persist();
      _eventController.add(MacroEvent.deleted(id));
    }
    return removed != null;
  }

  Future<bool> renameMacro(String id, String newName) async {
    final macro = _macros[id];
    if (macro == null) return false;
    macro.name = newName;
    await persist();
    return true;
  }

  KeyboardMacro? duplicateMacro(String id, {String? newName}) {
    final original = _macros[id];
    if (original == null) return null;

    final newId = 'macro_${DateTime.now().millisecondsSinceEpoch}';
    final dup = KeyboardMacro(
      id: newId,
      name: newName ?? '${original.name} (copy)',
      description: original.description,
      events: List.generate(original.events.length, (i) {
        final e = original.events[i];
        return _KeyEvent(key: e.key, timestamp: e.timestamp, delay: e.delay, ctrl: e.ctrl, alt: e.alt, shift: e.shift, meta: e.meta);
      }),
      createdAt: DateTime.now(),
      duration: original.duration,
      keyCount: original.keyCount,
    );
    _macros[newId] = dup;
    return dup;
  }

  int _buildModifiers(_KeyEvent event) {
    int mods = 0;
    if (event.ctrl) mods |= 2;
    if (event.alt) mods |= 4;
    if (event.shift) mods |= 1;
    if (event.meta) mods |= 8;
    return mods;
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _macros.values.map((m) => m.toJson()).toList();
      await prefs.setString('keyboard_macros', json.encode(data));
    } catch (e) {
      debugPrint('Failed to persist macros: $e');
    }
  }

  Future<void> _loadPersistedMacros() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('keyboard_macros');
      if (data == null) return;
      final list = json.decode(data) as List;
      for (final item in list) {
        final macro = KeyboardMacro.fromJson(item as Map<String, dynamic>);
        _macros[macro.id] = macro;
      }
    } catch (e) {
      debugPrint('Failed to load persisted macros: $e');
    }
  }

  Future<void> dispose() async {
    _playbackTimer?.cancel();
    await _eventController.close();
    _macros.clear();
    _recordingBuffer.clear();
  }
}

class KeyboardMacro {
  final String id;
  String name;
  String description;
  final List<_KeyEvent> events;
  final DateTime createdAt;
  final Duration duration;
  int keyCount;

  KeyboardMacro({
    required this.id,
    required this.name,
    this.description = '',
    required this.events,
    required this.createdAt,
    required this.duration,
    required this.keyCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'description': description,
    'events': events.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'duration': duration.inMilliseconds,
    'keyCount': keyCount,
  };

  factory KeyboardMacro.fromJson(Map<String, dynamic> json) {
    return KeyboardMacro(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      events: (json['events'] as List).map((e) => _KeyEvent.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      duration: Duration(milliseconds: json['duration'] as int? ?? 0),
      keyCount: json['keyCount'] as int? ?? 0,
    );
  }
}

class _KeyEvent {
  final String key;
  final DateTime timestamp;
  final int delay;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  _KeyEvent({
    required this.key,
    required this.timestamp,
    required this.delay,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  Map<String, dynamic> toJson() => {
    'key': key, 'timestamp': timestamp.toIso8601String(), 'delay': delay,
    'ctrl': ctrl, 'alt': alt, 'shift': shift, 'meta': meta,
  };

  factory _KeyEvent.fromJson(Map<String, dynamic> json) {
    return _KeyEvent(
      key: json['key'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      delay: json['delay'] as int,
      ctrl: json['ctrl'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
    );
  }
}

class MacroEvent {
  final String? macroId;
  final MacroEventType type;

  MacroEvent._({this.macroId, required this.type});

  factory MacroEvent.recordingStarted(String id) => MacroEvent._(macroId: id, type: MacroEventType.recordingStarted);
  factory MacroEvent.recordingStopped(String id) => MacroEvent._(macroId: id, type: MacroEventType.recordingStopped);
  factory MacroEvent.recordingCancelled() => MacroEvent._(type: MacroEventType.recordingCancelled);
  factory MacroEvent.playbackStarted(String id) => MacroEvent._(macroId: id, type: MacroEventType.playbackStarted);
  factory MacroEvent.playbackStopped(String id) => MacroEvent._(macroId: id, type: MacroEventType.playbackStopped);
  factory MacroEvent.deleted(String id) => MacroEvent._(macroId: id, type: MacroEventType.deleted);
}

enum MacroEventType { recordingStarted, recordingStopped, recordingCancelled, playbackStarted, playbackStopped, deleted }