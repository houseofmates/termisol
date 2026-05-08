import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:zlib/zlib.dart';

/// Compressed scrollback buffer with ring buffer implementation
/// 
/// Replaces the unbounded scrollback with a memory-efficient ring buffer
/// that uses compression to reduce memory footprint for long terminal sessions.
class CompressedScrollbackBuffer {
  final int maxLines;
  final int compressionThreshold;
  final bool enableCompression;
  
  // Ring buffer storage
  final List<ScrollbackChunk> _chunks;
  int _headIndex = 0;
  int _tailIndex = 0;
  int _currentSize = 0;
  
  // Compression
  final Map<int, Uint8List> _compressedCache = {};
  final Map<int, String> _textCache = {};
  Timer? _compressionTimer;
  
  // Performance metrics
  int _totalLines = 0;
  int _compressedChunks = 0;
  int _memoryUsage = 0;
  
  CompressedScrollbackBuffer({
    this.maxLines = 50000,
    this.compressionThreshold = 1000,
    this.enableCompression = true,
  }) : _chunks = List.generate(maxLines ~/ compressionThreshold + 1, (_) => ScrollbackChunk.empty()) {
    if (enableCompression) {
      _startCompressionTimer();
    }
  }
  
  /// Add a line to the scrollback buffer
  void addLine(String line, {TerminalLineStyle? style}) {
    final chunkIndex = _totalLines ~/ compressionThreshold;
    final lineInChunk = _totalLines % compressionThreshold;
    
    // Get or create chunk
    ScrollbackChunk chunk;
    if (_currentSize < _chunks.length) {
      chunk = _chunks[_headIndex];
    } else {
      // Ring buffer is full, overwrite oldest
      chunk = _chunks[_headIndex];
      _tailIndex = (_tailIndex + 1) % _chunks.length;
      _currentSize = _chunks.length;
    }
    
    // Add line to chunk
    chunk.addLine(lineInChunk, line, style: style);
    chunk.markDirty();
    
    // Update head position
    _headIndex = (_headIndex + 1) % _chunks.length;
    if (_currentSize < _chunks.length) {
      _currentSize++;
    }
    
    _totalLines++;
    
    // Trigger compression if needed
    if (enableCompression && chunk.lineCount >= compressionThreshold) {
      _scheduleCompression(chunkIndex);
    }
  }
  
  /// Get lines from scrollback buffer
  List<String> getLines(int startLine, int count) {
    final result = <String>[];
    var linesRemaining = count;
    var currentLine = startLine;
    
    while (linesRemaining > 0 && currentLine < _totalLines) {
      final chunkIndex = currentLine ~/ compressionThreshold;
      final lineInChunk = currentLine % compressionThreshold;
      
      if (_isValidChunkIndex(chunkIndex)) {
        final chunk = _getChunk(chunkIndex);
        final linesInChunk = math.min(linesRemaining, chunk.lineCount - lineInChunk);
        
        for (int i = 0; i < linesInChunk; i++) {
          final line = chunk.getLine(lineInChunk + i);
          if (line != null) {
            result.add(line);
          }
        }
        
        linesRemaining -= linesInChunk;
        currentLine += linesInChunk;
      } else {
        break;
      }
    }
    
    return result;
  }
  
  /// Get a specific line from scrollback
  String? getLine(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= _totalLines) {
      return null;
    }
    
    final chunkIndex = lineIndex ~/ compressionThreshold;
    final lineInChunk = lineIndex % compressionThreshold;
    
    if (_isValidChunkIndex(chunkIndex)) {
      final chunk = _getChunk(chunkIndex);
      return chunk.getLine(lineInChunk);
    }
    
