import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/ui/edit.dart';
import '../lib/core/editor_validator.dart';
import 'dart:convert';
import 'dart:io';

/// Encoding and File Type Test Suite for Multi-Cursor Editor
/// 
/// Tests multi-cursor functionality with different file types, encodings,
/// and complex character sets to ensure robustness across all scenarios.
void main() {
  group('Multi-Cursor Encoding Tests', () {
    
    testWidgets('should handle UTF-8 encoded files', (WidgetTester tester) async {
      final utf8Content = _generateUTF8Content();
      
      final editor = EditTerminal(
        filePath: '/test/utf8.txt',
        initialContent: utf8Content,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at different positions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.tapAt(Offset(300, 150));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      expect(editor._cursors.length, equals(2)); // 2 additional + 1 main = 3 total
      
      // Type UTF-8 characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('UTF'), isTrue);
    });
    
    testWidgets('should handle Unicode and emoji characters', (WidgetTester tester) async {
      final unicodeContent = _generateUnicodeContent();
      
      final editor = EditTerminal(
        filePath: '/test/unicode.txt',
        initialContent: unicodeContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors near Unicode characters
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(150, 60));
      await tester.tapAt(Offset(250, 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type emoji characters
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
    });
    
    testWidgets('should handle bidirectional text', (WidgetTester tester) async {
      final bidiContent = _generateBidirectionalContent();
      
      final editor = EditTerminal(
        filePath: '/test/bidi.txt',
        initialContent: bidiContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors in bidirectional text
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(120, 70));
      await tester.tapAt(Offset(220, 140));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type in bidirectional context
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('BIDI'), isTrue);
    });
    
    testWidgets('should handle mixed encoding content', (WidgetTester tester) async {
      final mixedContent = _generateMixedEncodingContent();
      
      final editor = EditTerminal(
        filePath: '/test/mixed.txt',
        initialContent: mixedContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors in mixed content
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.tapAt(Offset(300, 150));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type ASCII characters in mixed content
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('MIX'), isTrue);
    });
  });
  
  group('File Type Tests', () {
    
    testWidgets('should handle JavaScript files with multi-cursor', (WidgetTester tester) async {
      final jsContent = _generateJavaScriptContent();
      
      final editor = EditTerminal(
        filePath: '/test/script.js',
        initialContent: jsContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at function definitions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(150, 80));
      await tester.tapAt(Offset(250, 160));
      await tester.tapAt(Offset(350, 240));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type JavaScript syntax
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('AWAIT'), isTrue);
    });
    
    testWidgets('should handle Python files with multi-cursor', (WidgetTester tester) async {
      final pythonContent = _generatePythonContent();
      
      final editor = EditTerminal(
        filePath: '/test/script.py',
        initialContent: pythonContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at class definitions
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(120, 70));
      await tester.tapAt(Offset(220, 140));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type Python syntax
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('DEF'), isTrue);
    });
    
    testWidgets('should handle JSON files with multi-cursor', (WidgetTester tester) async {
      final jsonContent = _generateJSONContent();
      
      final editor = EditTerminal(
        filePath: '/test/data.json',
        initialContent: jsonContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at JSON properties
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(100, 50));
      await tester.tapAt(Offset(200, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type JSON syntax
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('NEW'), isTrue);
    });
    
    testWidgets('should handle Markdown files with multi-cursor', (WidgetTester tester) async {
      final markdownContent = _generateMarkdownContent();
      
      final editor = EditTerminal(
        filePath: '/test/doc.md',
        initialContent: markdownContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at Markdown headers
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(80, 40));
      await tester.tapAt(Offset(180, 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type Markdown syntax
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('HEAD'), isTrue);
    });
    
    testWidgets('should handle configuration files with multi-cursor', (WidgetTester tester) async {
      final configContent = _generateConfigContent();
      
      final editor = EditTerminal(
        filePath: '/test/config.yaml',
        initialContent: configContent,
        readOnly: false,
      );
      
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
      await tester.pumpAndSettle();
      
      // Add cursors at configuration keys
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(Offset(120, 60));
      await tester.tapAt(Offset(220, 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      
      expect(editor._multiCursorMode, isTrue);
      
      // Type configuration syntax
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      
      expect(editor._controller.text.contains('CONF'), isTrue);
    });
  });
  
  group('Encoding Validation Tests', () {
    
    test('should validate UTF-8 content', () {
      final utf8Content = _generateUTF8Content();
      
      final result = EditorValidator.validateFileContent('/test/utf8.txt', utf8Content);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate Unicode content', () {
      final unicodeContent = _generateUnicodeContent();
      
      final result = EditorValidator.validateFileContent('/test/unicode.txt', unicodeContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should validate bidirectional content', () {
      final bidiContent = _generateBidirectionalContent();
      
      final result = EditorValidator.validateFileContent('/test/bidi.txt', bidiContent);
      
      expect(result.isValid, isTrue);
    });
    
    test('should reject invalid control characters', () {
      final invalidContent = 'Valid text\x00\x01\x02\x03Invalid control chars';
      
      final result = EditorValidator.validateFileContent('/test/invalid.txt', invalidContent);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.controlChars));
    });
    
    test('should sanitize dangerous content', () {
      final dangerousContent = '<script>alert("xss")</script>\nValid text';
      
      final result = EditorValidator.validateFileContent('/test/dangerous.txt', dangerousContent);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.security));
    });
    
    test('should handle large Unicode content', () {
      final largeUnicode = _generateLargeUnicodeContent(500 * 1024); // 500KB
      
      final result = EditorValidator.validateFileContent('/test/large_unicode.txt', largeUnicode);
      
      expect(result.isValid, isTrue);
    });
  });
  
  group('Input Sanitization Tests', () {
    
    test('should sanitize user input', () {
      final dangerousInput = '<script>alert("xss")</script>valid';
      
      final result = EditorValidator.validateInput(dangerousInput);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.security));
    });
    
    test('should allow safe Unicode input', () {
      final safeInput = 'Hello 🌍 你好 🚀';
      
      final result = EditorValidator.validateInput(safeInput);
      
      expect(result.isValid, isTrue);
    });
    
    test('should reject control characters in input', () {
      final controlInput = 'valid\x00\x01invalid';
      
      final result = EditorValidator.validateInput(controlInput);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.controlChars));
    });
    
    test('should limit input length', () {
      final longInput = 'a' * 2000; // Exceeds maxInputLength
      
      final result = EditorValidator.validateInput(longInput);
      
      expect(result.isValid, isFalse);
      expect(result.type, equals(ValidationType.inputLength));
    });
  });
}

