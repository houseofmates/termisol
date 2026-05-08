// Stub implementation for NvidiaAITerminalAssistant
class NvidiaAITerminalAssistant {
  Future<AIServiceResponse> processText({
    required String input,
    required AICapability capability,
    required String contextId,
    bool preferLocal = true,
  }) async {
    // Stub implementation
    return AIServiceResponse(
      success: true,
      output: 'AI response stub',
      confidence: 0.8,
      processingTime: Duration(milliseconds: 100),
    );
  }
}

class AIServiceResponse {
  final bool success;
  final String output;
  final double confidence;
  final Duration processingTime;

  AIServiceResponse({
    required this.success,
    required this.output,
    required this.confidence,
    required this.processingTime,
  });
}

enum AICapability {
  textGeneration,
  codeCompletion,
  terminalCommand,
  fileAnalysis,
}