import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:xterm/xterm.dart' show Terminal, BufferPosition;
import 'dart:convert';
import '../core/terminal_session.dart';
import 'clipboard_manager.dart';

/// Custom hotkey manager for Termisol with user-defined bindings
class CustomHotkeyManager {
  final TerminalSession session;
  final TerminalClipboardManager clipboard;
  final VoidCallback? onNewTab;
  final VoidCallback? onSaveFile;
  final VoidCallback? onSearch;
  final VoidCallback? onCopyAll;
  
  // Transcript recording state
  bool _isRecording = false;
  Timer? _recordingTimer;
  List<String> _transcriptBuffer = [];
  String? _whisperServerUrl;
  
  CustomHotkeyManager({
    required this.session,
    required this.clipboard,
    this.onNewTab,
    this.onSaveFile,
    this.onSearch,
    this.onCopyAll,
  }) {
    _whisperServerUrl = 'http://192.168.4.250:9000'; // Default Whisper server
  }
  
  /// Handle key events with custom bindings
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    
    // Ctrl+C: Copy (instead of interrupt)
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyC) {
      _handleCopy();
      return KeyEventResult.handled;
    }
    
    // Ctrl+Shift+C: Original interrupt behavior
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyC) {
      _handleInterrupt();
      return KeyEventResult.handled;
    }
    
    // Ctrl+Z: Paste (instead of undo)
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _handlePaste();
      return KeyEventResult.handled;
    }
    
    // Ctrl+A: Copy all
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyA) {
      _handleCopyAll();
      return KeyEventResult.handled;
    }
    
    // Ctrl+F: Search
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyF) {
      onSearch?.call();
      return KeyEventResult.handled;
    }
    
    // Ctrl+B: Toggle transcript recording
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyB) {
      _handleTranscriptToggle();
      return KeyEventResult.handled;
    }
    
    // Ctrl+S: Save file
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyS) {
      onSaveFile?.call();
      return KeyEventResult.handled;
    }
    
    // Ctrl+N: New tab
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyN) {
      onNewTab?.call();
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
  
  /// Copy selected text to clipboard
  void _handleCopy() {
    final selection = session.terminal.selection;
    if (selection != null) {
      final text = session.terminal.buffer.getText(selection.start, selection.end);
      clipboard.copy(text);
      _showFeedback('Copied to clipboard');
    } else {
      _showFeedback('No text selected');
    }
  }
  
  /// Send interrupt signal (Ctrl+C original behavior)
  void _handleInterrupt() {
    session.sendRawInput('\x03'); // Ctrl+C character
    _showFeedback('Interrupt sent');
  }
  
  /// Paste from clipboard
  void _handlePaste() {
    clipboard.paste();
    _showFeedback('Pasted from clipboard');
  }
  
  /// Copy all terminal content
  void _handleCopyAll() {
    final buffer = session.terminal.buffer;
    final allText = buffer.getText(
      BufferPosition(0, 0),
      BufferPosition(buffer.columns - 1, buffer.height - 1),
    );
    clipboard.copy(allText);
    _showFeedback('All content copied to clipboard');
  }
  
  /// Toggle transcript recording with Whisper
  void _handleTranscriptToggle() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }
  
  /// Start recording audio transcript
  void _startRecording() {
    _isRecording = true;
    _transcriptBuffer.clear();
    _showFeedback('🎙️ Recording transcript... (Press Ctrl+B again to stop)');
    
    // Start recording timer (simulated - in real implementation would use audio recording)
    _recordingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      // This would interface with actual audio recording
      // For now, we'll simulate it
    });
  }
  
  /// Stop recording and process with Whisper
  void _stopRecording() async {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _showFeedback('🔍 Processing transcript with Whisper...');
    
    try {
      // In real implementation, this would send recorded audio to Whisper
      // For now, we'll simulate the process
      final processedText = await _processWithWhisper();
      
      if (processedText.isNotEmpty) {
        // Insert the processed text at cursor position
        session.sendRawInput(processedText);
        _showFeedback('✅ Transcript processed and inserted');
      } else {
        _showFeedback('❌ No speech detected');
      }
    } catch (e) {
      _showFeedback('❌ Whisper processing failed: $e');
    }
  }
  
  /// Process audio with Whisper API
  Future<String> _processWithWhisper() async {
    try {
      // Simulate Whisper API call to 192.168.4.250
      // In real implementation, this would send actual audio data
      
      // For demo purposes, we'll simulate a response
      await Future.delayed(Duration(seconds: 2)); // Simulate processing time
      
      // Mock response - in real implementation this would be the actual transcription
      final mockTranscription = "this is a sample transcription from whisper";
      
      // Clean up the transcription
      return _cleanTranscription(mockTranscription);
      
    } catch (e) {
      throw Exception('Whisper API error: $e');
    }
  }
  
  /// Clean up transcription by removing filler words
  String _cleanTranscription(String text) {
    final fillerWords = [
      'uhh', 'uhm', 'umm', 'uhhhs', 'uhmms', 'errrh', 'errs',
      'uh', 'um', 'er', 'ah', 'like', 'you know', 'I mean',
      'actually', 'basically', 'literally', 'sort of', 'kind of'
    ];
    
    String cleaned = text.toLowerCase();
    
    // Remove filler words with proper spacing
    for (final filler in fillerWords) {
      cleaned = cleaned.replaceAll(RegExp('\\b$filler\\b', caseSensitive: false), '');
    }
    
    // Clean up extra spaces and punctuation
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+([.,!?])'), r'\1');
    cleaned = cleaned.trim();
    
    // Capitalize first letter
    if (cleaned.isNotEmpty) {
      cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
    }
    
    return cleaned;
  }
  
  /// Show feedback message (could be implemented as toast, status bar, etc.)
  void _showFeedback(String message) {
    // This would show a toast or status message
    // For now, we'll print to debug
    debugPrint('Termisol Hotkey: $message');
    
    // In a real implementation, you could use:
    // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  
  /// Dispose resources
  void dispose() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }
}

