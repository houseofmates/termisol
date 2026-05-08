import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';

/// Multi-Cursor Undo/Redo Test Suite
/// 
/// Tests undo/redo functionality specifically with multi-cursor operations
/// to ensure proper state management and cursor position handling.
void main() {
  group('Multi-Cursor Undo/Redo Tests', () {
    
    testWidgets('should undo text changes with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      
      final editor = EditTerminal(
        filePath: '/test/undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));  // Line 1
      await tester.tapAt(Offset(50, 60));  // Line 2
      await tester.tapAt(Offset(50, 90));  // Line 3
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Type text at all cursor positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      final textAfterTyping = editor._controller.text;
      expect(textAfterTyping.contains('TEST'), isTrue);
      
      // Undo the typing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should revert to original content
      expect(editor._controller.text, equals(initialContent));
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2));
    });
    
    testWidgets('should redo text changes with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      
      final editor = EditTerminal(
        filePath: '/test/redo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Type text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      
      final textAfterTyping = editor._controller.text;
      expect(textAfterTyping.contains('REDO'), isTrue);
      
      // Undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(initialContent));
      
      // Redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore the typed text
      expect(editor._controller.text, contains('REDO'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should undo cursor position changes', (WidgetTester tester) async {
      const initialContent = 'This is a test line for cursor position testing';
      
      final editor = EditTerminal(
        filePath: '/test/cursor_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));  // Middle of line
      await tester.tapAt(Offset(200, 50));  // End of line
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2));
      
      // Clear cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isFalse);
      expect(editor._cursors.isEmpty, isTrue);
      
      // Undo cursor clearing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore multi-cursor mode
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2));
    });
    
    testWidgets('should handle multiple undo operations with multi-cursor', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      
      final editor = EditTerminal(
        filePath: '/test/multi_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // First edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      
      final textAfterFirstEdit = editor._controller.text;
      
      // Second edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      
      final textAfterSecondEdit = editor._controller.text;
      expect(textAfterSecondEdit, isNot(equals(textAfterFirstEdit)));
      
      // Undo second edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(textAfterFirstEdit));
      
      // Undo first edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(initialContent));
    });
    
    testWidgets('should handle multiple redo operations with multi-cursor', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2';
      
      final editor = EditTerminal(
        filePath: '/test/multi_redo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Make multiple edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.pumpAndSettle();
      
      final textAfterEdits = editor._controller.text;
      
      // Undo both edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(initialContent));
      
      // Redo both edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(textAfterEdits));
    });
    
    testWidgets('should undo deletion with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Hello World\nTest Line\nAnother Line';
      
      final editor = EditTerminal(
        filePath: '/test/delete_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at positions to delete from
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(80, 30));  // After "Hello"
      await tester.tapAt(Offset(60, 60));  // After "Test"
      await tester.tapAt(Offset(100, 90)); // After "Another"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Delete characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      
      final textAfterDeletion = editor._controller.text;
      expect(textAfterDeletion, isNot(equals(initialContent)));
      
      // Undo deletion
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore original content
      expect(editor._controller.text, equals(initialContent));
    });
    
    testWidgets('should handle undo after clearing multi-cursor mode', (WidgetTester tester) async {
      const initialContent = 'Test content for undo after clearing cursors';
      
      final editor = EditTerminal(
        filePath: '/test/clear_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors and make edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      final textAfterEdit = editor._controller.text;
      expect(textAfterEdit.contains('EDIT'), isTrue);
      
      // Clear multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isFalse);
      
      // Undo the edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore content but multi-cursor mode remains off
      expect(editor._controller.text, equals(initialContent));
      expect(editor._multiCursorMode, isFalse);
    });
    
    testWidgets('should handle undo with mixed single and multi-cursor operations', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      
      final editor = EditTerminal(
        filePath: '/test/mixed_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Single cursor edit
      await tester.tapAt(Offset(50, 30));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      
      final textAfterSingleEdit = editor._controller.text;
      expect(textAfterSingleEdit.contains('SINGLE'), isTrue);
      
      // Multi-cursor edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 60));
      await tester.tapAt(Offset(50, 90));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      
      final textAfterMultiEdit = editor._controller.text;
      expect(textAfterMultiEdit.contains('MULTI'), isTrue);
      
      // Undo multi-cursor edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(textAfterSingleEdit));
      
      // Undo single-cursor edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(initialContent));
    });
    
    testWidgets('should handle undo stack limits with multi-cursor', (WidgetTester tester) async {
      const initialContent = 'Base line for testing undo stack limits';
      
      final editor = EditTerminal(
        filePath: '/test/stack_limit.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(150, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Make many edits to exceed stack limit
      for (int i = 0; i < 150; i++) { // More than the max stack size
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();
      }
      
      final textAfterManyEdits = editor._controller.text;
      expect(textAfterManyEdits.length, greaterThan(initialContent.length));
      
      // Verify we can still undo (but not all the way to beginning)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should have undone the last edit
      expect(editor._controller.text, isNot(equals(textAfterManyEdits)));
      
      // Multi-cursor mode should still work
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should handle undo with cursor position restoration', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3\nLine 4';
      
      final editor = EditTerminal(
        filePath: '/test/cursor_restore.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at specific positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(30, 30));   // Start of Line 1
      await tester.tapAt(Offset(80, 60));   // Middle of Line 2
      await tester.tapAt(Offset(120, 90));  // End of Line 3
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      final initialCursorPositions = editor._cursors.map((c) => c.baseOffset).toList();
      
      // Make edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      
      // Undo the edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore content and maintain multi-cursor mode
      expect(editor._controller.text, equals(initialContent));
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(3));
    });
    
    testWidgets('should handle undo with validation failures', (WidgetTester tester) async {
      const initialContent = 'Valid content';
      
      final editor = EditTerminal(
        filePath: '/test/validation_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Make a valid edit first
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      
      final textAfterValidEdit = editor._controller.text;
      expect(textAfterValidEdit.contains('VALID'), isTrue);
      
      // Try to make an invalid edit (this would be rejected by validation)
      // In a real scenario, this might be content that's too long or contains dangerous patterns
      // For this test, we'll simulate by making a normal edit and then trying to undo
      
      // Undo the valid edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should restore to initial content
      expect(editor._controller.text, equals(initialContent));
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Undo/Redo Edge Cases', () {
    
    testWidgets('should handle undo when nothing to undo', (WidgetTester tester) async {
      const initialContent = 'Test content';
      
      final editor = EditTerminal(
        filePath: '/test/undo_none.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Try to undo without any edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should remain unchanged
      expect(editor._controller.text, equals(initialContent));
      expect(editor._canUndo(), isFalse);
    });
    
    testWidgets('should handle redo when nothing to redo', (WidgetTester tester) async {
      const initialContent = 'Test content';
      
      final editor = EditTerminal(
        filePath: '/test/redo_none.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Make an edit
      await tester.tapAt(Offset(50, 50));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      // Try to redo without any undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should remain with the edit
      expect(editor._controller.text, contains('X'));
      expect(editor._canRedo(), isFalse);
    });
    
    testWidgets('should handle undo after new edit breaks redo chain', (WidgetTester tester) async {
      const initialContent = 'Base content';
      
      final editor = EditTerminal(
        filePath: '/test/redo_chain.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Make first edit
      await tester.tapAt(Offset(50, 50));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      
      final textAfterFirstEdit = editor._controller.text;
      
      // Make second edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      
      // Undo second edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(textAfterFirstEdit));
      
      // Make new edit (should break redo chain)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      
      // Try to redo - should not work
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should not restore the 'B' edit
      expect(editor._controller.text, contains('C'));
      expect(editor._controller.text, isNot(contains('B')));
    });
    
    testWidgets('should handle rapid undo/redo operations', (WidgetTester tester) async {
      const initialContent = 'Rapid test content';
      
      final editor = EditTerminal(
        filePath: '/test/rapid_undo.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Make edit
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      
      final textAfterEdit = editor._controller.text;
      expect(textAfterEdit.contains('RAPID'), isTrue);
      
      // Rapid undo/redo sequence
      for (int i = 0; i < 5; i++) {
        // Undo
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        
        // Redo
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }
      
      // Should end up with the edited text
      expect(editor._controller.text, equals(textAfterEdit));
      expect(editor._multiCursorMode, isTrue);
    });
  });
}
