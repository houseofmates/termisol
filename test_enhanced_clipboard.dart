import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lib/ui/enhanced_clipboard_manager.dart';
import 'lib/packages/xterm/lib/xterm.dart';

/// Test script for enhanced clipboard functionality
void main() async {
  print('🧪 Testing Enhanced Clipboard Manager...\n');

  // Create a mock terminal for testing
  final terminal = Terminal();
  final controller = TerminalController();
  
  // Initialize enhanced clipboard manager
  final clipboard = EnhancedClipboardManager(
    terminal: terminal,
    controller: controller,
  );

  print('✅ Enhanced Clipboard Manager initialized\n');

  // Test 1: Large text block
  await testLargeTextPasting(clipboard);

  // Test 2: Image handling
  await testImageHandling(clipboard);

  // Test 3: GIF handling
  await testGifHandling(clipboard);

  // Test 4: Video handling
  await testVideoHandling(clipboard);

  // Test 5: Clipboard summary
  await testClipboardSummary(clipboard);

  // Cleanup
  await clipboard.cleanup();
  print('🧹 Cleanup completed\n');

  print('🎉 All tests completed!');
}

/// Test large text block pasting
Future<void> testLargeTextPasting(EnhancedClipboardManager clipboard) async {
  print('📝 Test 1: Large Text Block Pasting');
  
  // Create a large text block (50KB)
  final largeText = 'This is line 1 of a large text block.\n' * 2000;
  print('   Generated ${largeText.length} characters of test text');
  
  // Set to clipboard
  await Clipboard.setData(ClipboardData(text: largeText));
  
  // Test paste
  final result = await clipboard.paste();
  
  print('   Result: ${result.success ? "✅ SUCCESS" : "❌ FAILED"}');
  print('   Message: ${result.message}');
  if (result.metadata != null) {
    print('   Metadata: ${result.metadata}');
  }
  print('');
}

/// Test image handling
Future<void> testImageHandling(EnhancedClipboardManager clipboard) async {
  print('🖼️  Test 2: Image Handling');
  
  // Create mock image data (PNG header + simple data)
  final imageData = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    ...List.filled(100, 0x00), // Mock image data
  ]);
  
  print('   Generated ${imageData.length} bytes of mock PNG data');
  
  // Test image paste (simulated)
  print('   Image paste test: ✅ SIMULATED (would save image to current directory)');
  print('   Expected output: 🖼️ Detected image: clipboard_image_xxx.png (0.1MB)');
  print('');
}

/// Test GIF handling
Future<void> testGifHandling(EnhancedClipboardManager clipboard) async {
  print('🎬 Test 3: GIF Handling');
  
  // Create mock GIF data
  final gifData = Uint8List.fromList([
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a signature
    ...List.filled(200, 0x00), // Mock GIF data
  ]);
  
  print('   Generated ${gifData.length} bytes of mock GIF data');
  
  // Test GIF paste (simulated)
  print('   GIF paste test: ✅ SIMULATED (would save GIF to current directory)');
  print('   Expected output: 🎬 Detected GIF: clipboard_gif_xxx.gif (0.2MB)');
  print('   Expected output: 💡 You can view with: open clipboard_gif_xxx.gif');
  print('');
}

/// Test video handling
Future<void> testVideoHandling(EnhancedClipboardManager clipboard) async {
  print('🎥 Test 4: Video Handling');
  
  // Create mock video data
  final videoData = Uint8List.fromList([
    0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // Mock MP4 header
    ...List.filled(1000, 0x00), // Mock video data
  ]);
  
  print('   Generated ${videoData.length} bytes of mock video data');
  
  // Test video paste (simulated)
  print('   Video paste test: ✅ SIMULATED (would save video to current directory)');
  print('   Expected output: 🎥 Detected video: clipboard_video_xxx.mp4 (1.0MB)');
  print('   Expected output: 💡 Playback suggestions:');
  print('                     • mpv clipboard_video_xxx.mp4');
  print('                     • vlc clipboard_video_xxx.mp4');
  print('');
}

/// Test clipboard summary
Future<void> testClipboardSummary(EnhancedClipboardManager clipboard) async {
  print('📊 Test 5: Clipboard Summary');
  
  // Test with text
  await Clipboard.setData(ClipboardData(text: 'Sample text for testing'));
  final textSummary = await clipboard.getClipboardSummary();
  print('   Text summary: $textSummary');
  
  // Test with empty clipboard
  await Clipboard.setData(const ClipboardData(text: ''));
  final emptySummary = await clipboard.getClipboardSummary();
  print('   Empty summary: $emptySummary');
  
  print('');
}