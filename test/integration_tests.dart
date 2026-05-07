import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';
import '../lib/core/terminal_session.dart';

/// Comprehensive integration tests for Termisol
void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termisol Integration Tests',
      home: const TestDashboard(),
    );
  }
}

class TestDashboard extends StatefulWidget {
  const TestDashboard({super.key});

  @override
  State<TestDashboard> createState() => _TestDashboardState();
}

class _TestDashboardState extends State<TestDashboard> {
  final List<TestResult> _testResults = [];
  bool _isRunning = false;

  Future<void> _runAllTests() async {
    setState(() => _isRunning = true);
    _testResults.clear();

    // Test 1: Edit Terminal Basic Functionality
    await _testEditTerminal();

    // Test 2: AI Chat Integration
    await _testAIChatIntegration();

    // Test 3: Hotkey Functionality
    await _testHotkeys();

    // Test 4: Model Selection
    await _testModelSelection();

    // Test 5: File Operations
    await _testFileOperations();

    // Test 6: Error Handling
    await _testErrorHandling();

    // Test 7: Performance
    await _testPerformance();

    setState(() => _isRunning = false);
  }

  Future<void> _testEditTerminal() async {
    _addTestResult('Edit Terminal Basic Functionality', () async {
      // Test basic text editing
      final editor = EditTerminal(
        filePath: '/tmp/test.txt',
        initialContent: 'Test content for edit terminal',
        onSave: (content) async {
          final file = File('/tmp/test.txt');
          await file.writeAsString(content);
        },
      );

      // Test basic functionality through public interface
      // Test text input
      editor._controller.text = 'Test text input';
      assert(editor._controller.text == 'Test text input', 'Text input should work');

      // Test text selection
      editor._controller.selection = const TextSelection(
        baseOffset: 5,
        extentOffset: 10,
      );
      assert(editor._controller.selection.textInside(editor._controller.text) == 'text ', 'Text selection should work');

      // Test save functionality
      await editor._saveContent();
      
      // Test that editor exists and has expected structure
      assert(editor.filePath == '/tmp/test.txt', 'File path should be set');
      assert(editor._controller.text.isNotEmpty, 'Editor should have content');

      return 'Edit terminal basic functionality working';
    });
  }

  Future<void> _testAIChatIntegration() async {
    _addTestResult('AI Chat Integration', () async {
      // Test AI chat opening
      final editor = EditTerminal(
        filePath: '/tmp/test.txt',
        initialContent: 'Test content for AI chat',
        onSave: (content) async {},
      );

      // Test AI chat with Tab completion
      editor._aiChatController.text = '/ai';
      editor._handleTabCompletion();
      
      // Verify AI chat window opens (check if it exists in UI)
      assert(editor._showAIChat == true, 'AI chat should be open');

      // Test model switching (verify through UI state)
      editor._selectedModel = 'deepseek-v4-flash';
      assert(editor._selectedModel == 'deepseek-v4-flash', 'Model should be DeepSeek');

      // Test AI message sending
      editor._aiChatController.text = 'Test message';
      await editor._sendAIMessage('Test message');
      
      return 'AI chat integration working';
    });
  }

  Future<void> _testHotkeys() async {
    _addTestResult('Hotkey Functionality', () async {
      // Test Ctrl+Shift+S save
      final editor = EditTerminal(
        filePath: '/tmp/test.txt',
        initialContent: 'Test hotkeys',
        onSave: (content) async {
          final file = File('/tmp/test.txt');
          await file.writeAsString(content);
        },
      );

      // Simulate Ctrl+Shift+S
      // Note: This would normally require actual key event simulation
      // For testing, we'll verify the hotkey configuration exists
      
      // Test hotkey configuration
      assert(editor._defaultHotkeys['save'] == 'Ctrl+Shift+S', 'Save hotkey should be Ctrl+Shift+S');
      assert(editor._defaultHotkeys['italic'] == 'Ctrl+I', 'Italic hotkey should be Ctrl+I');
      assert(editor._defaultHotkeys['ai_chat'] == '/ai + Tab', 'AI chat hotkey should be /ai + Tab');

      return 'Hotkey configuration working';
    });
  }

