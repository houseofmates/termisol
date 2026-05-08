import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/service_registry.dart';
import '../core/terminal_session.dart';
import '../core/ai_assistant_integration.dart';
import '../config/pkm_theme.dart';
import 'settings_sheet.dart';
import 'terminal_view.dart';
import 'command_palette.dart';
import 'search_overlay.dart';

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
  bool _showCommandPalette = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _createInitialTab();
  }

  TerminalSession? get _activeSession {
    try {
      return _tabs.firstWhere((t) => t.id == _activeTab);
    } catch (_) {
      return _tabs.isNotEmpty ? _tabs.first : null;
    }
  }

  Future<String> _handleAiQuery(String query) async {
    debugPrint('AI query: $query');
    try {
      // Get AI service from registry
      final aiService = widget.registry.getAIAssistant();
      if (aiService != null) {
        final response = await aiService.processText(
          input: query,
          capability: AICapability.text_generation,
          contextId: 'terminal_${_activeTab}',
          preferLocal: true,
        );
        final success = response.success as bool? ?? false;
        final output = response.output as String?;
        return success && output != null ? output : 'AI service unavailable';
      }
      return 'AI service not configured';
    } catch (e) {
      debugPrint('AI query failed: $e');
      return 'AI query failed: $e';
    }
  }

  void _createInitialTab() {
    final session = TerminalSession(
      id: '0',
      name: 'Terminal',
    );
    session.onAiQuery = _handleAiQuery;
    session.start();

    _tabs.add(session);
    _tabFocusNodes['0'] = FocusNode();
    _activeTab = '0';
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
    newTab.onAiQuery = _handleAiQuery;
    newTab.start();

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
  
  void _toggleCommandPalette() {
    setState(() => _showCommandPalette = !_showCommandPalette);
  }

  void _toggleSearch() {
    setState(() => _showSearch = !_showSearch);
  }

  List<PaletteAction> _buildPaletteActions() {
    return [
      PaletteAction(
        id: 'new_tab',
        title: 'new tab',
        subtitle: 'create a new terminal tab',
        icon: Icons.add,
        keywords: ['tab', 'new', 'create'],
        onExecute: _addTab,
      ),
      PaletteAction(
        id: 'close_tab',
        title: 'close current tab',
        subtitle: 'close the active terminal tab',
        icon: Icons.close,
        keywords: ['tab', 'close', 'remove'],
        onExecute: () {
          final idx = _tabs.indexWhere((t) => t.id == _activeTab);
          if (idx >= 0) _closeTab(idx);
        },
      ),
      PaletteAction(
        id: 'search',
        title: 'search in terminal',
        subtitle: 'find text in the current terminal buffer',
        icon: Icons.search,
        keywords: ['find', 'search', 'grep'],
        onExecute: _toggleSearch,
      ),
      PaletteAction(
        id: 'settings',
        title: 'open settings',
        subtitle: 'configure termisol',
        icon: Icons.settings,
        keywords: ['config', 'preferences', 'settings'],
        onExecute: _showSettings,
      ),
      PaletteAction(
        id: 'copy_url',
        title: 'copy last detected url',
        subtitle: 'copy the most recently detected link',
        icon: Icons.link,
        keywords: ['url', 'link', 'copy'],
        onExecute: () async {
          final session = _activeSession;
          if (session != null && session.detectedUrls.isNotEmpty) {
            final url = session.detectedUrls.last.url;
            await Clipboard.setData(ClipboardData(text: url));
            debugPrint('URL copied to clipboard: $url');
          }
        },
        enabled: _activeSession?.detectedUrls.isNotEmpty ?? false,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PkmTheme.background,
      body: Stack(
        children: [
          Column(
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
                    IconButton(
                      onPressed: _toggleSearch,
                      icon: const Icon(Icons.search, color: PkmTheme.primary),
                      tooltip: 'Search (Ctrl+Shift+F)',
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
                    IconButton(
                      onPressed: _toggleCommandPalette,
                      icon: const Icon(Icons.keyboard_command_key, color: PkmTheme.primary),
                      tooltip: 'Command Palette (Ctrl+Shift+P)',
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
                            border: Border.all(
                              color: PkmTheme.primary.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: TermisolTerminalView(
                            session: tab,
                            focusNode: _tabFocusNodes[tab.id],
                            onNewTab: _addTab,
                            onCloseTab: () => _closeTab(
                              _tabs.indexWhere((t) => t.id == tab.id),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Command palette overlay
          if (_showCommandPalette)
            CommandPalette(
              actions: _buildPaletteActions(),
              onClose: () => setState(() => _showCommandPalette = false),
            ),

          // Search overlay
          if (_showSearch && _activeSession != null)
            TerminalSearchOverlay(
              terminal: _activeSession!.terminal,
              onClose: () => setState(() => _showSearch = false),
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
