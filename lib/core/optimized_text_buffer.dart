import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Optimized circular buffer for terminal text output
/// 
/// Features:
/// - Circular buffer with configurable size
/// - Efficient memory usage
/// - Fast append operations
/// - Line-based access
/// - Scrolling support
/// - Search functionality
class OptimizedTextBuffer {
  final List<String> _lines;
  final int _maxLines;
  int _startLine = 0;
  int _cursorPosition = 0;
  
  OptimizedTextBuffer({
    required int maxLines,
  }) : _lines = List.filled(maxLines, ''),
         _maxLines = maxLines;

  /// Add text to buffer
  void append(String text) {
    if (text.isEmpty) return;
    
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      _addLine(lines[i]);
    }
  }

  /// Add a single line to buffer
  void _addLine(String line) {
    final currentLine = _startLine + _lines.length - _maxLines;
    if (currentLine >= _maxLines) {
      // Remove oldest line to make space
      _lines.removeAt(0);
      _startLine = (_startLine - 1) % _maxLines;
    }
    
    if (currentLine < _lines.length) {
      _lines[currentLine] = line;
    } else {
      _lines.add(line);
    }
    
    _cursorPosition = _lines.length - 1;
  }

  /// Get all lines in current view window
  List<String> getVisibleLines(int windowSize) {
    final start = _startLine;
    final end = (_startLine + windowSize).clamp(0, _lines.length);
    return _lines.sublist(start, end);
  }

  /// Get text in current view window
  String getVisibleText(int windowSize) {
    return getVisibleLines(windowSize).join('\n');
  }

  /// Clear buffer
  void clear() {
    _lines.clear();
    _startLine = 0;
    _cursorPosition = 0;
  }

  /// Scroll up by specified number of lines
  void scrollUp(int lines) {
    _startLine = (_startLine - lines).clamp(0, _lines.length - 1);
    _cursorPosition = (_cursorPosition - lines).clamp(0, _lines.length - 1);
  }

  /// Scroll down by specified number of lines
  void scrollDown(int lines) {
    _startLine = (_startLine + lines).clamp(0, _lines.length - 1);
    _cursorPosition = (_cursorPosition + lines).clamp(0, _lines.length - 1);
  }

  /// Search for text in buffer
  List<int> search(String pattern, {bool caseSensitive = false}) {
    final searchPattern = caseSensitive ? pattern : pattern.toLowerCase();
    final results = <int>[];
    
    for (int i = 0; i < _lines.length; i++) {
      final line = caseSensitive ? _lines[i] : _lines[i].toLowerCase();
      final index = line.indexOf(searchPattern);
      if (index != -1) {
        results.add(i);
      }
    }
    
    return results;
  }

  /// Get buffer statistics
  BufferStats get stats => BufferStats(
    totalLines: _lines.length,
    usedLines: _lines.where((line) => line.isNotEmpty).length,
    memoryUsage: _lines.length * 50, // Approximate bytes per line
    cursorPosition: _cursorPosition,
    startLine: _startLine,
  );
}

/// Buffer statistics for monitoring
class BufferStats {
  final int totalLines;
  final int usedLines;
  final int memoryUsage;
  final int cursorPosition;
  final int startLine;

  const BufferStats({
    required this.totalLines,
    required this.usedLines,
    required this.memoryUsage,
    required this.cursorPosition,
    required this.startLine,
  });
}
