import 'package:flutter/material.dart';
import 'lib/ui/edit.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1e1e1e),
        body: EditTerminal(
          filePath: '/test.txt',
          initialContent:
              'Test content\nLine 2\nLine 3\n' *
              50, // Multiple lines to test scrolling
        ),
      ),
    );
  }
}