    return null;
  }
  
  /// Search for text in scrollback
  List<ScrollbackMatch> searchText(String query, {bool caseSensitive = false}) {
    final matches = <ScrollbackMatch>[];
    final searchQuery = caseSensitive ? query : query.toLowerCase();
    
    for (int chunkIndex = 0; chunkIndex < _currentSize; chunkIndex++) {
      final chunk = _getChunk(chunkIndex);
      
      for (int lineInChunk = 0; lineInChunk < chunk.lineCount; lineInChunk++) {
        final line = chunk.getLine(lineInChunk);
        if (line != null) {
          final searchLine = caseSensitive ? line : line.toLowerCase();
          final index = searchLine.indexOf(searchQuery);
          
          if (index >= 0) {
            final globalLineIndex = chunkIndex * compressionThreshold + lineInChunk;
            matches.add(ScrollbackMatch(
              lineIndex: globalLineIndex,
              line: line,
              matchStart: index,
              matchEnd: index + query.length,
            ));
          }
        }
      }
    }
    
    return matches;
  }
  
  /// Clear scrollback buffer
  void clear() {
    for (final chunk in _chunks) {
      chunk.clear();
    }
    
    _headIndex = 0;
    _tailIndex = 0;
    _currentSize = 0;
    _totalLines = 0;
    
    _compressedCache.clear();
    _textCache.clear();
    _memoryUsage = 0;
  }
  
  /// Get buffer statistics
  ScrollbackStats getStats() {
    return ScrollbackStats(
      totalLines: _totalLines,
      maxLines: maxLines,
      chunkCount: _currentSize,
      compressedChunks: _compressedChunks,
      memoryUsage: _memoryUsage,
      compressionRatio: _calculateCompressionRatio(),
    );
  }
  
  /// Check if chunk index is valid
  bool _isValidChunkIndex(int chunkIndex) {
    if (_currentSize < _chunks.length) {
      return chunkIndex < _currentSize;
    } else {
      // Ring buffer is full, calculate actual index
      final actualIndex = (_tailIndex + chunkIndex) % _chunks.length;
      return actualIndex < _chunks.length;
    }
  }
  
  /// Get chunk by index (handles ring buffer)
  ScrollbackChunk _getChunk(int chunkIndex) {
    if (_currentSize < _chunks.length) {
      return _chunks[chunkIndex];
    } else {
      final actualIndex = (_tailIndex + chunkIndex) % _chunks.length;
      return _chunks[actualIndex];
    }
  }
  
  /// Start compression timer
  void _startCompressionTimer() {
    _compressionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _compressDirtyChunks();
    });
  }
  
  /// Schedule compression for a chunk
  void _scheduleCompression(int chunkIndex) {
    if (!_isValidChunkIndex(chunkIndex)) return;
    
    final chunk = _getChunk(chunkIndex);
    if (chunk.isDirty && !chunk.isCompressed) {
      _compressChunk(chunkIndex);
    }
  }
  
  /// Compress dirty chunks
  void _compressDirtyChunks() {
    for (int i = 0; i < _currentSize; i++) {
      final chunk = _getChunk(i);
      if (chunk.isDirty && !chunk.isCompressed) {
        _compressChunk(i);
      }
    }
  }
  
  /// Compress a single chunk
  void _compressChunk(int chunkIndex) {
    if (!enableCompression) return;
    
    final chunk = _getChunk(chunkIndex);
    if (chunk.lineCount == 0) return;
    
    try {
      // Serialize chunk data
      final jsonData = jsonEncode({
        'lines': chunk.lines,
        'styles': chunk.styles.map((s) => s?.toJson()).toList(),
      });
      
      // Compress the data
      final originalBytes = utf8.encode(jsonData);
      final compressedBytes = zlib.compress(originalBytes);
      
      // Cache compressed data
      _compressedCache[chunkIndex] = compressedBytes;
      chunk.isCompressed = true;
      chunk.markClean();
      
      _compressedChunks++;
      _memoryUsage = _calculateMemoryUsage();
      
      debugPrint('[scrollback] Compressed chunk $chunkIndex: ${originalBytes.length} -> ${compressedBytes.length} bytes');
      
    } catch (e) {
      debugPrint('[scrollback] Compression failed for chunk $chunkIndex: $e');
    }
  }
  
  /// Decompress a chunk
  void _decompressChunk(int chunkIndex) {
    if (!enableCompression) return;
    
    final compressedData = _compressedCache[chunkIndex];
    if (compressedData == null) return;
    
    try {
      // Decompress the data
      final decompressedBytes = zlib.decompress(compressedData);
      final jsonData = utf8.decode(decompressedBytes);
      
      // Parse chunk data
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final lines = (data['lines'] as List<dynamic>).cast<String>();
      final stylesData = (data['styles'] as List<dynamic>);
      
      // Restore chunk
      final chunk = _getChunk(chunkIndex);
      chunk.lines = lines;
      chunk.styles = stylesData.map((s) => s != null ? TerminalLineStyle.fromJson(s) : null).toList();
      chunk.isCompressed = false;
      
      _compressedChunks--;
      _memoryUsage = _calculateMemoryUsage();
      
    } catch (e) {
      debugPrint('[scrollback] Decompression failed for chunk $chunkIndex: $e');
    }
  }
  
  /// Calculate memory usage
  int _calculateMemoryUsage() {
    int total = 0;
    
    // Count uncompressed chunks
    for (int i = 0; i < _currentSize; i++) {
      final chunk = _getChunk(i);
      if (!chunk.isCompressed) {
        total += chunk.lines.length * 100; // Estimate 100 bytes per line
        total += chunk.styles.length * 20; // Estimate 20 bytes per style
      }
    }
    
    // Add compressed data size
    for (final compressed in _compressedCache.values) {
      total += compressed.length;
    }
    
    return total;
  }
  
  /// Calculate compression ratio
  double _calculateCompressionRatio() {
    if (_compressedChunks == 0) return 0.0;
    
    int originalSize = 0;
    int compressedSize = 0;
    
    for (int i = 0; i < _currentSize; i++) {
      final chunk = _getChunk(i);
      if (chunk.isCompressed) {
        originalSize += chunk.lines.length * 100; // Estimate
        compressedSize += _compressedCache[i]?.length ?? 0;
      }
    }
    
    return originalSize > 0 ? compressedSize / originalSize : 0.0;
  }
  
  /// Dispose resources
  void dispose() {
    _compressionTimer?.cancel();
    clear();
    _compressedCache.clear();
    _textCache.clear();
  }
}