// Helper functions for generating test content
String _generateUTF8Content() {
  return '''
UTF-8 Test File
=============

This file contains UTF-8 encoded text with various characters:

English: Hello World!
Spanish: ¡Hola Mundo!
French: Bonjour le monde!
German: Guten Tag Welt!
Italian: Ciao mondo!
Portuguese: Olá mundo!
Russian: Привет мир!
Chinese: 你好世界
Japanese: こんにちは世界
Korean: 안녕하세요 세계
Arabic: مرحبا بالعالم
Hebrew: שלום עולם
Thai: สวัสดีโลก
Hindi: नमस्ते दुनिया

Special characters: àáâãäåæçèéêë ìíîïðñòóôõö ùúûüýþÿ

Numbers: 0123456789
Symbols: !@#$%^&*()_+-=[]{}|;:,.<>?

Mixed content: This is UTF-8 encoded text with multiple languages and special characters.
''';
}

String _generateUnicodeContent() {
  return '''
Unicode Test File
=================

Emojis and Symbols:
🚀 🎉 💻 📱 🌍 ⭐ 💡 🔥 🌈 🎨 🎭 🎪 🎯 🎲 🎸 🎺 🎷 🎻 🎹 🎼 🎧 🎮 🎰 🎳 🎯 🎪 🎭 🎨

Mathematical Symbols:
∑ ∏ ∫ ∂ ∇ ∆ ∞ ± × ÷ ≈ ≠ ≤ ≥ ∈ ∉ ∪ ∩ ⊂ ⊃ ⊆ ⊇

Currency Symbols:
$ € £ ¥ ₽ ₹ ₩ ₪ ₫ ₡ ₨ ₮ ₯ ₤ ₠ ₧ ₢ ₣ ₤ ₥ ₦ ₧ ₨ ₩ ₪ ₫ ₭ ₮ ₯

Arrows and Shapes:
← → ↑ ↓ ↔ ↕ ↖ ↗ ↘ ↙ ⬆ ⬇ ⬅ ➡ ➢ ➣ ➤ ➥ ➦ ➧ ➨ ➩ ➪ ➫ ➬ ➭ ➮ ➯ ➰ ➱ ➲ ➳ ➴ ➵ ➶ ➷ ➸ ➹ ➺ ➻ ➼ ➽ ➾ ➿ ⤴ ⤵ ⤶ ⤷ ⤸ ⤹ ⤺ ⤻ ⤼ ⤽ ⤾ ⤿

Box Drawing Characters:
┌ ┍ ┎ ┏ ┐ ┑ ┒ ┓ └ ┕ ┖ ┗ ┘ ┙ ┚ ┛ ├ ┝ ┞ ┟ ┠ ┡ ┢ ┣ ┤ ┥ ┦ ┧ ┨ ┩ ┪ ┫ ┬ ┭ ┮ ┯ ┰ ┱ ┲ ┳ ┴ ┵ ┶ ┷ ┸ ┹ ┺ ┻ ┼ ┽ ┾ ┿ ╀ ╁ ╂ ╃ ╄ ╅ ╆ ╇ ╈ ╉ ╊ ╋ ╌ ╍ ╎ ╏

Block Elements:
▀ ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▉ ▊ ▋ ▌ ▍ ▎ ▏ ▐ ░ ▒ ▓ ▔ ▕ ▖ ▗ ▘ ▙ ▚ ▛ ▜ ▝ ▞ ▟ ■ □ ▢ ▣ ▤ ▥ ▦ ▧ ▨ ▩ ▪ ▫ ▬ ▭ ▮ ▯ ▰ ▱ ▲ △ ▴ ▵ ▶ ▷ ▸ ▹ ► ▻ ▼ ▽ ▾ ▿ ▀ ◁ ◂ ◃ ◄ ◅ ◆ ◇ ◈ ◉ ◊ ○ ◌ ◍ ◎ ● ◐ ◑ ◒ ◓ ◔ ◕ ◖ ◗ ◘ ◙ ◚ ◛ ◜ ◝ ◞ ◟ ◠ ◡ ◢ ◣ ◤ ◥ ◦ ◧ ◨ ◩ ◪ ◫ ◬ ◭ ◮ ◯ ◰ ◱ ◲ ◳ ◴ ◵ ◶ ◷ ◸ ◹ ◺ ◻ ◼ ◽ ◾ ◿

Geometric Shapes:
● ◐ ◑ ◒ ◓ ◔ ◕ ◖ ◗ ◘ ◙ ◚ ◛ ◜ ◝ ◞ ◟ ◠ ◡ ◢ ◣ ◤ ◥ ◦ ◧ ◨ ◩ ◪ ◫ ◬ ◭ ◮ ◯ ◰ ◱ ◲ ◳ ◴ ◵ ◶ ◷ ◸ ◹ ◺ ◻ ◼ ◽ ◾ ◿ ⬀ ⬁ ⬂ ⬃ ⬄ ⬅ ⬆ ⬇ ⬈ ⬉ ⬊ ⬋ ⬌ ⬍ ⬎ ⬏ ⬐ ⬑ ⬒ ⬓ ⬔ ⬕ ⬖ ⬗ ⬘ ⬙ ⬚ ⬛ ⬜ ⬝ ⬞ ⬟ ⬠ ⬡ ⬢ ⬣ ⬤ ⬥ ⬦ ⬧ ⬨ ⬩ ⬪ ⬫ ⬬ ⬭ ⬮ ⬯ ⬰ ⬱ ⬲ ⬳ ⬴ ⬵ ⬶ ⬷ ⬸ ⬹ ⬺ ⬻ ⬼ ⬽ ⬾ ⬿

Miscellaneous Symbols:
♠ ♣ ♥ ♦ ♩ ♪ ♫ ♬ ♭ ♮ ♯ ♰ ♱ ♲ ♳ ♴ ♵ ♶ ♷ ♸ ♹ ♺ ♻ ♼ ♽ ♾ ♿ ♨ ♨ ♩ ♪ ♫ ♬ ♭ ♮ ♯

Unicode content with various symbols and characters from different categories.
''';
}

