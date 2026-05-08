/// Lazy terminal output
class LazyTerminalOutput {
  LazyTerminalOutput({required String sessionId, required int visibleLines});

  int get visibleLineCount => 0;
  bool get isLoading => false;

  void dispose() {
    // Stub implementation
  }
}