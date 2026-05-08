import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/config/termisol_config.dart';

void main() {
  group('TermisolConfig', () {
    test('default config has sensible values', () {
      const config = TermisolConfig.defaultConfig;

      expect(config.fontFamily, 'JetBrains Mono');
      expect(config.fontSize, 14.0);
      expect(config.scrollbackLines, 100000);
      expect(config.cursorBlink, isTrue);
      expect(config.cursorStyle, CursorStyle.block);
    });

    test('copyWith creates modified copy', () {
      const config = TermisolConfig.defaultConfig;
      final modified = config.copyWith(fontSize: 16.0);

      expect(modified.fontSize, 16.0);
      expect(modified.fontFamily, config.fontFamily);
    });

    test('toJson and fromJson roundtrip', () {
      const config = TermisolConfig.defaultConfig;
      final json = config.toJson();
      final restored = TermisolConfig.fromJson(json);

      expect(restored.fontFamily, config.fontFamily);
      expect(restored.fontSize, config.fontSize);
      expect(restored.scrollbackLines, config.scrollbackLines);
      expect(restored.cursorBlink, config.cursorBlink);
    });
  });

  group('ClipboardConfig', () {
    test('defaults are correct', () {
      const config = ClipboardConfig();
      expect(config.enableBracketedPaste, isTrue);
      expect(config.copyOnSelect, isFalse);
      expect(config.historySize, 50);
    });
  });
}
