import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import '../lib/core/robust_error_handler.dart';
import '../lib/core/advanced_performance_optimizer.dart';
import '../lib/core/production_config_system.dart';
import '../lib/core/asciicast_recorder.dart';
import '../lib/core/command_guard.dart';
import '../lib/core/cross_platform_optimizer.dart';
import '../lib/core/intelligent_cache_manager.dart';

/// Comprehensive Platform Test Suite
/// 
/// Tests all critical components across target platforms:
/// - Ubuntu 24.04.3 (house@192.168.4.250)
/// - Android (Google Pixel 10 Pro)
/// - Oculus Quest 2 VR
/// - Windows 11
void main() {
  group('Comprehensive Platform Tests', () {
    late RobustErrorHandler errorHandler;
    late AdvancedPerformanceOptimizer performanceOptimizer;
    late ProductionConfigSystem configSystem;
    late AsciicastRecorder asciicastRecorder;
    late CommandGuard commandGuard;
    late CrossPlatformOptimizer platformOptimizer;
    late IntelligentCacheManager cacheManager;

    setUpAll(() async {
      // Initialize all components
      errorHandler = RobustErrorHandler();
      await errorHandler.initialize();
      
      performanceOptimizer = AdvancedPerformanceOptimizer();
      await performanceOptimizer.initialize();
      
      configSystem = ProductionConfigSystem();
      await configSystem.initialize();
      
      asciicastRecorder = AsciicastRecorder();
      
      commandGuard = CommandGuard(
        strictMode: true,
        auditMode: true,
      );
      
      platformOptimizer = CrossPlatformOptimizer.instance;
      
      cacheManager = IntelligentCacheManager.instance;
      await cacheManager.initialize();
    });

    tearDownAll(() async {
      // Cleanup all components
      errorHandler.dispose();
      performanceOptimizer.dispose();
      asciicastRecorder.dispose();
      commandGuard.dispose();
      platformOptimizer.dispose();
      cacheManager.dispose();
    });

    group('Robust Error Handler Tests', () {
      test('should initialize correctly', () {
        expect(errorHandler.isInitialized, isTrue);
      });

      test('should handle errors gracefully', () async {
        final testError = Exception('Test error');
        await errorHandler.handleError(
          testError,
          StackTrace.current,
          context: 'Test Context',
          severity: ErrorSeverity.error,
        );
        
        final stats = errorHandler.getErrorStats();
        expect(stats['totalErrors'], greaterThan(0));
      });

      test('should perform recovery actions', () async {
        await errorHandler.triggerRecovery(ErrorType.memory);
        // Should not throw
        expect(true, isTrue);
      });

      test('should persist and load error history', () async {
        await errorHandler._persistError(ErrorReport(
          id: 'test-1',
          timestamp: DateTime.now(),
          error: 'Test error',
          stackTrace: StackTrace.current.toString(),
          context: 'Test',
          metadata: {},
          severity: ErrorSeverity.error,
          recoverable: true,
          platform: Platform.operatingSystem,
          version: '1.0.0',
        ));
        
        await errorHandler._loadErrorHistory();
        final history = errorHandler.getErrorHistory();
        expect(history.length, greaterThan(0));
      });
    });

    group('Advanced Performance Optimizer Tests', () {
      test('should initialize with platform detection', () {
        expect(performanceOptimizer.isInitialized, isTrue);
        expect(performanceOptimizer.platformType, isNotNull);
      });

      test('should monitor performance metrics', () async {
        performanceOptimizer.recordFrame(16.7); // 60 FPS
        await Future.delayed(Duration(milliseconds: 100));
        
        final metrics = performanceOptimizer.getCurrentMetrics();
        expect(metrics.fps, greaterThan(0));
        expect(metrics.frameTime, greaterThan(0));
      });

      test('should apply optimizations based on performance', () async {
        await performanceOptimizer.optimizePerformance();
        expect(performanceOptimizer.isOptimized, isTrue);
      });

      test('should detect performance issues', () async {
        // Simulate low FPS
        for (int i = 0; i < 10; i++) {
          performanceOptimizer.recordFrame(50.0); // 20 FPS
        }
        
        final issues = performanceOptimizer.getPerformanceIssues();
        expect(issues.length, greaterThan(0));
        expect(issues.any((issue) => issue.type == PerformanceIssueType.lowFPS), isTrue);
      });
    });

    group('Production Config System Tests', () {
      test('should detect platform correctly', () {
        expect(configSystem.platformType, isNotNull);
        expect(configSystem.isVRPlatform(), isA<bool>());
      });

      test('should load and save configuration', () async {
        await configSystem.set('test.key', 'test_value');
        final value = configSystem.get<String>('test.key');
        expect(value, equals('test_value'));
      });

      test('should apply platform-specific settings', () async {
        await configSystem.applyPlatformSettings();
        final settings = configSystem.getAllSettings();
        expect(settings.isNotEmpty, isTrue);
      });

      test('should validate configuration values', () {
        final result = configSystem.validateConfig({
          'performance.target_fps': 60,
          'performance.max_memory_mb': 512,
        });
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });
    });

    group('Asciicast Recorder Tests', () {
      test('should initialize correctly', () {
        expect(asciicastRecorder.isRecording, isFalse);
        expect(asciicastRecorder.frameCount, equals(0));
      });

      test('should start and stop recording', () async {
        await asciicastRecorder.startRecording();
        expect(asciicastRecorder.isRecording, isTrue);
        
        await Future.delayed(Duration(milliseconds: 200));
        
        await asciicastRecorder.stopRecording();
        expect(asciicastRecorder.isRecording, isFalse);
        expect(asciicastRecorder.frameCount, greaterThan(0));
      });

      test('should capture terminal output', () async {
        await asciicastRecorder.startRecording();
        
        asciicastRecorder.captureTerminalOutput('echo "Hello World"');
        
        await asciicastRecorder.stopRecording();
        
        final stats = asciicastRecorder.getStatistics();
        expect(stats['frameCount'], greaterThan(0));
      });

      test('should handle terminal resize', () async {
        await asciicastRecorder.startRecording();
        
        asciicastRecorder.resizeTerminal(120, 40);
        
        await asciicastRecorder.stopRecording();
        
        final stats = asciicastRecorder.getStatistics();
        expect(stats['metadata']['width'], equals(120));
        expect(stats['metadata']['height'], equals(40));
      });
    });

    group('Command Guard Tests', () {
      test('should initialize with security settings', () {
        expect(commandGuard.strictMode, isTrue);
        expect(commandGuard.auditMode, isTrue);
      });

      test('should block dangerous commands', () {
        final dangerousCommands = [
          'rm -rf /',
          'dd if=/dev/zero of=/dev/sda',
          ':(){ :|:& };:', // fork bomb
        ];
        
        for (final cmd in dangerousCommands) {
          final result = commandGuard.validateCommand(cmd);
          expect(result.isAllowed, isFalse, reason: 'Command should be blocked: $cmd');
          expect(result.reason, isNotNull);
        }
      });

      test('should allow safe commands', () {
        final safeCommands = [
          'ls -la',
          'echo "Hello"',
          'cd /home',
          'pwd',
        ];
        
        for (final cmd in safeCommands) {
          final result = commandGuard.validateCommand(cmd);
          expect(result.isAllowed, isTrue, reason: 'Command should be allowed: $cmd');
          expect(result.sanitizedCommand, isNotNull);
        }
      });

      test('should maintain audit log', () {
        commandGuard.validateCommand('ls -la');
        commandGuard.validateCommand('rm -rf /'); // This should be blocked
        
        final auditLog = commandGuard.getAuditLog();
        expect(auditLog.length, equals(2));
        
        final blockedCount = auditLog.where((entry) => entry.type == CommandValidationType.blocked).length;
        expect(blockedCount, equals(1));
      });

      test('should manage whitelist and blacklist', () {
        commandGuard.addToWhitelist('custom-command');
        expect(commandGuard.getStatistics()['whitelistedCommands'], equals(1));
        
        commandGuard.addToBlacklist('blocked-command');
        expect(commandGuard.getStatistics()['blacklistedCommands'], equals(1));
        
        commandGuard.removeFromWhitelist('custom-command');
        commandGuard.removeFromBlacklist('blocked-command');
        
        expect(commandGuard.getStatistics()['whitelistedCommands'], equals(0));
        expect(commandGuard.getStatistics()['blacklistedCommands'], equals(0));
      });
    });

    group('Cross-Platform Optimizer Tests', () {
      test('should detect current platform', () {
        expect(platformOptimizer.platformType, isNot(equals(PlatformType.unknown)));
      });

      test('should apply platform-specific optimizations', () {
        expect(platformOptimizer.isOptimized, isTrue);
        final settings = platformOptimizer.getOptimizationSettings();
        expect(settings.isNotEmpty, isTrue);
      });

      test('should provide platform recommendations', () {
        final recommendations = platformOptimizer.getPlatformRecommendations();
        expect(recommendations.isNotEmpty, isTrue);
        
        // Check that recommendations have proper structure
        for (final rec in recommendations) {
          expect(rec.title, isNotNull);
          expect(rec.description, isNotNull);
          expect(rec.actions, isNotEmpty);
        }
      });

      test('should handle optimization settings', () {
        platformOptimizer.applyOptimization('test.setting', 'test_value');
        final settings = platformOptimizer.getOptimizationSettings();
        expect(settings['test.setting'], equals('test_value'));
        
        platformOptimizer.resetOptimizations();
        expect(platformOptimizer.isOptimized, isFalse);
      });
    });

    group('Intelligent Cache Manager Tests', () {
      test('should initialize correctly', () async {
        expect(cacheManager.isInitialized, isTrue);
      });

      test('should store and retrieve from memory cache', () async {
        const testKey = 'test_memory_key';
        const testValue = 'test_memory_value';
        
        final putResult = await cacheManager.putMemory(testKey, testValue);
        expect(putResult, isTrue);
        
        final retrievedValue = cacheManager.getMemory<String>(testKey);
        expect(retrievedValue, equals(testValue));
      });

      test('should handle cache expiration', () async {
        const testKey = 'test_expiration_key';
        const testValue = 'test_expiration_value';
        
        await cacheManager.putMemory(testKey, testValue, ttl: Duration(milliseconds: 100));
        
        // Should be available immediately
        expect(cacheManager.getMemory<String>(testKey), equals(testValue));
        
        // Wait for expiration
        await Future.delayed(Duration(milliseconds: 150));
        
        // Should be expired
        expect(cacheManager.getMemory<String>(testKey), isNull);
      });

      test('should manage disk cache', () async {
        const testKey = 'test_disk_key';
        const testValue = {'test': 'disk_value'};
        
        final putResult = await cacheManager.putDisk(testKey, testValue);
        expect(putResult, isTrue);
        
        final retrievedValue = cacheManager.getDisk<Map<String, dynamic>>(testKey);
        expect(retrievedValue, equals(testValue));
      });

      test('should provide cache statistics', () {
        final stats = cacheManager.getCacheStatistics();
        expect(stats['memoryCache'], isNotNull);
        expect(stats['diskCache'], isNotNull);
        expect(stats['gpuCache'], isNotNull);
        expect(stats['totalEvents'], isA<int>());
      });

      test('should handle memory pressure', () async {
        // Fill cache to trigger memory pressure
        for (int i = 0; i < 100; i++) {
          await cacheManager.putMemory('pressure_test_$i', 'value_$i' * 1000);
        }
        
        final stats = cacheManager.getCacheStatistics();
        expect(stats['isUnderMemoryPressure'], isTrue);
      });
    });

    group('Platform-Specific Tests', () {
      test('Ubuntu 24.04 optimizations', () {
        if (Platform.isLinux) {
          final optimizer = CrossPlatformOptimizer.instance;
          if (optimizer.platformType == PlatformType.ubuntu2404) {
            final settings = optimizer.getOptimizationSettings();
            expect(settings['preferOpenGL'], isTrue);
            expect(settings['enableSystemIntegration'], isTrue);
          }
        }
      });

      test('Android optimizations', () {
        if (Platform.isAndroid) {
          final optimizer = CrossPlatformOptimizer.instance;
          final settings = optimizer.getOptimizationSettings();
          expect(settings['enableHapticFeedback'], isTrue);
          expect(settings['preferMobileLayout'], isTrue);
        }
      });

      test('Quest 2 VR optimizations', () {
        final optimizer = CrossPlatformOptimizer.instance;
        if (optimizer.platformType == PlatformType.quest2) {
          final settings = optimizer.getOptimizationSettings();
          expect(settings['enableVRMode'], isTrue);
          expect(settings['targetFPS'], equals(72));
          expect(settings['enableHandTracking'], isTrue);
        }
      });

      test('Windows 11 optimizations', () {
        if (Platform.isWindows) {
          final optimizer = CrossPlatformOptimizer.instance;
          if (optimizer.platformType == PlatformType.windows11) {
            final settings = optimizer.getOptimizationSettings();
            expect(settings['preferDirectX'], isTrue);
            expect(settings['enableWindowsIntegration'], isTrue);
          }
        }
      });
    });

    group('Integration Tests', () {
      test('should handle error recovery with performance optimization', () async {
        // Simulate error
        await errorHandler.handleError(
          Exception('Integration test error'),
          StackTrace.current,
          context: 'Integration Test',
          severity: ErrorSeverity.error,
        );
        
        // Trigger performance optimization
        await performanceOptimizer.optimizePerformance();
        
        // Verify both systems are still functional
        expect(errorHandler.isInitialized, isTrue);
        expect(performanceOptimizer.isInitialized, isTrue);
      });

      test('should coordinate cache and performance systems', () async {
        // Put items in cache
        await cacheManager.putMemory('integration_test', 'test_value');
        
        // Monitor performance
        performanceOptimizer.recordFrame(16.7);
        
        // Verify cache statistics are updated
        final cacheStats = cacheManager.getCacheStatistics();
        expect(cacheStats['memoryCache']['size'], greaterThan(0));
        
        // Verify performance metrics are recorded
        final perfStats = performanceOptimizer.getCurrentMetrics();
        expect(perfStats.fps, greaterThan(0));
      });

      test('should maintain security during optimization', () async {
        // Apply optimizations
        await performanceOptimizer.optimizePerformance();
        platformOptimizer.applyOptimization('security.level', 'high');
        
        // Test command security still works
        final result = commandGuard.validateCommand('rm -rf /');
        expect(result.isAllowed, isFalse);
        
        // Verify security settings are preserved
        final settings = platformOptimizer.getOptimizationSettings();
        expect(settings['security.level'], equals('high'));
      });
    });

    group('Performance Benchmarks', () {
      test('memory cache performance', () async {
        final stopwatch = Stopwatch()..start();
        
        // Perform 1000 cache operations
        for (int i = 0; i < 1000; i++) {
          await cacheManager.putMemory('bench_$i', 'value_$i');
          cacheManager.getMemory<String>('bench_$i');
        }
        
        stopwatch.stop();
        final operationsPerSecond = 1000 / (stopwatch.elapsedMilliseconds / 1000);
        
        // Should handle at least 1000 operations per second
        expect(operationsPerSecond, greaterThan(1000));
      });

      test('command validation performance', () {
        final stopwatch = Stopwatch()..start();
        
        // Validate 1000 commands
        for (int i = 0; i < 1000; i++) {
          commandGuard.validateCommand('echo "test $i"');
        }
        
        stopwatch.stop();
        final validationsPerSecond = 1000 / (stopwatch.elapsedMilliseconds / 1000);
        
        // Should handle at least 5000 validations per second
        expect(validationsPerSecond, greaterThan(5000));
      });

      test('error handling performance', () async {
        final stopwatch = Stopwatch()..start();
        
        // Handle 1000 errors
        for (int i = 0; i < 1000; i++) {
          await errorHandler.handleError(
            Exception('Test error $i'),
            StackTrace.current,
            context: 'Performance Test',
            severity: ErrorSeverity.warning,
          );
        }
        
        stopwatch.stop();
        final errorsPerSecond = 1000 / (stopwatch.elapsedMilliseconds / 1000);
        
        // Should handle at least 1000 errors per second
        expect(errorsPerSecond, greaterThan(1000));
      });
    });

    group('Stress Tests', () {
      test('high memory usage stress test', () async {
        // Fill memory cache
        for (int i = 0; i < 10000; i++) {
          await cacheManager.putMemory('stress_$i', 'x' * 10000);
        }
        
        final stats = cacheManager.getCacheStatistics();
        expect(stats['isUnderMemoryPressure'], isTrue);
        
        // Verify cache is still functional
        final value = cacheManager.getMemory<String>('stress_0');
        expect(value, isNotNull);
      });

      test('rapid command validation stress test', () {
        // Rapid command validation
        for (int i = 0; i < 10000; i++) {
          commandGuard.validateCommand('echo "rapid test $i"');
        }
        
        final auditLog = commandGuard.getAuditLog();
        expect(auditLog.length, equals(10000));
        
        // Verify system is still responsive
        final result = commandGuard.validateCommand('echo "final test"');
        expect(result.isAllowed, isTrue);
      });

      test('concurrent operations stress test', () async {
        // Perform multiple operations concurrently
        final futures = <Future>[];
        
        for (int i = 0; i < 100; i++) {
          futures.add(cacheManager.putMemory('concurrent_$i', 'value_$i'));
          futures.add(performanceOptimizer.recordFrame(16.7));
          futures.add(commandGuard.validateCommand('echo "concurrent $i"'));
        }
        
        await Future.wait(futures);
        
        // Verify all operations completed
        final cacheStats = cacheManager.getCacheStatistics();
        expect(cacheStats['memoryCache']['size'], equals(100));
        
        final auditLog = commandGuard.getAuditLog();
        expect(auditLog.length, equals(100));
      });
    });

    group('Edge Cases', () {
      test('handle null and empty values gracefully', () async {
        // Test cache with null values
        final result1 = await cacheManager.putMemory('null_test', '');
        expect(result1, isTrue);
        
        // Test command validation with empty string
        final result2 = commandGuard.validateCommand('');
        expect(result2.isAllowed, isTrue); // Empty command should be allowed
        
        // Test error handling with null error
        await errorHandler.handleError(
          Exception('Null test'),
          null,
          context: 'Edge Case Test',
          severity: ErrorSeverity.warning,
        );
        
        final stats = errorHandler.getErrorStats();
        expect(stats['totalErrors'], greaterThan(0));
      });

      test('handle extreme values gracefully', () async {
        // Test with very large cache values
        final largeValue = 'x' * 1000000; // 1MB string
        final result1 = await cacheManager.putMemory('large_test', largeValue);
        expect(result1, isTrue);
        
        // Test with very long command
        final longCommand = 'echo "' + 'x' * 10000 + '"';
        final result2 = commandGuard.validateCommand(longCommand);
        expect(result2.sanitizedCommand, isNotNull);
        expect(result2.sanitizedCommand!.length, lessThanOrEqualTo(longCommand.length));
      });

      test('handle resource exhaustion gracefully', () async {
        // Exhaust cache memory
        for (int i = 0; i < 100000; i++) {
          await cacheManager.putMemory('exhaust_$i', 'x' * 10000);
        }
        
        // System should still be functional
        final stats = cacheManager.getCacheStatistics();
        expect(stats['isUnderMemoryPressure'], isTrue);
        
        // Should still be able to cache new items (with eviction)
        final result = await cacheManager.putMemory('final_test', 'final_value');
        expect(result, isTrue);
      });
    });
  });
}
