import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Manages terminal focus events using Flutter's FocusNode.
/// Emits ANSI focus in (\x1b[I) and focus out (\x1b[O) sequences
/// to the PTY when focus changes, per xterm focus-event protocol.
class FocusManager {
  final Terminal terminal;
  final TerminalController controller;
  final Function(bool)? onFocusChanged;
  final Function(bool)? onFocusEvent;
  final FocusNode focusNode = FocusNode();

  FocusManager(this.terminal, this.controller, this.onFocusChanged, this.onFocusEvent);

  /// Initialize focus management by wiring the FocusNode listener.
  void initialize() {
    focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final hasFocus = focusNode.hasFocus;
    onFocusChanged?.call(hasFocus);
    onFocusEvent?.call(hasFocus);
    if (hasFocus) {
      terminal.write('\x1b[I');
    } else {
      terminal.write('\x1b[O');
    }
  }

  /// Enable focus events (idempotent; actual wiring happens in initialize).
  void enableFocusEvents() {
    if (!focusNode.hasListeners) {
      focusNode.addListener(_onFocusChanged);
    }
  }

  /// Disable focus events.
  void disableFocusEvents() {
    focusNode.removeListener(_onFocusChanged);
  }

  void dispose() {
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
  }
}
