import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';
import 'package:termisol/core/termisol_features.dart';

void main() {
  group('Graceful Degradation Tests', () {
    late ServiceRegistry registry;

    setUp(() {
      registry = ServiceRegistry.instance;
    });

    testWidgets('Terminal works when AI is disabled', (WidgetTester tester) async {
      // Disable AI feature
      registry.setFeature(TermisolFeatures.aiAssistant, false);

      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify app still loads
      expect(find.text('termisol'), findsOneWidget);

      // Verify terminal core functionality works
      expect(find.byIcon(Icons.add), findsWidgets);

      // Try to create a tab
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Verify tab was created
      expect(find.text('Terminal 2'), findsOneWidget);
    });

    testWidgets('Terminal works when GPU renderer is disabled', (WidgetTester tester) async {
      // Disable GPU rendering
      registry.setFeature(TermisolFeatures.gpuRenderer, false);

      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify app still loads and functions
      expect(find.text('termisol'), findsOneWidget);

      // Verify basic UI elements work
      expect(find.byIcon(Icons.settings), findsOneWidget);

      // Test settings access
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify settings sheet appears
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('Terminal works when VR support is disabled', (WidgetTester tester) async {
      // Disable VR features
      registry.setFeature(TermisolFeatures.vrSupport, false);

      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify app loads normally
      expect(find.text('termisol'), findsOneWidget);

      // Verify tab management still works
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Terminal 2'), findsOneWidget);

      // Test tab switching
      await tester.tap(find.text('Terminal 2'));
      await tester.pumpAndSettle();

      // Verify tab is active (should have different styling)
      expect(find.text('Terminal 2'), findsOneWidget);
    });

    testWidgets('Terminal works when multiple features are disabled', (WidgetTester tester) async {
      // Disable multiple features
      registry.setFeature(TermisolFeatures.aiAssistant, false);
      registry.setFeature(TermisolFeatures.gpuRenderer, false);
      registry.setFeature(TermisolFeatures.vrSupport, false);
      registry.setFeature(TermisolFeatures.videoPlayback, false);
      registry.setFeature(TermisolFeatures.audioVisualization, false);

      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify core functionality still works
      expect(find.text('termisol'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);

      // Test tab operations
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Terminal 2'), findsOneWidget);

      // Test settings access
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // Check diagnostics still work
      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('Service health report shows disabled features correctly', (WidgetTester tester) async {
      // Disable some features
      registry.setFeature(TermisolFeatures.aiAssistant, false);
      registry.setFeature(TermisolFeatures.gpuRenderer, false);

      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Open settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Check that diagnostics section exists
      expect(find.text('Service Health Report'), findsOneWidget);

      // The health report should show disabled services
      final healthReport = registry.healthReport();

      expect(healthReport[TermisolFeatures.aiAssistant]?['enabled'], false);
      expect(healthReport[TermisolFeatures.gpuRenderer]?['enabled'], false);
      expect(healthReport[TermisolFeatures.terminalCore]?['enabled'], true);
    });
  });
}