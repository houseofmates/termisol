import 'dart:collection';

/// Lazy terminal output that buffers content and provides visibility tracking.
class LazyTerminalOutput {
  final String sessionId;
  final int visibleLines;
  final _buffer = Queue<String>();
  int _totalLines = 0;
  final bool _loading = false;
  bool _disposed = false;

  LazyTerminalOutput({required this.sessionId, required this.visibleLines});

  int get visibleLineCount => _buffer.length.clamp(0, visibleLines);
  bool get isLoading => _loading;
  int get totalLineCount => _totalLines;

  void addContent(dynamic data) {
    if (_disposed) return;
    final text = data?.toString() ?? '';
    if (text.isEmpty) return;

    final lines = text.split('\n');
    for (final line in lines) {
      _buffer.addLast(line);
      _totalLines++;
    }

    // Trim to reasonable memory bounds
    while (_buffer.length > visibleLines * 2) {
      _buffer.removeFirst();
    }
  }

  List<String> getVisibleContent() {
    if (_buffer.length <= visibleLines) return _buffer.toList();
    return _buffer.skip(_buffer.length - visibleLines).toList();
  }

  void dispose() {
    _disposed = true;
    _buffer.clear();
    _totalLines = 0;
  }
}
