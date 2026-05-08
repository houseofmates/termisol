import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    final registry = ServiceRegistry.instance;
    final app = TermisolApp(registry: registry);

    await tester.pumpWidget(app);
    expect(app, isNotNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
