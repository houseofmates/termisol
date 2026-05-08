import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/service_registry.dart';
import '../core/terminal_session.dart';
import '../ai/ai_terminal_assistant.dart';
import '../core/headerbar_actions.dart';
import '../config/pkm_theme.dart';
import 'settings_page.dart';
import 'terminal_view.dart';
import 'command_palette.dart';
import 'search_overlay.dart';
import 'edit.dart';
import 'command_history_search.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _showHistorySearch = false;

  @override
  void initState() {
    super.initState();
    _createInitialTab();
    HeaderbarActions.action.addListener(_onHeaderbarAction);
  }

  @override
  void dispose() {
    HeaderbarActions.action.removeListener(_onHeaderbarAction);
    for (final tab in _tabs) {
      tab.dispose();
    }
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onHeaderbarAction() {
    final action = HeaderbarActions.action.value;
    if (action == null) return;
    switch (action) {
      case 'newTab':
        _addTab();
        break;
      case 'search':
        _toggleSearch();
        break;
      case 'settings':
        _showSettings();
        break;
      case 'dictate':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('dictation not yet implemented')),
        );
        break;
    }
  }

  Future<void> _handleEditCommand(String filePath) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditTerminal(
          filePath: filePath,
          initialContent: '',
          onSave: (content) async {
            final file = File(filePath);
            await file.writeAsString(content);
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
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
        );
        final success = response.success as bool? ?? false;
        final output = response.output as String?;
        return success && output != null ? output : 'AI service unavailable';
      }
      return 'AI service not configured';
    } catch (e, stack) {
      debugPrint('AI query failed: $e\n$stack');
      return 'AI query failed: $e';
    }
  }

  void _createInitialTab() {
    final session = TerminalSession(
      id: '0',
      name: 'Terminal',
    );
    session.onAiQuery = _handleAiQuery;
    session.onEditCommand = _handleEditCommand;
    session.start();

    _tabs.add(session);
    _tabFocusNodes['0'] = FocusNode();
    _activeTab = '0';
  }

  void _showSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsPage(registry: widget.registry),
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

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, item);
    });
  }

  void _showTabContextMenu(TapUpDetails details, int index) {
    final overlay = Navigator.of(context).overlay!;
    final renderBox = overlay.context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & Size.zero,
        Offset.zero & renderBox.size,
      ),
      color: PkmTheme.popup,
      items: [
        PopupMenuItem(
          value: 'new',
          onTap: _addTab,
          child: Text(
            '+ new',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          onTap: () => _renameTab(index),
          child: Text(
            'rename',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        PopupMenuItem(
          value: 'close',
          onTap: () => _closeTab(index),
          child: Text(
            'close',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
      ],
    );
  }

  void _renameTab(int index) {
    final tab = _tabs[index];
    final controller = TextEditingController(text: tab.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PkmTheme.background,
        title: Text(
          'rename tab',
          style: TextStyle(
            color: PkmTheme.primary,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
          ),
          decoration: InputDecoration(
            hintText: 'tab name',
            hintStyle: TextStyle(
              color: PkmTheme.text.withValues(alpha: 0.5),
              fontFamily: PkmTheme.fontUi,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'cancel',
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              tab.rename(controller.text);
              setState(() {});
              Navigator.of(context).pop();
            },
            child: Text(
              'rename',
              style: TextStyle(
                color: PkmTheme.primary,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleCommandPalette() {
    setState(() => _showCommandPalette = !_showCommandPalette);
  }

  void _toggleSearch() {
    setState(() => _showSearch = !_showSearch);
  }

  void _toggleHistorySearch() {
    setState(() => _showHistorySearch = !_showHistorySearch);
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
        id: 'history',
        title: 'command history',
        subtitle: 'search and replay previous commands',
        icon: Icons.history,
        keywords: ['history', 'commands', 'previous', 'search'],
        onExecute: _toggleHistorySearch,
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
        id: 'open_url',
        title: 'open last detected url',
        subtitle: 'open the most recently detected link in browser',
        icon: Icons.open_in_browser,
        keywords: ['url', 'link', 'open', 'browser'],
        onExecute: () async {
          final session = _activeSession;
          if (session != null && session.detectedUrls.isNotEmpty) {
            final url = session.detectedUrls.last.url;
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              debugPrint('cannot launch url: $url');
            }
          }
        },
        enabled: _activeSession?.detectedUrls.isNotEmpty ?? false,
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
                    const Text(
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
                height: PkmTheme.tabBarHeight,
                color: PkmTheme.background,
                child: Row(
                  children: [
                    Expanded(
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        onReorder: _onReorder,
                        itemCount: _tabs.length,
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              return Material(
                                elevation: 0,
                                color: Colors.transparent,
                                child: child,
                              );
                            },
                            child: child,
                          );
                        },
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          final isActive = _activeTab == tab.id;
                          return ConstrainedBox(
                            key: ValueKey(tab.id),
                            constraints: const BoxConstraints(
                              minWidth: 120,
                              maxWidth: 220,
                            ),
                            child: Container(
                              height: PkmTheme.tabBarHeight,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? PkmTheme.tabActiveBg
                                      : PkmTheme.tabInactiveBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isActive
                                      ? Border.all(
                                          color: PkmTheme.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    // Drag handle
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Container(
                                        width: 20,
                                        height: double.infinity,
                                        color: Colors.transparent,
                                        child: Center(
                                          child: Icon(
                                            Icons.drag_indicator,
                                            size: 12,
                                            color: PkmTheme.text.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Tab content (tap + right-click)
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _switchTab(index),
                                        onSecondaryTapUp: (details) =>
                                            _showTabContextMenu(details, index),
                                        child: Container(
                                          height: double.infinity,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            tab.name,
                                            style: TextStyle(
                                              color: isActive
                                                  ? PkmTheme.primary
                                                  : PkmTheme.text,
                                              fontWeight: isActive
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              fontFamily: PkmTheme.fontUi,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Close button
                                    InkWell(
                                      onTap: () => _closeTab(index),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: PkmTheme.text.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
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
                      padding: EdgeInsets.zero,
                      child: Container(
                        constraints: const BoxConstraints.expand(),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(
                            color: PkmTheme.primary.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.zero,
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
                    );
                  }).toList(),
                ),
              ),
            ],
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
           // Command history search overlay
           if (_showHistorySearch && _activeSession != null)
             CommandHistorySearch(
               session: _activeSession!,
               onClose: () => setState(() => _showHistorySearch = false),
             ),
        ],
      ),
    );
  }

}
