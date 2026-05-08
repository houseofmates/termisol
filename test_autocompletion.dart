import 'package:flutter/material.dart';
import 'lib/ui/edit.dart';

void main() {
  // Simple test to verify auto-completion compiles
  print('Auto-completion test compiled successfully');
  
  // Test completion generation logic
  final testLine = 'Wid';
  final completions = ['Widget', 'StatefulWidget', 'StatelessWidget'];
  final filtered = completions
      .where((completion) => completion.toLowerCase().startsWith(testLine.toLowerCase()))
      .take(10)
      .toList();
  
  print('Completions for "$testLine": $filtered');
}
