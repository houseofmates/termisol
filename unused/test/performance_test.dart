import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';
import '../lib/core/editor_validator.dart';

/// Performance Test Suite for Multi-Cursor Editor
/// 
/// Tests performance characteristics and optimization for large files
/// and complex multi-cursor operations to ensure production readiness.
void main() {
  group('Multi-Cursor Performance Tests', () {
    
    testWidgets('should handle large file with multi-cursor efficiently', (WidgetTester tester) async {
      // Generate large test content (1MB)
      final largeContent = _generateLargeContent(1024 * 1024);
      
      final editor = EditTerminal(
        filePath: '/test/large.dart',
        initialContent: largeContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      final stopwatch = Stopwatch()..start();
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 10; i++) {
        await tester.tapAt(Offset(100 + i * 50, 100 + i * 20));
        await tester.pumpAndSettle(Duration(milliseconds: 10));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      stopwatch.stop();
      
      // Should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(9)); // 9 additional + 1 main = 10 total
      
      // Test typing performance
      final typingStopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.pumpAndSettle(Duration(milliseconds: 50));
      }
      
      typingStopwatch.stop();
      
      // Typing should complete within reasonable time even with large file
      expect(typingStopwatch.elapsedMilliseconds, lessThan(3000));
    });
    
    testWidgets('should maintain performance with many cursors', (WidgetTester tester) async {
      final content = _generateMediumContent(100 * 1024); // 100KB
      
      final editor = EditTerminal(
        filePath: '/test/medium.dart',
        initialContent: content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      final stopwatch = Stopwatch()..start();
      
      // Add many cursors (approaching limit)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 50; i++) {
        await tester.tapAt(Offset(50 + i * 10, 50 + i * 5));
        await tester.pumpAndSettle(Duration(milliseconds: 5));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      stopwatch.stop();
      
      // Should handle many cursors efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(editor._cursors.length, equals(49)); // 49 additional + 1 main = 50 total
      
      // Test deletion performance
      final deletionStopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 3; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle(Duration(milliseconds: 50));
      }
      
      deletionStopwatch.stop();
      
      expect(deletionStopwatch.elapsedMilliseconds, lessThan(2000));
    });
    
    testWidgets('should handle rapid cursor operations', (WidgetTester tester) async {
      final content = _generateMediumContent(50 * 1024); // 50KB
      
      final editor = EditTerminal(
        filePath: '/test/rapid.dart',
        initialContent: content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      final stopwatch = Stopwatch()..start();
      
      // Rapid cursor addition and removal
      for (int cycle = 0; cycle < 5; cycle++) {
        // Add cursors rapidly
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        for (int i = 0; i < 10; i++) {
          await tester.tapAt(Offset(100 + i * 20, 100 + i * 10));
          await tester.pumpAndSettle(Duration(milliseconds: 2));
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        
        // Clear cursors
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        
        expect(editor._multiCursorMode, isFalse);
      }
      
      stopwatch.stop();
      
      // Should handle rapid operations efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
    
    testWidgets('should handle memory usage with large operations', (WidgetTester tester) async {
      final content = _generateLargeContent(512 * 1024); // 512KB
      
      final editor = EditTerminal(
        filePath: '/test/memory.dart',
        initialContent: content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 20; i++) {
        await tester.tapAt(Offset(50 + i * 15, 50 + i * 8));
        await tester.pumpAndSettle(Duration(milliseconds: 10));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Perform many text operations
      for (int operation = 0; operation < 50; operation++) {
        if (operation % 2 == 0) {
          // Type
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
        } else {
          // Delete
          await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
        }
        await tester.pumpAndSettle(Duration(milliseconds: 20));
      }
      
      // Should not crash and maintain reasonable performance
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, greaterThan(0));
    });
    
    testWidgets('should enforce performance limits', (WidgetTester tester) async {
      final content = _generateMediumContent(100 * 1024);
      
      final editor = EditTerminal(
        filePath: '/test/limits.dart',
        initialContent: content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Try to add too many cursors (should be limited)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 150; i++) { // Exceed the 100 cursor limit
        await tester.tapAt(Offset(50 + i * 5, 50 + i * 3));
        await tester.pumpAndSettle(Duration(milliseconds: 2));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Should be limited to maximum cursor count
      expect(editor._cursors.length, lessThanOrEqualTo(99)); // 99 additional + 1 main = 100 total max
    });
  });
  
  group('Validator Performance Tests', () {
    
    test('should validate large content efficiently', () {
      final largeContent = _generateLargeContent(2 * 1024 * 1024); // 2MB
      
      final stopwatch = Stopwatch()..start();
      
      final result = EditorValidator.validateFileContent('/test/large.txt', largeContent);
      
      stopwatch.stop();
      
      // Should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(result.isValid, isTrue); // Should be valid for generated content
    });
    
    test('should handle many validation operations', () {
      final contents = List.generate(100, (index) => _generateMediumContent(10 * 1024));
      
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < contents.length; i++) {
        final result = EditorValidator.validateFileContent('/test/file_$i.txt', contents[i]);
        expect(result.isValid, isTrue);
      }
      
      stopwatch.stop();
      
      // Should handle many validations efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
    
    test('should validate multi-cursor setup efficiently', () {
      final textLength = 100000; // 100KB
      final cursorOffsets = List.generate(50, (index) => index * 2000);
      
      final stopwatch = Stopwatch()..start();
      
      final result = EditorValidator.validateMultiCursorSetup(cursorOffsets, textLength);
      
      stopwatch.stop();
      
      // Should complete quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
      expect(result.isValid, isTrue);
    });
    
    test('should measure operation performance', () {
      final operations = List.generate(1000, (index) => 'operation_$index');
      
      final result = EditorPerformanceMonitor.measureOperation('batch_operations', () {
        for (final operation in operations) {
          final validation = EditorValidator.validateInput(operation);
          expect(validation.isValid, isTrue);
        }
      });
      
      // Should complete operations and measure performance
      expect(result, isNotNull);
    });
  });
  
  group('Stress Tests', () {
    
    testWidgets('should handle extreme load', (WidgetTester tester) async {
      final content = _generateLargeContent(1024 * 1024); // 1MB
      
      final editor = EditTerminal(
        filePath: '/test/extreme.dart',
        initialContent: content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Extreme cursor operations
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      
      // Add maximum cursors
      for (int i = 0; i < 100; i++) {
        await tester.tapAt(Offset(10 + i * 8, 10 + i * 5));
        await tester.pumpAndSettle(Duration(milliseconds: 1));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Rapid typing and deletion
      for (int cycle = 0; cycle < 20; cycle++) {
        // Type multiple characters
        for (int i = 0; i < 5; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
          await tester.pumpAndSettle(Duration(milliseconds: 5));
        }
        
        // Delete multiple characters
        for (int i = 0; i < 5; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
          await tester.pumpAndSettle(Duration(milliseconds: 5));
        }
      }
      
      // Should survive extreme load
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, greaterThan(0));
    });
    
    testWidgets('should handle memory pressure', (WidgetTester tester) async {
      // Create multiple editors to simulate memory pressure
      final editors = <EditTerminal>[];
      
      for (int i = 0; i < 5; i++) {
        final content = _generateMediumContent(200 * 1024); // 200KB each
        final editor = EditTerminal(
          filePath: '/test/memory_$i.dart',
          initialContent: content,
          readOnly: false,
        );
        editors.add(editor);
      }
      
      // Test all editors
      for (int editorIndex = 0; editorIndex < editors.length; editorIndex++) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: editors[editorIndex])));
        await tester.pumpAndSettle();
        
        // Add cursors and perform operations
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        for (int i = 0; i < 10; i++) {
          await tester.tapAt(Offset(50 + i * 20, 50 + i * 10));
          await tester.pumpAndSettle(Duration(milliseconds: 10));
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        
        // Type at all cursors
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
        await tester.pumpAndSettle();
        
        // Clear cursors
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        
        expect(editors[editorIndex]._multiCursorMode, isFalse);
      }
    });
  });
}

// Helper functions for generating test content
String _generateLargeContent(int sizeInBytes) {
  final buffer = StringBuffer();
  final line = '// Large test file line with some content ${'x' * 80}\n';
  
  while (buffer.length < sizeInBytes) {
    buffer.write(line);
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}

String _generateMediumContent(int sizeInBytes) {
  final buffer = StringBuffer();
  final lines = [
    'function testFunction$index() {',
    '  const variable = "test";',
    '  let result = variable + " processed";',
    '  return result;',
    '}',
    '',
    'class TestClass$index {',
    '  constructor(name) {',
    '    this.name = name;',
    '    this.data = [];',
    '  }',
    '  ',
    '  method() {',
    '    return this.name.toUpperCase();',
    '  }',
    '}',
    '',
    'const testString$index = "This is test string number $index";',
    'const anotherString$index = "Another test string for testing purposes";',
    '',
  ];
  
  int lineIndex = 0;
  while (buffer.length < sizeInBytes) {
    final line = lines[lineIndex % lines.length].replaceAll('\$index', '${buffer.length ~/ 1000}');
    buffer.write(line);
    lineIndex++;
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}

String _generateComplexContent(int sizeInBytes) {
  final buffer = StringBuffer();
  
  // Include various character types
  final complexChars = [
    'Hello World 🌍', // Emoji
    '你好世界', // Chinese
    'مرحبا بالعالم', // Arabic
    'Привет мир', // Cyrillic
    'Γειά σου κόσμε', // Greek
    'こんにちは世界', // Japanese
    '안녕하세요 세계', // Korean
    '🚀🎉💻📱', // More emojis
    'Special chars: !@#$%^&*()_+-=[]{}|;:,.<>?',
    'Tabs\t\tand\nnewlines\n\nand\r\rcarriage returns',
  ];
  
  while (buffer.length < sizeInBytes) {
    final line = complexChars[buffer.length % complexChars.length];
    buffer.write('$line\n');
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}
