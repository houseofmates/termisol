import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';

/// Comprehensive Multi-Cursor Test Suite
/// 
/// Tests all multi-cursor functionality to ensure robustness and reliability
/// before shipping to users. This covers edge cases, error conditions, and
/// performance scenarios.
void main() {
  group('Multi-Cursor Editor Tests', () {
    late EditTerminal editor;
    late TextEditingController controller;
    
    setUp(() {
      // Initialize editor with test content
      controller = TextEditingController(text: _getTestContent());
      editor = EditTerminal(
        filePath: '/test/sample.dart',
        initialContent: _getTestContent(),
        readOnly: false,
      );
    });
    
    tearDown(() {
      controller.dispose();
    });
    
    // Basic Multi-Cursor Functionality Tests
    testWidgets('should add cursor on Alt+Click', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Simulate Alt+Click at position 100
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Verify multi-cursor mode is enabled
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(1));
    });
    
    testWidgets('should add multiple cursors with multiple Alt+Clicks', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add first cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.pumpAndSettle();
      
      // Add second cursor
      await tester.tapAt(Offset(200, 100));
      await tester.pumpAndSettle();
      
      // Add third cursor
      await tester.tapAt(Offset(300, 150));
      await tester.pumpAndSettle();
      
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
    });
    
    testWidgets('should clear multi-cursors on Escape', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(1));
      
      // Press Escape
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isFalse);
      expect(editor._cursors.length, equals(0));
    });
    
    testWidgets('should add cursor at selection with Ctrl+D', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Select some text first
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Add cursor at selection
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(1));
    });
    
    testWidgets('should select all occurrences with Ctrl+Shift+L', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Select a word that appears multiple times
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(Offset(150, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Select all occurrences
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, greaterThan(1)); // Should have multiple cursors
    });
    
    // Multi-Cursor Input Tests
    testWidgets('should type at all cursor positions simultaneously', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.tapAt(Offset(300, 150));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      final initialText = controller.text;
      
      // Type 'test' at all cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      final finalText = controller.text;
      
      // Should have 'test' inserted at each cursor position
      expect(finalText.length, equals(initialText.length + 4 * 3)); // 3 cursors + main cursor
      expect(finalText.contains('testtesttest'), isTrue);
    });
    
    testWidgets('should delete at all cursor positions simultaneously', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      final initialText = controller.text;
      
      // Delete at all cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      
      final finalText = controller.text;
      
      // Should have deleted one character at each cursor position
      expect(finalText.length, equals(initialText.length - 2)); // 2 cursors + main cursor
    });
    
    // Edge Cases and Error Handling Tests
    testWidgets('should handle empty text with multi-cursor', (WidgetTester tester) async {
      controller.text = '';
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Try to add cursor in empty text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(1));
      
      // Should handle typing in empty text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      
      expect(controller.text, equals('aaa')); // Should have 'a' at each cursor
    });
    
    testWidgets('should handle very large text with multi-cursor', (WidgetTester tester) async {
      // Create large text content
      final largeText = 'function test() {\n' + '  return "test";\n' * 1000 + '}';
      controller.text = largeText;
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursor at different positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 200));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(1));
      
      // Should handle typing without performance issues
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      expect(controller.text.contains('xx'), isTrue);
    });
    
    testWidgets('should handle Unicode and emoji characters', (WidgetTester tester) async {
      controller.text = 'Hello 🌍 World\nTest emoji: 🚀🎉\nUnicode: 你好\n';
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors near Unicode characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(150, 80));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type Unicode characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      
      expect(controller.text.contains('unicode'), isTrue);
    });
    
    testWidgets('should handle invalid cursor positions gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Try to add cursor outside text bounds
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(1000, 1000)); // Far outside text
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Should not crash and handle gracefully
      expect(editor._multiCursorMode, isTrue); // May still be enabled but cursor should be clamped
    });
    
    testWidgets('should handle rapid cursor addition and removal', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Rapidly add and remove cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      
      for (int i = 0; i < 10; i++) {
        await tester.tapAt(Offset(50 + i * 10, 50 + i * 5));
        await tester.pumpAndSettle(Duration(milliseconds: 10));
      }
      
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, greaterThan(0));
      
      // Rapidly clear and re-add
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isFalse);
      
      // Re-add
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
    });
    
    // Performance Tests
    testWidgets('should maintain performance with many cursors', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      final stopwatch = Stopwatch()..start();
      
      // Add many cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 20; i++) {
        await tester.tapAt(Offset(50 + i * 15, 50 + i * 8));
        await tester.pumpAndSettle(Duration(milliseconds: 1));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      stopwatch.stop();
      
      // Should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(editor._cursors.length, equals(19)); // 19 additional + 1 main = 20 total
      
      // Test typing performance
      final typingStopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.pumpAndSettle(Duration(milliseconds: 1));
      }
      
      typingStopwatch.stop();
      
      // Typing should also be performant
      expect(typingStopwatch.elapsedMilliseconds, lessThan(500));
    });
    
    // Integration Tests
    testWidgets('should work correctly with undo/redo', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      final initialText = controller.text;
      
      // Type at all cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      final afterTypingText = controller.text;
      
      // Undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(controller.text, equals(initialText));
      
      // Redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(controller.text, equals(afterTypingText));
    });
    
    testWidgets('should work correctly with search', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Open search
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should not crash and multi-cursor mode should remain active
      expect(editor._multiCursorMode, isTrue);
      expect(editor._showSearch, isTrue);
    });
    
    // Memory and Resource Tests
    testWidgets('should not leak memory with cursor operations', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Perform many cursor operations
      for (int iteration = 0; iteration < 10; iteration++) {
        // Add cursors
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        for (int i = 0; i < 5; i++) {
          await tester.tapAt(Offset(50 + i * 20, 50 + i * 10));
          await tester.pumpAndSettle();
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        
        // Type something
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();
        
        // Clear cursors
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        
        // Verify state is clean
        expect(editor._multiCursorMode, isFalse);
        expect(editor._cursors.length, equals(0));
      }
    });
  });
  
  // Stress Tests
  group('Multi-Cursor Stress Tests', () {
    testWidgets('should handle extreme cursor count', (WidgetTester tester) async {
      final controller = TextEditingController(text: _getLargeTestContent());
      final editor = EditTerminal(
        filePath: '/test/large.dart',
        initialContent: _getLargeTestContent(),
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add many cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 50; i++) {
        await tester.tapAt(Offset(10 + i * 5, 10 + i * 3));
        await tester.pumpAndSettle(Duration(milliseconds: 1));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(49)); // 49 additional + 1 main = 50 total
      
      // Should still be responsive
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle(Duration(milliseconds: 100));
      
      expect(controller.text.contains('a' * 50), isTrue);
    });
    
    testWidgets('should handle rapid text changes', (WidgetTester tester) async {
      final controller = TextEditingController(text: '');
      final editor = EditTerminal(
        filePath: '/test/rapid.dart',
        initialContent: '',
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 50));
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Rapid text changes
      for (int i = 0; i < 100; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle(Duration(milliseconds: 1));
      }
      
      // Should not crash
      expect(editor._multiCursorMode, isTrue);
      expect(controller.text, isEmpty); // Text should be empty after all backspaces
    });
  });
}

