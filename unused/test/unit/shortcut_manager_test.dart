import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/ui/shortcut_manager.dart';

void main() {
  group('ShortcutManager', () {
    test('loads standard preset by default', () async {
      final manager = ShortcutManager();
      await manager.load();

      expect(manager.shortcuts.containsKey('new_tab'), isTrue);
      expect(manager.shortcuts.containsKey('close_tab'), isTrue);
      expect(manager.shortcuts.containsKey('search'), isTrue);
    });

    test('applyPreset switches presets', () {
      final manager = ShortcutManager();
      manager.applyPreset(ShortcutPreset.standard);

      expect(manager.shortcuts['copy']?.shortcut, 'Ctrl+Shift+C');

      manager.applyPreset(ShortcutPreset.emacs);
      expect(manager.shortcuts['copy']?.shortcut, 'Alt+W');
    });

    test('getReference returns human-readable list', () {
      final manager = ShortcutManager();
      manager.applyPreset(ShortcutPreset.standard);

      final refs = manager.getReference();
      expect(refs.isNotEmpty, isTrue);
      expect(refs.first.description.isNotEmpty, isTrue);
      expect(refs.first.shortcut.isNotEmpty, isTrue);
    });
  });
}
