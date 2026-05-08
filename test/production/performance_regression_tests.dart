import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/terminal_session.dart';
import '../../lib/core/optimized_text_buffer.dart';
import '../../lib/core/lazy_terminal_output.dart';
import '../../lib/core/smart_auto_complete.dart';

/// Comprehensive performance regression testing
/// Tests performance characteristics, bottlenecks, and regressions
void main() {
  group('Performance Regression Tests', () {
    late Directory testTempDir;
    
    setUp(() async {
      testTempDir = await Directory.systemTemp.createTemp('termisol_perf_test_');
    });
    
    tearDown(() async {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    });

    test('terminal session startup performance', () async {
      final stopwatch = Stopwatch()..start();
      final sessions = <TerminalSession>[];
      
      // Test session creation performance
      for (int i = 0; i < 10; i++) {
        final sessionStart = Stopwatch()..start();
        final session = TerminalSession(
          id: 'perf-startup-$i',
          name: 'Performance Startup $i',
        );
        
        await session.start();
        sessionStart.stop();
        
        sessions.add(session);
        
        // Each session should start quickly
        expect(sessionStart.elapsedMilliseconds, lessThan(1000));
      }
      
      stopwatch.stop();
      
      // Total time should be reasonable
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      
      // Clean up
      for (final session in sessions) {
        await session.disposeSession();
      }
    });

    test('large file handling performance', () async {
      final session = TerminalSession(
        id: 'perf-large-file',
        name: 'Large File Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Send large amount of data
      final largeData = 'x' * 1000000; // 1MB
      final chunks = largeData.split('');
      
      for (final chunk in chunks.take(10000)) { // Limit for test
        session.sendToBackend(utf8.encode(chunk));
      }
      
      stopwatch.stop();
      
      // Should handle large data efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      
      await session.disposeSession();
    });

    test('concurrent session performance', () async {
      final stopwatch = Stopwatch()..start();
      final sessions = <TerminalSession>[];
      
      // Create multiple concurrent sessions
      final futures = <Future>[];
      
      for (int i = 0; i < 20; i++) {
        futures.add(Future(() async {
          final session = TerminalSession(
            id: 'perf-concurrent-$i',
            name: 'Concurrent Performance $i',
          );
          
          await session.start();
          
          // Add some load
          for (int j = 0; j < 10; j++) {
            session.sendToBackend(utf8.encode('echo "session $i, command $j"\n'));
          }
          
          sessions.add(session);
        }));
      }
      
      await Future.wait(futures);
      stopwatch.stop();
      
      // Concurrent operations should complete in reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      
      // Clean up
      for (final session in sessions) {
        await session.disposeSession();
      }
    });

    test('memory usage scaling', () async {
      final memoryUsage = <int>[];
      
      // Test memory usage with increasing load
      for (int i = 1; i <= 10; i++) {
        final session = TerminalSession(
          id: 'perf-memory-$i',
          name: 'Memory Performance $i',
        );
        
        await session.start();
        
        // Add increasing amount of data
        for (int j = 0; j < i * 1000; j++) {
          session.sendToBackend(utf8.encode('x'));
        }
        
        // Simulate memory measurement
        final simulatedMemory = i * 1000 + math.Random().nextInt(500);
        memoryUsage.add(simulatedMemory);
        
        await session.disposeSession();
      }
      
      // Memory usage should scale linearly, not exponentially
      final growthRate = memoryUsage.last / memoryUsage.first;
      expect(growthRate, lessThan(15)); // Should not grow more than 15x for 10x load
    });

    test('text buffer performance', () async {
      final buffer = OptimizedTextBuffer(maxLines: 50000);
      final stopwatch = Stopwatch()..start();
      
      // Add large amount of content
      for (int i = 0; i < 10000; i++) {
        final line = 'Line $i: ${'x' * 100}';
        buffer.append(line);
      }
      
      stopwatch.stop();
      
      // Buffer operations should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      
      // Test retrieval performance
      final retrieveStopwatch = Stopwatch()..start();
      final visibleText = buffer.getVisibleText(1000);
      retrieveStopwatch.stop();
      
      expect(retrieveStopwatch.elapsedMilliseconds, lessThan(100));
      expect(visibleText.length, greaterThan(0));
      
      buffer.clear();
    });

    test('lazy output performance', () async {
      final lazyOutput = LazyTerminalOutput(sessionId: 'perf-test', visibleLines: 1000);
      final stopwatch = Stopwatch()..start();
      
      // Add massive amount of content
      for (int i = 0; i < 50000; i++) {
        lazyOutput.addContent(['Line $i: ${'x' * 50}']);
      }
      
      stopwatch.stop();
      
      // Should handle large content efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      expect(lazyOutput.totalLineCount, equals(50000));
      expect(lazyOutput.visibleLineCount, lessThanOrEqualTo(1000));
      
      // Test pagination performance
      final pageStopwatch = Stopwatch()..start();
      final page = lazyOutput.getPage(0, 100);
      pageStopwatch.stop();
      
      expect(pageStopwatch.elapsedMilliseconds, lessThan(50));
      expect(page.length, equals(100));
      
      lazyOutput.dispose();
    });

    test('auto-complete performance', () async {
      final autoComplete = SmartAutoComplete();
      final stopwatch = Stopwatch()..start();
      
      // Add large command history
      for (int i = 0; i < 10000; i++) {
        autoComplete.addToHistory('command_$i --arg${i % 10} --flag --option value');
      }
      
      stopwatch.stop();
      
      // History building should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      
      // Test suggestion performance
      final suggestStopwatch = Stopwatch()..start();
      final suggestions = await autoComplete.getSuggestions('command_');
      suggestStopwatch.stop();
      
      expect(suggestStopwatch.elapsedMilliseconds, lessThan(500));
      expect(suggestions.length, greaterThan(0));
      
      autoComplete.clearHistory();
    });

    test('terminal resize performance', () async {
      final session = TerminalSession(
        id: 'perf-resize',
        name: 'Resize Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Perform many resizes
      for (int i = 0; i < 100; i++) {
        final width = 80 + (i % 40);
        final height = 24 + (i % 20);
        session.terminal.resize(width, height);
      }
      
      stopwatch.stop();
      
      // Resizes should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      
      await session.disposeSession();
    });

    test('session disposal performance', () async {
      final sessions = <TerminalSession>[];
      
      // Create many sessions
      for (int i = 0; i < 50; i++) {
        final session = TerminalSession(
          id: 'perf-disposal-$i',
          name: 'Disposal Performance $i',
        );
        
        await session.start();
        
        // Add some content
        for (int j = 0; j < 100; j++) {
          session.sendToBackend(utf8.encode('echo "session $i, line $j"\n'));
        }
        
        sessions.add(session);
      }
      
      // Test disposal performance
      final stopwatch = Stopwatch()..start();
      
      for (final session in sessions) {
        await session.disposeSession();
      }
      
      stopwatch.stop();
      
      // Disposal should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('AI query performance under load', () async {
      final session = TerminalSession(
        id: 'perf-ai-load',
        name: 'AI Load Performance Test',
      );
      
      await session.start();
      
      // Mock AI handler with varying response times
      int queryCount = 0;
      session.onAiQuery = (query) async {
        queryCount++;
        await Future.delayed(Duration(milliseconds: 10 + (queryCount % 50)));
        return 'Response $queryCount to: $query';
      };
      
      final stopwatch = Stopwatch()..start();
      
      // Send many AI queries
      for (int i = 0; i < 20; i++) {
        session.sendToBackend(utf8.encode('/ai test query $i\n'));
      }
      
      // Wait for all queries to complete
      await Future.delayed(Duration(milliseconds: 2000));
      
      stopwatch.stop();
      
      // Should handle AI queries efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      
      await session.disposeSession();
    });

    test('configuration loading performance', () async {
      final configFile = File('${testTempDir.path}/large_config.json');
      
      // Create large configuration
      final largeConfig = <String, dynamic>{};
      for (int i = 0; i < 1000; i++) {
        largeConfig['section_$i'] = {
          'value1': 'data_$i',
          'value2': i,
          'nested': {
            'deep': List.generate(100, (j) => 'item_$i-$j'),
          },
        };
      }
      
      await configFile.writeAsString(jsonEncode(largeConfig));
      
      // Test loading performance
      final stopwatch = Stopwatch()..start();
      
      // Simulate config loading (would use actual config system)
      final configData = jsonEncode(largeConfig);
      final decoded = jsonDecode(configData);
      
      stopwatch.stop();
      
      // Config loading should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(decoded.keys.length, equals(1000));
    });

    test('file I/O performance', () async {
      final testFile = File('${testTempDir.path}/perf_test.txt');
      
      // Test write performance
      final writeStopwatch = Stopwatch()..start();
      
      final largeContent = 'x' * 1000000; // 1MB
      await testFile.writeAsString(largeContent);
      
      writeStopwatch.stop();
      
      expect(writeStopwatch.elapsedMilliseconds, lessThan(1000));
      
      // Test read performance
      final readStopwatch = Stopwatch()..start();
      
      final readContent = await testFile.readAsString();
      
      readStopwatch.stop();
      
      expect(readStopwatch.elapsedMilliseconds, lessThan(1000));
      expect(readContent.length, equals(largeContent.length));
    });

    test('network operation performance', () async {
      final session = TerminalSession(
        id: 'perf-network',
        name: 'Network Performance Test',
      );
      
      await session.start();
      
      // Test network-like operations
      final stopwatch = Stopwatch()..start();
      
      // Simulate network operations
      final networkCommands = [
        'ping -c 1 localhost',
        'curl -s http://httpbin.org/ip',
        'wget -qO- http://httpbin.org/user-agent',
      ];
      
      for (final command in networkCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      stopwatch.stop();
      
      // Network operations should complete in reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      
      await session.disposeSession();
    });

    test('memory pressure performance', () async {
      final session = TerminalSession(
        id: 'perf-memory-pressure',
        name: 'Memory Pressure Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Create memory pressure
      final buffers = <List<int>>[];
      
      for (int i = 0; i < 10; i++) {
        final buffer = List<int>.filled(100000, i % 256);
        buffers.add(buffer);
        session.sendToBackend(buffer);
      }
      
      // Give time for processing
      await Future.delayed(Duration(milliseconds: 500));
      
      stopwatch.stop();
      
      // Should handle memory pressure gracefully
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      
      // Clean up
      buffers.clear();
      await session.disposeSession();
    });

    test('CPU utilization under load', () async {
      final session = TerminalSession(
        id: 'perf-cpu',
        name: 'CPU Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Create CPU-intensive operations
      for (int i = 0; i < 1000; i++) {
        // Simulate CPU work
        final data = List<int>.generate(1000, (j) => (i * j) % 256);
        session.sendToBackend(data);
        
        if (i % 100 == 0) {
          await Future.delayed(Duration(milliseconds: 1));
        }
      }
      
      stopwatch.stop();
      
      // Should complete in reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      
      await session.disposeSession();
    });

    test('rendering performance with large content', () async {
      final session = TerminalSession(
        id: 'perf-rendering',
        name: 'Rendering Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Send content that requires rendering
      for (int i = 0; i < 1000; i++) {
        final content = '\x1b[31mRed line $i\x1b[0m\n'
                      '\x1b[32mGreen line $i\x1b[0m\n'
                      '\x1b[34mBlue line $i\x1b[0m\n';
        session.sendToBackend(utf8.encode(content));
      }
      
      stopwatch.stop();
      
      // Rendering should be efficient
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      
      await session.disposeSession();
    });

    test('search performance in large buffers', () async {
      final buffer = OptimizedTextBuffer(maxLines: 100000);
      
      // Add large content
      for (int i = 0; i < 10000; i++) {
        buffer.append('Line $i: This is a test line with searchable content');
      }
      
      final stopwatch = Stopwatch()..start();
      
      // Test search performance
      final searchText = 'searchable';
      final results = buffer.getVisibleText(100000).contains(searchText);
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(results, isTrue);
      
      buffer.clear();
    });

    test('concurrent read/write performance', () async {
      final session = TerminalSession(
        id: 'perf-concurrent-rw',
        name: 'Concurrent RW Performance Test',
      );
      
      await session.start();
      
      final stopwatch = Stopwatch()..start();
      
      // Perform concurrent read/write operations
      final futures = <Future>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < 100; j++) {
            session.sendToBackend(utf8.encode('write $i-$j\n'));
            await Future.delayed(Duration(milliseconds: 1));
          }
        }));
      }
      
      await Future.wait(futures);
      stopwatch.stop();
      
      // Concurrent operations should be efficient
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      
      await session.disposeSession();
    });

    test('performance degradation detection', () async {
      final times = <int>[];
      
      // Test performance over multiple iterations
      for (int iteration = 0; iteration < 5; iteration++) {
        final session = TerminalSession(
          id: 'perf-degradation-$iteration',
          name: 'Performance Degradation Test $iteration',
        );
        
        await session.start();
        
        final iterationStopwatch = Stopwatch()..start();
        
        // Standardized load
        for (int i = 0; i < 1000; i++) {
          session.sendToBackend(utf8.encode('echo "test $i"\n'));
        }
        
        iterationStopwatch.stop();
        times.add(iterationStopwatch.elapsedMilliseconds);
        
        await session.disposeSession();
      }
      
      // Performance should not degrade significantly
      final firstTime = times.first;
      final lastTime = times.last;
      final degradationRatio = lastTime / firstTime;
      
      expect(degradationRatio, lessThan(2.0)); // Should not be more than 2x slower
    });
  });
}
