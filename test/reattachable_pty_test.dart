import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import '../lib/core/reattachable_pty_manager.dart';

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
  group('ReattachablePtyManager Tests', () {
    late ReattachablePtyManager manager;
    late Directory testDir;

    setUpAll(() async {
      PathProviderPlatform.instance = MockPathProvider();
      testDir = await Directory.systemTemp.createTemp('pty_test_');
    });

    setUp(() async {
      manager = ReattachablePtyManager();
      await manager.initialize();
    });

    tearDown(() async {
      await manager.dispose();
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }
    });

    test('should create PTY session successfully', () async {
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
        cols: 80,
        rows: 24,
      );

      expect(sessionId, isNotEmpty);
      expect(manager.activeSessions, equals(1));
      expect(manager.sessionIds, contains(sessionId));
    });

    test('should handle session limits', () async {
      // create sessions up to the limit
      final futures = <Future<String>>[];
      for (int i = 0; i < 101; i++) {
        futures.add(manager.createSession(
          workingDirectory: Directory.current.path,
          shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
        ));
      }

      expect(
        () => Future.wait(futures),
        throwsA(isA<StateError>()),
      );
    });

    test('should recover existing sessions on restart', () async {
      // create initial session
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
      );

      // dispose and recreate manager (simulating restart)
      await manager.dispose();
      manager = ReattachablePtyManager();
      await manager.initialize();

      expect(manager.activeSessions, equals(1));
      expect(manager.sessionIds, contains(sessionId));
    });

    test('should cleanup dead sessions', () async {
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
      );

      // simulate dead session
      final session = await manager.getSession(sessionId);
      if (session != null) {
        // mark session as dead by setting old last activity
        session.lastActivity = DateTime.now().subtract(const Duration(hours: 25));
        await manager.updateSession(sessionId);
      }

      // trigger cleanup
      await manager.performCleanup();

      expect(manager.activeSessions, equals(0));
    });

    test('should handle socket cleanup', () async {
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
      );

      // verify socket file exists
      final socketDir = Directory('${testDir.path}/.termisol/sockets');
      final socketFile = File('${socketDir.path}/$sessionId.sock');
      expect(await socketFile.exists(), isTrue);

      // detach session
      await manager.detachSession(sessionId);

      // socket should be cleaned up
      await Future.delayed(const Duration(milliseconds: 100));
      expect(await socketFile.exists(), isFalse);
    });

    test('should generate unique session IDs', () async {
      final futures = <Future<String>>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(manager.createSession(
          workingDirectory: Directory.current.path,
          shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
        ));
      }

      final sessionIds = await Future.wait(futures);
      final uniqueIds = sessionIds.toSet();
      
      expect(uniqueIds.length, equals(10));
    });

    test('should handle heartbeat monitoring', () async {
      // wait for heartbeat to be sent
      await Future.delayed(const Duration(seconds: 31));

      final heartbeatFile = File('${testDir.path}/.termisol/sockets/heartbeat');
      expect(await heartbeatFile.exists(), isTrue);

      final content = await heartbeatFile.readAsString();
      expect(content, contains('timestamp'));
      expect(content, contains('sessions'));
      expect(content, contains('pid'));
    });

    test('should maintain instance ID across restarts', () async {
      final instanceId1 = manager.instanceId;
      
      await manager.dispose();
      manager = ReattachablePtyManager();
      await manager.initialize();

      final instanceId2 = manager.instanceId;
      
      expect(instanceId1, equals(instanceId2));
      expect(instanceId1?.length, equals(8));
    });

    test('should handle session reconnection', () async {
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
      );

      // simulate reconnection by creating new manager instance
      await manager.dispose();
      manager = ReattachablePtyManager();
      await manager.initialize();

      expect(manager.activeSessions, equals(1));
      expect(manager.sessionIds, contains(sessionId));
    });

    test('should validate session integrity', () async {
      final sessionId = await manager.createSession(
        workingDirectory: Directory.current.path,
        shell: Platform.isWindows ? 'cmd.exe' : '/bin/bash',
      );

      final session = await manager.getSession(sessionId);
      expect(session, isNotNull);
      expect(session!.isValid, isTrue);
      expect(session.id, equals(sessionId));
      expect(session.shell, isNotEmpty);
      expect(session.workingDirectory, isNotEmpty);
    });
  });
}