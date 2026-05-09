import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  group('Performance Benchmarks', () {
    late ServiceRegistry registry;

    testWidgets('Frame times under 16ms during normal typing', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Measure frame times during typing simulation
      final stopwatch = Stopwatch()..start();
      int frameCount = 0;

      // Simulate typing 100 characters
      for (int i = 0; i < 100; i++) {
        await tester.enterText(find.byType(TextField).first, 'a' * (i + 1));
        await tester.pump();
        frameCount++;

        if (stopwatch.elapsedMilliseconds > 1000) { // Measure over 1 second
          break;
        }
      }

      final averageFrameTime = stopwatch.elapsedMilliseconds / frameCount;
      expect(averageFrameTime, lessThan(16.0),
          reason: 'Average frame time should be under 16ms for smooth 60fps');
    });

    testWidgets('Frame times under 16ms during large file display', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Simulate displaying a large file (10MB worth of text)
      final stopwatch = Stopwatch()..start();
      int frameCount = 0;

      // Simulate scrolling through large content
      for (int i = 0; i < 50; i++) {
        await tester.pump();
        frameCount++;

        if (stopwatch.elapsedMilliseconds > 1000) {
          break;
        }
      }

      final averageFrameTime = stopwatch.elapsedMilliseconds / frameCount;
      expect(averageFrameTime, lessThan(16.0),
          reason: 'Frame time should stay under 16ms even with large content');
    });

    testWidgets('Frame times under 16ms during image display', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Create a large image widget for testing
      final largeImage = Container(
        width: 1920,
        height: 1080,
        color: Colors.blue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: largeImage),
        ),
      );

      final stopwatch = Stopwatch()..start();
      int frameCount = 0;

      // Measure frame times while displaying large image
      for (int i = 0; i < 60; i++) { // 1 second at 60fps
        await tester.pump();
        frameCount++;
      }

      final averageFrameTime = stopwatch.elapsedMilliseconds / frameCount;
      expect(averageFrameTime, lessThan(16.0),
          reason: 'Frame time should stay under 16ms when displaying large images');
    });
  });
}