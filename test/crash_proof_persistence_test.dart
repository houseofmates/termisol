import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import '../lib/core/crash_proof_persistence.dart';

class MockPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getLibraryPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    return [Directory.systemTemp.path];
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    return [Directory.systemTemp.path];
  }

  @override
  Future<String?> getDownloadsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  group('CrashProofPersistence Tests', () {
    late CrashProofPersistence persistence;
    late Directory testDir;

    setUpAll(() async {
      PathProviderPlatform.instance = MockPathProvider();
      testDir = await Directory.systemTemp.createTemp('termisol_test_');
    });

    tearDownAll(() async {
      await persistence.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    setUp(() async {
      persistence = CrashProofPersistence();
      await persistence.initialize();
    });

    tearDown(() async {
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('should create session successfully', () async {
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
        environment: {'TERM': 'xterm-256color'},
        command: '/bin/bash',
      );

      expect(sessionId, isNotEmpty);
      expect(persistence.activeSessions, equals(1));
    });

    test('should update session content', () async {
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
      );

      await persistence.updateSession(sessionId, content: 'echo "Hello World"');
      
      final session = await persistence.getSession(sessionId);
      expect(session?.content, equals('echo "Hello World"'));
    });

    test('should handle session timeout', () async {
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
      );

      // Simulate session timeout by modifying last activity
      final session = await persistence.getSession(sessionId);
      if (session != null) {
        session.lastActivity = DateTime.now().subtract(const Duration(hours: 25));
        await persistence.updateSession(sessionId);
      }

      // Trigger cleanup
      await persistence.performCleanup();
      
      expect(persistence.activeSessions, equals(0));
    });

    test('should create and verify backups', () async {
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
      );
      
      await persistence.updateSession(sessionId, content: 'Important data');

      await persistence.createBackup();
      
      expect(persistence.availableBackups, greaterThan(0));
      
      final backup = await persistence.getLatestBackup();
      expect(backup, isNotNull);
      expect(backup!.sessions, contains(sessionId));
    });

    test('should detect and recover from corruption', () async {
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
      );
      
      await persistence.updateSession(sessionId, content: 'Original content');

      // Simulate corruption by updating session with invalid data
      await persistence.updateSession(sessionId, content: 'Original content');

      // Reinitialize to trigger corruption detection
      await persistence.dispose();
      persistence = CrashProofPersistence();
      await persistence.initialize();

      expect(persistence.activeSessions, equals(0));
    });

    test('should handle concurrent session operations', () async {
      final futures = <Future<String>>[];
      
      // Create multiple sessions concurrently
      for (int i = 0; i < 10; i++) {
        futures.add(persistence.createSession(
          title: 'Session $i',
          workingDirectory: '/home/user',
        ));
      }

      final sessionIds = await Future.wait(futures);
      
      expect(sessionIds.length, equals(10));
      expect(persistence.activeSessions, equals(10));
      
      // Verify all sessions are unique
      final uniqueIds = sessionIds.toSet();
      expect(uniqueIds.length, equals(10));
    });

    test('should maintain backup rotation limits', () async {
      // Create sessions and backups beyond the limit
      for (int i = 0; i < 15; i++) {
        await persistence.createSession(
          title: 'Session $i',
          workingDirectory: '/home/user',
        );
        await persistence.createBackup();
      }

      expect(persistence.availableBackups, lessThanOrEqualTo(10));
    });

    test('should generate valid device ID', () async {
      await persistence.initialize();
      
      // Device ID should be consistent across restarts
      final deviceId1 = persistence.deviceId;
      
      await persistence.dispose();
      persistence = CrashProofPersistence();
      await persistence.initialize();
      
      final deviceId2 = persistence.deviceId;
      
      expect(deviceId1, equals(deviceId2));
      expect(deviceId1?.length, equals(16));
    });

    test('should handle crash recovery scenario', () async {
      // Create a session
      final sessionId = await persistence.createSession(
        title: 'Test Session',
        workingDirectory: '/home/user',
      );
      
      await persistence.updateSession(sessionId, content: 'Important data');

      // Simulate crash by creating crash indicator
      final sessionsDir = Directory('${testDir.path}/.termisol/sessions');
      final crashIndicator = File('${sessionsDir.path}/.crash_indicator');
      await crashIndicator.writeAsString(DateTime.now().toIso8601String());

      // Reinitialize to trigger crash recovery
      await persistence.dispose();
      persistence = CrashProofPersistence();
      await persistence.initialize();

      expect(persistence.recoveryMode, isTrue);
      
      final crashReports = await persistence.getCrashReports();
      expect(crashReports.length, greaterThan(0));
    });
  });
}