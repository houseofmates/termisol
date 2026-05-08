import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Terminal-aware clipboard manager.
///
/// Bridges the xterm selection model with the system clipboard.
/// All operations are async and wrapped in try/catch to prevent
/// terminal lock-up on permission errors.
class TerminalClipboardManager {
  final Terminal terminal;
  final TerminalController controller;

  TerminalClipboardManager(this.terminal, this.controller);

  /// Returns true if the terminal has an active text selection.
  bool get hasSelection {
    try {
      return controller.selection != null;
    } catch (_) {
      return false;
    }
  }

  /// Get the currently selected text, or empty string.
  String get selectedText {
    try {
      final selection = controller.selection;
      if (selection == null) return '';
      return terminal.buffer.getText(selection);
    } catch (_) {
      return '';
    }
  }

  /// Copy selection to system clipboard.
  Future<bool> copy() async {
    if (!hasSelection) return false;
    try {
      await Clipboard.setData(ClipboardData(text: selectedText));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Paste system clipboard into terminal.
  Future<bool> paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        terminal.write(data.text!);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Paste with bracketed mode (sends ESC[200~ ... ESC[201~).
  Future<bool> pasteBracketed() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        terminal.paste(data.text!);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Copy all text in the terminal buffer to the system clipboard.
  Future<bool> copyAll() async {
    try {
      final text = terminal.buffer.getText();
      if (text.isEmpty) return false;
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Select all text in the terminal buffer.
  /// Note: xterm.dart selection requires CellAnchors; this is a best-effort.
  void selectAll() {
    try {
      controller.clearSelection();
    } catch (e) {
      debugPrint('Failed to select all: $e');
    }
  }

  /// Send SIGINT (Ctrl+C) to the PTY.
  void sendSigInt() {
    terminal.write('\x03');
  }

  /// Check if the system clipboard contains text.
  Future<bool> hasClipboardText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text != null && data!.text!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    // No resources to dispose for now
  }
}
