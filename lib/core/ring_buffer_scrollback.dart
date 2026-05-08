import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// High-performance ring buffer for terminal scrollback with memory optimization
/// Prevents memory exhaustion and provides configurable limits with compression
class RingBufferScrollback {
  final int maxLines;
  final int compressionThreshold;
  final int gcThreshold;
  
  late final List<TerminalLine> _buffer;
  int _head = 0;
  int _tail = 0;
  int _size = 0;
  bool _isFull = false;
  
  // Memory optimization
  final Map<int, Uint8List> _compressedLines = {};
  Timer? _gcTimer;
  int _lastGcTime = 0;
  
  // Performance metrics
  int _totalLinesAdded = 0;
  int _totalLinesCompressed = 0;
  int _totalLinesEvicted = 0;
  final _metricsController = StreamController<ScrollbackMetrics>.broadcast();

  RingBufferScrollback({
    this.maxLines = 50000,
    this.compressionThreshold = 10000,
    this.gcThreshold = 75000,
  }) : _buffer = List<TerminalLine>.filled(maxLines, TerminalLine.fromText('')) {
    _startGcTimer();
  }

  /// Stream of scrollback performance metrics
  Stream<ScrollbackMetrics> get metrics => _metricsController.stream;

  /// Add a new line to the scrollback buffer
  void addLine(TerminalLine line) {
    if (_isFull) {
      // Compress old line before overwriting
      _compressLine(_tail);
      _tail = (_tail + 1) % maxLines;
      _totalLinesEvicted++;
    }
    
    _buffer[_head] = line;
    _head = (_head + 1) % maxLines;
    _size = (_size + 1).clamp(0, maxLines);
    _isFull = _size >= maxLines;
    _totalLinesAdded++;
    
    // Trigger compression if threshold reached
    if (_totalLinesAdded >= compressionThreshold) {
      _compressOldLines();
    }
  }

  /// Get a line by index (0 = newest, size-1 = oldest)
  TerminalLine? getLine(int index) {
    if (index < 0 || index >= _size) return null;
    
    int actualIndex;
    if (_isFull) {
      actualIndex = (_head - 1 - index + maxLines) % maxLines;
    } else {
      actualIndex = _head - 1 - index;
      if (actualIndex < 0) return null;
    }
    
    final line = _buffer[actualIndex];
    if (line.isCompressed) {
      return _decompressLine(line);
    }
    return line;
  }

  /// Get the most recent N lines
  List<TerminalLine> getRecentLines(int count) {
    final result = <TerminalLine>[];
    final actualCount = count < _size ? count : _size;
    
    for (int i = 0; i < actualCount; i++) {
      final line = getLine(i);
      if (line != null) {
        result.add(line);
      }
    }
    
    return result;
  }

  /// Search for lines containing the specified text
  List<int> searchLines(String pattern, {bool caseSensitive = false}) {
    final results = <int>[];
    final searchPattern = caseSensitive ? pattern : pattern.toLowerCase();
    
    for (int i = 0; i < _size; i++) {
      final line = getLine(i);
      if (line != null) {
        final text = line.getText();
        final searchText = caseSensitive ? text : text.toLowerCase();
        if (searchText.contains(searchPattern)) {
          results.add(i);
        }
      }
    }
    
    return results;
  }

  /// Clear all lines
  void clear() {
    _head = 0;
    _tail = 0;
    _size = 0;
    _isFull = false;
    _compressedLines.clear();
    _totalLinesAdded = 0;
    _totalLinesCompressed = 0;
    _totalLinesEvicted = 0;
  }

  /// Get current buffer statistics
  ScrollbackMetrics getMetrics() {
    return ScrollbackMetrics(
      totalLines: _size,
      maxLines: maxLines,
      compressedLines: _compressedLines.length,
      totalLinesAdded: _totalLinesAdded,
      totalLinesCompressed: _totalLinesCompressed,
      totalLinesEvicted: _totalLinesEvicted,
      memoryUsage: _estimateMemoryUsage(),
      isFull: _isFull,
    );
  }

  /// Compress old lines to save memory
  void _compressOldLines() {
    if (_size < compressionThreshold) return;
    
    final linesToCompress = compressionThreshold ~/ 2;
    final startIndex = (_tail + linesToCompress) % maxLines;
    
    for (int i = 0; i < linesToCompress; i++) {
      final index = (startIndex + i) % maxLines;
      final line = _buffer[index];
      if (line != null && !line.isCompressed) {
        _compressLine(index);
      }
    }
    
    _totalLinesCompressed += linesToCompress;
  }

  /// Compress a single line
  void _compressLine(int index) {
    final line = _buffer[index];
    if (line == null || line.isCompressed) return;
    
    try {
      final text = line.getText();
      final compressed = gzip.encode(utf8.encode(text));
      final compressedBytes = Uint8List.fromList(compressed);
      _compressedLines[index] = compressedBytes;
      
      // Replace with compressed data marker
      _buffer[index] = TerminalLine.compressed(
        index: index,
        compressedData: compressedBytes,
        originalLength: text.length,
      );
    } catch (e) {
      debugPrint('[scrollback] Failed to compress line $index: $e');
    }
  }

