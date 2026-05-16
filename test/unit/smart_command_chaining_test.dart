import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termisol/core/smart_command_chaining.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SmartCommandChaining smartChaining;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    smartChaining = SmartCommandChaining();
    await smartChaining.initialize();
  });

  group('SmartCommandChaining.forgetCommand', () {
    test('removes command from statistics', () async {
      const command = 'ls -la';
      smartChaining.recordCommand('session1', command);

      var popular = smartChaining.getPopularCommands();
      expect(popular.any((s) => s.command == command), isTrue);

      await smartChaining.forgetCommand(command);

      popular = smartChaining.getPopularCommands();
      expect(popular.any((s) => s.command == command), isFalse);
    });

    test('removes command from transitions in other patterns', () async {
      const cmd1 = 'git status';
      const cmd2 = 'git add .';

      smartChaining.recordCommand('session1', cmd1);
      smartChaining.recordCommand('session1', cmd2);

      var suggestions = smartChaining.suggestNext(cmd1);
      expect(suggestions.any((s) => s.command == cmd2), isTrue);

      await smartChaining.forgetCommand(cmd2);

      suggestions = smartChaining.suggestNext(cmd1);
      expect(suggestions.any((s) => s.command == cmd2), isFalse);
    });

    test('removes command as a pattern source', () async {
      const cmd1 = 'npm install';
      const cmd2 = 'npm start';

      smartChaining.recordCommand('session1', cmd1);
      smartChaining.recordCommand('session1', cmd2);

      var suggestions = smartChaining.suggestNext(cmd1);
      expect(suggestions.isNotEmpty, isTrue);

      await smartChaining.forgetCommand(cmd1);

      suggestions = smartChaining.suggestNext(cmd1);
      expect(suggestions.isEmpty, isTrue);
    });

    test('removes command from multi-depth patterns', () async {
      const cmd1 = 'mkdir test';
      const cmd2 = 'cd test';
      const cmd3 = 'touch file.txt';

      smartChaining.recordCommand('session1', cmd1);
      smartChaining.recordCommand('session1', cmd2);
      smartChaining.recordCommand('session1', cmd3);

      // Verify chain: cmd1|cmd2 -> cmd3
      final context = [cmd1, cmd2];
      var suggestions = smartChaining.suggestChain(context);
      expect(suggestions.any((s) => s.command == cmd3), isTrue);

      await smartChaining.forgetCommand(cmd3);

      suggestions = smartChaining.suggestChain(context);
      expect(suggestions.any((s) => s.command == cmd3), isFalse);
    });

    test('handles forgetting non-existent command gracefully', () async {
      final result = await smartChaining.forgetCommand('non-existent');
      expect(result, isTrue);
    });
  });
}
