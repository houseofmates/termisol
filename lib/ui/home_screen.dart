import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';
import '../config/pkm_theme.dart';
import '../core/adaptive_frame_pacer.dart';
import '../core/automated_workflows.dart';
import '../core/background_processor.dart';
import '../core/conversational_ai.dart';
import '../core/enhanced_ai_suggestions.dart';
import '../core/github_integration.dart';
import '../core/llm_plugin_system.dart';
import '../core/memory_optimizer.dart';
import '../core/network_resilience.dart';
import '../core/neural_processing.dart';
import '../core/performance_enforcer.dart';
import '../core/plugin_ecosystem.dart';
import '../core/production_gpu_renderer.dart';
import '../core/semantic_search_engine.dart';
import '../core/session_sync_manager.dart';
import '../core/smart_command_chaining.dart';
import '../core/speech_service.dart';
import '../core/sub_16ms_latency_optimizer.dart';
import '../core/terminal_session.dart';
import '../config/production_config_system.dart';
import '../ui/gnome_integration.dart';
import '../ui/connection_profiles.dart';
import '../ui/search_overlay.dart';
import '../ui/settings_sheet.dart';
import '../core/terminal_pane_manager.dart' as pane_mod;
import '../vr/advanced_vr_terminal.dart';

class HomeScreen extends StatefulWidget {
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
  final SmartCommandChaining smartCommandChaining;
  final SemanticSearchEngine semanticSearchEngine;
  final EnhancedAISuggestions enhancedAISuggestions;
  final ConversationalAI conversationalAI;
  final AutomatedWorkflowSystem automatedWorkflows;
  final AdvancedVRTerminal advancedVRTerminal;
  final GitHubIntegration githubIntegration;
  final NeuralProcessingSystem neuralProcessing;
  final PluginManager pluginManager;
  final pane_mod.TerminalPaneManager paneManager;