String _generateBidirectionalContent() {
  return '''
Bidirectional Text Test
========================

English (LTR): This text flows left to right.

Arabic (RTL): مرحبا بالعالم! هذا النص يقرأ من اليمين إلى اليسار.

Hebrew (RTL): שלום עולם! טקסט זה נקרא מימין לשמאל.

Mixed LTR/RTL: English text العربية Hebrew text עברית English again.

Numbers in RTL context: ١٢٣٤٥٦٧٨٩٠ (Arabic-Indic digits)

Punctuation in RTL: .،؟!؛

Mixed content with emojis: 🌍 مرحبا Hello שלום 🚀

Bidirectional algorithms should handle:
- Text direction detection
- Cursor positioning
- Selection behavior
- Line breaking
- Character ordering

Complex example:
English phrase "Hello world" in Arabic: "مرحبا بالعالم"
Hebrew phrase "Good morning" in Arabic: "صباح الخير"
Mixed: English العربية Hebrew עברית English

URLs in RTL: http://example.com/path/file.html
Email in RTL: user@example.com

Code in RTL context: function test() { return "Hello"; }

Math in RTL: 1 + 2 = 3, x² + y² = z²

This file tests bidirectional text handling with multi-cursor editing.
''';
}

String _generateMixedEncodingContent() {
  return '''
Mixed Encoding Test
==================

This file contains content from various character sets and encodings:

ASCII: Hello World! 1234567890

Latin-1: Café naïve résumé déjà vu

UTF-8: 你好世界 🌍 🚀 💻

Windows-1252: "Smart quotes" and em—dashes

ISO-8859-1: ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ

Mixed content:
English: The quick brown fox jumps over the lazy dog.
Spanish: El rápido zorro marrón salta sobre el perro perezoso.
French: Le rapide renard marron saute par-dessus le chien paresseux.
German: Der schnelle braune Fuchs springt über den faulen Hund.
Russian: Быстрый коричневый лис прыгает через ленивую собаку.
Chinese: 快速的棕色狐狸跳过懒狗。
Japanese: 速い茶色のキツネが怠惰な犬を飛び越える。
Korean: 빠른 갈색 여우가 게으른 개를 뛰어넘습니다.
Arabic: الثعلب البني السريع يقفز فوق الكلب الكسول.

Special characters and symbols:
© ® ™ ℠ ℡ ℧ ℩ K Å ℬ ℭ ℮ ℯ ℰ ℱ Ⅎ ℳ ℴ ℵ ℶ ℷ ℸ ℹ ℺ ℻ ℼ ℽ ℾ ℿ ⅀ ⅁ ⅂ ⅃ ⅄ ⅅ ⅆ ⅇ ⅈ ⅉ ⅊ ⅋ ⅌ ⅍ ⅎ ⅏ ⅐ ⅑ ⅒ ⅓ ⅔ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞ ⅟ Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ Ⅵ Ⅶ Ⅷ Ⅸ Ⅹ Ⅺ Ⅻ Ⅼ Ⅽ Ⅾ Ⅿ ⅰ ⅱ ⅲ ⅳ ⅴ ⅵ ⅶ ⅷ ⅸ ⅹ ⅺ ⅻ ⅼ ⅽ ⅾ ⅿ

Programming keywords in different languages:
English: function, class, return, if, else, for, while
Spanish: función, clase, devolver, si, sino, para, mientras
French: fonction, classe, retourner, si, sinon, pour, tant que
German: Funktion, Klasse, zurückgeben, wenn, sonst, für, während

This mixed content tests encoding handling and character set compatibility.
''';
}

