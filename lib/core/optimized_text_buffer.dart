/// Optimized text buffer
class OptimizedTextBuffer {
  OptimizedTextBuffer({required int maxLines});

  int get cursorPosition => 0;
  Map<String, dynamic> get stats => {};

  String getVisibleText(int maxLines) => '';

  void clear() {
    // Stub implementation
  }
}