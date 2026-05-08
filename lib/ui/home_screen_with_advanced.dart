import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';
import '../core/performance_enforcer.dart';
import '../core/terminal_session.dart';
import '../config/pkm_theme.dart';
import '../config/ssh_passcode_manager.dart';
import 'terminal_view.dart';
import '../backends/ssh_backend.dart';
import 'production_fps_overlay.dart';
import 'search_overlay.dart';
import 'settings_sheet.dart';
import 'connection_profiles.dart';
import '../core/smart_command_chaining.dart';
import '../core/semantic_search_engine.dart';
import '../core/predictive_suggestions.dart';
import '../core/conversational_ai.dart';
import '../core/automated_workflows.dart';
import '../vr/vr_terminal.dart';
import '../core/github_integration.dart';
import '../core/neural_processing.dart';
import '../core/terminal_pane_manager.dart';
import '../core/plugin_ecosystem.dart';

/// Minimal home screen with core terminal functionality
class HomeScreen extends StatefulWidget {
  final NvidiaAITerminalAssistant aiAssistant;
  final PerformanceEnforcer performanceEnforcer;

  const HomeScreen({
    super.key,
    required this.aiAssistant,
    required this.performanceEnforcer,
    required this.productionGpuRenderer,
    required this.sub16msLatencyOptimizer,
    required this.adaptiveFramePacer,
    required this.productionConfigSystem,
    required this.backgroundProcessor,
    required this.memoryOptimizer,
    required this.networkResilience,
    required this.sshPasscodeManager,
    required this.aiMemoryPredictor,
    required this.intelligentCPUAllocator,
    required this.smartThermalManager,
    required this.commandPatternRecognizer,
    required this.smartErrorRecovery,
    required this.smartSSHOptimizer,
    required this.smartFileCacher,
    required this.syncConflictResolver,
    required this.advancedFilePreview,
    required this.smartMultitasking,
    required this.predictiveSuggestions,
    required this.smartLayoutMemory,
    required this.smartResourceCleanup,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<TerminalSession> _tabs = [];
  final Map<int, FocusNode> _tabFocusNodes = {};
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    
    // Initialize all advanced systems
    widget.aiMemoryPredictor.initialize();
    widget.intelligentCPUAllocator.initialize();
    widget.smartThermalManager.initialize();
    widget.commandPatternRecognizer.initialize();
    widget.smartErrorRecovery.initialize();
    widget.smartSSHOptimizer.initialize();
    widget.smartFileCacher.initialize();
    widget.syncConflictResolver.initialize();
    widget.advancedFilePreview.initialize();
    widget.smartMultitasking.initialize();
    widget.predictiveSuggestions.initialize();
    widget.smartLayoutMemory.initialize();
    widget.smartResourceCleanup.initialize();
    
    // Create initial tab
    _createInitialTab();
    
    // Setup performance monitoring
    widget.performanceEnforcer.addListener(_onPerformanceUpdate);
  }

  void _createInitialTab() {
    final session = TerminalSession(
      id: 0,
      backend: LocalBackend(),
      onAiQuery: _handleAiQuery,
    );
    
    _tabs.add(session);
    _tabFocusNodes[0] = FocusNode();
    _activeTab = 0;
  }

  void _handleAiQuery(String query) {
    // Handle AI queries
    widget.aiAssistant.processQuery(query);
  }

  void _onPerformanceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _addTab() {
    final newTab = TerminalSession(
      id: _tabs.length,
      backend: LocalBackend(),
      onAiQuery: _handleAiQuery,
    );
    
    setState(() {
      _tabs.add(newTab);
      _tabFocusNodes[newTab.id] = FocusNode();
      _activeTab = newTab.id;
    });
    
    _tabFocusNodes[newTab.id]?.requestFocus();
  }

  void _switchTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      setState(() {
        _activeTab = index;
      });
      
      _tabFocusNodes[index]?.requestFocus();
    }
  }

  void _closeTab(int index) {
    if (_tabs.length > 1 && index >= 0 && index < _tabs.length) {
      _tabs[index].dispose();
      _tabFocusNodes[index]?.dispose();
      
      setState(() {
        _tabs.removeAt(index);
        _tabFocusNodes.remove(index);
        
        if (_activeTab >= index) {
          _activeTab = (_activeTab - 1).clamp(0, _tabs.length - 1);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PkmTheme.background,
      body: Column(
        children: [
          // Top toolbar
          Container(
            height: 50,
            color: PkmTheme.terminalBg,
            child: Row(
              children: [
                IconButton(
                  onPressed: _addTab,
                  icon: const Icon(Icons.add, color: PkmTheme.primary),
                  tooltip: 'New Tab',
                ),
                const Spacer(),
                Text(
                  'Termisol Terminal',
                  style: TextStyle(
                    color: PkmTheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PkmTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${widget.performanceEnforcer.currentFps.toStringAsFixed(1)} FPS',
                    style: TextStyle(
                      color: PkmTheme.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Tab bar
          Container(
            height: 40,
            color: PkmTheme.tabActiveBg,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _tabs.asMap().entries.map((entry) {
                        return GestureDetector(
                          onTap: () => _switchTab(entry.key),
                          onSecondaryTap: () => _closeTab(entry.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _activeTab == entry.key 
                                  ? PkmTheme.tabActiveBg 
                                  : PkmTheme.tabInactiveBg,
                              border: Border(
                                top: BorderSide(
                                  color: _activeTab == entry.key 
                                      ? PkmTheme.primary 
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Terminal ${entry.key + 1}',
                              style: TextStyle(
                                color: _activeTab == entry.key 
                                    ? PkmTheme.primary 
                                    : PkmTheme.text,
                                fontWeight: _activeTab == entry.key 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).values.toList(),
                    ),
                  ),
                ),
                 IconButton(
                  onPressed: _addTab,
                  icon: const Icon(Icons.add, color: PkmTheme.primary),
                  tooltip: 'New Tab',
                ),
                IconButton(
                  onPressed: _createPluginWithAI,
                  icon: const Icon(Icons.smart_toy, color: PkmTheme.primary),
                  tooltip: 'Create Plugin with AI',
                ),
              ],
            ),
          ),
          
          // Terminal area
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: _tabs.asMap().entries.map((entry) {
                return Container(
                  key: ValueKey(entry.key),
                  color: PkmTheme.terminalBg,
                  child: Column(
                    children: [
                      // Terminal header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: PkmTheme.tabActiveBg,
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              color: PkmTheme.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Terminal ${entry.key + 1}',
                              style: TextStyle(
                                color: PkmTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: PkmTheme.statusConnected,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Connected',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Terminal content
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Terminal ${entry.key + 1} - Ready',
                                style: TextStyle(
                                  color: PkmTheme.primary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    border: Border.all(color: PkmTheme.primary.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Terminal Ready\nType commands to begin...',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).values.toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPluginWithAI() async {
    final result = await showDialog<PluginCreationData>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PluginCreationDialog(),
    );

    if (result == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating plugin with DeepSeek V4 Pro...'),
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

      // Close loading dialog
      Navigator.of(context).pop();

      if (creationResult.success && creationResult.pluginCode != null && creationResult.metadata != null) {
        // Show success dialog with option to install
        final install = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Plugin Created Successfully!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plugin: ${creationResult.metadata!.name}'),
                Text('Description: ${creationResult.metadata!.description}'),
                const SizedBox(height: 16),
                const Text('Install this plugin now?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Install Plugin'),
              ),
            ],
          ),
        );

        if (install == true) {
          final installed = await widget.pluginManager.installGeneratedPlugin(
            creationResult.pluginCode!,
            creationResult.metadata!,
          );

          if (installed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Plugin installed successfully!')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to install plugin')),
            );
          }
        }
      } else {
        // Show error dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Plugin Creation Failed'),
            content: Text(creationResult.error ?? 'Unknown error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Plugin Creation Failed'),
          content: Text('Error: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    widget.performanceEnforcer.removeListener(_onPerformanceUpdate);
    super.dispose();
  }
}

// ─── plugin creation dialog ───

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
    // Dispose all tabs
    for (final tab in _tabs) {
      tab.dispose();
    }
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    
    // Dispose all advanced systems
    widget.aiMemoryPredictor.dispose();
    widget.intelligentCPUAllocator.dispose();
    widget.smartThermalManager.dispose();
    widget.commandPatternRecognizer.dispose();
    widget.smartErrorRecovery.dispose();
    widget.smartSSHOptimizer.dispose();
    widget.smartFileCacher.dispose();
    widget.syncConflictResolver.dispose();
    widget.advancedFilePreview.dispose();
    widget.smartMultitasking.dispose();
    widget.predictiveSuggestions.dispose();
    widget.smartLayoutMemory.dispose();
    widget.smartResourceCleanup.dispose();
    
    // Dispose core systems
    widget.performanceEnforcer.dispose();
    widget.aiAssistant.dispose();
    
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
      title: const Text(
        'Create Plugin with AI',
        style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Describe what you want your plugin to do, and DeepSeek V4 Pro will generate the code for you!',
              style: TextStyle(color: PkmTheme.secondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontTerminal),
              decoration: const InputDecoration(
                labelText: 'Plugin Name',
                labelStyle: TextStyle(color: PkmTheme.secondary),
                hintText: 'My Awesome Plugin',
                hintStyle: TextStyle(color: PkmTheme.secondary),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              style: const TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontTerminal),
              decoration: const InputDecoration(
                labelText: 'Plugin Description',
                labelStyle: TextStyle(color: PkmTheme.secondary),
                hintText: 'Describe what this plugin should do in detail...',
                hintStyle: TextStyle(color: PkmTheme.secondary),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              style: const TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontTerminal),
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                labelStyle: TextStyle(color: PkmTheme.secondary),
                hintText: 'utility, productivity, development, etc.',
                hintStyle: TextStyle(color: PkmTheme.secondary),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _featuresController,
              maxLines: 2,
              style: const TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontTerminal),
              decoration: const InputDecoration(
                labelText: 'Key Features (optional)',
                labelStyle: TextStyle(color: PkmTheme.secondary),
                hintText: 'One feature per line...',
                hintStyle: TextStyle(color: PkmTheme.secondary),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: PkmTheme.secondary, fontFamily: PkmTheme.fontUi),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isEmpty || _descriptionController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please fill in plugin name and description')),
              );
              return;
            }

            final features = _featuresController.text.isEmpty
                ? null
                : _featuresController.text.split('\n').where((f) => f.trim().isNotEmpty).toList();

            Navigator.pop(context, PluginCreationData(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
              features: features,
            ));
          },
          child: const Text(
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

// ─── intents ───

class NewPaneIntent extends Intent {
  const NewPaneIntent();
}

class SplitHorizontalIntent extends Intent {
  const SplitHorizontalIntent();
}

class SplitVerticalIntent extends Intent {
  const SplitVerticalIntent();
}

class ToggleFpsIntent extends Intent {
  const ToggleFpsIntent();
}

class AiIntent extends Intent {
  const AiIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class SettingsIntent extends Intent {
  const SettingsIntent();
}

class CreatePluginIntent extends Intent {
  const CreatePluginIntent();
}
