import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

extension IterableTakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int n) {
    if (n <= 0) return const [];
    final list = toList();
    if (list.length <= n) return list;
    return list.sublist(list.length - n);
  }
}

/// Session Recovery
///
/// Recovers terminal sessions after crashes or disconnections.
/// Maintains journal entries of session state, terminal scrollback,
/// and working directory for transparent recovery.
class SessionRecovery {
  final Map<String, RecoveryJournal> _journals = {};
  final Map<String, SessionSnapshot> _snapshots = {};
  String? _journalPath;
  Timer? _checkpointTimer;
  Timer? _journalFlushTimer;
  bool _autoRecover = true;

  static const Duration _checkpointInterval = Duration(seconds: 30);
  static const Duration _journalFlushInterval = Duration(seconds: 5);
  static const int _maxSnapshotAge = 1000;
  static const int _maxJournalEntries = 500;

  Future<void> initialize({bool autoRecover = true}) async {
    _autoRecover = autoRecover;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _journalPath = '${appDir.path}/recovery_journals';
      final dir = Directory(_journalPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _loadJournals();
      _checkpointTimer = Timer.periodic(_checkpointInterval, (_) => _createCheckpoints());
      _journalFlushTimer = Timer.periodic(_journalFlushInterval, (_) => _flushJournals());
      debugPrint('SessionRecovery initialized (autoRecover: $_autoRecover)');
    } catch (e) {
      debugPrint('Failed to initialize SessionRecovery: $e');
    }
  }

  void startJournal(String sessionId, {String? title, String? workingDirectory, Map<String, dynamic>? metadata}) {
    if (_journals.containsKey(sessionId)) return;
    _journals[sessionId] = RecoveryJournal(
      sessionId: sessionId,
      title: title ?? 'Session $sessionId',
      createdAt: DateTime.now(),
      entries: [],
      workingDirectory: workingDirectory ?? '/',
      lastActivity: DateTime.now(),
      metadata: metadata ?? {},
    );
  }

  void recordEntry(String sessionId, RecoveryEntry entry) {
    final journal = _journals[sessionId];
    if (journal == null) return;
    journal.entries.add(entry);
    if (journal.entries.length > _maxJournalEntries) {
      journal.entries.removeRange(0, 50);
    }
    journal.lastActivity = DateTime.now();
    if (entry.type == RecoveryEntryType.checkpoint) {
      journal.lastCheckpoint = DateTime.now();
    }
  }

  void recordCommand(String sessionId, String command, {int? exitCode, String? output}) {
    recordEntry(sessionId, RecoveryEntry.command(sessionId, command, exitCode: exitCode, output: output));
  }

  void recordScrollback(String sessionId, List<String> lines, {int? cursorRow, int? cursorCol}) {
    recordEntry(sessionId, RecoveryEntry.scrollback(sessionId, lines, cursorRow: cursorRow, cursorCol: cursorCol));
  }

  void recordCwd(String sessionId, String directory) {
    final journal = _journals[sessionId];
    if (journal == null) return;
    journal.workingDirectory = directory;
    recordEntry(sessionId, RecoveryEntry.cwdChange(sessionId, directory));
  }

  void recordError(String sessionId, String error) {
    recordEntry(sessionId, RecoveryEntry.error(sessionId, error));
  }

  Future<void> createCheckpoint(String sessionId) async {
    final journal = _journals[sessionId];
    if (journal == null) return;

    final snapshot = SessionSnapshot(
      sessionId: sessionId,
      title: journal.title,
      workingDirectory: journal.workingDirectory,
      commandCount: journal.entries.where((e) => e.type == RecoveryEntryType.command).length,
      recentCommands: journal.entries
          .where((e) => e.type == RecoveryEntryType.command)
          .takeLast(20)
          .map((e) => e.data['command'] as String)
          .toList(),
      recentScrollback: journal.entries
          .where((e) => e.type == RecoveryEntryType.scrollback)
          .lastOrNull
          ?.data['lines'] as List<String>? ?? [],
      metadata: Map.from(journal.metadata),
      timestamp: DateTime.now(),
      entryCount: journal.entries.length,
    );

    _snapshots[sessionId] = snapshot;
    recordEntry(sessionId, RecoveryEntry.checkpoint(sessionId));
    await _persistSnapshot(sessionId, snapshot);

    if (_snapshots.length > _maxSnapshotAge) {
      final oldest = _snapshots.keys.first;
      _snapshots.remove(oldest);
    }
  }

