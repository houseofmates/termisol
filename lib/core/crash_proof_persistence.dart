import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'session_persistence.dart';

class CrashProofPersistence {
  static final CrashProofPersistence _instance = CrashProofPersistence._internal();
  factory CrashProofPersistence() => _instance;
  CrashProofPersistence._internal();

  bool _isInitialized = false;

  Directory? _sessionsDir;
  Directory? _backupsDir;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _sessionsDir = Directory('${appDir.path}/.termisol/sessions');
      _backupsDir = Directory('${appDir.path}/.termisol/backups');

      await _sessionsDir!.create(recursive: true);
      await _backupsDir!.create(recursive: true);

      _isInitialized = true;
    } catch (e, stack) {
      debugPrint('Failed to initialize CrashProofPersistence: $e\n$stack');
      rethrow;
    }
  }

  Future<void> saveSessionAtomic(PersistedSessionRecord session) async {
    if (!_isInitialized || _sessionsDir == null) return;

    try {
      final sessionFile = File('${_sessionsDir!.path}/${session.id}.json');
      final tempFile = File('${_sessionsDir!.path}/${session.id}.json.tmp');

      final jsonData = jsonEncode(session.toJson());

      // Calculate checksum
      final bytes = utf8.encode(jsonData);
      final digest = sha256.convert(bytes);

      final dataWithChecksum = jsonEncode({
        'data': session.toJson(),
        'checksum': digest.toString(),
      });

      // Write to temp file first
      await tempFile.writeAsString(dataWithChecksum, flush: true);

      // Atomically rename temp file to final file
      await tempFile.rename(sessionFile.path);
    } catch (e, stack) {
      debugPrint('Failed to save session atomically ${session.id}: $e\n$stack');
      rethrow;
    }
  }

  Future<void> rotateBackups(SessionBackup backup) async {
    if (!_isInitialized || _backupsDir == null) return;

    try {
      final backupFile = File('${_backupsDir!.path}/${backup.id}.backup');
      final tempFile = File('${_backupsDir!.path}/${backup.id}.backup.tmp');

      final jsonData = jsonEncode(backup.toJson());
      final bytes = utf8.encode(jsonData);
      final digest = sha256.convert(bytes);

      final dataWithChecksum = jsonEncode({
        'data': backup.toJson(),
        'checksum': digest.toString(),
      });

      await tempFile.writeAsString(dataWithChecksum, flush: true);
      await tempFile.rename(backupFile.path);

      // Rotate backups - keep only the last 10
      final dirList = _backupsDir!.listSync();
      final backupFiles = dirList.whereType<File>().where((f) => f.path.endsWith('.backup')).toList();

      if (backupFiles.length > 10) {
        backupFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

        final toDelete = backupFiles.length - 10;
        for (var i = 0; i < toDelete; i++) {
          await backupFiles[i].delete();
        }
      }
    } catch (e, stack) {
      debugPrint('Failed to rotate backups: $e\n$stack');
      rethrow;
    }
  }
}