String _generateJavaScriptContent() {
  return '''
// JavaScript Test File for Multi-Cursor Editing
// =============================================

// Function definitions
function calculateSum(a, b) {
  return a + b;
}

function calculateProduct(a, b) {
  return a * b;
}

function calculateDifference(a, b) {
  return a - b;
}

// Class definition
class Calculator {
  constructor() {
    this.history = [];
    this.result = 0;
  }
  
  add(value) {
    this.result += value;
    this.history.push(`Added ${value}`);
    return this.result;
  }
  
  subtract(value) {
    this.result -= value;
    this.history.push(`Subtracted ${value}`);
    return this.result;
  }
  
  multiply(value) {
    this.result *= value;
    this.history.push(`Multiplied by ${value}`);
    return this.result;
  }
  
  divide(value) {
    if (value !== 0) {
      this.result /= value;
      this.history.push(`Divided by ${value}`);
      return this.result;
    } else {
      throw new Error('Division by zero');
    }
  }
  
  clear() {
    this.result = 0;
    this.history.push('Cleared');
    return this.result;
  }
  
  getHistory() {
    return this.history.slice();
  }
}

// Async function
async function fetchUserData(userId) {
  try {
    const response = await fetch(`/api/users/${userId}`);
    const userData = await response.json();
    return userData;
  } catch (error) {
    console.error('Error fetching user data:', error);
    throw error;
  }
}

// Arrow functions
const square = (x) => x * x;
const cube = (x) => x * x * x;
const factorial = (n) => {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
};

// Object with methods
const mathUtils = {
  PI: 3.141592653589793,
  E: 2.718281828459045,
  
  circleArea(radius) {
    return this.PI * radius * radius;
  },
  
  circleCircumference(radius) {
    return 2 * this.PI * radius;
  },
  
  random(min, max) {
    return Math.random() * (max - min) + min;
  }
};

// Array operations
const numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

const doubled = numbers.map(n => n * 2);
const evens = numbers.filter(n => n % 2 === 0);
const sum = numbers.reduce((acc, n) => acc + n, 0);

// Template literals
const user = {
  name: 'John Doe',
  age: 30,
  email: 'john@example.com'
};

const greeting = \`Hello, \${user.name}! You are \${user.age} years old.\`;

// Destructuring
const {name, age} = user;
const [first, second, ...rest] = numbers;

// Promise chain
fetch('/api/data')
  .then(response => response.json())
  .then(data => {
    console.log('Data received:', data);
    return processData(data);
  })
  .then(processedData => {
    console.log('Data processed:', processedData);
  })
  .catch(error => {
    console.error('Error:', error);
  });

// Error handling
try {
  const result = riskyOperation();
  console.log('Success:', result);
} catch (error) {
  console.error('Error occurred:', error.message);
} finally {
  console.log('Operation completed');
}

// Module pattern
const Module = (function() {
  let privateVariable = 0;
  
  return {
    increment() {
      return ++privateVariable;
    },
    
    decrement() {
      return --privateVariable;
    },
    
    getValue() {
      return privateVariable;
    }
  };
})();

// This JavaScript file contains various syntax elements for testing multi-cursor editing.
''';
}