  const HomeScreen({
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
    required this.smartCommandChaining,
    required this.semanticSearchEngine,
    required this.enhancedAISuggestions,
    required this.conversationalAI,
    required this.automatedWorkflows,
    required this.advancedVRTerminal,
    required this.githubIntegration,
    required this.neuralProcessing,
    required this.pluginManager,
    required this.paneManager,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<TerminalSession> _sessions = [];
  final Map<int, FocusNode> _sessionFocusNodes = {};
  final Map<int, TextEditingController> _renameControllers = {};
  final Map<int, bool> _renaming = {};
  final Map<int, bool> _searchVisible = {};
  int _activeIndex = 0;
  bool _showConnections = false;
  bool _showFps = false;

  @override
  void initState() {
    super.initState();
    widget.aiAssistant.initialize();
    widget.llmPluginSystem.initialize();
    widget.pluginManager.initialize();
    widget.performanceEnforcer.addListener(_onPerformanceUpdate);
    _createInitialSession();
  }

  void _createInitialSession() {
    final session = TerminalSession(id: '0', name: 'local');
    session.terminal.write('\r\n\x1b[32mtermisol ready.\x1b[0m\r\n\r\n');
    session.terminal.write('\x1b[2mtype /ai <query> for AI assistance\x1b[0m\r\n\r\n');
    session.onAiQuery = _handleAiQuery;
    session.start();

    _sessions.add(session);
    _sessionFocusNodes[0] = FocusNode();
    _renameControllers[0] = TextEditingController(text: 'local');
    _renaming[0] = false;
    _searchVisible[0] = false;
    _activeIndex = 0;
  }

  Future<String> _handleAiQuery(String query) async {
    try {
      final result = await widget.aiAssistant.processAiQuery(query);
      return result;
    } catch (e) {
      return 'AI error: $e';
    }
  }

  void _onPerformanceUpdate() {
    if (mounted) setState(() {});
  }

  void _toggleFps() {
    setState(() => _showFps = !_showFps);
  }

  void _addLocalSession() {
    final id = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final idx = _sessions.length;
    final session = TerminalSession(id: id, name: 'local-$idx');
    session.onAiQuery = _handleAiQuery;
    session.start();

    setState(() {
      _sessions.add(session);
      _sessionFocusNodes[idx] = FocusNode();
      _renameControllers[idx] = TextEditingController(text: 'local-$idx');
      _renaming[idx] = false;
      _searchVisible[idx] = false;
      _activeIndex = idx;
    });
    _sessionFocusNodes[idx]?.requestFocus();
  }

  void _switchToIndex(int index) {
    if (index >= 0 && index < _sessions.length) {
      setState(() => _activeIndex = index);
      _sessionFocusNodes[index]?.requestFocus();
    }
  }

  void _closeSession(int index) {
    if (_sessions.length <= 1 || index < 0 || index >= _sessions.length) return;

    _sessions[index].dispose();
    _sessionFocusNodes[index]?.dispose();
    _renameControllers[index]?.dispose();

    setState(() {
      _sessions.removeAt(index);
      _sessionFocusNodes.remove(index);
      _renameControllers.remove(index);
      _renaming.remove(index);
      _searchVisible.remove(index);

      final newActive = _activeIndex >= index
          ? (_activeIndex - 1).clamp(0, _sessions.length - 1)
          : _activeIndex;
      _activeIndex = newActive;

      _reindexMaps();
    });
  }

  void _reindexMaps() {
    final sessions = List<TerminalSession>.from(_sessions);
    final focusNodes = Map<int, FocusNode>.from(_sessionFocusNodes);
    final renameCtrls = Map<int, TextEditingController>.from(_renameControllers);
    final renaming = Map<int, bool>.from(_renaming);
    final searchVisible = Map<int, bool>.from(_searchVisible);

    _sessionFocusNodes.clear();
    _renameControllers.clear();
    _renaming.clear();
    _searchVisible.clear();

    final focusValues = focusNodes.values.toList();
    final renameValues = renameCtrls.values.toList();
    final renamingValues = renaming.values.toList();
    final searchValues = searchVisible.values.toList();

    for (var i = 0; i < sessions.length; i++) {
      _sessionFocusNodes[i] = i < focusValues.length ? focusValues[i] : FocusNode();
      _renameControllers[i] = i < renameValues.length
          ? renameValues[i]
          : TextEditingController(text: sessions[i].name);
      _renaming[i] = i < renamingValues.length ? renamingValues[i] : false;
      _searchVisible[i] = i < searchValues.length ? searchValues[i] : false;
    }
  }

  void _startRename(int index) {
    setState(() {
      _renaming[index] = true;
      _renameControllers[index]?.text = _sessions[index].name;
    });
  }

  void _finishRename(int index) {
    final newName = _renameControllers[index]?.text.trim() ?? '';
    if (newName.isNotEmpty) {
      _sessions[index].rename(newName);
    }
    setState(() => _renaming[index] = false);
  }

  void _toggleSearch(int index) {
    setState(() => _searchVisible[index] = !(_searchVisible[index] ?? false));
  }

  Future<void> _createPluginWithAI() async {
    final result = await showDialog<PluginCreationData>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PluginCreationDialog(),
    );

    if (result == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PkmTheme.popup,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: PkmTheme.primary),
            const SizedBox(height: 16),
            Text(
              'Generating plugin with DeepSeek V4 Pro...',
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontUi,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final creationResult = await widget.pluginManager.createPluginWithAI(
        description: result.description,
        pluginName: result.name,
        category: result.category,
        features: result.features,
      );

      Navigator.of(context).pop();

      if (creationResult.success &&
          creationResult.pluginCode != null &&
          creationResult.metadata != null) {
        final install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: PkmTheme.popup,
            title: Text(
              'Plugin Created!',
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plugin: \x24{creationResult.metadata!.name}',
                  style: TextStyle(color: PkmTheme.primary, fontFamily: PkmTheme.fontUi),
                ),
                const SizedBox(height: 4),
                Text(
                  creationResult.metadata!.description,
                  style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  'Install this plugin now?',
                  style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: PkmTheme.primary),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Install', style: TextStyle(color: Colors.black, fontFamily: PkmTheme.fontUi)),
              ),
            ],
          ),
        );