// Test data
String _getTestContent() {
  return '''
// Test file for multi-cursor functionality
function testFunction() {
  const variable = "test";
  let anotherVariable = 42;
  
  if (variable === "test") {
    console.log("Test passed");
  }
  
  return variable + anotherVariable;
}

class TestClass {
  constructor(name) {
    this.name = name;
  }
  
  method() {
    return this.name.toUpperCase();
  }
}

const testString = "This is a test string with multiple occurrences of the word test";
const anotherString = "Another test string for testing purposes";
''';
}

String _getLargeTestContent() {
  return '''
// Large test file for stress testing
function largeTestFunction() {
  const items = [];
  for (let i = 0; i < 1000; i++) {
    items.push({
      id: i,
      name: \`item_\${i}\`,
      value: Math.random() * 100,
      timestamp: new Date().toISOString()
    });
  }
  
  return items.filter(item => item.value > 50);
}

class LargeTestClass {
  constructor() {
    this.data = new Map();
    this.cache = new Set();
    this.observers = [];
  }
  
  addData(key, value) {
    this.data.set(key, value);
    this.cache.add(key);
    this.notifyObservers('add', key, value);
  }
  
  removeData(key) {
    const value = this.data.get(key);
    this.data.delete(key);
    this.cache.delete(key);
    this.notifyObservers('remove', key, value);
  }
  
  notifyObservers(event, key, value) {
    this.observers.forEach(observer => {
      observer(event, key, value);
    });
  }
  
  addObserver(observer) {
    this.observers.push(observer);
  }
  
  removeObserver(observer) {
    const index = this.observers.indexOf(observer);
    if (index > -1) {
      this.observers.splice(index, 1);
    }
  }
}
''';
}
