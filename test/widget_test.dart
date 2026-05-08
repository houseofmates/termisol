import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  test('ServiceRegistry is available', () {
    final registry = ServiceRegistry.instance;
    expect(registry, isNotNull);
  });
}
