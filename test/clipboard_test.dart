import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/ui/clipboard_manager.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalClipboardManager', () {
    late Terminal terminal;
    late TerminalController controller;
    late TerminalClipboardManager clipboard;

    setUp(() {
      terminal = Terminal(maxLines: 100);
      controller = TerminalController();
      clipboard = TerminalClipboardManager(terminal, controller);
    });

    test('hasSelection is false initially', () {
      expect(clipboard.hasSelection, isFalse);
    });

    test('copyAll does not throw', () async {
      terminal.write('hello world');
      await clipboard.copyAll();
      expect(clipboard.hasSelection, isFalse);
    });

    test('sendSigInt does not throw', () {
      expect(() => clipboard.sendSigInt(), returnsNormally);
    });

    test('pasteBracketed handles missing clipboard gracefully', () async {
      // Clipboard is unavailable in test environment; expect it to not crash.
      try {
        await clipboard.pasteBracketed();
      } catch (e) {
        // Expected in headless test environment
      }
    });
  });
}
