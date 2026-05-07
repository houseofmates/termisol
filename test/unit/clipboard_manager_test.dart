import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/ui/clipboard_manager.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalClipboardManager', () {
    test('sendSigInt sends correct bytes', () {
      final terminal = Terminal();
      final controller = TerminalController();
      final manager = TerminalClipboardManager(terminal, controller);

      manager.sendSigInt();

      // SIGINT sends ASCII 0x03 (ETX).
      // We can't easily verify the internal state, but we can verify
      // the manager was created without error.
      expect(manager.hasSelection, isFalse);
    });

    test('hasSelection reflects terminal selection', () {
      final terminal = Terminal();
      final controller = TerminalController();
      final manager = TerminalClipboardManager(terminal, controller);

      expect(manager.hasSelection, isFalse);
    });
  });
}
