import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';
import '../core/terminal_session.dart';

const _estimatedLineHeight = 16.0;

/// a floating search bar for finding text within a terminal buffer.
class TerminalSearchOverlay extends StatefulWidget {
  final Terminal terminal;
  final VoidCallback onClose;
  final ScrollController? scrollController;
  final TerminalSession? session;

  const TerminalSearchOverlay({
    super.key,
    required this.terminal,
    required this.onClose,
    this.scrollController,
    this.session,
  });

  @override
  State<TerminalSearchOverlay> createState() => _TerminalSearchOverlayState();
}

class _TerminalSearchOverlayState extends State<TerminalSearchOverlay> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _caseSensitive = false;
  bool _semanticSearch = false;
  int _currentMatch = 0;
  int _totalMatches = 0;
  List<int> _matchLineIndices = [];
  List<String> _semanticResults = [];

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
        _matchLineIndices.clear();
        _semanticResults.clear();
      });
      return;
    }

    if (_semanticSearch && widget.session != null) {
      final results = widget.session!.searchTerminalOutput(query);
      setState(() {
        _semanticResults = results;
        _totalMatches = results.length;
        _currentMatch = results.isNotEmpty ? 1 : 0;
        _matchLineIndices.clear();
      });
      return;
    }

    final buffer = widget.terminal.buffer;
    final bufferText = buffer.getText();
    final searchText = _caseSensitive ? query : query.toLowerCase();
    final targetText = _caseSensitive ? bufferText : bufferText.toLowerCase();

    int count = 0;
    int start = 0;
    final List<int> offsets = [];
    while (true) {
      final idx = targetText.indexOf(searchText, start);
      if (idx == -1) break;
      count++;
      offsets.add(idx);
      start = idx + searchText.length;
    }

    final lineIndices = <int>[];
    for (final offset in offsets) {
      lineIndices.add(_offsetToLineIndex(buffer, offset));
    }

    setState(() {
      _totalMatches = count;
      _currentMatch = count > 0 ? 1 : 0;
      _matchLineIndices = lineIndices;
      _semanticResults.clear();
    });

    if (count > 0) {
      _scrollToFirstMatch();
    }
  }

  int _offsetToLineIndex(Buffer buffer, int offset) {
    int accumulated = 0;
    for (int i = 0; i < buffer.height; i++) {
      final lineText = buffer.lines[i].getText();
      if (offset >= accumulated && offset < accumulated + lineText.length) {
        return i;
      }
      accumulated += lineText.length + 1;
    }
    return buffer.height > 0 ? buffer.height - 1 : 0;
  }

  void _scrollToFirstMatch() {
    _scrollToMatch(0);
  }

  void _scrollToMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _totalMatches) return;

    if (_semanticSearch) {
      // Semantic results do not map to exact lines; skip scroll.
      return;
    }

    final lineIndex = _matchLineIndices[matchIndex];
    final scroll = widget.scrollController;
    if (scroll != null && scroll.hasClients) {
      scroll.jumpTo(lineIndex * _estimatedLineHeight);
    }
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatch = _currentMatch >= _totalMatches ? 1 : _currentMatch + 1;
    });
    _scrollToMatch(_currentMatch - 1);
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatch = _currentMatch <= 1 ? _totalMatches : _currentMatch - 1;
    });
    _scrollToMatch(_currentMatch - 1);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                      setState(() => _semanticSearch = !_semanticSearch);
                      _performSearch();
                    },
                    icon: Icon(
                      Icons.psychology,
                      size: 18,
                      color: _semanticSearch ? PkmTheme.primary : PkmTheme.secondary,
                    ),
                    tooltip: 'semantic search',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
              if (_semanticSearch && _semanticResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _semanticResults.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${index + 1}. ${_semanticResults[index]}',
                          style: const TextStyle(
                            color: PkmTheme.text,
                            fontFamily: PkmTheme.fontTerminal,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