  Future<RecoveryResult> recover(String sessionId, {bool restoreScrollback = true}) async {
    try {
      final snapshot = _snapshots[sessionId] ?? await _loadSnapshot(sessionId);
      final journal = _journals[sessionId] ?? await _loadJournal(sessionId);

      if (snapshot == null && journal == null) {
        return RecoveryResult(success: false, error: 'No recovery data for session $sessionId');
      }

      final state = <String, dynamic>{
        'workingDirectory': snapshot?.workingDirectory ?? journal?.workingDirectory ?? '/',
        'commandCount': snapshot?.commandCount ?? journal?.entries.length ?? 0,
        'recentCommands': snapshot?.recentCommands ?? [],
        'lastCheckpoint': snapshot?.timestamp ?? journal?.lastCheckpoint,
        'entryCount': snapshot?.entryCount ?? journal?.entries.length ?? 0,
      };

      if (restoreScrollback && snapshot?.recentScrollback != null) {
        state['scrollback'] = snapshot!.recentScrollback;
      }

      return RecoveryResult(success: true, sessionId: sessionId, recoveredState: state);
    } catch (e) {
      return RecoveryResult(success: false, error: e.toString());
    }
  }

  RecoveryStatistics getStatistics(String sessionId) {
    final journal = _journals[sessionId];
    final snapshot = _snapshots[sessionId];

    if (journal == null && snapshot == null) return RecoveryStatistics(sessionId: sessionId);

    return RecoveryStatistics(
      sessionId: sessionId,
      totalEntries: journal?.entries.length ?? 0,
      commandCount: journal?.entries.where((e) => e.type == RecoveryEntryType.command).length ?? 0,
      errorCount: journal?.entries.where((e) => e.type == RecoveryEntryType.error).length ?? 0,
      checkpointCount: journal?.entries.where((e) => e.type == RecoveryEntryType.checkpoint).length ?? 0,
      lastCheckpoint: snapshot?.timestamp ?? journal?.lastCheckpoint,
      lastActivity: journal?.lastActivity,
      workingDirectory: snapshot?.workingDirectory ?? journal?.workingDirectory,
    );
  }

