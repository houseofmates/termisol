import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';
import '../lib/core/editor_validator.dart';

/// Complex Text Test Suite for Multi-Cursor Editor
/// 
/// Tests multi-cursor functionality with complex text including Unicode,
/// emojis, bidirectional text, combining characters, and special scripts
/// to ensure robustness across all text scenarios.
void main() {
  group('Multi-Cursor Complex Text Tests', () {
    
    testWidgets('should handle emoji sequences correctly', (WidgetTester tester) async {
      final emojiContent = _generateEmojiContent();
      
      final editor = EditTerminal(
        filePath: '/test/emoji.txt',
        initialContent: emojiContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different emoji positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 60));
      await tester.tapAt(Offset(200, 120));
      await tester.tapAt(Offset(300, 180));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Type at emoji positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('EMOJI'), isTrue);
      
      // Verify emojis are preserved
      expect(editor._controller.text.contains('🚀'), isTrue);
      expect(editor._controller.text.contains('🎉'), isTrue);
      expect(editor._controller.text.contains('💻'), isTrue);
    });
    
    testWidgets('should handle combining characters and diacritics', (WidgetTester tester) async {
      final combiningContent = _generateCombiningContent();
      
      final editor = EditTerminal(
        filePath: '/test/combining.txt',
        initialContent: combiningContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors near combining characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(120, 70));
      await tester.tapAt(Offset(220, 140));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type ASCII characters near combining characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('TEST'), isTrue);
      
      // Verify combining characters are preserved
      expect(editor._controller.text.contains('é'), isTrue); // e + combining acute
      expect(editor._controller.text.contains('ñ'), isTrue); // n + combining tilde
      expect(editor._controller.text.contains('ö'), isTrue); // o + combining diaeresis
    });
    
    testWidgets('should handle right-to-left text correctly', (WidgetTester tester) async {
      final rtlContent = _generateRTLContent();
      
      final editor = EditTerminal(
        filePath: '/test/rtl.txt',
        initialContent: rtlContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors in RTL text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(150, 80));
      await tester.tapAt(Offset(250, 160));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type in RTL context
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('RTL'), isTrue);
      
      // Verify RTL characters are preserved
      expect(editor._controller.text.contains('مرحبا'), isTrue);
      expect(editor._controller.text.contains('שלום'), isTrue);
      expect(editor._controller.text.contains('العربية'), isTrue);
    });
    
    testWidgets('should handle mixed bidirectional text', (WidgetTester tester) async {
      final bidiContent = _generateBidiMixedContent();
      
      final editor = EditTerminal(
        filePath: '/test/bidi_mixed.txt',
        initialContent: bidiContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors in mixed bidirectional text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.tapAt(Offset(300, 150));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Type in mixed context
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('MIX'), isTrue);
      
      // Verify all text types are preserved
      expect(editor._controller.text.contains('English'), isTrue);
      expect(editor._controller.text.contains('العربية'), isTrue);
      expect(editor._controller.text.contains('עברית'), isTrue);
      expect(editor._controller.text.contains('🌍'), isTrue);
    });
    
    testWidgets('should handle complex scripts (Chinese, Japanese, Korean)', (WidgetTester tester) async {
      final cjkContent = _generateCJKContent();
      
      final editor = EditTerminal(
        filePath: '/test/cjk.txt',
        initialContent: cjkContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors in CJK text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(120, 70));
      await tester.tapAt(Offset(220, 140));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type ASCII in CJK context
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('CJK'), isTrue);
      
      // Verify CJK characters are preserved
      expect(editor._controller.text.contains('你好'), isTrue);
      expect(editor._controller.text.contains('こんにちは'), isTrue);
      expect(editor._controller.text.contains('안녕하세요'), isTrue);
      expect(editor._controller.text.contains('漢字'), isTrue);
      expect(editor._controller.text.contains('ひらがな'), isTrue);
      expect(editor._controller.text.contains('한글'), isTrue);
    });
    
    testWidgets('should handle mathematical symbols and equations', (WidgetTester tester) async {
      final mathContent = _generateMathContent();
      
      final editor = EditTerminal(
        filePath: '/test/math.txt',
        initialContent: mathContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors near mathematical symbols
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(130, 80));
      await tester.tapAt(Offset(230, 160));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type near mathematical symbols
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('MATH'), isTrue);
      
      // Verify mathematical symbols are preserved
      expect(editor._controller.text.contains('∑'), isTrue);
      expect(editor._controller.text.contains('∏'), isTrue);
      expect(editor._controller.text.contains('∫'), isTrue);
      expect(editor._controller.text.contains('∞'), isTrue);
      expect(editor._controller.text.contains('±'), isTrue);
    });
    
    testWidgets('should handle zero-width characters and invisible text', (WidgetTester tester) async {
      final invisibleContent = _generateInvisibleContent();
      
      final editor = EditTerminal(
        filePath: '/test/invisible.txt',
        initialContent: invisibleContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors near invisible characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type near invisible characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('VIS'), isTrue);
      
      // Verify invisible characters are handled correctly
      // Note: Zero-width characters don't have visible representation
      // but should be preserved in the text
      expect(editor._controller.text.length, greaterThan(10));
    });
    
    testWidgets('should handle complex Unicode normalization', (WidgetTester tester) async {
      final normalizationContent = _generateNormalizationContent();
      
      final editor = EditTerminal(
        filePath: '/test/normalization.txt',
        initialContent: normalizationContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different normalization forms
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(110, 60));
      await tester.tapAt(Offset(210, 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type near normalized characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('NORM'), isTrue);
      
      // Verify characters are preserved (they may be normalized internally)
      expect(editor._controller.text.length, greaterThan(20));
    });
  });
  
  group('Complex Text Validation Tests', () {
    
    test('should validate emoji content', () {
      final emojiContent = _generateEmojiContent();
      
      final result = EditorValidator.validateFileContent('/test/emoji.txt', emojiContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate combining character content', () {
      final combiningContent = _generateCombiningContent();
      
      final result = EditorValidator.validateFileContent('/test/combining.txt', combiningContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate RTL content', () {
      final rtlContent = _generateRTLContent();
      
      final result = EditorValidator.validateFileContent('/test/rtl.txt', rtlContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate CJK content', () {
      final cjkContent = _generateCJKContent();
      
      final result = EditorValidator.validateFileContent('/test/cjk.txt', cjkContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate mathematical content', () {
      final mathContent = _generateMathContent();
      
      final result = EditorValidator.validateFileContent('/test/math.txt', mathContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate mixed complex content', () {
      final mixedContent = _generateMixedComplexContent();
      
      final result = EditorValidator.validateFileContent('/test/mixed_complex.txt', mixedContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should handle very long Unicode strings', () {
      final longUnicode = _generateLongUnicodeContent(100000); // 100KB
      
      final result = EditorValidator.validateFileContent('/test/long_unicode.txt', longUnicode);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate cursor positions in complex text', () {
      final complexText = _generateMixedComplexContent();
      final cursorOffsets = [10, 50, 100, 200, 500]; // Various positions
      
      final result = EditorValidator.validateMultiCursorSetup(cursorOffsets, complexText.length);
      
      expect(result.isValid, isTrue);
    });
    
    test('should sanitize dangerous Unicode content', () {
      final dangerousContent = 'Text with <script>alert("xss")</script> and 🚀 emojis';
      
      final result = EditorValidator.validateInput(dangerousContent);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.security));
    });
    
    test('should allow safe Unicode input', () {
      final safeInput = 'Hello 🌍 你好 🚀 こんにちは 안녕하세요 مرحبا שלום';
      
      final result = EditorValidator.validateInput(safeInput);
      
      expect(result.isValid, isTrue);
    });
  });
  
  group('Complex Text Performance Tests', () {
    
    test('should handle large complex text efficiently', () {
      final largeComplex = _generateLargeComplexContent(500 * 1024); // 500KB
      
      final stopwatch = Stopwatch()..start();
      
      final result = EditorValidator.validateFileContent('/test/large_complex.txt', largeComplex);
      
      stopwatch.stop();
      
      expect(result.isValid, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
    
    test('should handle many Unicode operations efficiently', () {
      final unicodeStrings = List.generate(1000, (index) => _generateRandomUnicodeString(100));
      
      final stopwatch = Stopwatch()..start();
      
      for (final unicodeString in unicodeStrings) {
        final result = EditorValidator.validateInput(unicodeString);
        expect(result.isValid, isTrue);
      }
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}

// Helper functions for generating complex test content
String _generateEmojiContent() {
  return '''
Emoji Test Content
==================

Simple emojis: 🚀 🎉 💻 📱 🌍 ⭐ 💡 🔥 🌈 🎨 🎭 🎪 🎯 🎲

Face emojis: 😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 👹 👺 🤡 💩 👻 💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾

Animal emojis: 🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🦟 🦗 🕷️ 🕸️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🐆 🐅 🐃 🦏 🦛 🦒 🐘 🦏 🦛 🦒 🐪 🐫 🦙 🦘 🐐 🐑 🐏 🐄 🐎 🐖 🐀 🐁 🐿️ 🦔 🦇 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵

Food emojis: 🍎 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🦴 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🍝 🍜 🍲 🍛 🍣 🍱 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🡡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 🫖 ☕️ 🫖 🍵 🧃 🥤 🧋 🧃 🧉 🧊 🥢 🍽️ 🍴 🥄 🔪 🏺

Activity emojis: ⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛷 🚴 🚵 🪂 🏇 🧘 🏻‍♀️ 🏋️‍♀️ 🏌️‍♀️ 🤸‍♀️ 🤼‍♀️ 🤽‍♀️ 🤾‍♀️ 🤹‍♀️ 🧗‍♀️ 🪆 🪅 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🪘 🪇 🪈 🪉 🪊 🪋 🪬 🎲 ♟️ 🎯 🎳 🎮 🕹️ 🎰 🧩

Travel emojis: 🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🏍️ 🛵 🚲 🛴 🛹 🛼 🚁 🛸 🚀 🛰️ 🛩️ 🛫 🛬 🪂 ⛵️ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓️ 🪝 ⛽️ 🚧 🚨 🚥 🚦 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 🎪 🎭 🎨

Symbol emojis: ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎️ ♈️ ♉️ ♊️ ♋️ ♌️ ♍️ ♎️ ♏️ ♐️ ♑️ ♒️ ♓️ 🆔 ⭐️ ⭐️ 🌟 🌠 ✨ 💫 🌙 🌛 🌜 🌚 🌝 🌞 🪐 ⭐️ 🌟 🌠 ✨ 💫 🌙 🌛 🌜 🌚 🌝 🌞 🪐

This emoji content tests multi-cursor editing with various emoji sequences.
''';
}

String _generateCombiningContent() {
  return '''
Combining Character Test Content
=================================

Latin letters with combining diacritics:
a + ́ = á (e with acute)
a + ̀ = à (e with grave)
a + ̂ = â (e with circumflex)
a + ̃ = ã (e with tilde)
a + ̈ = ä (e with diaeresis)
a + ̄ = ā (e with macron)
a + ̆ = ă (e with breve)
a + ̇ = ȧ (e with dot above)
a + ̣ = ạ (e with dot below)
a + ̌ = ǎ (e with caron)

n + ̃ = ñ (n with tilde)
o + ̈ = ö (o with diaeresis)
u + ̈ = ü (u with diaeresis)
c + ̧ = ç (c with cedilla)
s + ̌ = š (s with caron)
z + ̌ = ž (z with caron)

Multiple combining marks:
a + ̈ + ́ = ä́ (e with diaeresis and acute)
o + ̈ + ̃ = ö̃ (o with diaeresis and tilde)
u + ̈ + ̄ = ǖ (u with diaeresis and macron)

Greek letters with diacritics:
α + ́ = ά (alpha with acute)
ε + ̀ = ὲ (epsilon with grave)
η + ̃ = η̃ (eta with tilde)
ι + ̈ = ϊ (iota with diaeresis)
ο + ̄ = ο̄ (omicron with macron)
υ + ̈ = ϋ (upsilon with diaeresis)
ω + ́ = ώ (omega with acute)

Cyrillic letters with diacritics:
а + ́ = а́ (a with acute)
е + ̀ = ѐ (e with grave)
и + ̈ = ӥ (i with diaeresis)
о + ̆ = о̆ (o with breve)
у + ̋ = ӳ (u with double acute)

Combining marks for tone:
a + ̀ = à (low tone)
a + ́ = á (high tone)
a + ̂ = â (rising tone)
a + ̌ = ǎ (falling tone)

Combining marks for vowel length:
a + ̄ = ā (long vowel)
a + ̆ = ă (short vowel)

Combining marks for ring below:
a + ̥ = ḁ (ring below)
i + ̥ = i̥ (ring below)

Combining marks for vertical line:
o + ̍ = o̍ (vertical line above)
o + ̎ = o̎ (double vertical line above)

Complex combining sequences:
a + ̈ + ́ + ̃ = ä́̃ (multiple combining marks)
e + ̀ + ̆ + ̇ = è̆̇ (complex sequence)

This content tests multi-cursor editing with combining characters and diacritics.
''';
}

String _generateRTLContent() {
  return '''
Right-to-Left Text Test Content
===============================

Arabic Text:
مرحبا بالعالم
كيف حالك اليوم؟
الطقس جميل اليوم
أحب البرمجة بلغة دارت
المكتبة تحتوي على العديد من الكتب
الشمس مشرقة والسماء صافية

Arabic Numbers:
١٢٣٤٥٦٧٨٩٠ (Arabic-Indic digits)
أرقام عربية: ١٢٣٤٥٦٧٨٩٠
التاريخ: ١٥/٦/٢٠٢٣
الوقت: ٢:٣٠ مساءً

Arabic Punctuation:
.،؟!؛

Hebrew Text:
שלום עולם
מה שלומך היום?
המזג אידיאלי היום
אני אוהב לתכנת בשפת דארט
הספרייה מכילה ספרים רבים
השמש זורחת והשמיים בהירים

Hebrew Numbers:
א1234567890 (Hebrew letters used as numbers)
תאריך: 15/6/2023
שעה: 14:30

Mixed Arabic and Hebrew:
مرحبا שלום עולם العالم
كيف מה שלומך?

RTL with LTR embedded:
Arabic: "Hello World" مرحبا بالعالم
Hebrew: "Programming" תכנות

RTL with numbers and symbols:
السعر: \$100.00
النسبة: 75.5%
التاريخ: 2023-06-15
البريد الإلكتروني: user@example.com
الموقع: http://example.com

RTL with emojis:
🌍 مرحبا بالعالم 🚀
📚 المكتبة تحتوي على كتب 📖
☀️ الشمس مشرقة 🌤️
💻 البرمجة ممتعة 🎮

Bidirectional Algorithm Testing:
This is English text followed by العربية text then more English.
Numbers like 123 work correctly in RTL context.
URLs like http://example.com/path/file.html should work.

Complex RTL Example:
قال المبرمج: "I love programming in Dart!" وأضاف: "إنها لغة رائعة".
The programmer said: "أنا أحب البرمجة بلغة دارت" and added: "It's a great language".

This RTL content tests multi-cursor editing with right-to-left text.
''';
}

String _generateBidiMixedContent() {
  return '''
Mixed Bidirectional Text Test Content
======================================

English (LTR) + Arabic (RTL) + Hebrew (RTL) + Emojis:
Hello World مرحبا بالعالم שלום עולם 🌍🚀💻

Programming in multiple languages:
Programming البرمجة תכנות Programming
Code الكود קוד Code
Developer المطور מפתח Developer

Mixed sentences:
I love programming أحب البرمجة אני אוהב תכנות
The weather is nice الطقس جميل המזג אידיאלי

Numbers in different contexts:
Price: \$100.00 السعر: 100.00 دولار
Date: 2023-06-15 التاريخ: 15/6/2023
Time: 14:30 الوقت: 2:30 مساءً

URLs and emails:
Website: http://example.com الموقع: http://example.com
Email: user@example.com البريد: user@example.com

Mixed with emojis:
📚 Books الكتب ספרים 📖
🎮 Games الألعاب משחקים 🎯
🌍 Languages اللغات שפות 🗣️

Code examples with comments:
// This is a comment في العربية
function greet() {
  console.log("Hello مرحبا שלום");
}

// Arabic comment: هذا تعليق باللغة العربية
// Hebrew comment: זהו הערה בעברית
const message = "Mixed text message";

Mathematical expressions:
E = mc² الطاقة = الكتلة × السرعة²
x + y = z س + ص = ع

Mixed quotes:
English: "Hello" Arabic: "مرحبا" Hebrew: "שלום"
'Single quotes' 'علامات تنصيص مفردة' 'גרש יחיד'

Mixed punctuation:
English period. Arabic period. Hebrew period.
English comma, Arabic comma, Hebrew comma,
English question? Arabic question? Hebrew question?

Complex mixed paragraph:
The developer said "أنا أحب البرمجة بلغة دارت" and then wrote in Hebrew "אני מעדיף תכנות בפייתון" while the system displayed 🚀 Launch successful! which was understood by all programmers regardless of their native language.

This mixed bidirectional content tests complex multi-cursor editing scenarios.
''';
}

String _generateCJKContent() {
  return '''
CJK (Chinese, Japanese, Korean) Test Content
============================================

Chinese (Simplified):
你好世界
编程很有趣
今天天气很好
我喜欢学习新技术
北京是中国的首都
上海是一个现代化城市

Chinese Characters (Hanzi):
汉字是中文的基本单位
简体字和繁体字有区别
常用汉字约有3000个
汉字的笔画很重要
部首帮助理解字义

Chinese Numbers:
一二三四五六七八九十
壹贰叁肆伍陆柒捌玖拾
百千万亿

Japanese:
こんにちは世界
プログラミングは楽しい
今日は天気が良い
新しい技術を学ぶのが好き
東京は日本の首都です
大阪は美食の町です

Japanese Scripts:
Hiragana: ひらがな あいうえお かきくけこ さしすせそ
Katakana: カタカナ アイウエオ カキクケコ サシスセソ
Kanji: 漢字 日本語 東京 大阪 学校 先生 学生

Japanese Numbers:
一二三四五六七八九十
壱弐参四五六七八九十
百千万億

Korean:
안녕하세요 세계
프로그래밍은 재미있습니다
오늘 날씨가 좋습니다
새로운 기술을 배우는 것을 좋아합니다
서울은 한국의 수도입니다
부산은 아름다운 항구 도시입니다

Korean Scripts:
Hangul: 안녕하세요 한국어 조선말
Hanja: 漢字 韓國語 朝鮮語

Korean Numbers:
하나 둘 셋 넷 다섯 여섯 일곱 여덟 아홉 열
일이삼사오육칠팔구십

Mixed CJK Content:
中文 + 日本語 + 한국어 = 多语言
你好 + こんにちは + 안녕하세요 = Hello in CJK
编程 + プログラミング + 프로그래밍 = Programming

CJK with Emojis:
🇨🇳 中国 🇯🇵 日本 🇰🇷 한국
🏮 灯笼 🗾 富士山 🏰 景福宫
🥟 饺子 🍣 寿司 🥘 韩式拌饭

CJK with Latin:
Hello 你好 こんにちは 안녕하세요
Programming 编程 プログラミング 프로그래밍
Computer 计算机 コンピューター 컴퓨터

CJK with Numbers:
2023年 2023年 2023년
100元 100円 100원

CJK Punctuation:
Chinese: 。！？，；：
Japanese: 。！？、
Korean: .!?,

CJK Technical Terms:
人工智能 人工知能 인공지능
机器学习 機械学習 기계 학습
深度学习 深層学習 심층 학습
神经网络 ニューラルネットワーク 신경망

This CJK content tests multi-cursor editing with East Asian characters.
''';
}

String _generateMathContent() {
  return '''
Mathematical Symbols Test Content
=================================

Basic Math Operators:
+ - × ÷ = ≠ ≈ ≡ ≢ ≣

Greek Letters:
α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω
Α Β Γ Δ Ε Ζ Η Θ Ι Κ Λ Μ Ν Ξ Ο Π Ρ Σ Τ Υ Φ Χ Ψ Ω

Mathematical Symbols:
∑ ∏ ∫ ∂ ∇ ∆ ∞ ± ∓ × ÷ ≤ ≥ < > = ≠ ≈ ≡ ≢ ≣
∈ ∉ ⊂ ⊃ ⊆ ⊇ ∪ ∩ ∅ ∁ ∖ ∆ ∇ ∂ ∃ ∀

Set Theory:
∈ ∉ ⊂ ⊃ ⊆ ⊇ ∪ ∩ ∅ ∁ ∖
∀ ∃ ∄ ∁ ∖ ∆ ∇

Logic:
∧ ∨ ¬ → ↔ ⊕ ⊤ ⊥
∀ ∃ ∄

Calculus:
∫ ∫∫ ∫∫∫ ∮ ∯ ∰
∂ ∇ ∆
lim sup inf max min

Geometry:
∠ ∡ ∢ ∟ ∠ ∡ ∢ ∟
° ′ ″ ‴
∥ ∦ ⊥
△ □ ▭ ○ ◇

Arrows:
← → ↑ ↓ ↔ ↕ ↖ ↗ ↘ ↙
⇐ ⇒ ⇑ ⇕ ⇖ ⇗ ⇘ ⇙
⇢ ⇣ ⇤ ⇥ ⇦ ⇧ ⇨ ⇩
⬀ ⬁ ⬂ ⬃ ⬄ ⬅ ⬆ ⬇ ⬈ ⬉ ⬊ ⬋ ⬌ ⬍ ⬎ ⬏

Brackets and Parentheses:
( ) [ ] { } 〈 〉 ⟨ ⟩
⌈ ⌉ ⌊ ⌋ ⎰ ⎱ ⎴ ⎵
⎛ ⎞ ⎜ ⎝ ⎠ ⎡ ⎤ ⎢ ⎣ ⎦

Superscripts and Subscripts:
⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ⁺ ⁻ ⁼ ⁽ ⁾
₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ ₊ ₋ ₌ ₍ ₎

Fractions:
¼ ½ ¾ ⅓ ⅔ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞
⅟ Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ Ⅵ Ⅶ Ⅷ Ⅸ Ⅹ Ⅺ Ⅻ
Ⅼ Ⅽ Ⅾ Ⅿ ⅰ ⅱ ⅲ ⅳ ⅴ ⅵ ⅶ ⅷ ⅸ ⅹ ⅺ ⅻ ⅼ ⅽ ⅾ ⅿ

Currency:
$ ¢ £ € ¥ ₽ ₹ ₩ ₪ ₫ ₨ ₮ ₯ ₤ ₠ ₧ ₢ ₣ ₤ ₥ ₦ ₧ ₨ ₩ ₪ ₫ ₭ ₮ ₯

Mathematical Expressions:
E = mc²
a² + b² = c²
∑(i=1 to n) i = n(n+1)/2
∫₀^∞ e^(-x²) dx = √π/2
lim(x→∞) (1 + 1/x)^x = e
∀x ∈ ℝ, x² ≥ 0
∃x ∈ ℚ, x² = 2

Complex Numbers:
i = √(-1)
z = a + bi
|z| = √(a² + b²)
z* = a - bi

Matrix Operations:
[1 2; 3 4] × [5 6; 7 8] = [19 22; 43 50]
det(A) = ad - bc
A⁻¹ = (1/det(A)) × [d -b; -c a]

This mathematical content tests multi-cursor editing with symbols and equations.
''';
}

String _generateInvisibleContent() {
  return '''
Invisible Character Test Content
================================

Zero-Width Characters:
Zero-Width Space: ​
Zero-Width Non-Joiner: ‌
Zero-Width Joiner: ‍
Zero-Width No-Break Space: ⁠

Text with invisible characters:
Hello​World (zero-width space)
Test‌ing (zero-width non-joiner)
Prog‍ramming (zero-width joiner)
Invisible⁠text (zero-width no-break space)

Soft Hyphen:
Soft hyphen: pro­gram­ming
Discretionary hyphen: word­wrap

Other Invisible Characters:
Object Replacement Character:
Replacement Character:
Word Joiner: ⁡
Function Application: ⁡
Invisible Separator: ⁢
Invisible Plus: ⁣
Invisible Times: ⁤
Invisible Comma: ⁥

Combining Grapheme Joiner:
a͏b (combining grapheme joiner)

Text Direction Formatting:
Left-to-Right Mark: ‎
Right-to-Left Mark: ‏
Left-to-Right Embedding: ‪
Right-to-Left Embedding: ‫
Pop Directional Formatting: ‬
Left-to-Right Override: ‭
Right-to-Left Override: ‮

Complex Example:
Hello​World‌Testing‍Programming⁡with⁢invisible⁣characters⁤and⁥formatting

Bidirectional with invisible:
English‌Arabic‏Hebrew‎Text

Line and Paragraph Separators:
Line Separator:  
Paragraph Separator:  

This content tests multi-cursor editing with invisible and zero-width characters.
''';
}

String _generateNormalizationContent() {
  return '''
Unicode Normalization Test Content
===================================

NFC (Normalization Form C - Canonical Decomposition followed by Canonical Composition):
é (composed form) vs e + ́ (decomposed form)
ñ (composed form) vs n + ̃ (decomposed form)
ö (composed form) vs o + ̈ (decomposed form)

NFD (Normalization Form D - Canonical Decomposition):
e + ́ (decomposed) vs é (composed)
n + ̃ (decomposed) vs ñ (composed)
o + ̈ (decomposed) vs ö (composed)

NFKC (Normalization Form KC - Compatibility Decomposition followed by Canonical Composition):
ﬁ (fi ligature) vs f + i
ﬂ (fl ligature) vs f + l
① (circled one) vs 1
② (circled two) vs 2
③ (circled three) vs 3

NFKD (Normalization Form KD - Compatibility Decomposition):
ﬁ → f + i
ﬂ → f + l
① → 1
② → 2
③ → 3

Compatibility Characters:
Fullwidth: ＡＢＣＤＥＦ vs ABCDEF
Halfwidth: ｱｲｳｴｵ vs アイウエオ
Superscripts: ¹²³⁴⁵⁶⁷⁸⁹⁰ vs 1234567890
Subscripts: ₀₁₂₃₄₅₆₇₈₉ vs 0123456789

Canonical Equivalence:
Multiple ways to write the same character:
é can be: é or e + ́
ñ can be: ñ or n + ̃
ö can be: ö or o + ̈
ü can be: ü or u + ̈

Complex Combinations:
Characters with multiple combining marks:
a + ̈ + ́ can normalize to ä́
o + ̈ + ̃ can normalize to ö̃
u + ̈ + ̄ can normalize to ǖ

Greek Examples:
ά (alpha with acute) vs α + ́
έ (epsilon with acute) vs ε + ́
ή (eta with acute) vs η + ́
ί (iota with acute) vs ι + ́
ό (omicron with acute) vs ο + ́
ύ (upsilon with acute) vs υ + ́
ώ (omega with acute) vs ω + ́

Cyrillic Examples:
ё (yo) vs е + ̈
ѓ (gje) vs г + ́
і (i) vs и + ̆
ї (yi) vs і + ̈

Armenian Examples:
ու (u) vs ո + ւ
և (ev) vs ե + ւ

Hebrew Examples:
אַ (alef with patah) vs א + ַ
בָ (bet with qamats) vs ב + ָ
גִ (gimel with hiriq) vs ג + ִ

This content tests multi-cursor editing with Unicode normalization forms.
''';
}

String _generateMixedComplexContent() {
  return '''
Mixed Complex Text Content
============================

This file contains various complex text types mixed together:

English: Hello World!
Chinese: 你好世界！
Japanese: こんにちは世界！
Korean: 안녕하세요 세계!
Arabic: مرحبا بالعالم!
Hebrew: שלום עולם!
Russian: Привет мир!
Hindi: नमस्ते दुनिया!
Thai: สวัสดีโลก!

Emojis: 🚀🎉💻📱🌍⭐💡🔥🌈🎨🎭

Mathematical: E = mc², ∑(i=1 to n) i = n(n+1)/2, ∀x ∈ ℝ, x² ≥ 0

Programming: function greet() { return "Hello 🌍!"; }

Combining characters: café, naïve, résumé, coöperate

Bidirectional mixed: English العربية Hebrew עברית English again

Numbers: 123, ١٢٣, 一二三, １２３

Currency: \$100, €100, ¥100, ₹100, ₽100

Punctuation: .,!?;:،؟!؛

Symbols: ©®™℠℡℧℩KÅℬℭ℮ℯℰℱℲℳℴℵℶℷℸℹ℺℻ℼℽℾℿ

This mixed content tests all complex text types together.
''';
}

String _generateRandomUnicodeString(int length) {
  final unicodeRanges = [
    // Basic Latin
    0x0020, 0x007F,
    // Latin-1 Supplement
    0x00A0, 0x00FF,
    // Latin Extended-A
    0x0100, 0x017F,
    // Cyrillic
    0x0400, 0x04FF,
    // Arabic
    0x0600, 0x06FF,
    // Hebrew
    0x0590, 0x05FF,
    // CJK Unified Ideographs
    0x4E00, 0x9FFF,
    // Hiragana
    0x3040, 0x309F,
    // Katakana
    0x30A0, 0x30FF,
    // Hangul Syllables
    0xAC00, 0xD7AF,
    // Mathematical Operators
    0x2200, 0x22FF,
    // Miscellaneous Symbols
    0x2600, 0x26FF,
    // Emojis
    0x1F300, 0x1F5FF,
    0x1F600, 0x1F64F,
    0x1F680, 0x1F6FF,
    0x1F700, 0x1F77F,
    0x1F780, 0x1F7FF,
    0x1F800, 0x1F8FF,
    0x1F900, 0x1F9FF,
    0x1FA00, 0x1FA6F,
    0x1FA70, 0x1FAFF,
    0x2600, 0x26FF,
    0x2700, 0x27BF,
  ];
  
  final buffer = StringBuffer();
  final random = DateTime.now().millisecondsSinceEpoch;
  
  for (int i = 0; i < length; i++) {
    final rangeIndex = ((random + i) % (unicodeRanges.length ~/ 2)) * 2;
    final start = unicodeRanges[rangeIndex];
    final end = unicodeRanges[rangeIndex + 1];
    final codePoint = start + ((random + i * 7) % (end - start + 1));
    
    if (codePoint >= 0x10000) {
      // Surrogate pair for characters beyond BMP
      final surrogate = codePoint - 0x10000;
      final highSurrogate = 0xD800 + (surrogate >> 10);
      final lowSurrogate = 0xDC00 + (surrogate & 0x3FF);
      buffer.writeCharCode(highSurrogate);
      buffer.writeCharCode(lowSurrogate);
    } else {
      buffer.writeCharCode(codePoint);
    }
  }
  
  return buffer.toString();
}

String _generateLargeComplexContent(int sizeInBytes) {
  final buffer = StringBuffer();
  final complexSections = [
    _generateEmojiContent(),
    _generateCombiningContent(),
    _generateRTLContent(),
    _generateCJKContent(),
    _generateMathContent(),
    _generateMixedComplexContent(),
  ];
  
  while (buffer.length < sizeInBytes) {
    final section = complexSections[buffer.length % complexSections.length];
    buffer.write(section);
    buffer.write('\n--- Section Break ---\n');
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}

String _generateLongUnicodeContent(int sizeInBytes) {
  final buffer = StringBuffer();
  
  while (buffer.length < sizeInBytes) {
    final unicodeString = _generateRandomUnicodeString(100);
    buffer.write(unicodeString);
    buffer.write(' ');
    
    if (buffer.length % 1000 == 0) {
      buffer.write('\n');
    }
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}
