import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../config/pkm_theme.dart';

/// A full-screen overlay for browsing and copying terminal scrollback.
///
/// Press `q` or click the close button to exit. Type in the search box to
/// filter lines. Select text and tap "copy selection" to copy to the system
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

  /// Extract the last [maxLines] of buffer text.
  String _getBufferText() {
    final buffer = widget.terminal.buffer;
    final height = buffer.height;
    const maxLines = 500;
    final startLine = height > maxLines ? height - maxLines : 0;

    final range = BufferRangeLine(
      CellOffset(0, startLine),
      CellOffset(buffer.viewWidth > 0 ? buffer.viewWidth - 1 : 0, height - 1),
    );

    return buffer.getText(range);
  }

  /// Filter buffer text by the current search query.
  String _getFilteredText(String bufferText) {
    if (_searchQuery.isEmpty) return bufferText;
    final lines = bufferText.split('\n');
    final query = _searchQuery.toLowerCase();
    final filtered = lines.where((line) {
      return line.toLowerCase().contains(query);
    }).toList();
    return filtered.join('\n');
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _copySelection(String displayText) async {
    final selection = _textSelection;
    if (selection == null || selection.isCollapsed) return;

    final text = displayText.substring(selection.start, selection.end);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bufferText = _getBufferText();
    final displayText = _getFilteredText(bufferText);
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
                  Text(
                    'copy mode — press q to exit',
                    style: const TextStyle(
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: hasSelection
                        ? () => _copySelection(displayText)
                        : null,
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