  Future<void> endJournal(String sessionId, {bool keepSnapshots = true}) async {
    if (!keepSnapshots) {
      _snapshots.remove(sessionId);
    }
    _journals.remove(sessionId);
    try {
      final file = File('$_journalPath/$sessionId.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _createCheckpoints() {
    for (final sessionId in _journals.keys) {
      createCheckpoint(sessionId);
    }
  }

  Future<void> _flushJournals() async {
    for (final entry in _journals.entries) {
      await _persistJournal(entry.key, entry.value);
    }
  }

  Future<void> _persistSnapshot(String sessionId, SessionSnapshot snapshot) async {
    try {
      if (_journalPath == null) return;
      final file = File('$_journalPath/${sessionId}_snapshot.json');
      await file.writeAsString(json.encode(snapshot.toJson()));
    } catch (e) {
      debugPrint('Failed to persist snapshot: $e');
    }
  }

  Future<void> _persistJournal(String sessionId, RecoveryJournal journal) async {
    try {
      if (_journalPath == null) return;
      final file = File('$_journalPath/$sessionId.json');
      final entries = journal.entries.takeLast(200).map((e) => e.toJson()).toList();
      await file.writeAsString(json.encode({
        'sessionId': journal.sessionId,
        'title': journal.title,
        'createdAt': journal.createdAt.toIso8601String(),
        'workingDirectory': journal.workingDirectory,
        'lastActivity': journal.lastActivity.toIso8601String(),
        'lastCheckpoint': journal.lastCheckpoint?.toIso8601String(),
        'entries': entries,
        'metadata': journal.metadata,
      }));
    } catch (e) {
      debugPrint('Failed to flush journal: $e');
    }
  }

  Future<SessionSnapshot?> _loadSnapshot(String sessionId) async {
    try {
      if (_journalPath == null) return null;
      final file = File('$_journalPath/${sessionId}_snapshot.json');
      if (!await file.exists()) return null;
      final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
      return SessionSnapshot.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  Future<RecoveryJournal?> _loadJournal(String sessionId) async {
    try {
      if (_journalPath == null) return null;
      final file = File('$_journalPath/$sessionId.json');
      if (!await file.exists()) return null;
      final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
      return RecoveryJournal(
        sessionId: data['sessionId'] as String,
        title: data['title'] as String? ?? '',
        createdAt: DateTime.parse(data['createdAt'] as String),
        entries: ((data['entries'] as List?)?.map((e) => RecoveryEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? []),
        workingDirectory: (data['workingDirectory'] as String?) ?? '/',
        lastActivity: DateTime.tryParse((data['lastActivity'] as String?) ?? '') ?? DateTime.now(),
        lastCheckpoint: DateTime.tryParse((data['lastCheckpoint'] as String?) ?? ''),
        metadata: Map<String, dynamic>.from((data['metadata'] as Map?) ?? {}),
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadJournals() async {
    try {
      if (_journalPath == null) return;
      final dir = Directory(_journalPath!);
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('_snapshot.json')) {
          final sessionId = entity.path.split('/').last.replaceAll('.json', '');
          final journal = await _loadJournal(sessionId);
          if (journal != null) {
            _journals[sessionId] = journal;
          }
        }
      }
      debugPrint('Loaded ${_journals.length} recovery journals');
    } catch (e) {
      debugPrint('Failed to load journals: $e');
    }
  }

  void dispose() {
    _checkpointTimer?.cancel();
    _journalFlushTimer?.cancel();
    _journals.clear();
    _snapshots.clear();
  }
}

enum RecoveryEntryType { command, scrollback, cwdChange, error, checkpoint }

class RecoveryJournal {
  final String sessionId;
  final String title;
  final DateTime createdAt;
  final List<RecoveryEntry> entries;
  String workingDirectory;
  DateTime lastActivity;
  DateTime? lastCheckpoint;
  final Map<String, dynamic> metadata;

  RecoveryJournal({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.entries,
    required this.workingDirectory,
    required this.lastActivity,
    this.lastCheckpoint,
    this.metadata = const {},
  });
}

class RecoveryEntry {
  final String sessionId;
  final RecoveryEntryType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  RecoveryEntry({
    required this.sessionId,
    required this.type,
    required this.timestamp,
    required this.data,
  });

  factory RecoveryEntry.command(String sessionId, String command, {int? exitCode, String? output}) {
    return RecoveryEntry(sessionId: sessionId, type: RecoveryEntryType.command, timestamp: DateTime.now(),
        data: {'command': command, if (exitCode != null) 'exitCode': exitCode, if (output != null) 'output': output});
  }

  factory RecoveryEntry.scrollback(String sessionId, List<String> lines, {int? cursorRow, int? cursorCol}) {
    return RecoveryEntry(sessionId: sessionId, type: RecoveryEntryType.scrollback, timestamp: DateTime.now(),
        data: {'lines': lines, if (cursorRow != null) 'cursorRow': cursorRow, if (cursorCol != null) 'cursorCol': cursorCol});
  }

  factory RecoveryEntry.cwdChange(String sessionId, String directory) {
    return RecoveryEntry(sessionId: sessionId, type: RecoveryEntryType.cwdChange, timestamp: DateTime.now(),
        data: {'directory': directory});
  }

  factory RecoveryEntry.error(String sessionId, String error) {
    return RecoveryEntry(sessionId: sessionId, type: RecoveryEntryType.error, timestamp: DateTime.now(),
        data: {'error': error});
  }

  factory RecoveryEntry.checkpoint(String sessionId) {
    return RecoveryEntry(sessionId: sessionId, type: RecoveryEntryType.checkpoint, timestamp: DateTime.now(),
        data: {});
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId, 'type': type.name, 'timestamp': timestamp.toIso8601String(), 'data': data,
  };

  factory RecoveryEntry.fromJson(Map<String, dynamic> json) {
    return RecoveryEntry(
      sessionId: json['sessionId'] as String,
      type: RecoveryEntryType.values.byName(json['type'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      data: Map<String, dynamic>.from((json['data'] as Map?) ?? {}),
    );
  }
}

class SessionSnapshot {
  final String sessionId;
  final String title;
  final String workingDirectory;
  final int commandCount;
  final List<String> recentCommands;
  final List<String> recentScrollback;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;
  final int entryCount;

  SessionSnapshot({
    required this.sessionId,
    required this.title,
    required this.workingDirectory,
    required this.commandCount,
    required this.recentCommands,
    required this.recentScrollback,
    required this.metadata,
    required this.timestamp,
    required this.entryCount,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId, 'title': title, 'workingDirectory': workingDirectory,
    'commandCount': commandCount, 'recentCommands': recentCommands,
    'recentScrollback': recentScrollback, 'metadata': metadata,
    'timestamp': timestamp.toIso8601String(), 'entryCount': entryCount,
  };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    return SessionSnapshot(
      sessionId: json['sessionId'] as String,
      title: json['title'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String? ?? '/',
      commandCount: json['commandCount'] as int? ?? 0,
      recentCommands: List<String>.from((json['recentCommands'] as List?) ?? []),
      recentScrollback: List<String>.from((json['recentScrollback'] as List?) ?? []),
      metadata: Map<String, dynamic>.from((json['metadata'] as Map?) ?? {}),
      timestamp: DateTime.parse(json['timestamp'] as String),
      entryCount: json['entryCount'] as int? ?? 0,
    );
  }
}

class RecoveryResult {
  final bool success;
  final String? sessionId;
  final Map<String, dynamic>? recoveredState;
  final String? error;

  RecoveryResult({required this.success, this.sessionId, this.recoveredState, this.error});
}

class RecoveryStatistics {
  final String sessionId;
  final int totalEntries;
  final int commandCount;
  final int errorCount;
  final int checkpointCount;
  final DateTime? lastCheckpoint;
  final DateTime? lastActivity;
  final String? workingDirectory;

  RecoveryStatistics({
    required this.sessionId,
    this.totalEntries = 0,
    this.commandCount = 0,
    this.errorCount = 0,
    this.checkpointCount = 0,
    this.lastCheckpoint,
    this.lastActivity,
    this.workingDirectory,
  });
}