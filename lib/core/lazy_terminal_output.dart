/// Lazy terminal output
class LazyTerminalOutput {
  LazyTerminalOutput({required String sessionId, required int visibleLines});

  int get visibleLineCount => 0;
  bool get isLoading => false;
  int get totalLineCount => 0;

  void dispose() {
    // Stub implementation
  }
}