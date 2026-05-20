import 'package:xterm/xterm.dart';

class _PendingHyperlink {
  final BufferLine startLine;
  final int startCol;
  final String url;

  _PendingHyperlink(this.startLine, this.startCol, this.url);
}

class _HyperlinkEntry {
  final BufferLine line;
  final int startCol;
  final int endCol;
  final String url;

  _HyperlinkEntry(this.line, this.startCol, this.endCol, this.url);
}

/// handles osc 8 hyperlinks in terminal output.
///
/// parses osc 8 escape sequences and maintains a map of buffer positions to urls.
/// uses the terminal's [onprivateosc] callback for accurate position tracking.
class HyperlinkHandler {
  Terminal? _terminal;
  final List<_PendingHyperlink> _pending = [];
  final List<_HyperlinkEntry> _entries = [];
  final Set<String> _detectedUrls = {};

  /// attaches this handler to a terminal to receive osc callbacks.
  void attach(Terminal terminal) {
    _terminal = terminal;
    terminal.onPrivateOSC = _onPrivateOSC;
  }

  /// feeds raw terminal output to the handler for url extraction.
  ///
  /// scans the raw text for osc 8 open sequences and records discovered urls.
  void processOutput(String text) {
    _extractUrlsFromRawText(text);
  }

  /// returns the url at the given buffer line and column, if any.
  String? getUrlAt(int line, int column) {
    _cleanupDetached();
    for (final entry in _entries) {
      if (!entry.line.attached) continue;
      if (entry.line.index == line &&
          column >= entry.startCol &&
          column < entry.endCol) {
        return entry.url;
      }
    }
    return null;
  }

  /// returns all unique urls detected in osc 8 sequences.
  List<String> get detectedUrls => _detectedUrls.toList();

  /// clears entries for lines that have scrolled out of the buffer.
  void clearOldEntries() {
    _cleanupDetached();
  }

  void _cleanupDetached() {
    _entries.removeWhere((e) => !e.line.attached);
    _pending.removeWhere((p) => !p.startLine.attached);
  }

  void _onPrivateOSC(String code, List<String> args) {
    if (code != '8' || args.isEmpty) return;

    final url = args.last;
    final buffer = _terminal!.buffer;

    if (url.isNotEmpty) {
      // osc 8 open sequence: esc ] 8 ; params ; uri st
      _pending.add(_PendingHyperlink(buffer.currentLine, buffer.cursorX, url));
    } else {
      // osc 8 close sequence: esc ] 8 ; params ; st
      if (_pending.isEmpty) return;

      final pending = _pending.removeLast();
      if (!pending.startLine.attached) return;

      final endLine = buffer.currentLine;
      final endCol = buffer.cursorX;

      _storeHyperlink(pending, endLine, endCol);
    }
  }

  void _storeHyperlink(
    _PendingHyperlink pending,
    BufferLine endLine,
    int endCol,
  ) {
    if (pending.startLine == endLine) {
      // single-line hyperlink.
      if (endCol > pending.startCol) {
        _entries.add(
          _HyperlinkEntry(
            pending.startLine,
            pending.startCol,
            endCol,
            pending.url,
          ),
        );
      }
    } else {
      // multi-line hyperlink.
      final width = _terminal!.viewWidth;
      // start line: from start column to end of line.
      _entries.add(
        _HyperlinkEntry(
          pending.startLine,
          pending.startCol,
          width,
          pending.url,
        ),
      );
      // end line: from beginning to end column.
      if (endLine.attached) {
        _entries.add(_HyperlinkEntry(endLine, 0, endCol, pending.url));
      }
      // note: intermediate full lines between start and end are not tracked.
      // this is sufficient for common tools like `ls --hyperlink=auto`.
    }
  }

  void _extractUrlsFromRawText(String text) {
    // osc 8 open: esc ] 8 ; params ; uri st
    // st is bel (\x07) or esc \\ (\x1b\\).
    // the close sequence has an empty uri.
    // this regex matches open sequences and captures the uri.
    final osc8Regex = RegExp(
      r'\u001b\]8;[^;\u0007\u001b]*;([^\u0007\u001b]+)(?:\u0007|\u001b\\)',
    );
    for (final match in osc8Regex.allMatches(text)) {
      final url = match.group(1)!;
      if (url.isNotEmpty) {
        _detectedUrls.add(url);
      }
    }
  }

  /// disposes resources.
  void dispose() {
    _entries.clear();
    _pending.clear();
    _detectedUrls.clear();
    _terminal = null;
  }
}
