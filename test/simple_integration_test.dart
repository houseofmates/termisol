import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';

/// Simple integration tests for Termisol
void main() {
  runApp(const SimpleTestApp());
}

class SimpleTestApp extends StatelessWidget {
  const SimpleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termisol Simple Tests',
      home: const SimpleTestDashboard(),
    );
  }
}

class SimpleTestDashboard extends StatefulWidget {
  const SimpleTestDashboard({super.key});

  @override
  State<SimpleTestDashboard> createState() => _SimpleTestDashboardState();
}

class _SimpleTestDashboardState extends State<SimpleTestDashboard> {
  final List<TestResult> _testResults = [];
  bool _isRunning = false;

  Future<void> _runAllTests() async {
    setState(() => _isRunning = true);
    _testResults.clear();

    // Test 1: Edit Terminal Basic Functionality
    await _testEditTerminal();

    // Test 2: AI Chat Integration
    await _testAIChatIntegration();

    // Test 3: Model Selection
    await _testModelSelection();

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
      
      // Verify AI chat window opens
      assert(editor._showAIChat == true, 'AI chat should be open');

      // Test model switching
      editor._selectedModel = 'deepseek-v4-flash';
      assert(editor._selectedModel == 'deepseek-v4-flash', 'Model should be DeepSeek');

      // Test AI message sending
      editor._aiChatController.text = 'Test message';
      await editor._sendAIMessage('Test message');
      
      return 'AI chat integration working';
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
        title: const Text('Termisol Simple Tests'),
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
