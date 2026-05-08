/// stub for ai assistant integration.
enum AICapability {
  text_generation,
  code_completion,
  command_suggestion,
  error_analysis,
}

class AIAssistantIntegration {
  Future<AIResponse> processText({
    required String input,
    required AICapability capability,
    String? contextId,
    bool preferLocal = false,
  }) async {
    return AIResponse(success: false, output: 'ai not configured');
  }
}

class AIResponse {
  final bool success;
  final String? output;
  final dynamic metadata;

  AIResponse({required this.success, this.output, this.metadata});
}