  /// Decompress a compressed line
  TerminalLine _decompressLine(TerminalLine compressedLine) {
    if (!compressedLine.isCompressed) return compressedLine;
    
    try {
      final decompressed = utf8.decode(gzip.decode(compressedLine.compressedData!));
      return TerminalLine.fromText(decompressed);
    } catch (e) {
      debugPrint('[scrollback] Failed to decompress line: $e');
      return TerminalLine.fromText('<decompression error>');
    }
  }

  /// Estimate memory usage in bytes
  int _estimateMemoryUsage() {
    int totalSize = 0;
    
    // Buffer size
    totalSize += _size * 1024; // Rough estimate per line
    
    // Compressed lines
    for (final compressed in _compressedLines.values) {
      totalSize += compressed.length;
    }
    
    return totalSize;
  }

  /// Start garbage collection timer
  void _startGcTimer() {
    _gcTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _performGarbageCollection();
    });
  }

  /// Perform garbage collection on old compressed lines
  void _performGarbageCollection() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGcTime < 300000) return; // Don't GC more than once per 5 minutes
    
    _lastGcTime = now;
    
    // Remove very old compressed lines if memory is high
    if (_estimateMemoryUsage() > gcThreshold * 1024) {
      final linesToRemove = _compressedLines.length ~/ 4;
      final keysToRemove = _compressedLines.keys.take(linesToRemove).toList();
      
      for (final key in keysToRemove) {
        _compressedLines.remove(key);
        _buffer[key] = TerminalLine.fromText(''); // Clear the reference
      }
      
      debugPrint('[scrollback] GC removed $linesToRemove old compressed lines');
    }
    
    _emitMetrics();
  }

  /// Emit current metrics
  void _emitMetrics() {
    _metricsController.add(getMetrics());
  }

  /// Dispose resources
  void dispose() {
    _gcTimer?.cancel();
    _metricsController.close();
    _compressedLines.clear();
    clear();
  }
}

/// Enhanced terminal line with compression support
class TerminalLine {
  final String text;
  final List<TerminalCell> cells;
  final DateTime timestamp;
  final bool isCompressed;
  final Uint8List? compressedData;
  final int originalLength;

  TerminalLine({
    required this.text,
    required this.cells,
    required this.timestamp,
    this.isCompressed = false,
    this.compressedData,
    this.originalLength = 0,
  });

  factory TerminalLine.fromText(String text) {
    final cells = _parseCells(text);
    return TerminalLine(
      text: text,
      cells: cells,
      timestamp: DateTime.now(),
    );
  }

  factory TerminalLine.compressed({
    required int index,
    required Uint8List compressedData,
    required int originalLength,
  }) {
    return TerminalLine(
      text: '',
      cells: [],
      timestamp: DateTime.now(),
      isCompressed: true,
      compressedData: compressedData,
      originalLength: originalLength,
    );
  }

  String getText() {
    if (isCompressed) {
      throw StateError('Cannot get text from compressed line directly');
    }
    return text;
  }

  List<TerminalCell> getCells() {
    if (isCompressed) {
      throw StateError('Cannot get cells from compressed line directly');
    }
    return cells;
  }

  static List<TerminalCell> _parseCells(String text) {
    // Simplified cell parsing - in a real implementation, this would parse ANSI codes
    return text.split('').map((char) => TerminalCell(char: char)).toList();
  }
}

/// Terminal cell representation
class TerminalCell {
  final String char;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool underline;

  TerminalCell({
    required this.char,
    this.foreground,
    this.background,
    this.bold = false,
    this.underline = false,
  });
}

/// Color representation for terminal cells
class Color {
  final int r, g, b;
  
  const Color(this.r, this.g, this.b);
  
  factory Color.fromHex(String hex) {
    final value = int.parse(hex.substring(1), radix: 16);
    return Color(
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    );
  }
}

/// Scrollback performance metrics
class ScrollbackMetrics {
  final int totalLines;
  final int maxLines;
  final int compressedLines;
  final int totalLinesAdded;
  final int totalLinesCompressed;
  final int totalLinesEvicted;
  final int memoryUsage;
  final bool isFull;
  final DateTime timestamp;

  ScrollbackMetrics({
    required this.totalLines,
    required this.maxLines,
    required this.compressedLines,
    required this.totalLinesAdded,
    required this.totalLinesCompressed,
    required this.totalLinesEvicted,
    required this.memoryUsage,
    required this.isFull,
  }) : timestamp = DateTime.now();

  double get memoryUsageMB => memoryUsage / (1024 * 1024);
  double get compressionRatio => totalLines > 0 ? compressedLines / totalLines : 0;
  double get bufferUtilization => maxLines > 0 ? totalLines / maxLines : 0;

  Map<String, dynamic> toJson() => {
    'totalLines': totalLines,
    'maxLines': maxLines,
    'compressedLines': compressedLines,
    'totalLinesAdded': totalLinesAdded,
    'totalLinesCompressed': totalLinesCompressed,
    'totalLinesEvicted': totalLinesEvicted,
    'memoryUsage': memoryUsage,
    'memoryUsageMB': memoryUsageMB,
    'compressionRatio': compressionRatio,
    'bufferUtilization': bufferUtilization,
    'isFull': isFull,
    'timestamp': timestamp.toIso8601String(),
  };
}
