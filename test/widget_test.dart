import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  testWidgets('App builds and renders', (WidgetTester tester) async {
    final registry = ServiceRegistry.instance;
    final app = TermisolApp(registry: registry);

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(app, isNotNull);
    // HomeScreen renders a scaffold with terminal tabs
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
