import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';
import '../lib/core/editor_validator.dart';
import '../lib/core/editor_crash_recovery.dart';

/// Integration Test Suite for Editor with All Termisol Features
/// 
/// Tests multi-cursor functionality in combination with all other Termisol features
/// including AI chat, collaboration, search, settings, validation, crash recovery, etc.
void main() {
  group('Editor Integration Tests', () {
    
    testWidgets('should integrate multi-cursor with AI chat', (WidgetTester tester) async {
      const initialContent = 'Multi-cursor with AI integration test';
      
      final editor = EditTerminal(
        filePath: '/test/ai_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2));
      
      // Open AI chat
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      
      // Toggle AI chat (simulated)
      await tester.tap(find.byType(IconButton)); // Find AI chat button
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
      
      // Type with multi-cursor while AI chat is open
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('TEST'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with search functionality', (WidgetTester tester) async {
      const initialContent = 'Search test line 1\nSearch test line 2\nSearch test line 3';
      
      final editor = EditTerminal(
        filePath: '/test/search_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 30));
      await tester.tapAt(Offset(100, 60));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Open search (Ctrl+F)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Type search term
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should be preserved during search
      expect(editor._multiCursorMode, isTrue);
      
      // Close search and continue editing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      // Continue typing with multi-cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('FOUND'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with collaboration', (WidgetTester tester) async {
      const initialContent = 'Collaboration test with multi-cursor';
      
      final editor = EditTerminal(
        filePath: '/test/collaboration_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Toggle collaboration (Ctrl+Shift+C)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should work with collaboration
      expect(editor._multiCursorMode, isTrue);
      
      // Type with multi-cursor while collaboration is active
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('COLLAB'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with settings and themes', (WidgetTester tester) async {
      const initialContent = 'Settings and theme integration test';
      
      final editor = EditTerminal(
        filePath: '/test/settings_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Open settings (Ctrl+P)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should be preserved
      expect(editor._multiCursorMode, isTrue);
      
      // Close settings
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      // Continue editing with multi-cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('THEME'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with validation system', (WidgetTester tester) async {
      const initialContent = 'Valid content for validation test';
      
      final editor = EditTerminal(
        filePath: '/test/validation_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type valid content
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
      
      expect(editor._controller.text, contains('VALID'));
      expect(editor._multiCursorMode, isTrue);
      
      // Test validation with potentially dangerous content (simulated)
      // In a real scenario, this would be rejected by validation
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('SAFE'));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with crash recovery', (WidgetTester tester) async {
      const initialContent = 'Crash recovery integration test';
      
      final editor = EditTerminal(
        filePath: '/test/recovery_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Make edits that should be saved for recovery
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('RECOVERY'));
      expect(editor._multiCursorMode, isTrue);
      
      // Simulate crash recovery by checking if state is saved
      // In a real scenario, this would involve restarting the editor
      final crashRecovery = EditorCrashRecovery.instance;
      await crashRecovery.initialize();
      
      final hasRecoveryData = await crashRecovery.hasRecoveryData();
      expect(hasRecoveryData, isTrue); // Should have recovery data
    });
    
    testWidgets('should integrate multi-cursor with undo/redo system', (WidgetTester tester) async {
      const initialContent = 'Undo/redo integration test';
      
      final editor = EditTerminal(
        filePath: '/test/undo_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Make edits
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      
      final textAfterEdit = editor._controller.text;
      expect(textAfterEdit, contains('UNDO'));
      
      // Undo with multi-cursor active
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(initialContent));
      expect(editor._multiCursorMode, isTrue);
      
      // Redo with multi-cursor active
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, equals(textAfterEdit));
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should integrate multi-cursor with keyboard shortcuts', (WidgetTester tester) async {
      const initialContent = 'Keyboard shortcuts integration test';
      
      final editor = EditTerminal(
        filePath: '/test/shortcuts_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Test various shortcuts while multi-cursor is active
      
      // Save (Ctrl+Shift+S)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Select all (Ctrl+A)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Copy (Ctrl+C)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Continue editing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('SHORTCUTS'));
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Complex Integration Scenarios', () {
    
    testWidgets('should handle multi-cursor with all features simultaneously', (WidgetTester tester) async {
      const initialContent = 'Complete integration test with all features';
      
      final editor = EditTerminal(
        filePath: '/test/complete_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.tapAt(Offset(300, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Open AI chat
      await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      
      // Enable collaboration
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Open search
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Type search term
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      
      // Close search
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      // Multi-cursor mode should still be active
      expect(editor._multiCursorMode, isTrue);
      
      // Make complex edits with multi-cursor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('COMPLEX'));
      expect(editor._multiCursorMode, isTrue);
      
      // Test undo/redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('COMPLEX'));
      expect(editor._multiCursorMode, isTrue);
      
      // Test copy/paste
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should handle multi-cursor with performance monitoring', (WidgetTester tester) async {
      const initialContent = 'Performance monitoring integration test';
      
      final editor = EditTerminal(
        filePath: '/test/performance_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode with many cursors
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      for (int i = 0; i < 10; i++) {
        await tester.tapAt(Offset(50.0 + i * 20, 50));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Make rapid edits to test performance
      for (int i = 0; i < 20; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.pumpAndSettle();
      }
      
      expect(editor._controller.text, contains('PERF'));
      expect(editor._multiCursorMode, isTrue);
      
      // Test performance with undo/redo
      for (int i = 0; i < 10; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }
      
      expect(editor._multiCursorMode, isTrue);
    });
    
    testWidgets('should handle multi-cursor with error recovery', (WidgetTester tester) async {
      const initialContent = 'Error recovery integration test';
      
      final editor = EditTerminal(
        filePath: '/test/error_integration.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Make edits that might trigger validation errors
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
      
      expect(editor._controller.text, contains('VALID'));
      expect(editor._multiCursorMode, isTrue);
      
      // Test error recovery by attempting operations that might fail
      // and ensuring the editor remains stable
      
      // Clear and restore multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isFalse);
      
      // Re-enable multi-cursor mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(150, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Continue editing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('RECOVER'));
      expect(editor._multiCursorMode, isTrue);
    });
  });
  
  group('Real-world Usage Scenarios', () {
    
    testWidgets('should handle complex editing workflow', (WidgetTester tester) async {
      const initialContent = '''# Project Documentation
## Overview
This is a sample project documentation file.
It contains multiple sections and various content types.

## Features
- Feature 1: Multi-cursor editing
- Feature 2: Advanced validation
- Feature 3: Crash recovery

## Code Example
```dart
void main() {
  print("Hello, World!");
}
```

## Conclusion
This demonstrates the editor's capabilities.''';
      
      final editor = EditTerminal(
        filePath: '/test/workflow.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Simulate complex editing workflow
      
      // 1. Add cursors at multiple section headers
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(50, 30));   // # Project Documentation
      await tester.tapAt(Offset(50, 90));   // ## Overview
      await tester.tapAt(Offset(50, 150));  // ## Features
      await tester.tapAt(Offset(50, 210));  // ## Code Example
      await tester.tapAt(Offset(50, 270));  // ## Conclusion
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(4)); // 4 additional + 1 main = 5 total
      
      // 2. Add "Updated " to all headers
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text, contains('Updated'));
      
      // 3. Clear multi-cursor and add new cursors at feature list
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(70, 170));  // Feature 1
      await tester.tapAt(Offset(70, 190));  // Feature 2
      await tester.tapAt(Offset(70, 210));  // Feature 3
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      // 4. Add "✓ " to all features
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // 5. Open search to find specific content
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      
      // 6. Close search and continue editing
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      
      // 7. Enable collaboration
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // 8. Save the document
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      
      // Verify final state
      expect(editor._controller.text, contains('Updated'));
      expect(editor._controller.text, contains('Project Documentation'));
      expect(editor._controller.text, contains('Features'));
      expect(editor._controller.text, contains('Code Example'));
      expect(editor._controller.text, contains('Conclusion'));
    });
    
    testWidgets('should handle rapid feature switching', (WidgetTester tester) async {
      const initialContent = 'Rapid switching test content';
      
      final editor = EditTerminal(
        filePath: '/test/rapid_switching.txt',
        initialContent: initialContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Rapidly switch between different features while maintaining multi-cursor
      
      for (int cycle = 0; cycle < 3; cycle++) {
        // Enable multi-cursor
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.tapAt(Offset(100, 50));
        await tester.tapAt(Offset(200, 50));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        
        // Type something
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
        await tester.pumpAndSettle();
        
        // Open search
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        
        // Close search
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        
        // Open settings
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        
        // Close settings
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        
        // Enable collaboration
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        
        // Clear multi-cursor
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      
      // Verify the editor handled all the rapid switching
      expect(editor._controller.text, contains('CYCLE'));
      expect(editor._multiCursorMode, isFalse); // Should be cleared at the end
    });
  });
}
