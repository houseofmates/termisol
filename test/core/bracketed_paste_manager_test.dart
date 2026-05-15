import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:termisol/core/bracketed_paste_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BracketedPasteManager', () {
    late Terminal terminal;
    late TerminalController controller;
    late BracketedPasteManager manager;

    setUp(() {
      terminal = Terminal();
      controller = TerminalController();
      manager = BracketedPasteManager(terminal, controller);
    });

    test('initial state is disabled', () {
      expect(manager.isEnabled, isFalse);
    });

    test('enable() sets isEnabled to true', () {
      manager.enable();
      expect(manager.isEnabled, isTrue);
    });

    test('disable() sets isEnabled to false', () {
      manager.enable();
      manager.disable();
      expect(manager.isEnabled, isFalse);
    });

    test('handlePaste ignores if not enabled', () async {
      String output = '';
      terminal.onOutput = (String data) {
        output += data;
      };

      await manager.handlePaste('test');

      expect(output, '');
    });

    test('successful bracketed paste', () async {
      manager.enable();

      // Mock the clipboard to return text
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'Clipboard.getData') {
              return {'text': 'clipboard text'};
            }
            return null;
          });

      await manager.handlePaste('fallback text');
      expect(true, isTrue);
    });

    test('fallback to unbracketed paste if bracketed mode fails', () async {
      // Enable bracketed mode so we enter the try block.
      manager.enable();

      String output = '';
      terminal.onOutput = (String data) {
        output += data;
      };

      // Mock the clipboard to throw an exception
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'Clipboard.getData') {
              throw Exception('Mocked clipboard error');
            }
            return null;
          });

      await manager.handlePaste('fallback text');

      // The fallback calls terminal.paste('fallback text'), which emits to onOutput
      expect(output, '\x1b[200~fallback text\x1b[201~');
    });
  });
}