/// Scrollback chunk containing multiple lines
class ScrollbackChunk {
  List<String> lines = [];
  List<TerminalLineStyle?> styles = [];
  bool isDirty = false;
  bool isCompressed = false;
  
  ScrollbackChunk();
  
  factory ScrollbackChunk.empty() => ScrollbackChunk();
  
  int get lineCount => lines.length;
  
  void addLine(int index, String line, {TerminalLineStyle? style}) {
    // Ensure arrays are large enough
    while (lines.length <= index) {
      lines.add('');
      styles.add(null);
    }
    
    lines[index] = line;
    styles[index] = style;
    isDirty = true;
  }
  
  String? getLine(int index) {
    if (index >= 0 && index < lines.length) {
      return lines[index];
    }
    return null;
  }
  
  void markDirty() => isDirty = true;
  void markClean() => isDirty = false;
  
  void clear() {
    lines.clear();
    styles.clear();
    isDirty = false;
    isCompressed = false;
  }
}

/// Terminal line style information
class TerminalLineStyle {
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  
  const TerminalLineStyle({
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });
  
  factory TerminalLineStyle.fromJson(Map<String, dynamic> json) {
    return TerminalLineStyle(
      foreground: json['foreground'] != null ? Color(int.parse(json['foreground'])) : null,
      background: json['background'] != null ? Color(int.parse(json['background'])) : null,
      bold: json['bold'] ?? false,
      italic: json['italic'] ?? false,
      underline: json['underline'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'foreground': foreground?.value.toString(),
      'background': background?.value.toString(),
      'bold': bold,
      'italic': italic,
      'underline': underline,
    };
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TerminalLineStyle &&
        other.foreground == foreground &&
        other.background == background &&
        other.bold == bold &&
        other.italic == italic &&
        other.underline == underline;
  }
  
  @override
  int get hashCode {
    return foreground.hashCode ^
        background.hashCode ^
        bold.hashCode ^
        italic.hashCode ^
        underline.hashCode;
  }
}

/// Scrollback search match
class ScrollbackMatch {
  final int lineIndex;
  final String line;
  final int matchStart;
  final int matchEnd;
  
  ScrollbackMatch({
    required this.lineIndex,
    required this.line,
    required this.matchStart,
    required this.matchEnd,
  });
  
  String get matchedText => line.substring(matchStart, matchEnd);
  String get context {
    final start = math.max(0, matchStart - 20);
    final end = math.min(line.length, matchEnd + 20);
    return line.substring(start, end);
  }
}

/// Scrollback buffer statistics
class ScrollbackStats {
  final int totalLines;
  final int maxLines;
  final int chunkCount;
  final int compressedChunks;
  final int memoryUsage;
  final double compressionRatio;
  
  const ScrollbackStats({
    required this.totalLines,
    required this.maxLines,
    required this.chunkCount,
    required this.compressedChunks,
    required this.memoryUsage,
    required this.compressionRatio,
  });
  
  double get utilization => totalLines / maxLines;
  double get compressionEfficiency => 1.0 - compressionRatio;
  
  @override
  String toString() {
    return 'ScrollbackStats(lines=$totalLines/$maxLines, chunks=$chunkCount, compressed=$compressedChunks, memory=${memoryUsage}B, ratio=${(compressionRatio * 100).toStringAsFixed(1)}%)';
  }
}