String _generatePythonContent() {
  return '''
# Python Test File for Multi-Cursor Editing
# ==========================================

# Function definitions
def calculate_sum(a, b):
    """Calculate the sum of two numbers."""
    return a + b

def calculate_product(a, b):
    """Calculate the product of two numbers."""
    return a * b

def calculate_difference(a, b):
    """Calculate the difference between two numbers."""
    return a - b

def calculate_quotient(a, b):
    """Calculate the quotient of two numbers."""
    if b != 0:
        return a / b
    else:
        raise ValueError("Division by zero")

# Class definition
class Calculator:
    """A simple calculator class with history tracking."""
    
    def __init__(self):
        self.history = []
        self.result = 0
    
    def add(self, value):
        """Add a value to the current result."""
        self.result += value
        self.history.append(f"Added {value}")
        return self.result
    
    def subtract(self, value):
        """Subtract a value from the current result."""
        self.result -= value
        self.history.append(f"Subtracted {value}")
        return self.result
    
    def multiply(self, value):
        """Multiply the current result by a value."""
        self.result *= value
        self.history.append(f"Multiplied by {value}")
        return self.result
    
    def divide(self, value):
        """Divide the current result by a value."""
        if value != 0:
            self.result /= value
            self.history.append(f"Divided by {value}")
            return self.result
        else:
            raise ValueError("Division by zero")
    
    def clear(self):
        """Clear the current result."""
        self.result = 0
        self.history.append("Cleared")
        return self.result
    
    def get_history(self):
        """Get the operation history."""
        return self.history.copy()

# Async function
import asyncio
import aiohttp

async def fetch_user_data(user_id):
    """Fetch user data from API asynchronously."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"/api/users/{user_id}") as response:
                if response.status == 200:
                    return await response.json()
                else:
                    raise ValueError(f"HTTP {response.status}")
    except Exception as error:
        print(f"Error fetching user data: {error}")
        raise

# Lambda functions
square = lambda x: x * x
cube = lambda x: x * x * x
factorial = lambda n: 1 if n <= 1 else n * factorial(n - 1)

# Object with methods
class MathUtils:
    """Utility class for mathematical operations."""
    
    PI = 3.141592653589793
    E = 2.718281828459045
    
    @classmethod
    def circle_area(cls, radius):
        """Calculate the area of a circle."""
        return cls.PI * radius * radius
    
    @classmethod
    def circle_circumference(cls, radius):
        """Calculate the circumference of a circle."""
        return 2 * cls.PI * radius
    
    @staticmethod
    def random(min_val, max_val):
        """Generate a random number between min and max."""
        import random
        return random.uniform(min_val, max_val)

# List operations
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

doubled = [n * 2 for n in numbers]
evens = [n for n in numbers if n % 2 == 0]
sum_all = sum(numbers)

# Dictionary operations
user = {
    "name": "John Doe",
    "age": 30,
    "email": "john@example.com",
    "address": {
        "street": "123 Main St",
        "city": "Anytown",
        "country": "USA"
    }
}

# String formatting
name = user["name"]
age = user["age"]
greeting = f"Hello, {name}! You are {age} years old."

# Exception handling
try:
    result = risky_operation()
    print(f"Success: {result}")
except ValueError as error:
    print(f"ValueError occurred: {error}")
except Exception as error:
    print(f"Unexpected error: {error}")
finally:
    print("Operation completed")

# Context manager
class FileManager:
    """Context manager for file operations."""
    
    def __init__(self, filename, mode):
        self.filename = filename
        self.mode = mode
        self.file = None
    
    def __enter__(self):
        self.file = open(self.filename, self.mode)
        return self.file
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.file:
            self.file.close()
        return False

# Generator function
def fibonacci_generator():
    """Generate Fibonacci numbers."""
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

# Decorator
def timing_decorator(func):
    """Decorator to measure function execution time."""
    import time
    
    def wrapper(*args, **kwargs):
        start_time = time.time()
        result = func(*args, **kwargs)
        end_time = time.time()
        print(f"{func.__name__} took {end_time - start_time:.4f} seconds")
        return result
    
    return wrapper

@timing_decorator
def slow_function():
    """A function that simulates slow work."""
    import time
    time.sleep(0.1)
    return "Done"

# This Python file contains various syntax elements for testing multi-cursor editing.
''';
}

