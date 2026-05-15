import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/pkm_theme.dart';

enum _HintType { url, path, email }

class _HintMatch {
  final String text;
  final _HintType type;
  final int line;
  final int start;
  final int end;

  _HintMatch({
    required this.text,
    required this.type,
    required this.line,
    required this.start,
    required this.end,
  });
}

/// an overlay that scans the visible terminal buffer for urls, file paths, and
/// email addresses, then displays letter hints over each match. typing the
/// hint letters opens urls/emails or copies paths to the clipboard.
class HintsModeOverlay extends StatefulWidget {
  final Terminal terminal;
  final VoidCallback onClose;

  const HintsModeOverlay({
    super.key,
    required this.terminal,
    required this.onClose,
  });

  @override
  State<HintsModeOverlay> createState() => _HintsModeOverlayState();
}

class _HintsModeOverlayState extends State<HintsModeOverlay> {
  final _focusNode = FocusNode();
  String _typedLetters = '';
  late final List<_HintMatch> _hints;

  static final _urlRegex = RegExp(
    r'''(?:https?://|ftp://)[^\s<>"'`\)\]\}]+''',
    caseSensitive: false,
  );

  static final _emailRegex = RegExp(
    r'''[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}''',
  );

  static final _pathRegex = RegExp(
    r'''(?:^|\s)((?:~?/|\.\.?/)[^ \t\n\r<>\"'|]+)''',
  );

  @override
  void initState() {
    super.initState();
    _hints = _scanHints();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<_HintMatch> _scanHints() {
    final buffer = widget.terminal.buffer;
    final startLine = buffer.scrollBack;
    final endLine = buffer.height;
    final matches = <_HintMatch>[];

    for (int line = startLine; line < endLine; line++) {
      final lineText = buffer.lines[line].getText();

      // Find URLs
      for (final match in _urlRegex.allMatches(lineText)) {
        matches.add(
          _HintMatch(
            text: match.group(0)!,
            type: _HintType.url,
            line: line,
            start: match.start,
            end: match.end,
          ),
        );
      }

      // Find emails
      for (final match in _emailRegex.allMatches(lineText)) {
        if (_overlapsExisting(matches, line, match.start, match.end)) {
          continue;
        }
        matches.add(
          _HintMatch(
            text: match.group(0)!,
            type: _HintType.email,
            line: line,
            start: match.start,
            end: match.end,
          ),
        );
      }

      // Find paths
      for (final match in _pathRegex.allMatches(lineText)) {
        final path = match.group(1)!;
        final start = match.start + match.group(0)!.indexOf(path);
        final end = start + path.length;

        if (_overlapsExisting(matches, line, start, end)) {
          continue;
        }
        matches.add(
          _HintMatch(
            text: path,
            type: _HintType.path,
            line: line,
            start: start,
            end: end,
          ),
        );
      }
    }

    return matches;
  }

  bool _overlapsExisting(
    List<_HintMatch> matches,
    int line,
    int start,
    int end,
  ) {
    for (final m in matches) {
      if (m.line == line && start < m.end && end > m.start) {
        return true;
      }
    }
    return false;
  }

  String _hintLabel(int index) {
    final chars = <String>[];
    int n = index;
    do {
      chars.add(String.fromCharCode(97 + (n % 26)));
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return chars.reversed.join();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    final key = event.logicalKey.keyLabel.toLowerCase();
    if (key.length == 1) {
      final code = key.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        setState(() {
          _typedLetters += key;
          _checkHint();
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _checkHint() {
    if (_typedLetters.isEmpty) return;

    for (int i = 0; i < _hints.length; i++) {
      if (_hintLabel(i) == _typedLetters) {
        _executeHint(_hints[i]);
        return;
      }
    }

    final hasPrefix = _hints.asMap().keys.any(
      (i) => _hintLabel(i).startsWith(_typedLetters),
    );
    if (!hasPrefix) {
      setState(() => _typedLetters = '');
    }
  }

  Future<void> _executeHint(_HintMatch hint) async {
    try {
      switch (hint.type) {
        case _HintType.url:
          final uri = Uri.parse(hint.text);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          break;
        case _HintType.path:
          await Clipboard.setData(ClipboardData(text: hint.text));
          break;
        case _HintType.email:
          final uri = Uri.parse('mailto:${hint.text}');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          break;
      }
    } on Exception catch (e, stack) {
      debugPrint('executeHint failed: $e\n$stack');
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = widget.terminal.viewWidth;
        final viewHeight = widget.terminal.viewHeight;
        if (viewWidth <= 0 || viewHeight <= 0) {
          return const SizedBox.shrink();
        }

        final cellWidth = constraints.maxWidth / viewWidth;
        final cellHeight = constraints.maxHeight / viewHeight;
        final buffer = widget.terminal.buffer;
        final scrollBack = buffer.scrollBack;

        final visibleHints = <int>[];
        for (int i = 0; i < _hints.length; i++) {
          final label = _hintLabel(i);
          if (_typedLetters.isEmpty || label.startsWith(_typedLetters)) {
            visibleHints.add(i);
          }
        }

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: Container(
            color: Colors.black.withValues(alpha: 0.25),
            child: Stack(
              children: [
                // Header
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: PkmTheme.popup,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: PkmTheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        'hints mode — type letters to open, esc to cancel',
                        style: TextStyle(
                          color: PkmTheme.text,
                          fontFamily: PkmTheme.fontUi,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                // Hint pills
                for (final index in visibleHints)
                  Positioned(
                    left: _hints[index].start * cellWidth,
                    top: (_hints[index].line - scrollBack) * cellHeight - 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: PkmTheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _hintLabel(index),
                        style: const TextStyle(
                          color: PkmTheme.background,
                          fontFamily: PkmTheme.fontTerminal,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
