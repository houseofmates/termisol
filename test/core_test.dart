import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/prompt_config.dart';
import 'package:termisol/core/service_registry.dart';
import 'package:termisol/core/headerbar_actions.dart';

void main() {
  group('PromptConfig', () {
    test('bashPs1 contains escape sequences', () {
      final ps1 = PromptConfig.bashPs1;
      expect(ps1.contains(r'\['), isTrue);
      expect(ps1.contains(r'\u'), isTrue);
      expect(ps1.contains(r'\w'), isTrue);
    });

    test('portablePs1 formats correctly', () {
      final ps1 = PromptConfig.portablePs1(
        user: 'alice',
        host: 'box',
        pwd: '/home',
      );
      expect(ps1.contains('alice@box'), isTrue);
      expect(ps1.contains('/home'), isTrue);
    });
  });

  group('ServiceRegistry', () {
    test('is a singleton', () {
      final a = ServiceRegistry.instance;
      final b = ServiceRegistry.instance;
      expect(identical(a, b), isTrue);
    });

    test('can register and retrieve services', () {
      final registry = ServiceRegistry.instance;
      registry.register('test_service', () => 'hello');
      expect(registry.get<String>('test_service'), equals('hello'));
    });
  });

  group('HeaderbarActions', () {
    test('dispatch updates value', () {
      HeaderbarActions.dispatch('newTab');
      expect(HeaderbarActions.action.value, equals('newTab'));
    });
  });
}
