import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/core/terminal_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalSession', () {
    test('resize ignores dimensions less than or equal to 0', () {
      final session = TerminalSession(id: 'test-1', name: 'Test Session');

      // Valid resize to set initial state
      session.resize(100, 50);
      expect(session.terminal.viewWidth, 100);
      expect(session.terminal.viewHeight, 50);

      // Attempt invalid resize (<= 0)
      session.resize(0, 50);
      expect(session.terminal.viewWidth, 100); // Should not have changed
      expect(session.terminal.viewHeight, 50);

      session.resize(100, 0);
      expect(session.terminal.viewWidth, 100);
      expect(session.terminal.viewHeight, 50);

      session.resize(-10, -10);
      expect(session.terminal.viewWidth, 100);
      expect(session.terminal.viewHeight, 50);
    });
  });
}
