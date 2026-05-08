import 'package:flutter/foundation.dart';

/// Lightweight directory tracker that parses terminal output to detect the
/// current working directory.
///
/// Uses OSC 7 escape sequences when available, falling back to heuristic
/// prompt parsing for bash/zsh-style prompts.
class DirectoryTracker {
  final ValueNotifier<String> directory = ValueNotifier<String>('');

  String? get currentDirectory => directory.value.isEmpty ? null : directory.value;

  final StringBuffer _buffer = StringBuffer();
  static const int _maxBufferSize = 4096;

  // OSC 7: \x1b]7;file://hostname/path\x07 or \x1b]7;file://hostname/path\x1b\\
  static final RegExp _osc7Regex = RegExp(
    r'\x1b\]7;file://[^/]*([^\x07\x1b]+)(?:\x07|\x1b\\)',
  );

  // Prompt patterns applied after stripping ANSI codes.
  static final List<RegExp> _promptPatterns = [
    // user@host:~/path $   or   user@host:/abs/path $
    RegExp(r':\s*([~/][^\$#%>\n]*?)\s*[\$#%>]\s*$'),
    // ~/path $   or   /abs/path $   (line start)
    RegExp(r'^([~/][^\$#%>\n]*?)\s*[\$#%>]\s*$'),
  ];

  /// Feed a chunk of terminal output to the tracker.
  void processOutput(String text) {
    _buffer.write(text);

    String bufferStr = _buffer.toString();
    if (bufferStr.length > _maxBufferSize) {
      bufferStr = bufferStr.substring(bufferStr.length - _maxBufferSize);
      _buffer.clear();
      _buffer.write(bufferStr);
    }

    // Attempt OSC 7 extraction first.
    final oscMatch = _osc7Regex.firstMatch(bufferStr);
    if (oscMatch != null) {
      final rawPath = oscMatch.group(1)!;
      final path = _decodeUriPath(rawPath);
      _updateDirectory(path);
      // Discard everything up to and including the matched sequence.
      _buffer.clear();
      if (oscMatch.end < bufferStr.length) {
        _buffer.write(bufferStr.substring(oscMatch.end));
      }
      return;
    }

    // Fallback: examine the last few lines for prompt patterns.
    final lines = bufferStr.split(RegExp(r'\r?\n'));
    for (final line in lines.reversed.take(3)) {
      final clean = _stripAnsi(line);
      for (final pattern in _promptPatterns) {
        final match = pattern.firstMatch(clean);
        if (match != null) {
          final path = match.group(1)!.trim();
          if (path.isNotEmpty) {
            _updateDirectory(path);
            return;
          }
        }
      }
    }
  }

  void _updateDirectory(String path) {
    if (path != directory.value) {
      directory.value = path;
    }
  }

  /// Remove ANSI escape sequences from [text].
  static String _stripAnsi(String text) {
    return text
        .replaceAll(RegExp(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)'), '') // OSC
        .replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), ''); // CSI
  }

  /// Decode a percent-encoded path from an OSC 7 URI.
  static String _decodeUriPath(String encoded) {
    try {
      return Uri.decodeComponent(encoded);
    } catch (_) {
      return encoded;
    }
  }

  void dispose() {
    directory.dispose();
  }
}
