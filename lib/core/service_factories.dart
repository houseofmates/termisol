import '../ai/ai_terminal_assistant.dart';
import '../core/production_config_system.dart';

/// real service factories for termisol.
/// only factories for services that are actually used in the working ui path.
class ServiceFactories {
  /// Create AI terminal assistant using cloud APIs.
  static NvidiaAITerminalAssistant createAIAssistant() {
    return NvidiaAITerminalAssistant();
  }

  /// Create production config system.
  static ProductionConfigSystem createConfigSystem() {
    return ProductionConfigSystem();
  }
}
