import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';

/// a floating search bar for finding text within a terminal buffer.
class TerminalSearchOverlay extends StatefulWidget {
  final Terminal terminal;
  final VoidCallback onClose;

  const TerminalSearchOverlay({
    super.key,
    required this.terminal,
    required this.onClose,
  });

  @override
  State<TerminalSearchOverlay> createState() => _TerminalSearchOverlayState();
}

class _TerminalSearchOverlayState extends State<TerminalSearchOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _caseSensitive = false;
  int _currentMatch = 0;
  int _totalMatches = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _controller.text;
    if (query.isEmpty) {
      setState(() {
        _currentMatch = 0;
        _totalMatches = 0;
      });
      return;
    }

    final buffer = widget.terminal.buffer.toString();
    final searchText = _caseSensitive ? query : query.toLowerCase();
    final targetText = _caseSensitive ? buffer : buffer.toLowerCase();

    int count = 0;
    int start = 0;
    while (true) {
      final idx = targetText.indexOf(searchText, start);
      if (idx == -1) break;
      count++;
      start = idx + searchText.length;
    }

    setState(() {
      _totalMatches = count;
      _currentMatch = count > 0 ? 1 : 0;
    });

    if (count > 0) {
      _scrollToFirstMatch();
    }
  }

  void _scrollToFirstMatch() {
    // scroll heuristic skipped — xterm.dart public api limitation
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatch = _currentMatch >= _totalMatches ? 1 : _currentMatch + 1;
    });
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatch = _currentMatch <= 1 ? _totalMatches : _currentMatch - 1;
    });
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _prevMatch();
        } else {
          _nextMatch();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 56,
      left: 16,
      right: 16,
      child: Material(
        color: PkmTheme.popup,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.search, color: PkmTheme.secondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: KeyboardListener(
                  focusNode: _focusNode,
                  onKeyEvent: _handleKey,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontTerminal,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'search...',
                      hintStyle: const TextStyle(color: PkmTheme.secondary),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      suffixText:
                          _totalMatches > 0 ? '$_currentMatch/$_totalMatches' : '',
                      suffixStyle: const TextStyle(
                        color: PkmTheme.primary,
                        fontFamily: PkmTheme.fontTerminal,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (_) => _performSearch(),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  _performSearch();
                },
                icon: Icon(
                  Icons.search,
                  size: 18,
                  color: _caseSensitive ? PkmTheme.primary : PkmTheme.secondary,
                ),
                tooltip: 'case sensitive',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                onPressed: _prevMatch,
                icon: const Icon(Icons.arrow_upward, color: PkmTheme.secondary, size: 18),
                tooltip: 'previous (shift+enter)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                onPressed: _nextMatch,
                icon: const Icon(Icons.arrow_downward, color: PkmTheme.secondary, size: 18),
                tooltip: 'next (enter)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, color: PkmTheme.secondary, size: 18),
                tooltip: 'close (escape)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
