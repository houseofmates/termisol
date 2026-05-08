import 'dart:async';
import 'package:xterm/xterm.dart';

/// Manages terminal focus events for bracketed paste mode and vim/emacs integration.
/// When terminal gains focus, sends bracketed paste enable sequence.
/// When terminal loses focus, sends bracketed paste disable sequence.
class FocusManager {
  final Terminal terminal;
  final TerminalController controller;
  final Function(bool)? onFocusChanged;
  final Function(bool)? onFocusEvent;

  FocusManager(this.terminal, this.controller, this.onFocusChanged, this.onFocusEvent);

  /// Initialize focus management.
  void initialize() {
    // xterm 4.0.0: Terminal does not have an onFocus setter.
    // terminal.onFocus = _handleTerminalFocus;
  }

  /// Handle focus events from the terminal widget.
  void _handleTerminalFocus(bool hasFocus) {
    // Notify listeners of focus change
    onFocusChanged?.call(hasFocus);
    
    // Send bracketed paste sequences when focus changes
    if (hasFocus) {
      // Terminal gained focus - enable bracketed paste
      terminal.write('\x1b[?2004h');
    } else {
      // Terminal lost focus - disable bracketed paste
      terminal.write('\x1b[?2004l');
    }
    
    // Notify focus event listeners (for vim/emacs integration)
    onFocusEvent?.call(hasFocus);
  }

  /// Enable focus events from terminal.
  void enableFocusEvents() {
    // xterm 4.0.0: Terminal does not have an onFocus setter.
    // terminal.onFocus = _handleTerminalFocus;
  }

  /// Disable focus events from terminal.
  void disableFocusEvents() {
    // xterm 4.0.0: Terminal does not have an onFocus setter.
    // terminal.onFocus = null;
  }
}
