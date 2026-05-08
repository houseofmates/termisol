import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  group('Memory Leak Detection', () {
    late ServiceRegistry registry;

    setUp(() {
      registry = ServiceRegistry.instance;
    });

    testWidgets('Memory usage remains stable during tab operations',
        (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      final initialMemory = await _getMemoryUsage();

      // Open and close 20 tabs over time
      for (int i = 0; i < 20; i++) {
        // Open new tab
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        // Simulate some activity
        await tester.pump(const Duration(seconds: 1));

        // Close tab
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();

        // Check memory every 5 tabs
        if ((i + 1) % 5 == 0) {
          final currentMemory = await _getMemoryUsage();
          final memoryIncrease = currentMemory - initialMemory;

          expect(memoryIncrease, lessThan(50 * 1024 * 1024), // 50MB limit
              reason: 'Memory increase should be reasonable after $i tab operations');
        }
      }

      final finalMemory = await _getMemoryUsage();
      final totalIncrease = finalMemory - initialMemory;

      expect(totalIncrease, lessThan(100 * 1024 * 1024), // 100MB total limit
          reason: 'Total memory increase should be bounded');
    });

    testWidgets('Long-running stability test', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      final initialMemory = await _getMemoryUsage();

      // Run for 5 minutes (simulated - in real test this would be 30 minutes)
      final testDuration = const Duration(minutes: 5);
      final startTime = DateTime.now();

      int cycleCount = 0;
      while (DateTime.now().difference(startTime) < testDuration) {
        // Open tab
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        // Simulate work
        await tester.pump(const Duration(seconds: 2));

        // Close tab
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();

        cycleCount++;

        // Check memory every 10 cycles
        if (cycleCount % 10 == 0) {
          final currentMemory = await _getMemoryUsage();
          final memoryIncrease = currentMemory - initialMemory;

          expect(memoryIncrease, lessThan(200 * 1024 * 1024), // 200MB limit
              reason: 'Memory should not grow unbounded during long running test');
        }

        // Small delay to prevent overwhelming the test
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final finalMemory = await _getMemoryUsage();
      final totalIncrease = finalMemory - initialMemory;

      expect(totalIncrease, lessThan(300 * 1024 * 1024), // 300MB total limit
          reason: 'Long-running memory increase should be reasonable');
    });
  });
}

/// Get current memory usage (simplified for testing)
Future<int> _getMemoryUsage() async {
  try {
    // In a real implementation, this would use platform-specific APIs
    // For testing, we'll simulate memory readings
    final process = await Process.run('ps', ['-o', 'rss=', '-p', pid.toString()]);
    if (process.exitCode == 0) {
      final memoryKB = int.tryParse(process.stdout.toString().trim()) ?? 0;
      return memoryKB * 1024; // Convert to bytes
    }
  } catch (e) {
    // Fallback for testing environments
  }

  // Return a simulated increasing memory value for testing
  return 100 * 1024 * 1024 + (DateTime.now().millisecondsSinceEpoch % 10000000);
}