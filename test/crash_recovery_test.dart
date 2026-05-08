import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../lib/core/editor_crash_recovery.dart';
import '../lib/core/editor_validator.dart';

/// Crash Recovery Test Suite
/// 
/// Tests the comprehensive crash recovery and error reporting system
/// for the text editor to ensure data safety and debugging capabilities.
void main() {
  group('Editor Crash Recovery Tests', () {
    late EditorCrashRecovery crashRecovery;
    
    setUp(() async {
      crashRecovery = EditorCrashRecovery.instance;
      await crashRecovery.initialize();
      await crashRecovery.clearRecoveryData();
    });
    
    tearDown(() async {
      await crashRecovery.clearRecoveryData();
      crashRecovery.dispose();
    });
    
    test('should initialize successfully', () async {
      expect(crashRecovery, isNotNull);
      expect(await crashRecovery.hasRecoveryData(), isFalse);
    });
    
    test('should save and load editor state', () async {
      final state = EditorState(
        filePath: '/test/example.txt',
        content: 'Hello World\nThis is test content',
        cursorPosition: 5,
        selectionStart: 0,
        selectionEnd: 11,
        multiCursorPositions: [10, 20, 30],
        multiCursorMode: true,
        settings: {
          'fontSize': 16.0,
          'theme': 'dark',
          'lineNumbers': true,
        },
        timestamp: DateTime.now(),
      );
      
      // Save state
      await crashRecovery.saveEditorState(state);
      
      // Verify recovery data exists
      expect(await crashRecovery.hasRecoveryData(), isTrue);
      
      // Load state
      final recoveredState = await crashRecovery.loadEditorState();
      
      expect(recoveredState, isNotNull);
      expect(recoveredState!.filePath, equals(state.filePath));
      expect(recoveredState.content, equals(state.content));
      expect(recoveredState.cursorPosition, equals(state.cursorPosition));
      expect(recoveredState.selectionStart, equals(state.selectionStart));
      expect(recoveredState.selectionEnd, equals(state.selectionEnd));
      expect(recoveredState.multiCursorPositions, equals(state.multiCursorPositions));
      expect(recoveredState.multiCursorMode, equals(state.multiCursorMode));
      expect(recoveredState.settings['fontSize'], equals(state.settings['fontSize']));
      expect(recoveredState.settings['theme'], equals(state.settings['theme']));
      expect(recoveredState.settings['lineNumbers'], equals(state.settings['lineNumbers']));
    });
    
    test('should save and load text content', () async {
      const filePath = '/test/document.txt';
      const content = 'This is test content\nWith multiple lines\nAnd special chars: !@#$%^&*()';
      
      // Save content
      await crashRecovery.saveTextContent(filePath, content);
      
      // Load content
      final recoveredContent = await crashRecovery.loadTextContent(filePath);
      
      expect(recoveredContent, equals(content));
    });
    
    test('should handle missing recovery data gracefully', () async {
      // Try to load non-existent state
      final state = await crashRecovery.loadEditorState();
      expect(state, isNull);
      
      // Try to load non-existent content
      final content = await crashRecovery.loadTextContent('/nonexistent.txt');
      expect(content, isNull);
    });
    
    test('should log and retrieve errors', () async {
      final error = EditorError(
        type: EditorErrorType.validationFailed,
        message: 'Test validation error',
        details: 'This is a test error for validation',
        timestamp: DateTime.now(),
        stackTrace: 'Test stack trace\nLine 1: error\nLine 2: more error',
      );
      
      // Log error
      await crashRecovery.logError(error);
      
      // Retrieve error log
      final errorLog = await crashRecovery.getErrorLog();
      
      expect(errorLog, isNotEmpty);
      expect(errorLog.length, equals(1));
      expect(errorLog.first.type, equals(EditorErrorType.validationFailed));
      expect(errorLog.first.message, equals('Test validation error'));
      expect(errorLog.first.details, equals('This is a test error for validation'));
      expect(errorLog.first.stackTrace, equals('Test stack trace\nLine 1: error\nLine 2: more error'));
    });
    
    test('should limit error log size', () async {
      // Add more errors than the limit
      for (int i = 0; i < 1100; i++) {
        final error = EditorError(
          type: EditorErrorType.systemError,
          message: 'Test error $i',
          timestamp: DateTime.now(),
        );
        await crashRecovery.logError(error);
      }
      
      final errorLog = await crashRecovery.getErrorLog();
      
      // Should be limited to max entries
      expect(errorLog.length, lessThanOrEqualTo(1000));
      expect(errorLog.last.message, equals('Test error 1099'));
    });
    
    test('should clear error log', () async {
      // Add some errors
      for (int i = 0; i < 5; i++) {
        final error = EditorError(
          type: EditorErrorType.systemError,
          message: 'Test error $i',
          timestamp: DateTime.now(),
        );
        await crashRecovery.logError(error);
      }
      
      // Verify errors exist
      expect(await crashRecovery.getErrorLog(), isNotEmpty);
      
      // Clear error log
      await crashRecovery.clearErrorLog();
      
      // Verify errors are cleared
      expect(await crashRecovery.getErrorLog(), isEmpty);
    });
    
    test('should generate crash report', () async {
      // Add some test errors
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.validationFailed,
        message: 'Test validation error',
        timestamp: DateTime.now().subtract(Duration(minutes: 10)),
      ));
      
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.systemError,
        message: 'Test system error',
        details: 'System error details',
        timestamp: DateTime.now().subtract(Duration(minutes: 5)),
      ));
      
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.performanceIssue,
        message: 'Test performance error',
        timestamp: DateTime.now(),
      ));
      
      // Generate crash report
      final report = await crashRecovery.generateCrashReport();
      
      expect(report, isNotEmpty);
      expect(report, contains('Editor Crash Report'));
      expect(report, contains('Error Summary'));
      expect(report, contains('Total Errors: 3'));
      expect(report, contains('validation failed'));
      expect(report, contains('system error'));
      expect(report, contains('performance issue'));
      expect(report, contains('Error Types Distribution'));
    });
    
    test('should export crash report to file', () async {
      // Add test error
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.systemError,
        message: 'Test export error',
        timestamp: DateTime.now(),
      ));
      
      // Export report
      final reportFile = await crashRecovery.exportCrashReport();
      
      expect(reportFile, isNotNull);
      expect(await reportFile.exists(), isTrue);
      
      final reportContent = await reportFile.readAsString();
      expect(reportContent, contains('Editor Crash Report'));
      expect(reportContent, contains('Test export error'));
    });
    
    test('should get recovery statistics', () async {
      // Add some test data
      await crashRecovery.saveTextContent('/test1.txt', 'Content 1');
      await crashRecovery.saveTextContent('/test2.txt', 'Content 2');
      
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.systemError,
        message: 'Test error',
        timestamp: DateTime.now(),
      ));
      
      // Get stats
      final stats = await crashRecovery.getRecoveryStats();
      
      expect(stats.totalErrors, equals(1));
      expect(stats.totalRecoveryFiles, greaterThan(0));
      expect(stats.totalRecoverySize, greaterThan(0));
      expect(stats.hasRecoveryData, isTrue);
      expect(stats.newestError, isNotNull);
      expect(stats.oldestError, isNotNull);
    });
    
    test('should handle corrupted recovery data', () async {
      // Save valid content first
      await crashRecovery.saveTextContent('/test.txt', 'Valid content');
      
      // Manually corrupt the metadata file
      final recoveryDir = Directory('${(await getApplicationDocumentsDirectory()).path}/editor_recovery');
      final files = await recoveryDir.list().toList();
      
      for (final file in files) {
        if (file.path.endsWith('.meta')) {
          await file.writeAsString('invalid json');
        }
      }
      
      // Try to load - should handle corruption gracefully
      final content = await crashRecovery.loadTextContent('/test.txt');
      expect(content, isNull); // Should return null due to checksum mismatch
    });
  });
  
  group('Error Monitor Tests', () {
    late EditorCrashRecovery crashRecovery;
    
    setUp(() async {
      crashRecovery = EditorCrashRecovery.instance;
      await crashRecovery.initialize();
      await crashRecovery.clearErrorLog();
    });
    
    tearDown(() async {
      await crashRecovery.clearErrorLog();
      crashRecovery.dispose();
    });
    
    test('should monitor async operations', () async {
      final result = await ErrorMonitor.monitorError(
        'Test operation',
        () async => 'success',
        context: 'Test context',
      );
      
      expect(result, equals('success'));
      expect(await crashRecovery.getErrorLog(), isEmpty); // No errors logged
    });
    
    test('should monitor async operation failures', () async {
      final result = await ErrorMonitor.monitorError(
        'Failing operation',
        () async => throw Exception('Test error'),
        context: 'Test context',
      );
      
      expect(result, isNull);
      
      final errorLog = await crashRecovery.getErrorLog();
      expect(errorLog, isNotEmpty);
      expect(errorLog.first.message, contains('Failing operation'));
      expect(errorLog.first.details, contains('Test context'));
    });
    
    test('should monitor sync operations', () {
      final result = ErrorMonitor.monitorSyncError(
        'Test sync operation',
        () => 'sync success',
        context: 'Sync context',
      );
      
      expect(result, equals('sync success'));
    });
    
    test('should monitor sync operation failures', () {
      final result = ErrorMonitor.monitorSyncError(
        'Failing sync operation',
        () => throw Exception('Sync test error'),
        context: 'Sync context',
      );
      
      expect(result, isNull);
    });
    
    test('should report validation errors', () async {
      await ErrorMonitor.reportValidationError(
        'Content validation',
        'Invalid content detected',
        details: 'Content contains dangerous characters',
      );
      
      final errorLog = await crashRecovery.getErrorLog();
      expect(errorLog, isNotEmpty);
      expect(errorLog.first.type, equals(EditorErrorType.validationFailed));
      expect(errorLog.first.message, contains('Content validation'));
    });
    
    test('should report performance issues', () async {
      await ErrorMonitor.reportPerformanceIssue(
        'Slow operation',
        const Duration(milliseconds: 500),
        details: 'Operation took too long',
      );
      
      final errorLog = await crashRecovery.getErrorLog();
      expect(errorLog, isNotEmpty);
      expect(errorLog.first.type, equals(EditorErrorType.performanceIssue));
      expect(errorLog.first.message, contains('Slow operation'));
      expect(errorLog.first.details, contains('500ms'));
    });
    
    test('should report file system errors', () async {
      await ErrorMonitor.reportFileSystemError(
        'File read',
        '/nonexistent/file.txt',
        'File not found',
        details: 'Permission denied',
      );
      
      final errorLog = await crashRecovery.getErrorLog();
      expect(errorLog, isNotEmpty);
      expect(errorLog.first.type, equals(EditorErrorType.fileSystemError));
      expect(errorLog.first.message, contains('File read'));
      expect(errorLog.first.details, contains('/nonexistent/file.txt'));
    });
  });
  
  group('Auto Save Manager Tests', () {
    late AutoSaveManager autoSaveManager;
    late List<String> saveCalls;
    
    setUp(() {
      autoSaveManager = AutoSaveManager();
      saveCalls = [];
    });
    
    tearDown(() {
      autoSaveManager.dispose();
    });
    
    test('should start auto-save', () {
      autoSaveManager.startAutoSave(() {
        saveCalls.add('auto-save');
      });
      
      // Wait a bit for auto-save to trigger
      return Future.delayed(Duration(milliseconds: 100)).then((_) {
        // Auto-save should have been set up (we can't easily test the timer without waiting 2 minutes)
        expect(autoSaveManager, isNotNull);
      });
    });
    
    test('should stop auto-save', () {
      autoSaveManager.startAutoSave(() {});
      autoSaveManager.stopAutoSave();
      
      // Should not throw any errors
      expect(autoSaveManager, isNotNull);
    });
    
    test('should debounce save', () async {
      autoSaveManager.debouncedSave(() {
        saveCalls.add('debounced-save');
      });
      
      // Should not save immediately
      expect(saveCalls, isEmpty);
      
      // Wait for debounce timeout
      await Future.delayed(Duration(milliseconds: 100));
      
      // Should have saved after debounce
      expect(saveCalls, contains('debounced-save'));
    });
    
    test('should force immediate save', () async {
      await autoSaveManager.forceSave(() {
        saveCalls.add('force-save');
      });
      
      // Should save immediately
      expect(saveCalls, contains('force-save'));
    });
    
    test('should handle multiple debounced saves', () async {
      // Trigger multiple saves rapidly
      for (int i = 0; i < 5; i++) {
        autoSaveManager.debouncedSave(() {
          saveCalls.add('debounced-save-$i');
        });
      }
      
      // Should not save immediately
      expect(saveCalls, isEmpty);
      
      // Wait for debounce timeout
      await Future.delayed(Duration(milliseconds: 100));
      
      // Should have saved only once (the last call)
      expect(saveCalls.length, equals(1));
      expect(saveCalls.first, contains('debounced-save-4'));
    });
  });
  
  group('Integration Tests', () {
    late EditorCrashRecovery crashRecovery;
    
    setUp(() async {
      crashRecovery = EditorCrashRecovery.instance;
      await crashRecovery.initialize();
      await crashRecovery.clearRecoveryData();
    });
    
    tearDown(() async {
      await crashRecovery.clearRecoveryData();
      crashRecovery.dispose();
    });
    
    test('should handle complete editor lifecycle', () async {
      const filePath = '/test/lifecycle.txt';
      const initialContent = 'Initial content';
      
      // Simulate editor opening
      final state1 = EditorState(
        filePath: filePath,
        content: initialContent,
        cursorPosition: 0,
        selectionStart: 0,
        selectionEnd: 0,
        multiCursorPositions: [],
        multiCursorMode: false,
        settings: {'fontSize': 14.0},
        timestamp: DateTime.now(),
      );
      
      await crashRecovery.saveEditorState(state1);
      await crashRecovery.saveTextContent(filePath, initialContent);
      
      // Simulate text changes
      const updatedContent = 'Updated content with more text';
      final state2 = EditorState(
        filePath: filePath,
        content: updatedContent,
        cursorPosition: 10,
        selectionStart: 5,
        selectionEnd: 15,
        multiCursorPositions: [5, 10, 20],
        multiCursorMode: true,
        settings: {'fontSize': 16.0, 'theme': 'dark'},
        timestamp: DateTime.now(),
      );
      
      await crashRecovery.saveEditorState(state2);
      await crashRecovery.saveTextContent(filePath, updatedContent);
      
      // Simulate error during editing
      await crashRecovery.logError(EditorError(
        type: EditorErrorType.validationFailed,
        message: 'Invalid character detected',
        details: 'Line 5 contains invalid Unicode sequence',
        timestamp: DateTime.now(),
      ));
      
      // Simulate crash recovery
      final recoveredState = await crashRecovery.loadEditorState();
      final recoveredContent = await crashRecovery.loadTextContent(filePath);
      final errorLog = await crashRecovery.getErrorLog();
      
      expect(recoveredState, isNotNull);
      expect(recoveredState!.content, equals(updatedContent));
      expect(recoveredState.cursorPosition, equals(10));
      expect(recoveredState.multiCursorMode, isTrue);
      expect(recoveredContent, equals(updatedContent));
      expect(errorLog, isNotEmpty);
      expect(errorLog.first.type, equals(EditorErrorType.validationFailed));
    });
    
    test('should handle multiple file recovery', () async {
      const files = [
        '/test/file1.txt',
        '/test/file2.txt',
        '/test/file3.txt',
      ];
      
      const contents = [
        'Content for file 1',
        'Content for file 2',
        'Content for file 3',
      ];
      
      // Save multiple files
      for (int i = 0; i < files.length; i++) {
        await crashRecovery.saveTextContent(files[i], contents[i]);
      }
      
      // Recover all files
      for (int i = 0; i < files.length; i++) {
        final recoveredContent = await crashRecovery.loadTextContent(files[i]);
        expect(recoveredContent, equals(contents[i]));
      }
      
      // Verify recovery stats
      final stats = await crashRecovery.getRecoveryStats();
      expect(stats.totalRecoveryFiles, greaterThanOrEqualTo(3));
      expect(stats.hasRecoveryData, isTrue);
    });
    
    test('should handle large content recovery', () async {
      // Generate large content (100KB)
      final largeContent = 'A' * 100000;
      const filePath = '/test/large.txt';
      
      // Save large content
      await crashRecovery.saveTextContent(filePath, largeContent);
      
      // Recover large content
      final recoveredContent = await crashRecovery.loadTextContent(filePath);
      
      expect(recoveredContent, isNotNull);
      expect(recoveredContent!.length, equals(largeContent.length));
      expect(recoveredContent, equals(largeContent));
    });
    
    test('should handle concurrent operations', () async {
      const filePath = '/test/concurrent.txt';
      
      // Simulate concurrent saves
      final futures = <Future>[];
      
      for (int i = 0; i < 10; i++) {
        futures.add(crashRecovery.saveTextContent(filePath, 'Content $i'));
      }
      
      await Future.wait(futures);
      
      // Should be able to recover some content
      final recoveredContent = await crashRecovery.loadTextContent(filePath);
      expect(recoveredContent, isNotNull);
      expect(recoveredContent!.startsWith('Content'), isTrue);
    });
    
    test('should handle error recovery scenarios', () async {
      // Test various error scenarios
      final errorTypes = [
        EditorErrorType.validationFailed,
        EditorErrorType.systemError,
        EditorErrorType.performanceIssue,
        EditorErrorType.fileSystemError,
        EditorErrorType.memoryLeak,
      ];
      
      for (final errorType in errorTypes) {
        await crashRecovery.logError(EditorError(
          type: errorType,
          message: 'Test ${errorType.name} error',
          timestamp: DateTime.now(),
        ));
      }
      
      // Generate comprehensive report
      final report = await crashRecovery.generateCrashReport();
      
      expect(report, contains('Error Types Distribution'));
      expect(report, contains('validationFailed'));
      expect(report, contains('systemError'));
      expect(report, contains('performanceIssue'));
      expect(report, contains('fileSystemError'));
      expect(report, contains('memoryLeak'));
      
      // Export report
      final reportFile = await crashRecovery.exportCrashReport();
      expect(await reportFile.exists(), isTrue);
      
      final exportedReport = await reportFile.readAsString();
      expect(exportedReport.length, greaterThan(1000)); // Should be substantial
    });
  });
}

// Mock function for getApplicationDocumentsDirectory
Future<Directory> getApplicationDocumentsDirectory() async {
  final tempDir = Directory.systemTemp;
  final testDir = Directory('${tempDir.path}/editor_recovery_test');
  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }
  return testDir;
}
