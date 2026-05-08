import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/service_registry.dart';
import '../core/terminal_session.dart';
import '../backends/local_backend.dart';
import '../production_fps_overlay.dart';
import '../config/pkm_theme.dart';

/// Home screen with core terminal functionality.
/// Services are pulled lazily from the registry on first use.
class HomeScreen extends StatefulWidget {
  final ServiceRegistry registry;

  const HomeScreen({super.key, required this.registry});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<TerminalSession> _tabs = [];
  final Map<int, FocusNode> _tabFocusNodes = {};
  int _activeTab = 0;
  bool _showFps = false;

  /// Lazily get the AI assistant; returns null if disabled or failed.
  dynamic get _ai => widget.registry.get(TermisolFeatures.aiAssistant);

  /// Lazily get performance enforcer.
  dynamic get _perf => widget.registry.get(TermisolFeatures.performanceMonitoring);

  @override
  void initState() {
    super.initState();
    _createInitialTab();
  }

  void _createInitialTab() {
    final session = TerminalSession(
      id: 0,
      title: 'Terminal',
      backend: LocalBackend(),
      onAiQuery: _handleAiQuery,
    );

    _tabs.add(session);
    _tabFocusNodes[0] = FocusNode();
    _activeTab = 0;
  }

  void _handleAiQuery(String query) {
    try {
      _ai?.processQuery(query);
    } catch (e) {
      // Graceful degradation: AI fails, but terminal continues working
      debugPrint('AI query failed, continuing without AI: $e');
    }
  }

  void _toggleFps() {
    setState(() => _showFps = !_showFps);
  }

  void _addTab() {
    final newTab = TerminalSession(
      id: _tabs.length,
      title: 'Terminal ${_tabs.length + 1}',
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
      setState(() => _activeTab = index);
      _tabFocusNodes[index]?.requestFocus();
    }
  }
  
  void _closeTab(int index) {
    if (_tabs.length > 1 && index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];
      tab.dispose();
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
                  onPressed: _toggleFps,
                  icon: Icon(
                    _showFps ? Icons.speed : Icons.speed_outlined,
                    color: _showFps ? Colors.red : PkmTheme.primary,
                  ),
                  tooltip: 'Toggle FPS',
                ),
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
                if (_perf != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PkmTheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_perf.currentFps.toStringAsFixed(1)} FPS',
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
                        padding: const EdgeInsets.all(16),
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
                              'Terminal ${entry.key + 1} - Ready',
                              style: TextStyle(
                                color: PkmTheme.primary,
                                fontSize: 14,
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
                  );
                );
              }).values.toList(),
            ),
          ),
          
          // FPS overlay
          if (_showFps)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ProductionFpsOverlay(
                  enforcer: widget.performanceEnforcer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Dispose all tabs
    for (final tab in _tabs) {
      tab.dispose();
    }
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    
    // Dispose core systems
    widget.aiAssistant.dispose();
    widget.performanceEnforcer.dispose();
    
    super.dispose();
  }
}
