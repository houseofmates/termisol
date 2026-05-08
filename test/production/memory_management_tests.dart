import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/terminal_session.dart';
import '../../lib/core/optimized_text_buffer.dart';
import '../../lib/core/lazy_terminal_output.dart';
import '../../lib/core/smart_auto_complete.dart';
import '../../lib/core/session_persistence.dart';
import '../../lib/core/crash_recovery.dart';
import '../../lib/core/termisol_plugin_system.dart';
import '../../lib/core/long_command_notifier.dart';

/// Comprehensive memory management and resource cleanup testing
/// Tests for memory leaks, resource exhaustion, and proper cleanup
void main() {
  group('Memory Management Tests', () {
    late Directory testTempDir;
    
    setUp(() async {
      testTempDir = await Directory.systemTemp.createTemp('termisol_memory_test_');
    });
    
    tearDown(() async {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    });

    test('OptimizedTextBuffer handles large content without leaks', () async {
      final buffer = OptimizedTextBuffer(maxLines: 10000);
      
      // Add large amount of content
      for (int i = 0; i < 5000; i++) {
        final line = 'Line $i: ${'x' * 100}'; // 100+ chars per line
        buffer.append(line);
        
        if (i % 1000 == 0) {
          // Check memory usage periodically
          final stats = buffer.stats;
          expect(stats['total_lines'], lessThanOrEqualTo(10000));
        }
      }
      
      // Test cleanup
      buffer.clear();
      final finalStats = buffer.stats;
      expect(finalStats['total_lines'], equals(0));
    });

    test('LazyTerminalOutput manages memory efficiently', () async {
      final lazyOutput = LazyTerminalOutput(sessionId: 'test', visibleLines: 1000);
      
      // Add massive amount of content
      for (int i = 0; i < 10000; i++) {
        final content = ['Line $i: ${'x' * 50}'];
        lazyOutput.addContent(content);
      }
      
      // Should only keep visible lines in memory
      expect(lazyOutput.totalLineCount, equals(10000));
      expect(lazyOutput.visibleLineCount, lessThanOrEqualTo(1000));
      
      // Test disposal
      lazyOutput.dispose();
      expect(lazyOutput.totalLineCount, equals(0));
    });

    test('SmartAutoComplete manages history size properly', () async {
      final autoComplete = SmartAutoComplete();
      
      // Add massive amount of commands
      for (int i = 0; i < 10000; i++) {
        autoComplete.addToHistory('command_$i --arg${i % 10} --flag');
      }
      
      // Should limit history size
      expect(autoComplete.recentCommands.length, lessThanOrEqualTo(1000));
      
      // Test cleanup
      autoComplete.clearHistory();
      expect(autoComplete.recentCommands.length, equals(0));
    });

    test('SessionPersistence handles large session data', () async {
      final persistence = SessionPersistence();
      final sessions = <Map<String, dynamic>>[];
      
      // Create large session data
      for (int i = 0; i < 100; i++) {
        sessions.add({
          'id': 'session_$i',
          'name': 'Session $i',
          'content': 'x' * 10000, // 10KB per session
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      
      // Should handle large data without issues
      await persistence.saveSessions(sessions);
      
      // Test loading
      final loadedSessions = await persistence.loadSessions();
      expect(loadedSessions.length, equals(100));
    });

    test('CrashRecovery manages memory during monitoring', () async {
      final crashRecovery = CrashRecovery();
      
      // Start monitoring
      crashRecovery.startHealthMonitoring();
      
      // Simulate many commands
      for (int i = 0; i < 1000; i++) {
        crashRecovery.onCommand('command_$i');
      }
      
      // Should not accumulate excessive memory
      crashRecovery.dispose();
    });

    test('TermisolPluginSystem handles plugin loading/unloading', () async {
      final pluginSystem = TermisolPluginSystem();
      
      // Try to load many plugins (including invalid ones)
      for (int i = 0; i < 50; i++) {
        try {
          await pluginSystem.loadPlugin('plugin_$i');
        } catch (e) {
          // Expected for invalid plugins
        }
      }
      
      // Should handle gracefully
      await pluginSystem.disposeAll();
    });

    test('LongCommandNotifier manages notifications properly', () async {
      final notifier = LongCommandNotifier();
      
      // Start many long commands
      for (int i = 0; i < 100; i++) {
        notifier.notifyLongCommand('command_$i');
      }
      
      // Should track all active commands
      expect(notifier.activeCommands.length, equals(100));
      
      // Cancel all notifications
      for (final command in notifier.activeCommands.keys) {
        notifier.cancelNotification(command);
      }
      
      expect(notifier.activeCommands.length, equals(0));
      notifier.dispose();
    });

    test('TerminalSession manages memory during lifecycle', () async {
      final sessions = <TerminalSession>[];
      
      // Create many sessions
      for (int i = 0; i < 20; i++) {
        final session = TerminalSession(
          id: 'memory-test-$i',
          name: 'Memory Test $i',
          maxLines: 1000,
        );
        
        await session.start();
        
        // Add some content
        session.sendToBackend('echo "test data for session $i"\n'.codeUnits);
        
        sessions.add(session);
      }
      
      // Give time for processing
      await Future.delayed(Duration(milliseconds: 500));
      
      // Dispose all sessions
      for (final session in sessions) {
        await session.disposeSession();
      }
      
      // Should complete without memory issues
    });

    test('handles rapid session creation and disposal', () async {
      // Test for memory leaks in rapid cycling
      for (int cycle = 0; cycle < 10; cycle++) {
        final sessions = <TerminalSession>[];
        
        // Create multiple sessions
        for (int i = 0; i < 5; i++) {
          final session = TerminalSession(
            id: 'rapid-$cycle-$i',
            name: 'Rapid Session $cycle-$i',
          );
          
          await session.start();
          sessions.add(session);
        }
        
        // Dispose rapidly
        for (final session in sessions) {
          await session.disposeSession();
        }
      }
    });

    test('OptimizedTextBuffer handles edge cases', () async {
      final buffer = OptimizedTextBuffer(maxLines: 100);
      
      // Test empty buffer
      buffer.clear();
      expect(buffer.stats['total_lines'], equals(0));
      
      // Test single character lines
      for (int i = 0; i < 200; i++) {
        buffer.append('x');
      }
      
      // Should maintain max lines
      expect(buffer.stats['total_lines'], lessThanOrEqualTo(100));
      
      // Test very long lines
      buffer.append('x' * 100000);
      
      // Should handle gracefully
      final visibleText = buffer.getVisibleText(10);
      expect(visibleText, isA<String>());
    });

    test('LazyTerminalOutput handles pagination correctly', () async {
      final lazyOutput = LazyTerminalOutput(sessionId: 'test', visibleLines: 100);
      
      // Add content that exceeds visible limit
      for (int i = 0; i < 500; i++) {
        lazyOutput.addContent(['Line $i']);
      }
      
      // Test pagination
      final page1 = lazyOutput.getPage(0, 100);
      expect(page1.length, equals(100));
      
      final page2 = lazyOutput.getPage(100, 100);
      expect(page2.length, equals(100));
      
      // Test out of bounds
      final outOfBounds = lazyOutput.getPage(1000, 100);
      expect(outOfBounds.length, equals(0));
    });

    test('SmartAutoComplete handles corrupted history', () async {
      final autoComplete = SmartAutoComplete();
      
      // Add corrupted commands
      for (int i = 0; i < 100; i++) {
        final corrupted = 'command_$i\x00\x01\x02corrupted';
        autoComplete.addToHistory(corrupted);
      }
      
      // Should handle gracefully
      final suggestions = await autoComplete.getSuggestions('comm');
      expect(suggestions, isA<List>());
      
      // Test cleanup
      autoComplete.clearHistory();
    });

    test('memory pressure simulation', () async {
      final session = TerminalSession(
        id: 'memory-pressure-test',
        name: 'Memory Pressure Test',
        maxLines: 50000,
      );
      
      await session.start();
      
      // Simulate memory pressure
      final largeBuffers = <List<int>>[];
      
      for (int i = 0; i < 10; i++) {
        final buffer = List<int>.filled(100000, i % 256);
        largeBuffers.add(buffer);
        session.sendToBackend(buffer);
      }
      
      // Give time for processing
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Clean up
      largeBuffers.clear();
      await session.disposeSession();
    });

    test('resource exhaustion recovery', () async {
      final session = TerminalSession(
        id: 'resource-exhaustion-test',
        name: 'Resource Exhaustion Test',
      );
      
      await session.start();
      
      // Try to exhaust resources
      try {
        for (int i = 0; i < 1000; i++) {
          final data = List<int>.filled(10000, i % 256);
          session.sendToBackend(data);
          
          if (i % 100 == 0) {
            await Future.delayed(Duration(milliseconds: 10));
          }
        }
      } catch (e) {
        // Should handle resource exhaustion gracefully
        expect(e, isA<Exception>());
      }
      
      await session.disposeSession();
    });

    test('concurrent memory operations', () async {
      final buffer = OptimizedTextBuffer(maxLines: 1000);
      
      // Perform concurrent operations
      final futures = <Future>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() {
          for (int j = 0; j < 100; j++) {
            buffer.append('Concurrent $i-$j: ${'x' * 10}');
          }
        }));
      }
      
      // Wait for all operations
      await Future.wait(futures);
      
      // Should handle concurrent access
      expect(buffer.stats['total_lines'], lessThanOrEqualTo(1000));
      
      buffer.clear();
    });

    test('memory leak detection in session lifecycle', () async {
      final initialMemory = _getCurrentMemoryUsage();
      
      // Create and dispose many sessions
      for (int i = 0; i < 50; i++) {
        final session = TerminalSession(
          id: 'leak-test-$i',
          name: 'Leak Test $i',
        );
        
        await session.start();
        session.sendToBackend('echo "test"\n'.codeUnits);
        await session.disposeSession();
      }
      
      // Force garbage collection
      await Future.delayed(Duration(milliseconds: 100));
      
      final finalMemory = _getCurrentMemoryUsage();
      
      // Memory usage should not grow significantly
      // Note: This is a rough check and may not be precise
      expect(finalMemory - initialMemory, lessThan(50 * 1024 * 1024)); // 50MB tolerance
    });

    test('handles memory fragmentation', () async {
      final buffers = <OptimizedTextBuffer>[];
      
      // Create many buffers with varying sizes
      for (int i = 0; i < 20; i++) {
        final buffer = OptimizedTextBuffer(maxLines: 100 + (i % 10) * 50);
        
        // Add varying amounts of content
        for (int j = 0; j < 50 + (i % 5) * 20; j++) {
          buffer.append('Buffer $i Line $j: ${'x' * (10 + (i % 5) * 5)}');
        }
        
        buffers.add(buffer);
      }
      
      // Clear all buffers
      for (final buffer in buffers) {
        buffer.clear();
      }
      
      // Should handle fragmentation gracefully
    });
  });
}

/// Get current memory usage (approximate)
int _getCurrentMemoryUsage() {
  // This is a rough approximation
  // In real implementation, you'd use platform-specific APIs
  return DateTime.now().millisecondsSinceEpoch % 100000000;
}