        if (install == true) {
          final installed = await widget.pluginManager.installGeneratedPlugin(
            creationResult.pluginCode!,
            creationResult.metadata!,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  installed ? 'Plugin installed!' : 'Failed to install plugin',
                  style: TextStyle(fontFamily: PkmTheme.fontUi),
                ),
                backgroundColor: PkmTheme.popup,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: PkmTheme.popup,
              title: Text('Plugin Creation Failed', style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi)),
              content: Text(
                creationResult.error ?? 'Unknown error',
                style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('OK', style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      Navigator.of(context).pop();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: PkmTheme.popup,
            title: Text('Error', style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi)),
            content: Text('\x24e', style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi)),
              ),
            ],
          ),
        );
      }
    }
  }

  void _openAiDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PkmTheme.popup,
        title: Row(
          children: [
            const Icon(Icons.smart_toy, color: PkmTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'AI Assistant',
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontUi,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            style: TextStyle(
              color: PkmTheme.text,
              fontFamily: PkmTheme.fontTerminal,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Ask anything...',
              hintStyle: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: PkmTheme.primary),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: PkmTheme.primary),
            onPressed: () {
              Navigator.pop(ctx);
              if (controller.text.isNotEmpty) {
                _handleAiQuery(controller.text);
              }
            },
            child: Text('Send', style: TextStyle(color: Colors.black, fontFamily: PkmTheme.fontUi)),
          ),
        ],
      ),
    );
  }

  void _toggleDictation() {
    final speech = SpeechService();
    if (speech.isListening) {
      speech.stop();
    } else {
      speech.listen(onResult: (text, isFinal) {
        if (_sessions.isNotEmpty && text.isNotEmpty) {
          _sessions[_activeIndex].terminal.write(text);
        }
      });
    }
  }

  void _openSearch() {
    if (_sessions.isEmpty) return;
    setState(() => _searchVisible[_activeIndex] = true);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsSheet(),
    );
  }

  void _openConnections() {
    setState(() => _showConnections = true);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyT:
            _addLocalSession();
            return KeyEventResult.handled;
        }
      } else {
        switch (event.logicalKey) {
          case LogicalKeyboardKey.keyT:
            _addLocalSession();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyW:
            if (_sessions.length > 1) _closeSession(_activeIndex);
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyF:
            _searchVisible[_activeIndex] = true;
            setState(() {});
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyK:
            _openAiDialog();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyD:
            _toggleDictation();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.comma:
            _openSettings();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.altLeft:
          case LogicalKeyboardKey.altRight:
            break;
        }
      }
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      for (var i = 1; i <= 9 && i <= _sessions.length; i++) {
        if (event.logicalKey.keyId >= LogicalKeyboardKey.digit0.keyId + i &&
            event.logicalKey.keyId <= LogicalKeyboardKey.digit9.keyId) {
          _switchToIndex(i - 1);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.digit0) {
        _switchToIndex(_sessions.length - 1);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: PkmTheme.background,
        body: _showConnections
            ? ConnectionProfiles(
                onConnect: (session) {
                  final idx = _sessions.length;
                  session.onAiQuery = _handleAiQuery;
                  setState(() {
                    _sessions.add(session);
                    _sessionFocusNodes[idx] = FocusNode();
                    _renameControllers[idx] =
                        TextEditingController(text: session.name);
                    _renaming[idx] = false;
                    _searchVisible[idx] = false;
                    _activeIndex = idx;
                    _showConnections = false;
                  });
                },
              )
            : Column(
                children: [
                  _buildToolbar(),
                  _buildTabBar(),
                  _buildTerminalArea(),
                  if (_showFps) _buildFpsOverlay(),
                ],
              ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 44,
      color: PkmTheme.terminalBg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _openConnections,
            icon: const Icon(Icons.power_settings_new, size: 18),
            color: PkmTheme.primary,
            tooltip: 'New Connection',
          ),
          IconButton(
            onPressed: _addLocalSession,
            icon: const Icon(Icons.add, size: 18),
            color: PkmTheme.primary,
            tooltip: 'New Local Tab (Ctrl+T)',
          ),
          const SizedBox(width: 4),
          Text(
            'termisol',
            style: TextStyle(
              color: PkmTheme.primary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const Spacer(),
          Text(
            '\x24{widget.performanceEnforcer.currentFps.toStringAsFixed(1)} fps',
            style: TextStyle(
              color: PkmTheme.primary.withOpacity(0.7),
              fontSize: 10,
              fontFamily: PkmTheme.fontTerminal,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _toggleDictation,
            icon: Icon(
              SpeechService().isListening ? Icons.mic : Icons.mic_none,
              size: 16,
            ),
            color: SpeechService().isListening ? Colors.redAccent : PkmTheme.primary,
            tooltip: 'Dictation (Ctrl+D)',
          ),
          IconButton(
            onPressed: _openAiDialog,
            icon: const Icon(Icons.smart_toy, size: 16),
            color: PkmTheme.primary,
            tooltip: 'AI Assistant (Ctrl+K)',
          ),
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search, size: 16),
            color: PkmTheme.primary,
            tooltip: 'Search (Ctrl+F)',
          ),
          IconButton(
            onPressed: _toggleFps,
            icon: Icon(
              _showFps ? Icons.speed : Icons.speed_outlined,
              size: 16,
            ),
            color: _showFps ? Colors.red : PkmTheme.primary,
            tooltip: 'Toggle FPS',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 16),
            color: PkmTheme.primary,
            tooltip: 'Settings (Ctrl+,)',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: PkmTheme.tabBarHeight,
      color: PkmTheme.tabActiveBg,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isActive = _activeIndex == index;
                final isRenaming = _renaming[index] ?? false;

                return GestureDetector(
                  onTap: () => _switchToIndex(index),
                  onSecondaryTap: () => _closeSession(index),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? PkmTheme.tabActiveBg : PkmTheme.tabInactiveBg,
                      border: Border(
                        top: BorderSide(
                          color: isActive ? PkmTheme.primary : Colors.transparent,
                          width: 2,
                        ),
                        right: BorderSide(
                          color: PkmTheme.primary.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                    ),
                    child: isRenaming
                        ? SizedBox(
                            width: 140,
                            height: 28,
                            child: TextField(
                              controller: _renameControllers[index],
                              autofocus: true,
                              style: TextStyle(
                                color: PkmTheme.text,
                                fontFamily: PkmTheme.fontUi,
                                fontSize: 12,
                              ),
                              decoration: const InputDecoration(
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                border: OutlineInputBorder(),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: PkmTheme.primary),
                                ),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _finishRename(index),
                              onTapOutside: (_) => _finishRename(index),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _sessions[index].connected
                                    ? Icons.circle
                                    : Icons.circle_outlined,
                                size: 8,
                                color: _sessions[index].connected
                                    ? PkmTheme.statusConnected
                                    : PkmTheme.statusDisconnected,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  session.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isActive ? PkmTheme.primary : PkmTheme.text,
                                    fontWeight:
                                        isActive ? FontWeight.bold : FontWeight.normal,
                                    fontFamily: PkmTheme.fontUi,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _closeSession(index),
                                child: Icon(
                                  Icons.close,
                                  size: 12,
                                  color: PkmTheme.secondary.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            onPressed: () => _startRename(_activeIndex),
            icon: const Icon(Icons.edit, size: 14),
            color: PkmTheme.primary.withOpacity(0.6),
            tooltip: 'Rename Tab',
            splashRadius: 14,
          ),
          IconButton(
            onPressed: _addLocalSession,
            icon: const Icon(Icons.add, size: 16),
            color: PkmTheme.primary,
            tooltip: 'New Tab (Ctrl+T)',
            splashRadius: 14,
          ),
          IconButton(
            onPressed: _createPluginWithAI,
            icon: const Icon(Icons.smart_toy, size: 16),
            color: PkmTheme.primary,
            tooltip: 'Create Plugin with AI',
            splashRadius: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalArea() {
    if (_sessions.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal, color: PkmTheme.primary, size: 48),
              const SizedBox(height: 16),
              Text(
                'no sessions open',
                style: TextStyle(
                  color: PkmTheme.primary,
                  fontFamily: PkmTheme.fontUi,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ctrl+T to create a new session',
                style: TextStyle(
                  color: PkmTheme.secondary,
                  fontFamily: PkmTheme.fontUi,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: Stack(
        children: [
          IndexedStack(
            index: _activeIndex,
            children: _sessions.map((session) {
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () =>
                            _toggleSearch(_sessions.indexOf(session)),
                        icon: const Icon(Icons.search, size: 14),
                        color: PkmTheme.primary.withOpacity(0.5),
                        tooltip: 'Search Buffer (Ctrl+F)',
                        splashRadius: 14,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: Colors.black,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          if (_searchVisible[_activeIndex] == true)
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              child: TerminalSearchOverlay(
                terminal: _sessions[_activeIndex].terminal,
                onClose: () =>
                    setState(() => _searchVisible[_activeIndex] = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFpsOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'FPS: \x24{widget.performanceEnforcer.currentFps.toStringAsFixed(1)}',
            style: TextStyle(
              color: Colors.greenAccent,
              fontFamily: PkmTheme.fontTerminal,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Frame: \x24{widget.performanceEnforcer.currentFrameTime.toStringAsFixed(1)}ms',
            style: TextStyle(
              color: PkmTheme.secondary,
              fontFamily: PkmTheme.fontTerminal,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    for (final node in _sessionFocusNodes.values) {
      node.dispose();
    }
    for (final ctrl in _renameControllers.values) {
      ctrl.dispose();
    }
    widget.performanceEnforcer.removeListener(_onPerformanceUpdate);
    widget.aiAssistant.dispose();
    widget.pluginManager.dispose();
    widget.llmPluginSystem.dispose();
    super.dispose();
  }
}

class _PluginCreationDialog extends StatefulWidget {
  const _PluginCreationDialog();

  @override
  State<_PluginCreationDialog> createState() => _PluginCreationDialogState();
}

class _PluginCreationDialogState extends State<_PluginCreationDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _featuresController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _featuresController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PkmTheme.popup,
      title: Text(
        'Create Plugin with AI',
        style: TextStyle(
          color: PkmTheme.text,
          fontFamily: PkmTheme.fontUi,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Describe what you want your plugin to do, and DeepSeek V4 Pro will generate the code for you.',
              style: TextStyle(
                color: PkmTheme.secondary,
                fontFamily: PkmTheme.fontUi,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Plugin Name',
                labelStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                hintText: 'My Awesome Plugin',
                hintStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: PkmTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Plugin Description',
                labelStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                hintText: 'Describe what this plugin should do in detail...',
                hintStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: PkmTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Category (optional)',
                labelStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                hintText: 'utility, productivity, development, etc.',
                hintStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: PkmTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _featuresController,
              maxLines: 2,
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Key Features (optional)',
                labelStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                hintText: 'One feature per line...',
                hintStyle: TextStyle(
                    color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: PkmTheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
                color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: PkmTheme.primary,
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            if (_nameController.text.isEmpty ||
                _descriptionController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Please fill in plugin name and description',
                    style: TextStyle(fontFamily: PkmTheme.fontUi),
                  ),
                  backgroundColor: PkmTheme.popup,
                ),
              );
              return;
            }

            final features = _featuresController.text.isEmpty
                ? null
                : _featuresController.text
                    .split('\n')
                    .where((f) => f.trim().isNotEmpty)
                    .toList();

            Navigator.pop(
              context,
              PluginCreationData(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                category: _categoryController.text.trim().isEmpty
                    ? null
                    : _categoryController.text.trim(),
                features: features,
              ),
            );
          },
          child: Text(
            'Generate Plugin',
            style: TextStyle(fontFamily: PkmTheme.fontUi),
          ),
        ),
      ],
    );
  }
}

class PluginCreationData {
  final String name;
  final String description;
  final String? category;
  final List<String>? features;

  PluginCreationData({
    required this.name,
    required this.description,
    this.category,
    this.features,
  });
}
