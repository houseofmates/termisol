import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SessionRecovery {
  static const String _stateFile = '/home/house/.termisol_session_state.json';
  static const String _lockFile = '/home/house/.termisol_session.lock';
  static const String _crashLogFile = '/home/house/.termisol_crash_log.jsonl';
  static const Duration _saveInterval = Duration(seconds: 5);
  static const int _maxCrashLogEntries = 100;
  static const int _maxBufferLines = 50000;

  Timer? _saveTimer;
  int _pid = 0;
  bool _isInitialized = false;
  bool _wasRecovered = false;
  bool _isDirty = false;
  String? _lastCrashId;

  final List<SessionTab> _tabs = [];
  final Map<String, dynamic> _extraState = {};
  final List<CrashLogEntry> _crashLog = [];

  final StreamController<RecoveryEvent> _eventController =
      StreamController<RecoveryEvent>.broadcast();

  Stream<RecoveryEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get wasRecovered => _wasRecovered;
  List<SessionTab> get tabs => List.unmodifiable(_tabs);

  Future<void> initialize() async {
    if (_isInitialized) return;
    _pid = pid;
    await _loadCrashLog();

    final recovered = await _detectAndRecover();
    if (recovered) {
      _wasRecovered = true;
      _eventController.add(RecoveryEvent(
        type: RecoveryEventType.recovered,
        message: 'Session recovered: ${_tabs.length} tab(s) restored',
      ));
    }

    await _acquireLock();
    _startAutoSave();
    _isInitialized = true;
    _eventController.add(RecoveryEvent(
      type: RecoveryEventType.initialized,
      message: _wasRecovered ? 'Session recovery active (restored)' : 'Session recovery active',
    ));
  }

  Future<bool> _detectAndRecover() async {
    try {
      final stateFile = File(_stateFile);
      if (!await stateFile.exists()) return false;

      final lockFile = File(_lockFile);
      if (await lockFile.exists()) {
        final lockContent = await lockFile.readAsString();
        final lockPid = int.tryParse(lockContent.trim());
        if (lockPid != null && _isProcessAlive(lockPid)) {
          return false;
        }

        _lastCrashId = 'crash_${DateTime.now().millisecondsSinceEpoch}';
        await _logCrash(CrashType.uncleanExit,
            'Previous process (PID $lockPid) no longer running');

        _eventController.add(RecoveryEvent(
          type: RecoveryEventType.crashDetected,
          message: 'Previous session (PID $lockPid) crashed. Recovering...',
        ));
      }

      final data = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      await _restoreFromData(data);
      return true;
    } catch (e) {
      _eventController.add(RecoveryEvent(
        type: RecoveryEventType.recoveryFailed,
        message: 'Session recovery failed: $e',
      ));
      await _logCrash(CrashType.recoveryFailed, e.toString());
      return false;
    }
  }

  Future<void> _restoreFromData(Map<String, dynamic> data) async {
    _tabs.clear();

    final tabsData = data['tabs'] as List<dynamic>? ?? [];
    for (final tabData in tabsData) {
      final tab = SessionTab(
        id: tabData['id'] ?? 'tab_${_tabs.length}',
        name: tabData['name'] ?? 'recovered',
        workingDirectory: tabData['workingDirectory'] ?? '/home/house',
        isConnected: tabData['isConnected'] ?? false,
        connectionType: tabData['connectionType'] ?? 'local',
        connectionHost: tabData['connectionHost'],
        commandHistory: List<String>.from(tabData['commandHistory'] ?? []),
        envVars: Map<String, String>.from(tabData['envVars'] ?? {}),
      );
      _tabs.add(tab);
    }

    if (data.containsKey('extra')) {
      _extraState.addAll(Map<String, dynamic>.from(data['extra']));
    }
  }

  void _startAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(_saveInterval, (_) => _autoSave());
  }

  void markDirty() {
    _isDirty = true;
  }

  Future<void> _autoSave() async {
    if (!_isDirty && _tabs.isNotEmpty) return;
    await _saveState();
    _isDirty = false;
  }

  Future<void> _saveState({bool isFinal = false}) async {
    try {
      final data = <String, dynamic>{
        'version': 2,
        'pid': _pid,
        'savedAt': DateTime.now().toIso8601String(),
        'tabCount': _tabs.length,
        'tabs': _tabs.map((t) => t.toJson()).toList(),
        'extra': _extraState,
      };

      final tmpFile = File('$_stateFile.tmp');
      await tmpFile.writeAsString(jsonEncode(data));
      await tmpFile.rename(_stateFile);
    } catch (e) {
      if (isFinal) {
        _eventController.add(RecoveryEvent(
          type: RecoveryEventType.saveFailed,
          message: 'Failed to save session state: $e',
        ));
      }
    }
  }

  Future<void> _acquireLock() async {
    await File(_lockFile).writeAsString('$_pid');
  }

  Future<void> _releaseLock() async {
    try {
      final lockFile = File(_lockFile);
      if (await lockFile.exists()) {
        final content = await lockFile.readAsString();
        if (content.trim() == '$_pid') {
          await lockFile.delete();
        }
      }
    } catch (e) {
      debugPrint('Failed to release session lock: $e');
    }
  }

  bool _isProcessAlive(int checkPid) {
    try {
      final result = Process.runSync('kill', ['-0', '$checkPid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _logCrash(CrashType type, String details) async {
    final entry = CrashLogEntry(
      id: _lastCrashId ?? 'crash_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      details: details,
      timestamp: DateTime.now(),
    );
    _crashLog.add(entry);
    if (_crashLog.length > _maxCrashLogEntries) _crashLog.removeAt(0);

    try {
      final line = '${jsonEncode(entry.toJson())}\n';
      await File(_crashLogFile).writeAsString(line, mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write crash log: $e');
    }
  }

  Future<void> _loadCrashLog() async {
    try {
      final file = File(_crashLogFile);
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          _crashLog.add(CrashLogEntry.fromJson(jsonDecode(line)));
        } catch (e) {
          debugPrint('Failed to parse crash log entry: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to load crash log: $e');
    }
  }

  SessionTab createTab({
    required String id,
    String name = 'local',
    String workingDirectory = '/home/house',
    String connectionType = 'local',
    String? connectionHost,
    List<String>? commandHistory,
    Map<String, String>? envVars,
  }) {
    final tab = SessionTab(
      id: id,
      name: name,
      workingDirectory: workingDirectory,
      connectionType: connectionType,
      connectionHost: connectionHost,
      commandHistory: commandHistory ?? [],
      envVars: envVars ?? {},
    );
    _tabs.add(tab);
    markDirty();
    return tab;
  }

  void removeTab(String id) {
    _tabs.removeWhere((t) => t.id == id);
    markDirty();
  }

  void updateTab(String id, {
    String? name,
    String? workingDirectory,
    bool? isConnected,
    List<String>? commandHistory,
    Map<String, String>? envVars,
  }) {
    final tab = _tabs.firstWhere((t) => t.id == id, orElse: () => SessionTab(
      id: id,
      name: 'unknown',
      workingDirectory: '/home/house',
      connectionType: 'local',
      commandHistory: [],
      envVars: {},
    ));

    if (name != null) tab.name = name;
    if (workingDirectory != null) tab.workingDirectory = workingDirectory;
    if (isConnected != null) tab.isConnected = isConnected;
    if (commandHistory != null) tab.commandHistory = commandHistory;
    if (envVars != null) tab.envVars = envVars;
    tab.lastUpdate = DateTime.now();
    markDirty();
  }

  void recordCommand(String tabId, String command) {
    final tab = _tabs.firstWhere((t) => t.id == tabId);
    tab.commandHistory.add(command);
    if (tab.commandHistory.length > 500) tab.commandHistory.removeAt(0);
    tab.lastUpdate = DateTime.now();
    markDirty();
  }

  void setExtra(String key, dynamic value) {
    _extraState[key] = value;
    markDirty();
  }

  T? getExtra<T>(String key) {
    return _extraState[key] as T?;
  }

  Future<void> forceSave() async {
    await _saveState(isFinal: true);
  }

  List<CrashLogEntry> getCrashLog() => List.unmodifiable(_crashLog);

  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _saveState(isFinal: true);
    await _releaseLock();
    _eventController.close();
    _isInitialized = false;
  }
}

class SessionTab {
  final String id;
  String name;
  String workingDirectory;
  bool isConnected;
  String connectionType;
  String? connectionHost;
  List<String> commandHistory;
  Map<String, String> envVars;
  DateTime lastUpdate;

  SessionTab({
    required this.id,
    required this.name,
    required this.workingDirectory,
    this.isConnected = false,
    required this.connectionType,
    this.connectionHost,
    required this.commandHistory,
    required this.envVars,
  }) : lastUpdate = DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'workingDirectory': workingDirectory,
    'isConnected': isConnected,
    'connectionType': connectionType,
    'connectionHost': connectionHost,
    'commandHistory': commandHistory,
    'envVars': envVars,
    'lastUpdate': lastUpdate.toIso8601String(),
  };
}

class CrashLogEntry {
  final String id;
  final CrashType type;
  final String details;
  final DateTime timestamp;

  CrashLogEntry({
    required this.id,
    required this.type,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
  };

  factory CrashLogEntry.fromJson(Map<String, dynamic> json) => CrashLogEntry(
    id: json['id'] ?? '',
    type: CrashType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => CrashType.unknown,
    ),
    details: json['details'] ?? '',
    timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
  );
}

enum CrashType { uncleanExit, recoveryFailed, unknown }

enum RecoveryEventType {
  initialized,
  recovered,
  crashDetected,
  recoveryFailed,
  saveFailed,
}

class RecoveryEvent {
  final RecoveryEventType type;
  final String message;
  final DateTime timestamp;

  RecoveryEvent({
    required this.type,
    required this.message,
  }) : timestamp = DateTime.now();
}