import 'dart:async';
import 'dart:io';
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
import '../core/audio_alert_service.dart';
import '../core/keyboard_macro_reader.dart' hide KeyEvent;
import '../core/sync_services.dart';
import '../core/docker_operations.dart';
import '../core/integrated_debugger_nim.dart';
import '../core/task_runner.dart';
import '../core/configurable_hotkeys.dart';
import '../core/smooth_animations.dart';
import '../core/auto_backup_system.dart';
import '../core/auto_ssh_key_management.dart' hide KeyEvent;
import '../core/multihop_ssh.dart';
import '../core/tunnel_management.dart';
import '../core/ssh_connection_persistence.dart';
import '../core/code_intelligence.dart';
import '../core/context_aware_prompt_optimizer.dart';
import '../core/session_recovery.dart';
import '../core/command_guard.dart';
import '../core/asciicast_recorder.dart';
import '../ui/edit.dart';
import '../ui/file_browser.dart';
import '../ui/file_viewer.dart';
import '../core/session_persistence.dart';
import '../core/crash_recovery.dart';
import '../core/long_command_notifier.dart';
import '../core/termisol_plugin_system.dart';

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
  final AudioAlertService audioAlertService;
  final KeyboardMacroReader keyboardMacroReader;
  final SyncServices syncServices;
  final DockerOperations dockerOperations;
  final IntegratedDebugger integratedDebugger;
  final TaskRunner taskRunner;
  final ConfigurableHotkeys configurableHotkeys;
  final SmoothAnimations smoothAnimations;
  final AutoBackupSystem autoBackupSystem;
  final AutoSSHKeyManagement autoSshKeyManagement;
  final MultihopSSH multihopSsh;
  final TunnelManagement tunnelManagement;
  final SSHConnectionPersistence sshConnectionPersistence;
  final CodeIntelligence codeIntelligence;
  final DatabaseClient databaseClient;
  final SessionRecovery sessionRecovery;
  final CommandGuard commandGuard;
  final AsciicastRecorder asciicastRecorder;
  final SessionPersistence sessionPersistence;
  final CrashRecovery crashRecovery;
  final LongCommandNotifier commandNotifier;
  final TermisolPluginSystem pluginSystem;

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
    required this.audioAlertService,
    required this.keyboardMacroReader,
    required this.syncServices,
    required this.dockerOperations,
    required this.integratedDebugger,
    required this.taskRunner,
    required this.configurableHotkeys,
    required this.smoothAnimations,
    required this.autoBackupSystem,
    required this.autoSshKeyManagement,
    required this.multihopSsh,
    required this.tunnelManagement,
    required this.sshConnectionPersistence,
    required this.codeIntelligence,
    required this.databaseClient,
    required this.sessionRecovery,
    required this.commandGuard,
    required this.asciicastRecorder,
    required this.sessionPersistence,
    required this.crashRecovery,
    required this.commandNotifier,
    required this.pluginSystem,
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
  bool _showFileBrowser = false;
  bool _showDockerPanel = false;
  bool _showDebugger = false;
  bool _showSyncPanel = false;
  bool _showMacroRecorder = false;
  bool _showDatabasePanel = false;
  bool _showGuardPanel = false;
  bool _showViewer = false;
  String? _viewerFilePath;
  final FileViewer _fileViewer = FileViewer();

  @override
  void initState() {
    super.initState();
    widget.aiAssistant.initialize();
    widget.llmPluginSystem.initialize();
    widget.pluginManager.initialize();
    widget.performanceEnforcer.addListener(_onPerformanceUpdate);
    
    // Initialize optimization systems
    _initializeOptimizationSystems();
    
    if (widget.sessionRecovery.wasRecovered) {
      _restoreRecoveredSession();
    } else {
      _createInitialSession();
    }
    
    // Check for crash recovery
    _checkCrashRecovery();
  }

  /// Initialize optimization systems
  void _initializeOptimizationSystems() {
    // Start crash recovery monitoring
    widget.crashRecovery._startHealthMonitoring();
    
    // Start session persistence auto-save
    widget.sessionPersistence.startAutoSave(() {
      _saveAllSessions();
    });
    
    // Load plugins
    _loadOptimizationPlugins();
  }

  /// Check for crash recovery
  Future<void> _checkCrashRecovery() async {
    if (await widget.crashRecovery.needsRecovery()) {
      final crashLog = await widget.crashRecovery.getCrashLog();
      if (crashLog.isNotEmpty) {
        // Show crash recovery dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Crash Recovery'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Termisol detected a previous crash.'),
                const SizedBox(height: 8),
                Text('Crash log: ${crashLog.first}'),
                const SizedBox(height: 8),
                const Text('Would you like to recover your sessions?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _restoreRecoveredSession();
                },
                child: const Text('Recover'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.crashRecovery.clearCrashLog();
                },
                child: const Text('Start Fresh'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Load optimization plugins
  Future<void> _loadOptimizationPlugins() async {
    // Load built-in optimization plugins
    final pluginPaths = [
      '/home/house/termisol/plugins/text_optimization.tisol',
      '/home/house/termisol/plugins/memory_optimization.tisol',
      '/home/house/termisol/plugins/performance_optimization.tisol',
    ];
    
    for (final pluginPath in pluginPaths) {
      try {
        await widget.pluginSystem.loadPlugin(pluginPath);
      } catch (e) {
        print('Failed to load plugin $pluginPath: $e');
      }
    }
  }

  /// Save all sessions
  Future<void> _saveAllSessions() async {
    final sessionDataList = _sessions.map((session) => TerminalSessionData(
      id: session.id,
      name: session.name,
      type: 'local',
      state: session.getSessionStats(),
      timestamp: DateTime.now(),
    )).toList();
    
    await widget.sessionPersistence.saveSessions(sessionDataList);
  }

  void _restoreRecoveredSession() {
    for (final tab in widget.sessionRecovery.tabs) {
      final session = TerminalSession(id: tab.id, name: tab.name);
      session.start();
      session.onAiQuery = _handleAiQuery;
      _sessions.add(session);
      final idx = _sessions.length - 1;
      _sessionFocusNodes[idx] = FocusNode();
      _renameControllers[idx] = TextEditingController(text: tab.name);
      _renaming[idx] = false;
      _searchVisible[idx] = false;
    }
    if (_sessions.isNotEmpty) {
      _activeIndex = 0;
    }
  }

  void _createInitialSession() {
    final session = TerminalSession(id: '0', name: 'local');
    session.terminal.write('\r\n\x1b[32mtermisol ready.\x1b[0m\r\n\r\n');
    session.terminal.write('\x1b[2mtype /ai <query> for AI assistance\x1b[0m\r\n');
    session.terminal.write('\x1b[2mtype edit <filename> to open editor\x1b[0m\r\n\r\n');
    session.onAiQuery = _handleAiQuery;
    session.onEditCommand = _handleEditCommand;
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

  Future<void> _handleEditCommand(String filename) async {
    try {
      // Get the current working directory from the active session
      final activeSession = _sessions[_activeIndex];
      final workingDirectory = Directory.current.path;
      
      // Construct full file path
      String fullPath;
      if (filename.startsWith('/')) {
        fullPath = filename;
      } else if (filename.startsWith('~')) {
        fullPath = filename.replaceFirst('~', Platform.environment['HOME'] ?? '');
      } else {
        fullPath = '$workingDirectory/$filename';
      }
      
      // Read file content if it exists
      String fileContent = '';
      final file = File(fullPath);
      if (await file.exists()) {
        fileContent = await file.readAsString();
      }
      
      // Show the edit terminal
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            child: EditTerminal(
              filePath: fullPath,
              initialContent: fileContent,
              onSave: (content) async {
                await file.writeAsString(content);
                // Show success message in terminal
                activeSession.terminal.write('\r\n\x1b[32m[EDIT] Saved: $fullPath\x1b[0m\r\n');
              },
              readOnly: false,
            ),
          ),
        ),
      );
    } catch (e) {
      // Show error in terminal
      final activeSession = _sessions[_activeIndex];
      activeSession.terminal.write('\r\n\x1b[31m[EDIT] Error: $e\x1b[0m\r\n');
    }
  }

  void _onPerformanceUpdate() {
    if (mounted) setState(() {});
  }

  void _addLocalSession() {
    final id = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final idx = _sessions.length;
    final session = TerminalSession(id: id, name: 'local-$idx');
    session.onAiQuery = _handleAiQuery;
    session.onEditCommand = _handleEditCommand;
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

  void _toggleAsciicastRecording() {
    widget.asciicastRecorder.toggleRecording();
    setState(() {});
  }

  void _openSearch() {
    if (_sessions.isEmpty) return;
    setState(() => _searchVisible[_activeIndex] = true);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SettingsSheet(performanceEnforcer: widget.performanceEnforcer),
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
          case LogicalKeyboardKey.keyP:
            _toggleAsciicastRecording();
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
            : Row(
                children: [
                  if (_showFileBrowser)
                    FileBrowser(
                      rootPath: '/home/house',
                      onFileSelected: (path) {
                        if (_sessions.isNotEmpty) {
                          _sessions[_activeIndex].terminal.write('$path ');
                        }
                      },
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildToolbar(),
                        _buildTabBar(),
                        _buildTerminalArea(),
                      ],
                    ),
                  ),
                  if (_showDockerPanel) _buildDockerPanel(),
                  if (_showDebugger) _buildDebuggerPanel(),
                  if (_showSyncPanel) _buildSyncPanel(),
                  if (_showMacroRecorder) _buildMacroPanel(),
                  if (_showDatabasePanel) _buildDatabasePanel(),
                  if (_showGuardPanel) _buildGuardPanel(),
                  if (_showViewer && _viewerFilePath != null)
                    FutureBuilder<FileViewResult>(
                      future: _fileViewer.openFile(_viewerFilePath!),
                      builder: (ctx, snap) {
                        if (!snap.hasData) return const SizedBox();
                        return Container(
                          width: 500,
                          color: const Color(0xFF0a0a0a),
                          child: FileViewerWidget(result: snap.data!),
                        );
                      },
                    ),
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
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 16),
            color: PkmTheme.primary,
            tooltip: 'Settings (Ctrl+,)',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() => _showFileBrowser = !_showFileBrowser),
            icon: const Icon(Icons.folder_open, size: 16),
            color: _showFileBrowser ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'File Browser',
          ),
          IconButton(
            onPressed: () => setState(() => _showDockerPanel = !_showDockerPanel),
            icon: const Icon(Icons.dock, size: 16),
            color: _showDockerPanel ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Docker Manager',
          ),
          IconButton(
            onPressed: () => setState(() => _showDebugger = !_showDebugger),
            icon: const Icon(Icons.bug_report, size: 16),
            color: _showDebugger ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Debugger',
          ),
          IconButton(
            onPressed: () => setState(() => _showSyncPanel = !_showSyncPanel),
            icon: const Icon(Icons.sync, size: 16),
            color: _showSyncPanel ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Sync Services',
          ),
          IconButton(
            onPressed: () => setState(() => _showMacroRecorder = !_showMacroRecorder),
            icon: const Icon(Icons.keyboard, size: 16),
            color: _showMacroRecorder ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Macro Recorder',
          ),
          IconButton(
            onPressed: () => setState(() => _showDatabasePanel = !_showDatabasePanel),
            icon: const Icon(Icons.storage, size: 16),
            color: _showDatabasePanel ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Database Client',
          ),
          IconButton(
            onPressed: () => setState(() => _showGuardPanel = !_showGuardPanel),
            icon: const Icon(Icons.security, size: 16),
            color: _showGuardPanel ? PkmTheme.primary : PkmTheme.primary.withOpacity(0.5),
            tooltip: 'Command Guard',
          ),
          IconButton(
            onPressed: () => _toggleAsciicastRecording(),
            icon: Icon(
              widget.asciicastRecorder.isRecording ? Icons.stop : Icons.videocam,
              size: 16,
            ),
            color: widget.asciicastRecorder.isRecording ? Colors.red : PkmTheme.primary,
            tooltip: 'Record Session (Ctrl+P)',
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

  Widget _buildDockerPanel() {
    return Container(
      width: 320,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dock, size: 14, color: Color(0xFF7CB9FF)),
                const SizedBox(width: 8),
                const Text('docker manager',
                  style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showDockerPanel = false),
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _dockerStatusRow('host', '192.168.4.233'),
                _dockerStatusRow('status', widget.dockerOperations.isConnected ? 'connected' : 'disconnected'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7CB9FF), foregroundColor: Colors.black),
                  onPressed: () {
                    widget.dockerOperations.connect(username: 'house', passwordOrKey: '');
                  },
                  icon: const Icon(Icons.link, size: 14),
                  label: const Text('connect to .233', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1a1a1a), foregroundColor: const Color(0xFF999999)),
                  onPressed: () {},
                  icon: const Icon(Icons.list, size: 14),
                  label: const Text('list containers', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockerStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 10)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFF999999), fontSize: 10, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildDebuggerPanel() {
    return Container(
      width: 320,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bug_report, size: 14, color: Color(0xFF7CB9FF)),
                const SizedBox(width: 8),
                const Text('debugger',
                  style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showDebugger = false),
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text('session ready\ndeepseek-v4-pro analyzer',
                textAlign: TextAlign.center,
                style: TextStyle(color: PkmTheme.secondary.withOpacity(0.5), fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncPanel() {
    return Container(
      width: 320,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sync, size: 14, color: Color(0xFF7CB9FF)),
                const SizedBox(width: 8),
                const Text('sync services',
                  style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showSyncPanel = false),
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _syncServiceRow('github', 'syncing to GitHub remote', 'active'),
                _syncServiceRow('n8n', 'workflow automation sync', 'idle'),
                _syncServiceRow('devices', 'ubuntu + pixel 10 pro + quest 2', 'connected'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7CB9FF), foregroundColor: Colors.black),
                  onPressed: () {},
                  icon: const Icon(Icons.cloud_sync, size: 14),
                  label: const Text('sync now', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _syncServiceRow(String name, String desc, String status) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: status == 'active' ? Colors.green : const Color(0xFF666666),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Color(0xFF999999), fontSize: 10)),
              Text(desc, style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroPanel() {
    return Container(
      width: 280,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.keyboard, size: 14, color: Color(0xFF7CB9FF)),
                const SizedBox(width: 8),
                const Text('macros',
                  style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showMacroRecorder = false),
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (widget.keyboardMacroReader.macros.isEmpty)
                  const Center(
                    child: Text('no macros recorded',
                      style: TextStyle(color: Color(0xFF666666), fontSize: 10)),
                  )
                else
                  ...widget.keyboardMacroReader.macros.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow, size: 12, color: Color(0xFF666666)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(m.name, style: const TextStyle(color: Color(0xFF999999), fontSize: 10)),
                        ),
                        Text('${m.keyCount}k', style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
                      ],
                    ),
                  )),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.keyboardMacroReader.isRecording ? Colors.red : const Color(0xFF7CB9FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    if (widget.keyboardMacroReader.isRecording) {
                      widget.keyboardMacroReader.cancelRecording();
                      setState(() {});
                    } else {
                      widget.keyboardMacroReader.startRecording('macro_${DateTime.now().millisecond}');
                      setState(() {});
                    }
                  },
                  icon: Icon(
                    widget.keyboardMacroReader.isRecording ? Icons.stop : Icons.fiber_manual_record,
                    size: 14,
                  ),
                  label: Text(
                    widget.keyboardMacroReader.isRecording ? 'stop recording' : 'record macro',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabasePanel() {
    final dbCtrl = TextEditingController();
    final queryCtrl = TextEditingController();

    return StatefulBuilder(builder: (ctx, setDbState) {
      final profiles = widget.databaseClient.profiles;
      return Container(
        width: 500,
        color: const Color(0xFF0a0a0a),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storage, size: 14, color: Color(0xFF7CB9FF)),
                  const SizedBox(width: 8),
                  const Text('database client',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _showDatabasePanel = false),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  const Text('add profile', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: dbCtrl,
                        style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11),
                        decoration: const InputDecoration(
                          hintText: 'profile name',
                          hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 11),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFF1a1a1a),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2a2a2a)),
                      onPressed: () => widget.databaseClient.addProfile(
                        name: dbCtrl.text, type: DbType.sqlite, filePath: '/home/house/${dbCtrl.text}.db',
                      ).then((_) { dbCtrl.clear(); setDbState(() {}); }),
                      child: const Text('+ sqlite', style: TextStyle(fontSize: 10, color: Color(0xFF999999))),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2a2a2a)),
                      onPressed: () => widget.databaseClient.addProfile(
                        name: dbCtrl.text, type: DbType.postgresql,
                        host: 'localhost', database: dbCtrl.text, username: 'postgres',
                      ).then((_) { dbCtrl.clear(); setDbState(() {}); }),
                      child: const Text('+ pg', style: TextStyle(fontSize: 10, color: Color(0xFF999999))),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (profiles.isNotEmpty) ...[
                    const Text('profiles', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                    ...profiles.map((p) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(p.type == DbType.postgresql ? Icons.dns : Icons.sd_card, size: 12, color: const Color(0xFF7CB9FF)),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${p.name} (${p.type.name})', style: const TextStyle(color: Color(0xFF999999), fontSize: 10))),
                          TextButton(
                            onPressed: () => widget.databaseClient.connect(p.id).then((_) => setDbState(() {})),
                            child: Text('connect', style: TextStyle(color: widget.databaseClient.activeProfile?.id == p.id ? Colors.green : const Color(0xFF7CB9FF), fontSize: 10)),
                          ),
                          TextButton(
                            onPressed: () => widget.databaseClient.removeProfile(p.id).then((_) => setDbState(() {})),
                            child: const Text('del', style: TextStyle(color: Color(0xFF666666), fontSize: 10)),
                          ),
                        ],
                      ),
                    )),
                  ],
                  if (widget.databaseClient.activeProfile != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF1a1a1a)),
                    const Text('query', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: queryCtrl,
                          style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11),
                          decoration: const InputDecoration(
                            hintText: 'SELECT * FROM ...',
                            hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 11),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: Color(0xFF1a1a1a),
                          ),
                          onSubmitted: (sql) {
                            widget.databaseClient.executeQuery(sql).then((r) {
                              setDbState(() {});
                            }).catchError((_) { setDbState(() {}); });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7CB9FF)),
                        onPressed: () {
                          widget.databaseClient.executeQuery(queryCtrl.text).then((_) => setDbState(() {})).catchError((_) { setDbState(() {}); });
                        },
                        child: const Text('run', style: TextStyle(fontSize: 10, color: Colors.black)),
                      ),
                    ]),
                  ],
                  if (widget.databaseClient.history.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF1a1a1a)),
                    const Text('history', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                    ...widget.databaseClient.history.take(10).map((h) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        h.sql.length > 60 ? '${h.sql.substring(0, 60)}...' : h.sql,
                        style: TextStyle(
                          color: h.success ? const Color(0xFF999999) : Colors.red.withOpacity(0.7),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildGuardPanel() {
    final patternCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    return StatefulBuilder(builder: (ctx, setGuardState) {
      return Container(
        width: 380,
        color: const Color(0xFF0a0a0a),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, size: 14, color: Color(0xFF7CB9FF)),
                  const SizedBox(width: 8),
                  const Text('command guard',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Switch(
                    value: widget.commandGuard.isEnabled,
                    onChanged: (_) {
                      widget.commandGuard.toggleEnabled();
                      setGuardState(() {});
                    },
                    activeColor: const Color(0xFF7CB9FF),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _showGuardPanel = false),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  const Text('add rule', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: patternCtrl,
                    style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: 'pattern (e.g. rm -rf)',
                      hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 11),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFF1a1a1a),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11),
                    decoration: const InputDecoration(
                      hintText: 'description (optional)',
                      hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 11),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFF1a1a1a),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7CB9FF)),
                    onPressed: () {
                      if (patternCtrl.text.isNotEmpty) {
                        widget.commandGuard.addRule(
                          pattern: patternCtrl.text,
                          description: descCtrl.text.isEmpty ? null : descCtrl.text,
                        ).then((_) {
                          patternCtrl.clear();
                          descCtrl.clear();
                          setGuardState(() {});
                        });
                      }
                    },
                    child: const Text('add rule', style: TextStyle(fontSize: 10, color: Colors.black)),
                  ),
                  const SizedBox(height: 10),
                  if (widget.commandGuard.rules.isEmpty)
                    Text('no rules defined \u2014 all commands allowed',
                      style: TextStyle(color: PkmTheme.secondary.withOpacity(0.5), fontSize: 10))
                  else ...[
                    const Text('rules', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
                    ...widget.commandGuard.rules.map((r) => Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a1a),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.pattern, style: const TextStyle(color: Color(0xFFF92672), fontSize: 10, fontFamily: 'monospace')),
                                if (r.description.isNotEmpty)
                                  Text(r.description, style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
                              ],
                            ),
                          ),
                          Text('${r.matchCount}', style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => widget.commandGuard.toggleRule(r.id).then((_) => setGuardState(() {})),
                            child: Icon(
                              r.enabled ? Icons.toggle_on : Icons.toggle_off,
                              size: 16,
                              color: r.enabled ? Colors.green : const Color(0xFF666666),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => widget.commandGuard.removeRule(r.id).then((_) => setGuardState(() {})),
                            child: const Icon(Icons.close, size: 12, color: Color(0xFF666666)),
                          ),
                        ],
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
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
