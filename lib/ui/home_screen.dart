import 'dart:io';
import 'dart:async';
import '../core/session_persistence.dart' hide TerminalSession;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/service_registry.dart';
import '../core/terminal_session.dart';
import '../ai/ai_terminal_assistant.dart';
import '../core/headerbar_actions.dart';
import '../config/pkm_theme.dart';
import 'settings_page.dart';
import 'terminal_view.dart';
import 'performance_overlay.dart';
import 'command_palette.dart';
import 'hints_mode.dart';
import 'search_overlay.dart';
import 'edit.dart';
import 'command_history_search.dart';
import 'split_pane.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isSplit = false;
  bool _showPerformanceOverlay = false;
  bool _broadcastMode = false;
  Timer? _saveDebounceTimer;

  @override
  void initState() {
    super.initState();
    _createInitialTab();
    _maybeRestoreSessions();
    HeaderbarActions.action.addListener(_onHeaderbarAction);
    PkmTheme.bgOpacity.addListener(_onBgOpacityChanged);
    _loadPerformanceOverlay();
  }

  Future<void> _loadPerformanceOverlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _showPerformanceOverlay = prefs.getBool('show_performance_overlay') ?? false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load performance overlay setting: $e');
    }
  }

  @override
  void dispose() {
    _saveDebounceTimer?.cancel();
    HeaderbarActions.action.removeListener(_onHeaderbarAction);
    PkmTheme.bgOpacity.removeListener(_onBgOpacityChanged);
    for (final tab in _tabs) {
      tab.directory.removeListener(_onDirectoryChanged);
      tab.dispose();
    }
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onDirectoryChanged() {
    if (mounted) setState(() {});
  }

  void _onBgOpacityChanged() {
    if (mounted) setState(() {});
  }

  String _tabDisplayName(TerminalSession tab) {
    final dir = tab.directory.value;
    if (dir == null || dir.isEmpty) return tab.name;
    if (dir == '~') return '~';
    final home = Platform.environment['HOME'] ?? '';
    if (dir == home) return '~';
    final parts = dir.split('/');
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => dir);
  }

  String _nextTabId() {
    int maxId = -1;
    for (final tab in _tabs) {
      final id = int.tryParse(tab.id) ?? -1;
      if (id > maxId) maxId = id;
    }
    return (maxId + 1).toString();
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
      case 'copy':
        _activeSession?.clipboardManager.copy();
        break;
      case 'paste':
        _activeSession?.clipboardManager.paste();
        break;
      case 'selectAll':
        _activeSession?.clipboardManager.selectAll();
        break;
    }
  }

  Future<void> _handleEditCommand(String filePath) async {
    if (!mounted) return;

    String content = '';
    try {
      final file = File(filePath);
      if (await file.exists()) {
        content = await file.readAsString();
      }
    } catch (e, stack) {
      debugPrint('edit: failed to read file: $e\n$stack');
      content = '';
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditTerminal(
          filePath: filePath,
          initialContent: content,
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
      final aiService = widget.registry.getAIAssistant() as NvidiaAITerminalAssistant?;
      if (aiService != null) {
        final response = await aiService.processText(
          input: query,
          capability: AICapability.text_generation,
          contextId: 'terminal_$_activeTab',
        );
        final success = response.success;
        final output = response.output;
        return success && output.isNotEmpty
            ? output
            : 'AI service unavailable';
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
    session.onInputIntercepted = (input) => _broadcastToOtherTabs(input);
    session.directory.addListener(_onDirectoryChanged);
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
    final newTabId = _nextTabId();
    final newTab = TerminalSession(
      id: newTabId,
      name: 'Terminal ${_tabs.length + 1}',
    );
    newTab.onAiQuery = _handleAiQuery;
    newTab.onInputIntercepted = (input) => _broadcastToOtherTabs(input);
    newTab.directory.addListener(_onDirectoryChanged);
    newTab.start();

    setState(() {
      _tabs.add(newTab);
      _tabFocusNodes[newTabId] = FocusNode();
      _activeTab = newTabId;
    });

    _tabFocusNodes[newTabId]?.requestFocus();
    _saveSessions();
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
      tab.directory.removeListener(_onDirectoryChanged);
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
      _saveSessions();
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

  void _duplicateTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final source = _tabs[index];
    final newTabId = _nextTabId();
    final newTab = TerminalSession(
      id: newTabId,
      name: '${source.name} copy',
    );
    newTab.onAiQuery = _handleAiQuery;
    newTab.onEditCommand = _handleEditCommand;
    newTab.onInputIntercepted = (input) => _broadcastToOtherTabs(input);
    newTab.directory.addListener(_onDirectoryChanged);
    newTab.start(workingDirectory: source.directory.value);

    setState(() {
      _tabs.add(newTab);
      _tabFocusNodes[newTabId] = FocusNode();
      _activeTab = newTabId;
    });

    _tabFocusNodes[newTabId]?.requestFocus();
    _saveSessions();
  }

  void _closeOthers(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final keep = _tabs[index];
    final keepId = keep.id;

    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (i == index) continue;
      final tab = _tabs[i];
      tab.directory.removeListener(_onDirectoryChanged);
      tab.dispose();
      _tabFocusNodes[tab.id]?.dispose();
      _tabFocusNodes.remove(tab.id);
      _tabs.removeAt(i);
    }

    setState(() {
      _activeTab = keepId;
    });
    _saveSessions();
  }

  void _closeToTheRight(int index) {
    if (index < 0 || index >= _tabs.length) return;
    for (int i = _tabs.length - 1; i > index; i--) {
      final tab = _tabs[i];
      tab.directory.removeListener(_onDirectoryChanged);
      tab.dispose();
      _tabFocusNodes[tab.id]?.dispose();
      _tabFocusNodes.remove(tab.id);
      _tabs.removeAt(i);
    }

    if (_tabs.indexWhere((t) => t.id == _activeTab) == -1) {
      _activeTab = _tabs[index].id;
    }

    setState(() {});
    _saveSessions();
  }

  void _duplicateActiveTab() {
    final idx = _tabs.indexWhere((t) => t.id == _activeTab);
    if (idx >= 0) _duplicateTab(idx);
  }

  void _closeOthersActive() {
    final idx = _tabs.indexWhere((t) => t.id == _activeTab);
    if (idx >= 0) _closeOthers(idx);
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
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          value: 'new',
          onTap: _addTab,
          child: const Text(
            '+ new',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          onTap: () => _duplicateTab(index),
          child: const Text(
            'duplicate tab',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          onTap: () => _renameTab(index),
          child: const Text(
            'rename',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          onTap: () => _closeTab(index),
          child: const Text(
            'close',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        PopupMenuItem(
          value: 'closeOthers',
          onTap: () => _closeOthers(index),
          child: const Text(
            'close others',
            style: TextStyle(color: PkmTheme.text),
          ),
        ),
        PopupMenuItem(
          value: 'closeToTheRight',
          onTap: () => _closeToTheRight(index),
          child: const Text(
            'close to the right',
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
        title: const Text(
          'rename tab',
          style: TextStyle(
            color: PkmTheme.primary,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
          ),
          decoration: InputDecoration(
            hintText: 'tab name',
            hintStyle: TextStyle(
              color: PkmTheme.text.withValues(alpha: 0.5),
              fontFamily: PkmTheme.fontUi,
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
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
              _saveSessions();
            },
            child: const Text(
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

  Future<void> _maybeRestoreSessions() async {
    try {
      final saved = await SessionPersistence().loadSessions();
      if (saved.isEmpty || !mounted) return;

      // Dispose initial tab
      for (final tab in _tabs) {
        tab.directory.removeListener(_onDirectoryChanged);
        tab.dispose();
      }
      for (final node in _tabFocusNodes.values) {
        node.dispose();
      }
      _tabs.clear();
      _tabFocusNodes.clear();

      for (final data in saved) {
        final id = data['id'] as String? ?? '';
        final name = data['name'] as String? ?? 'Terminal';
        final workingDirectory = data['workingDirectory'] as String?;

        final session = TerminalSession(
          id: id,
          name: name,
        );
        session.onAiQuery = _handleAiQuery;
        session.onEditCommand = _handleEditCommand;
        session.onInputIntercepted = (input) => _broadcastToOtherTabs(input);
        session.directory.addListener(_onDirectoryChanged);
        await session.start(workingDirectory: workingDirectory);

        if (!mounted) return;

        _tabs.add(session);
        _tabFocusNodes[id] = FocusNode();
      }

      if (_tabs.isNotEmpty) {
        _activeTab = _tabs.first.id;
      }

      if (mounted) {
        setState(() {});
      }
      _saveSessions();
    } catch (e) {
      debugPrint('Failed to restore sessions: $e');
    }
  }

  void _saveSessions() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await SessionPersistence().saveSessions(_tabs);
      } catch (e) {
        debugPrint('Failed to save sessions: $e');
      }
    });
  }

  void _toggleSplit() {
    if (_tabs.length < 2) {
      // Create second tab if needed
      _addTab();
    }
    setState(() => _isSplit = !_isSplit);
  }

  void _togglePerformanceOverlay() {
    setState(() => _showPerformanceOverlay = !_showPerformanceOverlay);
  }

  void _toggleHintsMode() {
    setState(() => _showHintsMode = !_showHintsMode);
  }

  void _toggleBroadcastMode() {
    setState(() => _broadcastMode = !_broadcastMode);
  }

  void _broadcastToOtherTabs(String input) {
    if (!_broadcastMode) return;
    for (final tab in _tabs) {
      if (tab.id != _activeTab) {
        tab.sendRawInput(input);
      }
    }
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
      PaletteAction(
        id: 'performance_overlay',
        title: 'toggle performance overlay',
        subtitle: 'show or hide fps and frame timing overlay',
        icon: Icons.speed,
        keywords: ['fps', 'performance', 'overlay', 'timing', 'frame'],
        onExecute: _togglePerformanceOverlay,
      ),
      PaletteAction(
        id: 'toggle_broadcast',
        title: 'toggle broadcast input',
        subtitle: 'send keystrokes to all open tabs simultaneously',
        icon: Icons.campaign,
        keywords: ['broadcast', 'input', 'sync', 'all tabs'],
        onExecute: _toggleBroadcastMode,
      ),
      PaletteAction(
        id: 'hints_mode',
        title: 'hints mode',
        subtitle: 'open urls and paths with keyboard shortcuts',
        icon: Icons.lightbulb_outline,
        keywords: ['hints', 'links', 'urls', 'open', 'keyboard'],
        onExecute: _toggleHintsMode,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PkmTheme.background,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(
            LogicalKeyboardKey.keyO,
            control: true,
            shift: true,
          ): _togglePerformanceOverlay,
          const SingleActivator(
            LogicalKeyboardKey.keyT,
            control: true,
            shift: true,
          ): _duplicateActiveTab,
          const SingleActivator(
            LogicalKeyboardKey.keyW,
            control: true,
            shift: true,
          ): _closeOthersActive,
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            control: true,
            shift: true,
          ): _toggleBroadcastMode,
          const SingleActivator(
            LogicalKeyboardKey.keyH,
            control: true,
            shift: true,
          ): _toggleHintsMode,
        },
        child: Stack(
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
                      onPressed: _toggleBroadcastMode,
                      icon: Icon(
                        Icons.campaign,
                        color: _broadcastMode ? Colors.orange : PkmTheme.primary,
                      ),
                      tooltip: 'Toggle Broadcast Input (Ctrl+Shift+B)',
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
                      onPressed: _toggleSplit,
                      icon: const Icon(Icons.vertical_split, color: PkmTheme.primary),
                      tooltip: 'Toggle Split View',
                    ),
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
                color: _broadcastMode
                    ? const Color(0xFF1a0f00)
                    : PkmTheme.background,
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
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  _tabDisplayName(tab),
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
                                              AnimatedBuilder(
                                                animation: tab.longCommandNotifier,
                                                builder: (context, child) {
                                                  final hasLongRunning = tab.longCommandNotifier.activeCommands.isNotEmpty;
                                                  return Container(
                                                    width: 6,
                                                    height: 6,
                                                    margin: const EdgeInsets.only(left: 4),
                                                    decoration: BoxDecoration(
                                                      color: hasLongRunning ? Colors.orange : Colors.transparent,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
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
              if (_broadcastMode)
                Container(
                  height: 24,
                  color: Colors.orange.withValues(alpha: 0.9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.campaign, size: 14, color: Colors.black),
                      const SizedBox(width: 6),
                      Text(
                        'BROADCASTING TO ${_tabs.length} TAB${_tabs.length == 1 ? '' : 'S'}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: PkmTheme.fontUi,
                        ),
                      ),
                    ],
                  ),
                ),
// Terminal area
              Expanded(
                child: _isSplit && _tabs.length >= 2
                    ? SplitPane(
                        sessions: [_tabs[0], _tabs[1]],
                        onNewTab: _addTab,
                        onCloseTab: () {
                          final idx = _tabs.indexWhere((t) => t.id == _activeTab);
                          if (idx >= 0) _closeTab(idx);
                        },
                      )
                    : IndexedStack(
                        index: _tabs.indexWhere((tab) => tab.id == _activeTab),
                        children: _tabs.map((tab) {
                          return Container(
                            key: ValueKey(tab.id),
                            color: PkmTheme.terminalBg.withValues(
                              alpha: PkmTheme.bgOpacity.value,
                            ),
                            padding: EdgeInsets.zero,
                            child: Container(
                              constraints: const BoxConstraints.expand(),
                              decoration: BoxDecoration(
                                color: PkmTheme.terminalBg.withValues(
                                  alpha: PkmTheme.bgOpacity.value,
                                ),
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
          // Performance overlay
          if (_showPerformanceOverlay)
            TermisolPerformanceOverlay(
              onDismiss: () => setState(() => _showPerformanceOverlay = false),
            ),
          // Hints mode overlay
          if (_showHintsMode && _activeSession != null && (!_isSplit || _tabs.length < 2))
            Positioned.fill(
              child: HintsModeOverlay(
                terminal: _activeSession!.terminal,
                onClose: () => setState(() => _showHintsMode = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
