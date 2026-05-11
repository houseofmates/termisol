import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// manages terminal focus events using flutter's focusnode.
/// emits ansi focus in (\x1b[i) and focus out (\x1b[o) sequences
/// to the pty when focus changes, per xterm focus-event protocol.
class FocusManager {
  final Terminal terminal;
  final TerminalController controller;
  final Function(bool)? onFocusChanged;
  final Function(bool)? onFocusEvent;
  final FocusNode focusNode = FocusNode();
  bool _listening = false;

  FocusManager(
    this.terminal,
    this.controller,
    this.onFocusChanged,
    this.onFocusEvent,
  );

  void initialize() {
    if (!_listening) {
      focusNode.addListener(_onFocusChanged);
      _listening = true;
    }
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

  void enableFocusEvents() {
    initialize();
  }

  void disableFocusEvents() {
    if (_listening) {
      focusNode.removeListener(_onFocusChanged);
      _listening = false;
    }
  }

  void dispose() {
    disableFocusEvents();
    focusNode.dispose();
  }
}
