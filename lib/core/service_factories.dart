import '../ai/ai_terminal_assistant.dart';
import '../core/production_config_system.dart';

/// real service factories for termisol.
/// only factories for services that are actually used in the working ui path.
class ServiceFactories {
  /// create ai terminal assistant using cloud apis.
  static NvidiaAITerminalAssistant createAIAssistant() {
    return NvidiaAITerminalAssistant();
  }

  /// create production config system.
  static ProductionConfigSystem createConfigSystem() {
    return ProductionConfigSystem();
  }
}
