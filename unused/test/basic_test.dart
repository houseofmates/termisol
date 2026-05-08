import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';

/// Basic test for EditTerminal public interface
void main() {
  runApp(const BasicTestApp());
}

class BasicTestApp extends StatelessWidget {
  const BasicTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edit Terminal Basic Test',
      home: const BasicTestDashboard(),
    );
  }
}

class BasicTestDashboard extends StatefulWidget {
  const BasicTestDashboard({super.key});

  @override
  State<BasicTestDashboard> createState() => _BasicTestDashboardState();
}

class _BasicTestDashboardState extends State<BasicTestDashboard> {
  final List<TestResult> _testResults = [];
  bool _isRunning = false;

  Future<void> _runBasicTest() async {
    setState(() => _isRunning = true);
    _testResults.clear();

    // Test EditTerminal basic functionality
    await _addTestResult('Edit Terminal Basic Test', () async {
      try {
        // Validate test environment
        final testDir = Directory('/tmp');
        if (!await testDir.exists()) {
          throw Exception('Test directory /tmp does not exist');
        }

        // Create editor with test content
        final editor = EditTerminal(
          filePath: '/tmp/basic_test.txt',
          initialContent: 'Test content for basic edit terminal',
          onSave: (content) async {
            if (content.isEmpty) {
              throw Exception('Content cannot be empty');
            }
            final file = File('/tmp/basic_test.txt');
            await file.writeAsString(content);
            debugPrint('File saved: ${file.path}');
          },
        );

        // Test that editor widget is created successfully
        if (editor.filePath == null) {
          throw Exception('Editor should have file path');
        }

        // Test text editing
        if (editor._controller == null) {
          throw Exception('Editor should have controller');
        }

        editor._controller.text = 'Basic test content';
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (editor._controller.text != 'Basic test content') {
          throw Exception('Text input failed: expected "Basic test content", got "${editor._controller.text}"');
        }

        // Test save functionality
        await editor._saveContent();
        
        // Verify file was saved
        final savedFile = File('/tmp/basic_test.txt');
        if (!await savedFile.exists()) {
          throw Exception('File was not saved');
        }
        
        final savedContent = await savedFile.readAsString();
        if (savedContent != 'Basic test content') {
          throw Exception('File content mismatch: expected "Basic test content", got "$savedContent"');
        }

        debugPrint('Save functionality tested and verified');
        return 'Basic test completed successfully';
      } catch (e) {
        debugPrint('Basic test error: $e');
        rethrow;
      }
    });

    setState(() => _isRunning = false);
  }

  Future<void> _addTestResult(String testName, Future<String> Function() test) async {
    _testResults.add(TestResult(
      name: testName,
      status: TestStatus.pending,
      result: null,
    ));

    setState(() {}); // Update UI to show pending status

    try {
      // Run the test
      final result = await test();
      
      setState(() {
        final index = _testResults.indexWhere((t) => t.name == testName);
        if (index != -1) {
          _testResults[index] = TestResult(
            name: testName,
            status: TestStatus.completed,
            result: result,
          );
        }
      });
      
      debugPrint('[TEST] $testName: PASSED');
    } catch (error, stackTrace) {
      setState(() {
        final index = _testResults.indexWhere((t) => t.name == testName);
        if (index != -1) {
          _testResults[index] = TestResult(
            name: testName,
            status: TestStatus.failed,
            result: 'Error: $error',
          );
        }
      });
      
      debugPrint('[TEST] $testName: FAILED - $error');
      debugPrint('[TEST] Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1e1e1e),
      appBar: AppBar(
        title: const Text('Edit Terminal Basic Test'),
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
                  onPressed: _isRunning ? null : _runBasicTest,
                  child: Text(_isRunning ? 'Running Test...' : 'Run Basic Test'),
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