String _generateJSONContent() {
  return '''
{
  "user": {
    "id": 12345,
    "name": "John Doe",
    "email": "john@example.com",
    "age": 30,
    "isActive": true,
    "profile": {
      "firstName": "John",
      "lastName": "Doe",
      "avatar": "https://example.com/avatars/john.jpg",
      "bio": "Software developer with expertise in web technologies",
      "location": {
        "city": "San Francisco",
        "state": "CA",
        "country": "USA",
        "coordinates": {
          "latitude": 37.7749,
          "longitude": -122.4194
        }
      },
      "preferences": {
        "theme": "dark",
        "language": "en",
        "timezone": "America/Los_Angeles",
        "notifications": {
          "email": true,
          "push": false,
          "sms": true
        }
      }
    },
    "settings": {
      "privacy": {
        "profileVisible": true,
        "showEmail": false,
        "showLocation": true
      },
      "security": {
        "twoFactorEnabled": true,
        "lastPasswordChange": "2023-01-15T10:30:00Z",
        "loginAttempts": 0,
        "sessionTimeout": 3600
      }
    },
    "activity": {
      "lastLogin": "2023-06-15T14:22:31Z",
      "loginCount": 142,
      "sessions": [
        {
          "id": "sess_001",
          "startTime": "2023-06-15T09:00:00Z",
          "endTime": "2023-06-15T17:30:00Z",
          "duration": 30600,
          "ipAddress": "192.168.1.100",
          "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        },
        {
          "id": "sess_002",
          "startTime": "2023-06-14T08:30:00Z",
          "endTime": "2023-06-14T16:45:00Z",
          "duration": 29700,
          "ipAddress": "192.168.1.101",
          "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        }
      ]
    },
    "projects": [
      {
        "id": "proj_001",
        "name": "E-commerce Platform",
        "description": "Modern e-commerce solution with React and Node.js",
        "status": "active",
        "progress": 75,
        "technologies": ["React", "Node.js", "MongoDB", "Docker"],
        "team": [
          {
            "id": "member_001",
            "name": "Alice Smith",
            "role": "Frontend Developer",
            "avatar": "https://example.com/avatars/alice.jpg"
          },
          {
            "id": "member_002",
            "name": "Bob Johnson",
            "role": "Backend Developer",
            "avatar": "https://example.com/avatars/bob.jpg"
          }
        ],
        "deadlines": {
          "milestone1": "2023-07-01T00:00:00Z",
          "milestone2": "2023-08-15T00:00:00Z",
          "final": "2023-09-30T00:00:00Z"
        }
      },
      {
        "id": "proj_002",
        "name": "Mobile App",
        "description": "Cross-platform mobile application using Flutter",
        "status": "planning",
        "progress": 15,
        "technologies": ["Flutter", "Firebase", "Redux"],
        "team": [
          {
            "id": "member_003",
            "name": "Carol Davis",
            "role": "Mobile Developer",
            "avatar": "https://example.com/avatars/carol.jpg"
          }
        ],
        "deadlines": {
          "prototype": "2023-08-01T00:00:00Z",
          "beta": "2023-10-15T00:00:00Z",
          "release": "2023-12-01T00:00:00Z"
        }
      }
    ],
    "notifications": [
      {
        "id": "notif_001",
        "type": "info",
        "title": "System Update",
        "message": "System will be updated tonight at 2 AM EST",
        "timestamp": "2023-06-15T12:00:00Z",
        "read": false,
        "priority": "low"
      },
      {
        "id": "notif_002",
        "type": "warning",
        "title": "Password Expiry",
        "message": "Your password will expire in 7 days",
        "timestamp": "2023-06-15T10:30:00Z",
        "read": true,
        "priority": "medium"
      },
      {
        "id": "notif_003",
        "type": "success",
        "title": "Project Milestone",
        "message": "E-commerce Platform milestone 1 completed",
        "timestamp": "2023-06-14T16:45:00Z",
        "read": true,
        "priority": "high"
      }
    ],
    "metadata": {
      "version": "1.2.3",
      "lastUpdated": "2023-06-15T14:22:31Z",
      "created": "2023-01-01T00:00:00Z",
      "tags": ["user", "profile", "projects", "activity"],
      "checksum": "a1b2c3d4e5f6789012345678901234567890abcdef"
  }
}
''';
}

String _generateMarkdownContent() {
  return '''
# Markdown Test File for Multi-Cursor Editing
# ==============================================

This is a **test file** for multi-cursor editing with *Markdown* syntax.

## Headers and Text Formatting

### H3 Header with `inline code`

Here's some **bold text**, *italic text*, and ~~strikethrough text~~.

You can also combine **bold and *italic*** text.

### Lists

#### Unordered List

- Item 1
- Item 2
  - Nested item 2.1
  - Nested item 2.2
- Item 3

#### Ordered List

1. First item
2. Second item
   1. Nested item 2.1
   2. Nested item 2.2
3. Third item

### Code Blocks

#### Inline Code
Use the `printf()` function for formatted output.

#### Fenced Code Block
```javascript
function greet(name) {
  return \`Hello, \${name}!\`;
}

const message = greet("World");
console.log(message);
```

#### Indented Code Block
    def calculate_sum(a, b):
        return a + b
    
    result = calculate_sum(5, 3)
    print(f"Result: {result}")

### Links and Images

#### Links
[GitHub](https://github.com)
[Google](https://google.com "Search Engine")

#### Reference Links
[GitHub Reference][1]
[Google Reference][2]

[1]: https://github.com
[2]: https://google.com

#### Images
![Alt Text](https://example.com/image.jpg "Image Title")

### Tables

| Name | Age | City | Country |
|------|-----|------|---------|
| John | 30 | New York | USA |
| Jane | 25 | London | UK |
| Bob | 35 | Tokyo | Japan |

### Blockquotes

> This is a blockquote.
> It can span multiple lines.
> 
> > Nested blockquotes are also supported.

### Horizontal Rules

---

### Task Lists

- [x] Completed task
- [ ] Incomplete task
- [ ] Another incomplete task
  - [x] Subtask completed
  - [ ] Subtask incomplete

### Footnotes

Here's a statement with a footnote[^1].

[^1]: This is the footnote content.

### Definition Lists

Term 1
: Definition 1

Term 2
: Definition 2
: Definition 2 continued

### Strikethrough and Highlighting

~~Strikethrough text~~

==Highlighted text== (if supported)

### Emoji and Special Characters

🚀 🎉 💻 📱 🌍

© ® ™ ℠

### Math (if supported)

Inline math: $E = mc^2$

Block math:
$$
\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
$$

### Raw HTML

<div style="color: red;">
  This is <strong>raw HTML</strong> in Markdown.
</div>

### Escaping

\\*Not italic\\*

\\`Not code\\*

### Comments (if supported)

<!-- This is a comment -->

---

This Markdown file contains various syntax elements for testing multi-cursor editing.
''';
}

