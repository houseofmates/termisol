import 'package:flutter/material.dart';
import '../core/service_registry.dart';
import '../core/terminal_session.dart';
import '../config/pkm_theme.dart';
import 'settings_sheet.dart';

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
  final Map<String, FocusNode> _tabFocusNodes = {};
  String _activeTab = '0';

  @override
  void initState() {
    super.initState();
    _createInitialTab();
  }

  void _createInitialTab() {
    final session = TerminalSession(
      id: '0',
      name: 'Terminal',
    );

    _tabs.add(session);
    _tabFocusNodes['0'] = FocusNode();
    _activeTab = '0';
  }

  void _handleAiQuery(String query) {
    try {
      _ai?.processQuery(query);
    } catch (e) {
      // Graceful degradation: AI fails, but terminal continues working
      debugPrint('AI query failed, continuing without AI: $e');
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: PkmTheme.popup,
      builder: (context) => SettingsSheet(
        registry: widget.registry,
      ),
    );
  }

  void _addTab() {
    final newTabId = _tabs.length.toString();
    final newTab = TerminalSession(
      id: newTabId,
      name: 'Terminal ${_tabs.length + 1}',
    );

    setState(() {
      _tabs.add(newTab);
      _tabFocusNodes[newTabId] = FocusNode();
      _activeTab = newTabId;
    });

    _tabFocusNodes[newTabId]?.requestFocus();
  }

  void _switchTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      final tabId = _tabs[index].id;
      setState(() => _activeTab = tabId);
      _tabFocusNodes[tabId]?.requestFocus();
    }
  }
  
  void _closeTab(int index) {
    if (_tabs.length > 1 && index >= 0 && index < _tabs.length) {
      final tab = _tabs[index];
      final tabId = tab.id;
      tab.dispose();
      _tabFocusNodes[tabId]?.dispose();

      setState(() {
        _tabs.removeAt(index);
        _tabFocusNodes.remove(tabId);

        // If we closed the active tab, switch to another one
        if (_activeTab == tabId && _tabs.isNotEmpty) {
          _activeTab = _tabs[0].id;
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
                IconButton(
                  onPressed: _showSettings,
                  icon: const Icon(Icons.settings, color: PkmTheme.primary),
                  tooltip: 'Settings',
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
                        final tabId = entry.value.id;
                        return GestureDetector(
                          onTap: () => _switchTab(entry.key),
                          onSecondaryTap: () => _closeTab(entry.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _activeTab == tabId
                                  ? PkmTheme.tabActiveBg
                                  : PkmTheme.tabInactiveBg,
                              border: Border(
                                top: BorderSide(
                                  color: _activeTab == tabId
                                      ? PkmTheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              entry.value.name,
                              style: TextStyle(
                                color: _activeTab == tabId
                                    ? PkmTheme.primary
                                    : PkmTheme.text,
                                fontWeight: _activeTab == tabId
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
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
              index: _tabs.indexWhere((tab) => tab.id == _activeTab),
              children: _tabs.map((tab) {
                return Container(
                  key: ValueKey(tab.id),
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
                              '${tab.name} - Ready',
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
                  ),
                );
              }).toList(),
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

    super.dispose();
  }
}
