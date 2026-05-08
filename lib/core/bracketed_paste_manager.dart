import 'dart:async';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Manages bracketed paste mode (OSC 52) for secure paste operations.
/// When enabled, terminal surrounds pasted text with \[200~ and \[201~
class BracketedPasteManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;

  BracketedPasteManager(this.terminal, this.controller);

  /// Enable bracketed paste mode.
  void enable() {
    _enabled = true;
    terminal.write('\x1b[?2004h');
  }

  /// Disable bracketed paste mode.
  void disable() {
    _enabled = false;
    terminal.write('\x1b[?2004l');
  }

  /// Check if bracketed paste mode is currently enabled.
  bool get isEnabled => _enabled;

  /// Handle a paste operation with bracketed mode support.
  Future<void> handlePaste(String text) async {
    if (!_enabled) return;

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final pastedText = clipboardData?.text;
      if (pastedText != null) {
        // Apply bracketed paste escape sequences
        final escaped = pastedText
            .replaceAll('\\', '\\\\')
            .replaceAll('\x1b', '\x1b\x1b')
            .replaceAll('\x07', '\x1b\x07')
            .replaceAll('\x08', '\x1b\x08')
            .replaceAll('\x09', '\x1b\x09')
            .replaceAll('\x0a', '\x1b\x0a')
            .replaceAll('\x0b', '\x1b\x0b')
            .replaceAll('\x0c', '\x1b\x0c')
            .replaceAll('\x0d', '\x1b\x0d');

        // Send bracketed paste sequence with the escaped content
        terminal.write('\x1b[200~$escaped\x1b[201~');
      }
    } catch (e) {
      // Fallback to unbracketed paste if bracketed mode fails
      terminal.paste(text);
    }
  }
}
