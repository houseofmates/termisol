import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// mouse protocol modes.
enum TermisolMouseMode {
  none,
  normal, // x10 - basic click reporting
  buttonTracking, // x11 - button press/release
  any, // x11 - all events
  highlight, // highlight tracking (for urls)
  urxvt, // urxvt extended mode
  sgr, // sgr - extended coordinates
}

/// manages mouse protocol (sgr, utf-8, urxvt) for terminal applications.
/// enables clicking links, selecting text in vim/tmux, and interactive apps.
class MouseProtocolManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;
  TermisolMouseMode _currentMode = TermisolMouseMode.none;

  MouseProtocolManager(this.terminal, this.controller);

  /// enable mouse protocol with specified mode.
  void enable(TermisolMouseMode mode) {
    if (!_enabled || _currentMode != mode) {
      _enabled = true;
      _currentMode = mode;

      switch (mode) {
        case TermisolMouseMode.none:
          break;
        case TermisolMouseMode.normal:
          terminal.write('\x1b[?9h'); // x10
          break;
        case TermisolMouseMode.buttonTracking:
          terminal.write('\x1b[?1000h'); // x11
          break;
        case TermisolMouseMode.any:
          terminal.write('\x1b[?1003h'); // x11 any
          break;
        case TermisolMouseMode.highlight:
          terminal.write('\x1b[?1001h'); // highlight
          break;
        case TermisolMouseMode.urxvt:
          terminal.write('\x1b[?1015h'); // urxvt
          break;
        case TermisolMouseMode.sgr:
          terminal.write('\x1b[?1006h'); // sgr
          break;
      }

      if (kDebugMode) debugPrint('Mouse protocol enabled: $mode');
    }
  }

  /// disable mouse protocol.
  void disable() {
    if (_enabled) {
      _enabled = false;
      _currentMode = TermisolMouseMode.none;

      // disable all mouse modes
      terminal.write('\x1b[?9l'); // x10
      terminal.write('\x1b[?1000l'); // x11
      terminal.write('\x1b[?1003l'); // x11 any
      terminal.write('\x1b[?1001l'); // highlight
      terminal.write('\x1b[?1015l'); // urxvt
      terminal.write('\x1b[?1006l'); // sgr

      if (kDebugMode) debugPrint('Mouse protocol disabled');
    }
  }

  /// check if mouse protocol is enabled.
  bool get isEnabled => _enabled;

  /// get current mouse mode.
  TermisolMouseMode get currentMode => _currentMode;

  /// handle mouse events from terminal.
  void handleMouseEvent(String event) {
    if (!_enabled) return;

    // parse mouse event sequences
    if (event.startsWith('\x1b[M') || event.startsWith('\x1b[<')) {
      final parts = event.split(';');
      if (parts.length >= 3) {
        final buttonCode = int.tryParse(parts[0].substring(3)) ?? 0;
        final x = int.tryParse(parts[1]) ?? 0;
        final y =
            int.tryParse(parts[2].substring(0, parts[2].indexOf('M'))) ?? 0;

        // determine button and action
        final button = _getButtonName(buttonCode);
        final action = _getAction(buttonCode);

        if (kDebugMode) debugPrint('Mouse: $button $action at ($x, $y)');

        // handle url clicks (highlight mode)
        if (_currentMode == TermisolMouseMode.highlight &&
            button == 'left' &&
            action == 'press') {
          _handleUrlClick(x, y);
        }
      }
    }
  }

  /// get button name from code.
  String _getButtonName(int code) {
    switch (code & 3) {
      case 0:
        return 'left';
      case 1:
        return 'middle';
      case 2:
        return 'right';
      case 3:
        return 'release';
      default:
        return 'unknown';
    }
  }

  /// get action from button code.
  String _getAction(int code) {
    if ((code & 32) != 0) return 'move';
    if ((code & 64) != 0) return 'wheel';
    if ((code & 1) != 0) return 'press';
    return 'release';
  }

  /// handle potential url clicks in highlight mode.
  void _handleUrlClick(int x, int y) {
    if (kDebugMode) debugPrint('Potential URL click at ($x, $y)');
  }

  void dispose() {
    disable();
  }
}
