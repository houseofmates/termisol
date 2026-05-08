import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/pkm_theme.dart';

/// A command palette action that can be executed.
class PaletteAction {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
  final VoidCallback? onExecute;
  final bool enabled;

  PaletteAction({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.icon,
    this.keywords = const [],
    this.onExecute,
    this.enabled = true,
  });
}

/// VS Code-style command palette for quick access to all actions.
class CommandPalette extends StatefulWidget {
  final List<PaletteAction> actions;
  final VoidCallback onClose;

  const CommandPalette({
    super.key,
    required this.actions,
    required this.onClose,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  List<PaletteAction> _filtered = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _filtered = widget.actions.where((a) => a.enabled).toList();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      setState(() {
        _filtered = widget.actions.where((a) => a.enabled).toList();
        _selectedIndex = 0;
      });
      return;
    }

    final scored = <(PaletteAction, int)>[];
    for (final action in widget.actions.where((a) => a.enabled)) {
      int score = 0;
      final title = action.title.toLowerCase();
      final subtitle = action.subtitle.toLowerCase();
      final keywords = action.keywords.map((k) => k.toLowerCase()).toList();

      if (title == q) {
        score += 100;
      } else if (title.startsWith(q)) {
        score += 50;
      } else if (title.contains(q)) {
        score += 30;
      }

      if (subtitle.contains(q)) score += 10;
      for (final k in keywords) {
        if (k.contains(q)) score += 15;
      }

      if (score > 0) scored.add((action, score));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    setState(() {
      _filtered = scored.map((s) => s.$1).toList();
      _selectedIndex = _filtered.isEmpty ? -1 : 0;
    });
  }

  void _execute(PaletteAction action) {
    widget.onClose();
    action.onExecute?.call();
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _filtered.length - 1);
    });
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final itemHeight = 48.0;
    final offset = _selectedIndex * itemHeight;
    _scrollController.animateTo(
      offset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onClose();
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
      case LogicalKeyboardKey.enter:
        if (_selectedIndex >= 0 && _selectedIndex < _filtered.length) {
          _execute(_filtered[_selectedIndex]);
        }
      case LogicalKeyboardKey.home:
        setState(() => _selectedIndex = 0);
        _scrollToSelected();
      case LogicalKeyboardKey.end:
        setState(() => _selectedIndex = _filtered.length - 1);
        _scrollToSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: PkmTheme.popup,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PkmTheme.primary.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search input
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: _handleKey,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(
                        color: PkmTheme.text,
                        fontSize: 16,
                        fontFamily: PkmTheme.fontUi,
                      ),
                      decoration: InputDecoration(
                        hintText: 'type a command...',
                        hintStyle: const TextStyle(color: PkmTheme.secondary),
                        prefixIcon: const Icon(Icons.search, color: PkmTheme.primary),
                        suffixText: '${_filtered.length}',
                        suffixStyle: const TextStyle(
                          color: PkmTheme.secondary,
                          fontSize: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: PkmTheme.primary.withOpacity(0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: PkmTheme.primary.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: PkmTheme.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      onChanged: _filter,
                    ),
                  ),
                ),

                // Divider
                const Divider(height: 1, color: PkmTheme.tabInactiveBg),

                // Results
                Flexible(
                  child: _filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'no matching commands',
                            style: TextStyle(
                              color: PkmTheme.secondary,
                              fontSize: 14,
                              fontFamily: PkmTheme.fontUi,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          shrinkWrap: true,
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final action = _filtered[index];
                            final isSelected = index == _selectedIndex;
                            return InkWell(
                              onTap: () => _execute(action),
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? PkmTheme.primary.withOpacity(0.15)
                                      : Colors.transparent,
                                  border: Border(
                                    left: BorderSide(
                                      color: isSelected ? PkmTheme.primary : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      action.icon,
                                      color: isSelected ? PkmTheme.primary : PkmTheme.secondary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            action.title,
                                            style: TextStyle(
                                              color: isSelected ? PkmTheme.text : PkmTheme.text,
                                              fontSize: 14,
                                              fontFamily: PkmTheme.fontUi,
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                          if (action.subtitle.isNotEmpty)
                                            Text(
                                              action.subtitle,
                                              style: const TextStyle(
                                                color: PkmTheme.secondary,
                                                fontSize: 11,
                                                fontFamily: PkmTheme.fontUi,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Text(
                                        'enter',
                                        style: TextStyle(
                                          color: PkmTheme.secondary,
                                          fontSize: 11,
                                          fontFamily: PkmTheme.fontTerminal,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
