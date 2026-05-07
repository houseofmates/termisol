import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'optimized_text_buffer.dart';

/// Lazy terminal output with optimized rendering
class LazyTerminalOutput {
  final OptimizedTextBuffer _buffer;
  final LazyLoadingManager _loadingManager;
  final String _sessionId;
  final int _visibleLines;
  final int _totalLines;
  bool _isLoading = false;

  LazyTerminalOutput({
    required String sessionId,
    required int visibleLines,
  }) : _buffer = OptimizedTextBuffer(maxLines: 5000),
         _loadingManager = LazyLoadingManager(),
         _sessionId = sessionId,
         _visibleLines = visibleLines,
         _totalLines = 0;

  /// Add content to terminal output
  void addContent(List<String> lines) {
    _totalLines += lines.length;
    
    // Add to buffer
    for (final line in lines) {
      _buffer.append(line);
    }
    
    // Update lazy loading manager
    _loadingManager.addContent(_sessionId, lines);
    
    // Trigger loading animation
    _isLoading = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      _isLoading = false;
    });
  }

  /// Get visible content for rendering
  LazyContent get content => _loadingManager.getContent(_sessionId);

  /// Get visible lines count
  int get visibleLineCount => _visibleLines;

  /// Get total lines count
  int get totalLineCount => _totalLines;

  /// Check if currently loading
  bool get isLoading => _isLoading;

  /// Scroll to specific line
  void scrollToLine(int lineNumber) {
    final content = _loadingManager.getContent(_sessionId);
    final targetIndex = lineNumber.clamp(0, content.lines.length - 1);
    
    // Update buffer cursor position
    _buffer._startLine = targetIndex - (_visibleLines ~/ 2);
    _buffer._cursorPosition = targetIndex;
    
    // Scroll to position
    content.scrollController.animateTo(
      targetIndex * 20.0, // Approximate line height
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Search in terminal content
  List<int> search(String pattern, {bool caseSensitive = false}) {
    final content = _loadingManager.getContent(_sessionId);
    return _buffer.search(pattern, caseSensitive: caseSensitive);
  }

  /// Get buffer statistics
  BufferStats get stats => _buffer.stats;

  /// Clear all content
  void clear() {
    _buffer.clear();
    _totalLines = 0;
    _loadingManager.clearCache(_sessionId);
  }

  /// Dispose resources
  void dispose() {
    _buffer.clear();
    _loadingManager.clearCache(_sessionId);
  }
}