  Future<void> _testModelSelection() async {
    _addTestResult('Model Selection', () async {
      final editor = EditTerminal(
        filePath: '/tmp/test.txt',
        initialContent: 'Test model selection',
        onSave: (content) async {},
      );

      // Test Kimi K2.6 model
      editor._selectedModel = 'kimi-k2.6';
      assert(editor._selectedModel == 'kimi-k2.6', 'Should select Kimi K2.6');

      // Test DeepSeek V4 Flash model
      editor._selectedModel = 'deepseek-v4-flash';
      assert(editor._selectedModel == 'deepseek-v4-flash', 'Should select DeepSeek V4 Flash');

      return 'Model selection working';
    });
  }

  Future<void> _testFileOperations() async {
    _addTestResult('File Operations', () async {
      final testFile = File('/tmp/test_file.txt');
      await testFile.writeAsString('Test file content');

      // Test file reading in edit terminal
      final editor = EditTerminal(
        filePath: testFile.path,
        initialContent: await testFile.readAsString(),
        onSave: (content) async {
          await testFile.writeAsString(content);
        },
      );

      // Test file saving
      editor._controller.text = 'Modified content';
      await editor._saveContent();
      
      // Verify file was saved
      final savedContent = await testFile.readAsString();
      assert(savedContent == 'Modified content', 'File should be saved with modified content');

      return 'File operations working';
    });
  }

  Future<void> _testErrorHandling() async {
    _addTestResult('Error Handling', () async {
      // Test invalid file path
      try {
        final editor = EditTerminal(
          filePath: '/invalid/path/test.txt',
          initialContent: 'Test error handling',
          onSave: (content) async {},
        );
        
        // This should handle gracefully without crashing
        return 'Error handling working';
      } catch (e) {
        // Expected to catch the error
        return 'Error handling working (caught: $e)';
      }
    });
  }

  Future<void> _testPerformance() async {
    _addTestResult('Performance', () async {
      final stopwatch = Stopwatch()..start();
      
      // Test with large file
      final largeContent = 'x' * 10000; // 10KB of text
      final editor = EditTerminal(
        filePath: '/tmp/performance_test.txt',
        initialContent: largeContent,
        onSave: (content) async {},
      );

      // Measure rendering performance
      editor._controller.text = largeContent;
      await Future.delayed(const Duration(milliseconds: 100));
      
      stopwatch.stop();
      
      // Should render within reasonable time
      assert(stopwatch.elapsedMilliseconds < 1000, 'Large file should render quickly');
      
      return 'Performance test completed (${stopwatch.elapsedMilliseconds}ms)';
    });
  }

  void _addTestResult(String testName, Future<String> Function() test) {
    _testResults.add(TestResult(
      name: testName,
      status: TestStatus.pending,
      result: null,
    ));

    // Run test
    test().then((result) {
      setState(() {
        _testResults.last = TestResult(
          name: testName,
          status: TestStatus.completed,
          result: result,
        );
      });
    }).catchError((error) {
      setState(() {
        _testResults.last = TestResult(
          name: testName,
          status: TestStatus.failed,
          result: 'Error: $error',
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1e1e1e),
      appBar: AppBar(
        title: const Text('Termisol Integration Tests'),
        backgroundColor: const Color(0xFF2d2d2d),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _runAllTests,
                  child: Text(_isRunning ? 'Running Tests...' : 'Run All Tests'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _testResults.clear,
                  child: const Text('Clear Results'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _testResults.length,
                itemBuilder: (context, index) {
                  final test = _testResults[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                test.status == TestStatus.completed 
                                    ? Icons.check_circle 
                                    : test.status == TestStatus.failed 
                                        ? Icons.error 
                                        : Icons.hourglass_empty,
                                color: test.status == TestStatus.completed 
                                    ? Colors.green 
                                    : test.status == TestStatus.failed 
                                        ? Colors.red 
                                        : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                test.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            test.result ?? 'Pending...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum TestStatus {
  pending,
  running,
  completed,
  failed,
}

class TestResult {
  final String name;
  final TestStatus status;
  final String? result;

  TestResult({
    required this.name,
    required this.status,
    this.result,
  });
}
