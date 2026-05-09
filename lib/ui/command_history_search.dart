import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/terminal_session.dart';
import '../config/pkm_theme.dart';

/// overlay for searching and selecting commands from history.
/// triggered via keyboard shortcut or command palette.
class CommandHistorySearch extends StatefulWidget {
  final TerminalSession session;
  final VoidCallback onClose;

  const CommandHistorySearch({
    super.key,
    required this.session,
    required this.onClose,
  });

  @override
  State<CommandHistorySearch> createState() => _CommandHistorySearchState();
}

class _CommandHistorySearchState extends State<CommandHistorySearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _results = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _refreshResults();
    _controller.addListener(_refreshResults);
  }

  void _refreshResults() {
    setState(() {
      _results = widget.session.commandHistory.search(_controller.text);
      _selectedIndex = 0;
    });
  }

  void _selectCommand(String command) {
    widget.session.terminal.write(command);
    widget.onClose();
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          widget.onClose();
          break;
        case LogicalKeyboardKey.arrowDown:
          setState(() {
            _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
          });
          break;
        case LogicalKeyboardKey.arrowUp:
          setState(() {
            _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
          });
          break;
        case LogicalKeyboardKey.enter:
          if (_results.isNotEmpty && _selectedIndex < _results.length) {
            _selectCommand(_results[_selectedIndex]);
          }
          break;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: 600,
          height: 400,
          decoration: BoxDecoration(
            color: PkmTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PkmTheme.primary.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              // Search input
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: PkmTheme.primary.withValues(alpha: 0.3)),
                  ),
                ),
                child: KeyboardListener(
                  focusNode: _focusNode,
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'search command history...',
                      hintStyle: TextStyle(
                        color: PkmTheme.text.withValues(alpha: 0.5),
                        fontFamily: PkmTheme.fontUi,
                      ),
                      prefixIcon: const Icon(Icons.search, color: PkmTheme.primary),
                      border: InputBorder.none,
                    ),
                    autofocus: true,
                  ),
                ),
              ),
              // Results list
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          'no matching commands',
                          style: TextStyle(
                            color: PkmTheme.text.withValues(alpha: 0.5),
                            fontFamily: PkmTheme.fontUi,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final cmd = _results[index];
                          final isSelected = index == _selectedIndex;
                          return InkWell(
                            onTap: () => _selectCommand(cmd),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              color: isSelected
                                  ? PkmTheme.primary.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.terminal,
                                    size: 16,
                                    color: isSelected
                                        ? PkmTheme.primary
                                        : PkmTheme.text.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      cmd,
                                      style: TextStyle(
                                        color: isSelected
                                            ? PkmTheme.primary
                                            : PkmTheme.text,
                                        fontFamily: 'DroidSansMono',
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    Text(
                                      'enter to select',
                                      style: TextStyle(
                                        color: PkmTheme.text.withValues(alpha: 0.4),
                                        fontFamily: PkmTheme.fontUi,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: PkmTheme.primary.withValues(alpha: 0.2)),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _KeyHint(keyLabel: '↑↓', action: 'navigate'),
                    SizedBox(width: 16),
                    _KeyHint(keyLabel: 'enter', action: 'select'),
                    SizedBox(width: 16),
                    _KeyHint(keyLabel: 'esc', action: 'close'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final String keyLabel;
  final String action;

  const _KeyHint({required this.keyLabel, required this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: PkmTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: PkmTheme.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(
              color: PkmTheme.primary,
              fontFamily: PkmTheme.fontUi,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          action,
          style: TextStyle(
            color: PkmTheme.text.withValues(alpha: 0.5),
            fontFamily: PkmTheme.fontUi,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
