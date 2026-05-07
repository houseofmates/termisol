import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/ai/nvidia_ai_terminal_assistant.dart';
import 'package:termisol/ai/ai_terminal_assistant.dart';
import 'package:termisol/core/nvidia_ai_client.dart';
import 'package:termisol/core/performance_enforcer.dart';
import 'package:termisol/core/production_gpu_renderer.dart';
import 'package:termisol/core/sub_16ms_latency_optimizer.dart';
import 'package:termisol/core/adaptive_frame_pacer.dart';
import 'package:termisol/config/production_config_system.dart';
import 'package:termisol/core/background_processor.dart';
import 'package:termisol/core/memory_optimizer.dart';
import 'package:termisol/core/network_resilience.dart';
import 'package:termisol/core/session_sync_manager.dart';
import 'package:termisol/core/llm_plugin_system.dart';
import 'package:termisol/ui/gnome_integration.dart';
import 'package:termisol/core/smart_command_chaining.dart';
import 'package:termisol/core/semantic_search_engine.dart';
import 'package:termisol/core/enhanced_search_engine.dart';
import 'package:termisol/core/enhanced_ai_suggestions.dart';
import 'package:termisol/core/conversational_ai.dart';
import 'package:termisol/core/automated_workflows.dart';
import 'package:termisol/vr/advanced_vr_terminal.dart';
import 'package:termisol/core/github_integration.dart';
import 'package:termisol/core/git_integration.dart';
import 'package:termisol/core/neural_processing.dart';
import 'package:termisol/core/terminal_pane_manager.dart';
import 'package:termisol/core/plugin_ecosystem.dart';
import 'package:termisol/core/terminal_pane_manager.dart';

void main() {
  group('App Integration', () {
    test('app widget can be instantiated', () async {
      final aiClient = NvidiaAIClient();
      final aiAssistant = NvidiaAITerminalAssistant(aiClient);
      final perf = PerformanceEnforcer();
      final gpuRenderer = ProductionGpuRenderer();
      final latencyOptimizer = Sub16msLatencyOptimizer();
      final framePacer = AdaptiveFramePacer();
      final configSystem = await ProductionConfigSystem.initialize();

      // Initialize core systems
      final backgroundProcessor = BackgroundProcessor();
      final memoryOptimizer = MemoryOptimizer();
      final networkResilience = NetworkResilience();
      final sessionSyncManager = SessionSyncManager();
      final llmPluginSystem = LLMPluginSystem();
      final gnomeIntegration = GnomeIntegration();

      await backgroundProcessor.initialize();
      await memoryOptimizer.initialize();
      await networkResilience.initialize();
      await sessionSyncManager.initialize();
      await llmPluginSystem.initialize();
      await gnomeIntegration.initialize();

      // Initialize enhanced systems
      final aiBaseAssistant = AITerminalAssistant();
      await aiBaseAssistant.initialize();

      final smartCommandChaining = SmartCommandChaining();
      final enhancedSearchEngine = EnhancedSearchEngine();
      final semanticSearchEngine = SemanticSearchEngine(enhancedSearchEngine, aiBaseAssistant);
      final enhancedAISuggestions = EnhancedAISuggestions(aiBaseAssistant);
      final conversationalAI = ConversationalAI(aiBaseAssistant, smartCommandChaining, semanticSearchEngine, enhancedAISuggestions);
      final automatedWorkflows = AutomatedWorkflowSystem(smartCommandChaining, conversationalAI);
      final advancedVRTerminal = AdvancedVRTerminal(
        conversationalAI: conversationalAI,
        workflowSystem: automatedWorkflows,
        aiSuggestions: enhancedAISuggestions,
        terminalWidget: const SizedBox(),
      );
      final gitIntegration = GitIntegration();
    final githubIntegration = GitHubIntegration(gitIntegration, conversationalAI, semanticSearchEngine);
    final neuralProcessing = NeuralProcessingSystem(aiBaseAssistant);
    final paneManager = TerminalPaneManager();
    final pluginManager = PluginManager();

      await smartCommandChaining.initialize();
      await semanticSearchEngine.initialize();
      await enhancedAISuggestions.initialize();
      await conversationalAI.initialize();
      await automatedWorkflows.initialize();
      await githubIntegration.initialize();
      await neuralProcessing.initialize();
      await paneManager.initialize();
      await pluginManager.initialize();

      final app = TermisolApp(
        aiAssistant: aiAssistant,
        performanceEnforcer: perf,
        gpuRenderer: gpuRenderer,
        latencyOptimizer: latencyOptimizer,
        framePacer: framePacer,
        configSystem: configSystem,
        backgroundProcessor: backgroundProcessor,
        memoryOptimizer: memoryOptimizer,
        networkResilience: networkResilience,
        sessionSyncManager: sessionSyncManager,
        llmPluginSystem: llmPluginSystem,
        gnomeIntegration: gnomeIntegration,
        smartCommandChaining: smartCommandChaining,
        semanticSearchEngine: semanticSearchEngine,
        enhancedAISuggestions: enhancedAISuggestions,
        conversationalAI: conversationalAI,
        automatedWorkflows: automatedWorkflows,
        advancedVRTerminal: advancedVRTerminal,
        githubIntegration: githubIntegration,
        neuralProcessing: neuralProcessing,
        paneManager: paneManager,
        pluginManager: pluginManager,
      );

      expect(app, isNotNull);
    });
  });
}
