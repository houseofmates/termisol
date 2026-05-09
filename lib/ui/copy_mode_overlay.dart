import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';

/// a full-screen overlay for browsing and copying terminal scrollback.
///
/// press `q` or click the close button to exit. type in the search box to
/// filter lines. select text and tap "copy selection" to copy to the system
/// clipboard.
class CopyModeOverlay extends StatefulWidget {
  final Terminal terminal;
  final VoidCallback onClose;

  const CopyModeOverlay({
    super.key,
    required this.terminal,
    required this.onClose,
  });

  @override
  State<CopyModeOverlay> createState() => _CopyModeOverlayState();
}

class _LineMapping {
  final int displayStart;
  final int displayEnd;
  final int bufferLine;

  _LineMapping({
    required this.displayStart,
    required this.displayEnd,
    required this.bufferLine,
  });
}

class _CopyModeOverlayState extends State<CopyModeOverlay> {
  final _focusNode = FocusNode();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  TextSelection? _textSelection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Build filtered display text and a mapping to buffer lines.
  ({String text, List<_LineMapping> mappings}) _buildDisplayMappings() {
    final buffer = widget.terminal.buffer;
    final height = buffer.height;
    const maxLines = 500;
    final startLine = height > maxLines ? height - maxLines : 0;

    final mappings = <_LineMapping>[];
    final builder = StringBuffer();
    int offset = 0;

    for (int i = startLine; i < height; i++) {
      final lineText = buffer.lines[i].getText();
      if (_searchQuery.isNotEmpty &&
          !lineText.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }
      mappings.add(_LineMapping(
        displayStart: offset,
        displayEnd: offset + lineText.length,
        bufferLine: i,
      ));
      builder.write(lineText);
      offset += lineText.length;
      if (i < height - 1) {
        builder.write('\n');
        offset += 1;
      }
    }

    return (text: builder.toString(), mappings: mappings);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _copySelection() async {
    final selection = _textSelection;
    if (selection == null || selection.isCollapsed) return;

    final display = _buildDisplayMappings();
    final start = selection.start.clamp(0, display.text.length);
    final end = selection.end.clamp(0, display.text.length);

    CellOffset? beginOffset;
    CellOffset? endOffset;

    for (final mapping in display.mappings) {
      if (beginOffset == null && start >= mapping.displayStart && start <= mapping.displayEnd) {
        beginOffset = CellOffset(start - mapping.displayStart, mapping.bufferLine);
      }
      if (endOffset == null && end >= mapping.displayStart && end <= mapping.displayEnd) {
        endOffset = CellOffset(end - mapping.displayStart, mapping.bufferLine);
      }
    }

    if (beginOffset == null || endOffset == null) return;

    final range = BufferRangeLine(beginOffset, endOffset);
    final text = widget.terminal.buffer.getText(range);
    if (text.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } on Exception catch (e, stack) {
        debugPrint('copy selection failed: $e\n$stack');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _buildDisplayMappings();
    final displayText = display.text;
    final hasSelection = _textSelection != null && !_textSelection!.isCollapsed;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        color: PkmTheme.background.withValues(alpha: 0.95),
        child: Column(
          children: [
            // Header bar
            Container(
              height: 44,
              color: PkmTheme.tabActiveBg,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Text(
                    'copy mode — press q to exit',
                    style: TextStyle(
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: hasSelection ? _copySelection : null,
                    child: Text(
                      'copy selection',
                      style: TextStyle(
                        color: hasSelection
                            ? PkmTheme.primary
                            : PkmTheme.secondary,
                        fontFamily: PkmTheme.fontUi,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: PkmTheme.text,
                      size: 18,
                    ),
                    onPressed: widget.onClose,
                    tooltip: 'close',
                  ),
                ],
              ),
            ),
            // Search box
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  color: PkmTheme.text,
                  fontFamily: PkmTheme.fontTerminal,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'search...',
                  hintStyle: const TextStyle(
                    color: PkmTheme.secondary,
                    fontFamily: PkmTheme.fontTerminal,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: PkmTheme.terminalBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: PkmTheme.secondary,
                    size: 18,
                  ),
                ),
              ),
            ),
            // Scrollable selectable text
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  displayText,
                  style: const TextStyle(
                    fontFamily: PkmTheme.fontTerminal,
                    fontSize: 14,
                    color: PkmTheme.text,
                  ),
                  onSelectionChanged: (selection, cause) {
                    setState(() => _textSelection = selection);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