String _generateConfigContent() {
  return '''
# Configuration File for Multi-Cursor Testing
# =============================================

# Application Settings
app:
  name: "Termisol"
  version: "2.0.0"
  description: "Advanced Terminal Emulator"
  author: "Termisol Team"
  license: "MIT"
  
  # Performance Settings
  performance:
    max_file_size: 52428800  # 50MB
    max_line_length: 10000
    max_line_count: 100000
    max_cursor_count: 100
    cache_size: 1048576  # 1MB
    
  # UI Settings
  ui:
    theme: "dark"
    font_size: 14
    font_family: "JetBrains Mono"
    line_height: 1.2
    tab_size: 4
    word_wrap: true
    show_line_numbers: true
    
    # Color Scheme
    colors:
      background: "#1e1e1e"
      foreground: "#d4d4d4"
      cursor: "#aeafad"
      selection: "#264f78"
      line_numbers: "#858585"
      
      # Syntax Highlighting
      syntax:
        keyword: "#569cd6"
        string: "#ce9178"
        comment: "#6a9955"
        number: "#b5cea8"
        function: "#dcdcaa"
        variable: "#9cdcfe"
        type: "#4ec9b0"
        operator: "#d4d4d4"
        punctuation: "#d4d4d4"

# Multi-Cursor Settings
multi_cursor:
  enabled: true
  max_cursors: 100
  visual_indicators: true
  main_cursor_color: "#0078d4"
  secondary_cursor_color: "#ff8c00"
  
  # Keyboard Shortcuts
  shortcuts:
    add_cursor: "Ctrl+D"
    select_all_occurrences: "Ctrl+Shift+L"
    clear_cursors: "Escape"
    next_cursor: "Ctrl+Alt+Down"
    previous_cursor: "Ctrl+Alt+Up"

# Editor Features
editor:
  # Auto-completion
  auto_complete:
    enabled: true
    trigger_delay: 200
    min_chars: 2
    max_suggestions: 10
    
  # Syntax Highlighting
  syntax_highlighting:
    enabled: true
    languages:
      - javascript
      - python
      - java
      - cpp
      - csharp
      - php
      - ruby
      - go
      - rust
      - typescript
      - html
      - css
      - json
      - yaml
      - markdown
      - sql
      - shell
    
  # Search and Replace
  search:
    case_sensitive: false
    whole_word: false
    regex: false
    highlight_matches: true
    
  replace:
    preserve_case: false
    confirm_replacements: true
    
  # Undo/Redo
  history:
    max_size: 200
    auto_save: true
    auto_save_delay: 2000

# Validation Settings
validation:
  # File Validation
  file:
    max_size: 52428800  # 50MB
    max_line_length: 10000
    max_line_count: 100000
    allowed_extensions:
      - ".txt"
      - ".js"
      - ".py"
      - ".java"
      - ".cpp"
      - ".c"
      - ".h"
      - ".cs"
      - ".php"
      - ".rb"
      - ".go"
      - ".rs"
      - ".ts"
      - ".html"
      - ".css"
      - ".json"
      - ".yaml"
      - ".yml"
      - ".md"
      - ".sql"
      - ".sh"
      - ".bat"
      - ".cmd"
    
    # Security Validation
    security:
      check_dangerous_content: true
      check_control_characters: true
      validate_encoding: true
      sanitize_input: true
      
    # Performance Validation
    performance:
      check_large_operations: true
      max_operation_count: 1000
      warn_slow_operations: true
      slow_operation_threshold: 100  # milliseconds

# Input Settings
input:
  # Keyboard
  keyboard:
    repeat_delay: 500
    repeat_rate: 50
    
  # Mouse
  mouse:
    double_click_time: 500
    scroll_speed: 3
    
  # Touch
  touch:
    tap_time: 200
    long_press_time: 500
    swipe_threshold: 50

# Plugin Settings
plugins:
  enabled:
    - "ai_assistant"
    - "file_manager"
    - "git_integration"
    - "docker_integration"
    - "database_client"
    - "debugger"
    - "performance_monitor"
  
  ai_assistant:
    provider: "openai"
    model: "gpt-4"
    max_tokens: 4096
    temperature: 0.7
    
  file_manager:
    show_hidden_files: false
    sort_by: "name"
    sort_order: "ascending"
    
  git_integration:
    auto_stage: false
    commit_template: |
      feat: Add new feature
      
      Description of the change
      
      Closes #123
      
  docker_integration:
    default_registry: "docker.io"
    auto_pull: true
    
  database_client:
    connections:
      - name: "development"
        type: "postgresql"
        host: "localhost"
        port: 5432
        database: "dev_db"
        username: "dev_user"
      - name: "production"
        type: "postgresql"
        host: "prod.example.com"
        port: 5432
        database: "prod_db"
        username: "prod_user"

# Logging Settings
logging:
  level: "info"
  file: "termisol.log"
  max_file_size: 10485760  # 10MB
  max_files: 5
  format: "%timestamp% [%level%] %message%"
  
  # Log Categories
  categories:
    editor: true
    multi_cursor: true
    validation: true
    performance: false
    plugins: true

# Debug Settings
debug:
  enabled: false
  console: false
  file: "debug.log"
  verbose: false
  
  # Debug Categories
  categories:
    multi_cursor: false
    validation: false
    performance: false
    input: false
    rendering: false

---
# This YAML configuration file contains various settings for testing multi-cursor editing.
# It includes nested structures, arrays, and different data types.
''';
}

