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

  /// Attaches this handler to a terminal to receive OSC callbacks.
  void attach(Terminal terminal) {
    _terminal = terminal;
    terminal.onPrivateOSC = _onPrivateOSC;
  }

  /// Feeds raw terminal output to the handler for URL extraction.
  ///
  /// Scans the raw text for OSC 8 open sequences and records discovered URLs.
  void processOutput(String text) {
    _extractUrlsFromRawText(text);
  }

  /// Returns the URL at the given buffer line and column, if any.
  String? getUrlAt(int line, int column) {
    _cleanupDetached();
    for (final entry in _entries) {
      if (!entry.line.attached) continue;
      if (entry.line.index == line && column >= entry.startCol && column < entry.endCol) {
        return entry.url;
      }
    }
    return null;
  }

  /// Returns all unique URLs detected in OSC 8 sequences.
  List<String> get detectedUrls => _detectedUrls.toList();

  /// Clears entries for lines that have scrolled out of the buffer.
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
      // OSC 8 open sequence: ESC ] 8 ; params ; URI ST
      _pending.add(_PendingHyperlink(
        buffer.currentLine,
        buffer.cursorX,
        url,
      ));
    } else {
      // OSC 8 close sequence: ESC ] 8 ; params ; ST
      if (_pending.isEmpty) return;

      final pending = _pending.removeLast();
      if (!pending.startLine.attached) return;

      final endLine = buffer.currentLine;
      final endCol = buffer.cursorX;

      _storeHyperlink(pending, endLine, endCol);
    }
  }

  void _storeHyperlink(_PendingHyperlink pending, BufferLine endLine, int endCol) {
    if (pending.startLine == endLine) {
      // Single-line hyperlink.
      if (endCol > pending.startCol) {
        _entries.add(_HyperlinkEntry(
          pending.startLine,
          pending.startCol,
          endCol,
          pending.url,
        ));
      }
    } else {
      // Multi-line hyperlink.
      final width = _terminal!.viewWidth;
      // Start line: from start column to end of line.
      _entries.add(_HyperlinkEntry(
        pending.startLine,
        pending.startCol,
        width,
        pending.url,
      ));
      // End line: from beginning to end column.
      if (endLine.attached) {
        _entries.add(_HyperlinkEntry(
          endLine,
          0,
          endCol,
          pending.url,
        ));
      }
      // Note: intermediate full lines between start and end are not tracked.
      // This is sufficient for common tools like `ls --hyperlink=auto`.
    }
  }

  void _extractUrlsFromRawText(String text) {
    // OSC 8 open: ESC ] 8 ; params ; URI ST
    // ST is BEL (\x07) or ESC \\ (\x1b\\).
    // The close sequence has an empty URI.
    // This regex matches open sequences and captures the URI.
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

  /// Disposes resources.
  void dispose() {
    _entries.clear();
    _pending.clear();
    _detectedUrls.clear();
    _terminal = null;
  }
}
