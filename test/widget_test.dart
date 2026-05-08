import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  testWidgets('App widget can be instantiated', (WidgetTester tester) async {
    // Create a basic service registry for testing
    final registry = ServiceRegistry.instance;

    final app = TermisolApp(registry: registry);

    // Test that the app can be built
    await tester.pumpWidget(app);

    expect(app, isNotNull);
    expect(find.text('termisol'), findsOneWidget);
  });
}
