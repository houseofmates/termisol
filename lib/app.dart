import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ai/nvidia_ai_terminal_assistant.dart';
import 'config/production_config_system.dart';
import 'core/performance_enforcer.dart';
import 'core/production_gpu_renderer.dart';
import 'core/sub_16ms_latency_optimizer.dart';
import 'core/adaptive_frame_pacer.dart';
import 'core/background_processor.dart';
import 'core/memory_optimizer.dart';
import 'core/network_resilience.dart';
import 'core/session_sync_manager.dart';
import 'core/llm_plugin_system.dart';
import 'ui/gnome_integration.dart';
import 'ui/home_screen.dart';
import 'config/pkm_theme.dart';
// New imports for enhanced features
import 'core/smart_command_chaining.dart';
import 'core/semantic_search_engine.dart';
import 'core/enhanced_ai_suggestions.dart';
import 'core/conversational_ai.dart';
import 'core/automated_workflows.dart';
import 'vr/advanced_vr_terminal.dart';
import 'core/github_integration.dart';
import 'core/neural_processing.dart';
import 'core/terminal_pane_manager.dart';
import 'core/plugin_ecosystem.dart';

/// root application widget for termisol with production optimizations and advanced features.
class TermisolApp extends StatelessWidget {
  final NvidiaAITerminalAssistant aiAssistant;
  final PerformanceEnforcer performanceEnforcer;
  final ProductionGpuRenderer gpuRenderer;
  final Sub16msLatencyOptimizer latencyOptimizer;
  final AdaptiveFramePacer framePacer;
  final ProductionConfigSystem configSystem;
  final BackgroundProcessor backgroundProcessor;
  final MemoryOptimizer memoryOptimizer;
  final NetworkResilience networkResilience;
  final SessionSyncManager sessionSyncManager;
  final LLMPluginSystem llmPluginSystem;
  final GnomeIntegration gnomeIntegration;
  // Enhanced features
  final SmartCommandChaining smartCommandChaining;
  final SemanticSearchEngine semanticSearchEngine;
  final EnhancedAISuggestions enhancedAISuggestions;
  final ConversationalAI conversationalAI;
  final AutomatedWorkflowSystem automatedWorkflows;
  final AdvancedVRTerminal advancedVRTerminal;
  final GitHubIntegration githubIntegration;
  final NeuralProcessingSystem neuralProcessing;
  final TerminalPaneManager paneManager;
  final PluginManager pluginManager;

  const TermisolApp({
    super.key,
    required this.aiAssistant,
    required this.performanceEnforcer,
    required this.gpuRenderer,
    required this.latencyOptimizer,
    required this.framePacer,
    required this.configSystem,
    required this.backgroundProcessor,
    required this.memoryOptimizer,
    required this.networkResilience,
    required this.sessionSyncManager,
    required this.llmPluginSystem,
    required this.gnomeIntegration,
    // Enhanced features
    required this.smartCommandChaining,
    required this.semanticSearchEngine,
    required this.enhancedAISuggestions,
    required this.conversationalAI,
    required this.automatedWorkflows,
    required this.advancedVRTerminal,
    required this.githubIntegration,
    required this.neuralProcessing,
    required this.paneManager,
    required this.pluginManager,
  });

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.varelaRoundTextTheme(
      ThemeData.dark().textTheme,
    );

    return MaterialApp(
      title: 'termisol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: PkmTheme.primary,
          secondary: PkmTheme.secondary,
          surface: PkmTheme.popup,
          surfaceContainerHighest: PkmTheme.tabActiveBg,
        ),
        scaffoldBackgroundColor: PkmTheme.background,
        textTheme: baseTextTheme,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: PkmTheme.popup,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: PkmTheme.popup,
        ),
      ),
      home: HomeScreen(
        aiAssistant: aiAssistant,
        performanceEnforcer: performanceEnforcer,
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
        // Enhanced features
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
      ),
    );
  }
}
