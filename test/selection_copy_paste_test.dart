import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:termisol/ui/edit.dart';

/// Multi-Cursor Selection and Copy/Paste Test Suite
/// 
/// Tests selection, copying, and pasting operations with multiple cursors
/// to ensure proper clipboard handling and text manipulation.
void main() {
  group('Multi-Cursor Selection Tests', () {
    
    testWidgets('should handle text selection with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1: Select this text\nLine 2: And this text\nLine 3: Also this text';
      
      final editor = EditTerminal(
        filePath: '/test/selection.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(80, 30));  // Middle of "Select this text"
      await tester.tapAt(Offset(80, 60));  // Middle of "And this text"  
      await tester.tapAt(Offset(85, 90));  // Middle of "Also this text"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Create selections by holding Shift and moving cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      
      // Extend selection at each cursor position
      for (int i = 0; i < 4; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Verify selections were created
      expect(editor._cursors.isNotEmpty, isTrue);
      
      // Each cursor should have a selection
      for (final cursor in editor._cursors) {
        expect(cursor.isValid, isTrue);
        expect(cursor.isCollapsed, isFalse); // Should have selection
      }
    });
    
    testWidgets('should handle word selection with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'word1 word2 word3\nword4 word5 word6\nword7 word8 word9';
      
      final editor = EditTerminal(
        filePath: '/test/word_selection.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different words
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(30, 30));   // At "word1"
      await tester.tapAt(Offset(90, 30));   // At "word2"
      await tester.tapAt(Offset(150, 30));  // At "word3"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Double-click to select words at each cursor
      await tester.tapAt(Offset(30, 30));
      await tester.pump();
      await tester.tapAt(Offset(30, 30));
      await tester.pumpAndSettle();
      
      // Verify word selections
      expect(editor._cursors.isNotEmpty, isTrue);
      
      // Check that selections contain whole words
      for (final cursor in editor._cursors) {
        if (cursor.isValid && !cursor.isCollapsed) {
          final selectedText = editor._controller.text.substring(
            cursor.start,
            cursor.end,
          );
          expect(selectedText, contains('word'));
        }
      }
    });
    
    testWidgets('should handle line selection with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1 content\nLine 2 content\nLine 3 content\nLine 4 content';
      
      final editor = EditTerminal(
        filePath: '/test/line_selection.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different lines
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(10, 30));  // Line 1
      await tester.tapAt(Offset(10, 60));  // Line 2
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Triple-click to select lines
      await tester.tapAt(Offset(10, 30));
      await tester.pump();
      await tester.tapAt(Offset(10, 30));
      await tester.pump();
      await tester.tapAt(Offset(10, 30));
      await tester.pumpAndSettle();
      
      // Verify line selections
      expect(editor._cursors.isNotEmpty, isTrue);
      
      // Check that selections contain entire lines
      for (final cursor in editor._cursors) {
        if (cursor.isValid && !cursor.isCollapsed) {
          final selectedText = editor._controller.text.substring(
            cursor.start,
            cursor.end,
          );
          expect(selectedText, contains('Line'));
          expect(selectedText, contains('content'));
        }
      }
    });
    
    testWidgets('should handle select all with multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      
      final editor = EditTerminal(
        filePath: '/test/select_all.txt',
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
      
      expect(editor._multiCursorMode, isTrue);
      
      // Select all (Ctrl+A)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should select entire content but maintain multi-cursor mode
      expect(editor._controller.selection.start, equals(0));
      expect(editor._controller.selection.end, equals(initialContent.length));
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Multi-Cursor Copy Tests', () {
    
    testWidgets('should copy text from multiple selections', (WidgetTester tester) async {
      const initialContent = 'Copy this text\nAnd copy this\nAlso copy this';
      
      final editor = EditTerminal(
        filePath: '/test/copy.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors and create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));  // "Copy this text"
      await tester.tapAt(Offset(40, 60));  // "And copy this"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (int i = 0; i < 4; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Copy selections (Ctrl+C)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify clipboard contains copied text
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData, isNotNull);
      expect(clipboardData!.text, isNotNull);
      
      // Should contain text from multiple selections
      final copiedText = clipboardData.text!;
      expect(copiedText.length, greaterThan(0));
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should copy single word from multiple cursors', (WidgetTester tester) async {
      const initialContent = 'word1 word2 word3 word4 word5';
      
      final editor = EditTerminal(
        filePath: '/test/copy_words.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different words
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(30, 50));   // word1
      await tester.tapAt(Offset(90, 50));   // word3
      await tester.tapAt(Offset(150, 50));  // word5
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Double-click to select words
      await tester.tapAt(Offset(30, 50));
      await tester.pump();
      await tester.tapAt(Offset(30, 50));
      await tester.pumpAndSettle();
      
      // Copy words (Ctrl+C)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify clipboard
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData, isNotNull);
      
      final copiedText = clipboardData!.text!;
      expect(copiedText, isNotNull);
      expect(copiedText.length, greaterThan(0));
    });
    
    testWidgets('should handle copy with no selections', (WidgetTester tester) async {
      const initialContent = 'Test content for copying without selections';
      
      final editor = EditTerminal(
        filePath: '/test/copy_no_selection.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors but don't create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 50));
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Try to copy (Ctrl+C)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should handle gracefully - might copy current line or nothing
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Multi-Cursor Paste Tests', () {
    
    testWidgets('should paste text at multiple cursor positions', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      const pasteText = 'PASTED';
      
      final editor = EditTerminal(
        filePath: '/test/paste.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard data
      await Clipboard.setData(ClipboardData(text: pasteText));
      
      // Add cursors at different positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));  // Line 1
      await tester.tapAt(Offset(50, 60));  // Line 2
      await tester.tapAt(Offset(50, 90));  // Line 3
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Paste at all cursors (Ctrl+V)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify text was pasted at all positions
      final finalText = editor._controller.text;
      expect(finalText, contains(pasteText));
      
      // Count occurrences - should be pasted 3 times
      final occurrences = finalText.split(pasteText).length - 1;
      expect(occurrences, equals(3));
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should paste multiline text at multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2';
      const multilinePaste = 'Multiline\npaste\ntext';
      
      final editor = EditTerminal(
        filePath: '/test/multiline_paste.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard data
      await Clipboard.setData(ClipboardData(text: multilinePaste));
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste multiline text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify multiline text was pasted
      final finalText = editor._controller.text;
      expect(finalText, contains('Multiline'));
      expect(finalText, contains('paste'));
      expect(finalText, contains('text'));
      
      // Should have multiple line breaks
      final lineBreaks = finalText.split('\n').length - 1;
      expect(lineBreaks, greaterThan(initialContent.split('\n').length - 1));
    });
    
    testWidgets('should paste Unicode text at multiple cursors', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2';
      const unicodePaste = '🚀 Unicode 🌍 Text 🎉';
      
      final editor = EditTerminal(
        filePath: '/test/unicode_paste.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard data with Unicode
      await Clipboard.setData(ClipboardData(text: unicodePaste));
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste Unicode text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify Unicode text was pasted correctly
      final finalText = editor._controller.text;
      expect(finalText, contains('🚀'));
      expect(finalText, contains('🌍'));
      expect(finalText, contains('🎉'));
      expect(finalText, contains('Unicode'));
      expect(finalText, contains('Text'));
      
      // Should handle Unicode properly
      final occurrences = finalText.split('🚀').length - 1;
      expect(occurrences, equals(2)); // Pasted at 2 cursor positions
    });
    
    testWidgets('should handle paste with empty clipboard', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2';
      
      final editor = EditTerminal(
        filePath: '/test/empty_paste.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Clear clipboard
      await Clipboard.setData(const ClipboardData(text: ''));
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Try to paste (Ctrl+V)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should handle gracefully - content should remain unchanged
      expect(editor._controller.text, equals(initialContent));
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Multi-Cursor Cut Tests', () {
    
    testWidgets('should cut text from multiple selections', (WidgetTester tester) async {
      const initialContent = 'Cut this text\nAnd cut this\nAlso cut this';
      
      final editor = EditTerminal(
        filePath: '/test/cut.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors and create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(40, 30));  // "Cut this text"
      await tester.tapAt(Offset(30, 60));  // "And cut this"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (int i = 0; i < 4; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Cut selections (Ctrl+X)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify text was removed
      final finalText = editor._controller.text;
      expect(finalText, isNot(equals(initialContent)));
      
      // Verify clipboard contains cut text
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData, isNotNull);
      expect(clipboardData!.text, isNotNull);
      expect(clipboardData.text!.length, greaterThan(0));
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should handle cut with no selections', (WidgetTester tester) async {
      const initialContent = 'Test content for cutting without selections';
      
      final editor = EditTerminal(
        filePath: '/test/cut_no_selection.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors but don't create selections
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 50));
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Try to cut (Ctrl+X)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should handle gracefully - might cut current line or nothing
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Combined Copy/Paste Operations', () {
    
    testWidgets('should copy and paste between different cursor positions', (WidgetTester tester) async {
      const initialContent = 'Source text here\nTarget position here';
      
      final editor = EditTerminal(
        filePath: '/test/copy_paste_between.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursor at source position and create selection
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(60, 30));  // Middle of "Source text here"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Create selection
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (int i = 0; i < 4; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      
      // Copy selection
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Clear multi-cursor mode and add cursor at target position
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(80, 60));  // Middle of "Target position here"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste at target position
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify text was copied and pasted
      final finalText = editor._controller.text;
      expect(finalText, contains('Source'));
      expect(finalText.length, greaterThan(initialContent.length));
    });
    
    testWidgets('should handle copy/paste with large text', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2\nLine 3';
      const largeText = 'This is a large piece of text that will be copied and pasted ' * 10;
      
      final editor = EditTerminal(
        filePath: '/test/large_copy_paste.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard with large text
      await Clipboard.setData(ClipboardData(text: largeText));
      
      // Add multiple cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste large text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify large text was pasted
      final finalText = editor._controller.text;
      expect(finalText.length, greaterThan(initialContent.length));
      expect(finalText, contains('large piece of text'));
      
      // Should be pasted at multiple positions
      final occurrences = finalText.split('large piece of text').length - 1;
      expect(occurrences, equals(2));
    });
    
    testWidgets('should handle copy/paste with special characters', (WidgetTester tester) async {
      const initialContent = 'Line 1\nLine 2';
      const specialText = 'Special chars: !@#$%^&*()[]{}|\\:";\'<>?,./';
      
      final editor = EditTerminal(
        filePath: '/test/special_chars.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard with special characters
      await Clipboard.setData(ClipboardData(text: specialText));
      
      // Add cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));
      await tester.tapAt(Offset(50, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste special characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify special characters were pasted correctly
      final finalText = editor._controller.text;
      expect(finalText, contains('!@#$%^&*()'));
      expect(finalText, contains('[]{}|\\'));
      expect(finalText, contains(':";\'<>?,./'));
      
      // Should handle special characters properly
      final occurrences = finalText.split('Special chars:').length - 1;
      expect(occurrences, equals(2));
    });
  });
  
  group('Edge Cases and Error Handling', () {
    
    testWidgets('should handle copy/paste with read-only editor', (WidgetTester tester) async {
      const initialContent = 'Read-only content';
      const pasteText = 'Cannot paste here';
      
      final editor = EditTerminal(
        filePath: '/test/readonly.txt',
        initialContent: initialContent,
        readOnly: true,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard data
      await Clipboard.setData(ClipboardData(text: pasteText));
      
      // Try to add cursors (should not work in read-only mode)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should not be enabled in read-only
      expect(editor._multiCursorMode, isFalse);
      
      // Try to paste (should not work)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Content should remain unchanged
      expect(editor._controller.text, equals(initialContent));
    });
    
    testWidgets('should handle copy/paste with empty content', (WidgetTester tester) async {
      const initialContent = '';
      const pasteText = 'Paste into empty';
      
      final editor = EditTerminal(
        filePath: '/test/empty_content.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Set clipboard data
      await Clipboard.setData(ClipboardData(text: pasteText));
      
      // Add cursor at beginning
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(10, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // Paste into empty content
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Should paste successfully
      expect(editor._controller.text, equals(pasteText));
    });
    
    testWidgets('should handle rapid copy/paste operations', (WidgetTester tester) async {
      const initialContent = 'Base content';
      
      final editor = EditTerminal(
        filePath: '/test/rapid_operations.txt',
        initialContent: initialContent,
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
      
      // Perform rapid copy/paste operations
      for (int i = 0; i < 5; i++) {
        // Set clipboard
        await Clipboard.setData(ClipboardData(text: 'Rapid $i'));
        
        // Paste
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }
      
      // Should handle rapid operations without crashing
      expect(editor._controller.text.length, greaterThan(initialContent.length));
      expect(editor._multiCursorMode, isTrue);
      
      // Should contain text from all paste operations
      for (int i = 0; i < 5; i++) {
        expect(editor._controller.text, contains('Rapid $i'));
      }
    });
  });
}
