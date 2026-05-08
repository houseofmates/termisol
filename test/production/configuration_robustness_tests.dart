import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/terminal_session.dart';
import '../../lib/config/global_config.dart';
import '../../lib/config/production_config_system.dart';

/// Comprehensive configuration system robustness testing
/// Tests configuration loading, validation, corruption, and edge cases
void main() {
  group('Configuration Robustness Tests', () {
    late Directory testTempDir;
    late File configFile;
    
    setUp(() async {
      testTempDir = await Directory.systemTemp.createTemp('termisol_config_test_');
      configFile = File('${testTempDir.path}/config.json');
    });
    
    tearDown(() async {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    });

    test('handles missing configuration file', () async {
      // Test with non-existent config file
      final config = ProductionConfigSystem(configPath: '/non/existent/config.json');
      
      // Should handle gracefully with defaults
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), isNotNull);
      expect(config.get('ai.api_key'), isNull); // Should be null for missing sensitive config
      
      await config.dispose();
    });

    test('handles corrupted JSON configuration', () async {
      // Write corrupted JSON
      await configFile.writeAsString('{"invalid": json, "missing": quotes}');
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should handle corrupted JSON gracefully
      await config.initialize();
      
      // Should fall back to defaults
      expect(config.get('terminal.max_lines'), isNotNull);
      
      await config.dispose();
    });

    test('handles configuration file permission errors', () async {
      // Create config file
      await configFile.writeAsString('{"terminal": {"max_lines": 1000}}');
      
      // Make file unreadable (if possible)
      try {
        await configFile.setMode(0o000);
      } catch (e) {
        // Some systems don't support this, skip permission test
        return;
      }
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should handle permission errors gracefully
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), isNotNull);
      
      await config.dispose();
    });

    test('handles configuration with invalid data types', () async {
      final invalidConfig = {
        'terminal': {
          'max_lines': 'not_a_number', // Should be int
          'font_size': null, // Should be double
          'theme': 123, // Should be string
        },
        'ai': {
          'api_key': [], // Should be string
          'timeout': 'not_a_duration', // Should be Duration
        },
      };
      
      await configFile.writeAsString(jsonEncode(invalidConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Should handle invalid types gracefully
      expect(config.get('terminal.max_lines'), isA<int>());
      expect(config.get('terminal.font_size'), isA<double>());
      expect(config.get('terminal.theme'), isA<String>());
      
      await config.dispose();
    });

    test('handles configuration with circular references', () async {
      // Create config with circular reference (simulated)
      final circularConfig = {
        'terminal': {
          'max_lines': 1000,
          'parent': 'terminal', // Circular reference
        },
        'ai': {
          'model': 'gpt-4',
          'fallback': 'ai', // Circular reference
        },
      };
      
      await configFile.writeAsString(jsonEncode(circularConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should handle circular references without infinite loops
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), equals(1000));
      
      await config.dispose();
    });

    test('handles configuration with extremely large values', () async {
      final largeConfig = {
        'terminal': {
          'max_lines': 999999999, // Extremely large
          'font_size': 999999.999, // Large float
          'theme': 'x' * 10000, // Very long string
        },
        'history': {
          List.generate(10000, (i) => 'command_$i'): 'value', // Large map
        },
      };
      
      await configFile.writeAsString(jsonEncode(largeConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should handle large values without memory issues
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), isA<int>());
      expect(config.get('terminal.theme'), isA<String>());
      
      await config.dispose();
    });

    test('handles configuration hot-reloading', () async {
      // Create initial config
      final initialConfig = {'terminal': {'max_lines': 1000}};
      await configFile.writeAsString(jsonEncode(initialConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), equals(1000));
      
      // Update config file
      final updatedConfig = {'terminal': {'max_lines': 2000}};
      await configFile.writeAsString(jsonEncode(updatedConfig));
      
      // Trigger reload
      await config.reload();
      
      expect(config.get('terminal.max_lines'), equals(2000));
      
      await config.dispose();
    });

    test('handles configuration validation errors', () async {
      final invalidConfig = {
        'terminal': {
          'max_lines': -100, // Invalid negative value
          'font_size': 0, // Invalid zero value
        },
        'network': {
          'timeout': -1, // Invalid negative timeout
        },
      };
      
      await configFile.writeAsString(jsonEncode(invalidConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should validate and correct invalid values
      await config.initialize();
      
      expect(config.get('terminal.max_lines'), greaterThan(0));
      expect(config.get('terminal.font_size'), greaterThan(0));
      expect(config.get('network.timeout'), greaterThan(0));
      
      await config.dispose();
    });

    test('handles configuration with nested structures', () async {
      final nestedConfig = {
        'terminal': {
          'appearance': {
            'theme': {
              'colors': {
                'background': '#1e1e1e',
                'foreground': '#ffffff',
                'cursor': '#00ff00',
              },
              'fonts': {
                'family': 'Monospace',
                'size': 14,
                'weight': 'normal',
              },
            },
          },
          'behavior': {
            'scrolling': {
              'max_lines': 10000,
              'buffer_size': 5000,
            },
          },
        },
      };
      
      await configFile.writeAsString(jsonEncode(nestedConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Should handle deep nesting
      expect(config.get('terminal.appearance.theme.colors.background'), equals('#1e1e1e'));
      expect(config.get('terminal.behavior.scrolling.max_lines'), equals(10000));
      
      await config.dispose();
    });

    test('handles configuration environment variable override', () async {
      // Set environment variable
      final originalValue = Platform.environment['TERMISOL_MAX_LINES'];
      Platform.environment['TERMISOL_MAX_LINES'] = '5000';
      
      try {
        final config = ProductionConfigSystem();
        await config.initialize();
        
        // Should use environment variable override
        expect(config.get('terminal.max_lines'), equals(5000));
        
        await config.dispose();
      } finally {
        // Restore original value
        if (originalValue != null) {
          Platform.environment['TERMISOL_MAX_LINES'] = originalValue;
        } else {
          Platform.environment.remove('TERMISOL_MAX_LINES');
        }
      }
    });

    test('handles configuration with special characters', () async {
      final specialConfig = {
        'terminal': {
          'prompt': 'user@host:~\$ ', // Special chars
          'welcome': 'Welcome to Termisol™! ©2024', // Unicode
          'escape_sequences': '\x1b[31mRed\x1b[0m', // Escape sequences
        },
        'paths': {
          'home': '/home/user/with spaces/and/特殊字符',
          'temp': '/tmp/termisol-test',
        },
      };
      
      await configFile.writeAsString(jsonEncode(specialConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Should handle special characters correctly
      expect(config.get('terminal.prompt'), contains('user@host'));
      expect(config.get('terminal.welcome'), contains('™'));
      expect(config.get('paths.home'), contains('特殊字符'));
      
      await config.dispose();
    });

    test('handles configuration backup and recovery', () async {
      // Create valid config
      final validConfig = {'terminal': {'max_lines': 1000}};
      await configFile.writeAsString(jsonEncode(validConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Create backup
      await config.createBackup();
      
      // Corrupt original config
      await configFile.writeAsString('completely invalid json');
      
      // Should recover from backup
      await config.recoverFromBackup();
      
      expect(config.get('terminal.max_lines'), equals(1000));
      
      await config.dispose();
    });

    test('handles configuration schema migration', () async {
      // Create old version config
      final oldConfig = {
        'version': '1.0',
        'max_lines': 1000, // Old location
        'font_size': 12, // Old location
      };
      
      await configFile.writeAsString(jsonEncode(oldConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Should migrate to new schema
      expect(config.get('terminal.max_lines'), equals(1000));
      expect(config.get('terminal.font_size'), equals(12));
      expect(config.get('version'), equals('2.0')); // Updated version
      
      await config.dispose();
    });

    test('handles configuration concurrent access', () async {
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Simulate concurrent access
      final futures = <Future>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(Future(() async {
          config.set('test.concurrent.$i', 'value_$i');
          await Future.delayed(Duration(milliseconds: 10));
          final value = config.get('test.concurrent.$i');
          expect(value, equals('value_$i'));
        }));
      }
      
      await Future.wait(futures);
      
      await config.dispose();
    });

    test('handles configuration memory optimization', () async {
      // Create large config
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
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      
      // Should handle large config efficiently
      final startTime = DateTime.now();
      await config.initialize();
      final loadTime = DateTime.now().difference(startTime);
      
      expect(loadTime.inMilliseconds, lessThan(5000)); // Should load within 5 seconds
      
      await config.dispose();
    });

    test('handles configuration encryption for sensitive data', () async {
      final sensitiveConfig = {
        'ai': {
          'api_key': 'sk-1234567890abcdef', // Sensitive
          'webhook_url': 'https://api.example.com/webhook', // Sensitive
        },
        'ssh': {
          'private_key': '-----BEGIN RSA PRIVATE KEY-----\n...', // Sensitive
        },
        'terminal': {
          'max_lines': 1000, // Not sensitive
        },
      };
      
      await configFile.writeAsString(jsonEncode(sensitiveConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Sensitive data should be encrypted or masked
      expect(config.get('ai.api_key'), isNot(equals('sk-1234567890abcdef')));
      expect(config.get('ssh.private_key'), isNot(contains('BEGIN RSA PRIVATE KEY')));
      
      // Non-sensitive data should be accessible
      expect(config.get('terminal.max_lines'), equals(1000));
      
      await config.dispose();
    });

    test('handles configuration with array values', () async {
      final arrayConfig = {
        'terminal': {
          'themes': ['dark', 'light', 'solarized'],
          'font_families': ['Monaco', 'Consolas', 'Ubuntu Mono'],
        },
        'ai': {
          'models': [
            {'name': 'gpt-4', 'context': 8192},
            {'name': 'claude-3', 'context': 100000},
          ],
        },
      };
      
      await configFile.writeAsString(jsonEncode(arrayConfig));
      
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Should handle array values
      expect(config.get('terminal.themes'), isA<List>());
      expect(config.get('terminal.themes'), contains('dark'));
      expect(config.get('ai.models'), isA<List>());
      expect(config.get('ai.models.0.name'), equals('gpt-4'));
      
      await config.dispose();
    });

    test('handles configuration default value fallbacks', () async {
      final config = ProductionConfigSystem(configPath: configFile.path);
      await config.initialize();
      
      // Test various default value scenarios
      expect(config.get('nonexistent.key', 'default'), equals('default'));
      expect(config.get('nonexistent.number', 42), equals(42));
      expect(config.get('nonexistent.bool', true), equals(true));
      expect(config.get('nonexistent.list', []), equals([]));
      expect(config.get('nonexistent.map', {}), equals({}));
      
      await config.dispose();
    });
  });
}
