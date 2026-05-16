import 'dart:collection';

/// Optimized text buffer with bounded history and fast line access.
class OptimizedTextBuffer {
  final int maxLines;
  final _lines = Queue<String>();
  int _totalChars = 0;
  bool _disposed = false;

  OptimizedTextBuffer({required this.maxLines});

  int get cursorPosition => _totalChars;

  Map<String, dynamic> get stats => {
        'lineCount': _lines.length,
        'totalChars': _totalChars,
        'maxLines': maxLines,
      };

  String getVisibleText(int maxLines) {
    if (_lines.isEmpty) return '';
    final start = _lines.length > maxLines ? _lines.length - maxLines : 0;
    return _lines.skip(start).join('\n');
  }

  void append(String data) {
    if (_disposed) return;
    final split = data.split('\n');
    for (final line in split) {
      _lines.addLast(line);
      _totalChars += line.length;
    }
    _trim();
  }

  void clear() {
    _lines.clear();
    _totalChars = 0;
  }

  void _trim() {
    while (_lines.length > maxLines) {
      final removed = _lines.removeFirst();
      _totalChars -= removed.length;
    }
    if (_totalChars < 0) _totalChars = 0;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}