String _generateLargeUnicodeContent(int sizeInBytes) {
  final buffer = StringBuffer();
  final unicodeChars = [
    '🚀🎉💻📱🌍⭐💡🔥🌈🎨🎭🎪🎯🎲🎸🎺🎷🎻🎹🎼🎧🎮🎰🎳',
    '∑∏∫∂∇∆∞±×÷≈≠≤≥∈∉∪∩⊂⊃⊆⊇',
    '←→↑↓↔↕↖↗↘↙⬆⬇⬅➡➢➣➤➥➦➧➨➩➪➫➬➭➮➯➰➱➲➳➴➵➶➷➸➹➺➻➼➽➾➿⤴⤵⤶⤷⤸⤹⤺⤻⤼⤽⤾⤿',
    '┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋╌╍╎╏',
    '▀▁▂▃▄▅▆▇█▉▊▋▌▍▎▏▐░▒▓▔▕▖▗▘▙▚▛▜▝▞▟■□▢▣▤▥▦▧▨▩▪▫▬▭▮▯▰▱▲△▴▵▶▷▸▹►▻▼▽▾▿',
    '●◐◑◒◓◔◕◖◗◘◙◚◛◜◝◞◟◠◡◢◣◤◥◦◧◨◩◪◫◬◭◮◯◰◱◲◳◴◵◶◷◸◹◺◻◼◽◾◿⬀⬁⬂⬃⬄⬅⬆⬇⬈⬉⬊⬋⬌⬍⬎⬏⬐⬑⬒⬓⬔⬕⬖⬗⬘⬙⬚⬛⬜⬝⬞⬟⬠⬡⬢⬣⬤⬥⬦⬧⬨⬩⬪⬫⬬⬭⬮⬯⬰⬱⬲⬳⬴⬵⬶⬷⬸⬹⬺⬻⬼⬽⬾⬿',
    '♠♣♥♦♩♪♫♬♭♮♯♰♱♲♳♴♵♶♷♸♹♺♻♼♽♾♿♨♨♩♪♫♬♭♮♯',
    '©®™℠℡℧℩KÅℬℭ℮ℯℰℱℲℳℴℵℶℷℸℹ℺℻ℼℽℾℿ⅀⅁⅂⅃⅄ⅅⅆⅇⅈⅉ⅊⅋⅌⅍ⅎ⅏⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅟ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫⅬⅭⅮⅯⅰⅱⅲⅳⅴⅵⅶⅷⅸⅹⅺⅻⅼⅽⅾⅿ⤀⦁⦂⦃⦄⦅⦆⦇⦈⦉⦊⦋⦌⦍⦎⦏⦐⦑⦒⦓⦔⦕⦖⦗⦘⦙⦚⦛⦜⦝⦞⦟⦠⦡⦢⦣⦤⦥⦦⦧⦨⦩⦪⦫⦬⦭⦮⦯⦰⦱⦲⦳⦴⦵⦶⦷⦸⦹⦺⦻⦼⦽⦾⦿⧀⧁⧂⧃⧄⧅⧆⧇⧈⧉⧊⧋⧌⧍⧎⧏⧐⧑⧒⧓⧔⧕⧖⧗⧘⧙⧚⧛⧜⧝⧞⧟⧠⧡⧢⧣⧤⧥⧦⧧⧨⧩⧪⧫⧬⧭⧮⧯⧰⧱⧲⧳⧴⧵⧶⧷⧸⧹⧺⧻⧼⧽⧾⧿⨀⨁⨂⨃⨄⨅⨆⨇⨈⨉⨊⨋⨌⨍⨎⨏⨐⨑⨒⨓⨔⨕⨖⨗⨘⨙⨚⨛⨜⨝⨞⨟⨠⨡⨢⨣⨤⨥⨦⨧⨨⨩⨪⨫⨬⨭⨮⨯⨰⨱⨲⨳⨴⨵⨶⨷⨸⨹⨺⨻⨼⨽⨾⨿⩀⩁⩂⩃⩄⩅⩆⩇⩈⩉⩊⩋⩌⩍⩎⩏⩐⩑⩒⩓⩔⩕⩖⩗⩘⩙⩚⩛⩜⩝⩞⩟⩠⩡⩢⩣⩤⩥⩦⩧⩨⩩⩪⩫⩬⩭⩮⩯⩰⩱⩲⩳⩴⩵⩶⩷⩸⩹⩺⩻⩼⩽⩾⩿',
  ];
  
  while (buffer.length < sizeInBytes) {
    final line = unicodeChars[buffer.length % unicodeChars.length];
    buffer.write('$line\n');
  }
  
  return buffer.toString().substring(0, sizeInBytes);
}
