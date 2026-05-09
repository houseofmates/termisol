import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' show Terminal, BufferPosition;
import '../core/terminal_session.dart';
import '../core/whisper_service.dart';
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
  AudioRecorder? _audioRecorder;
  WhisperService? _whisperService;
  
  CustomHotkeyManager({
    required this.session,
    required this.clipboard,
    this.onNewTab,
    this.onSaveFile,
    this.onSearch,
    this.onCopyAll,
  }) {
    _audioRecorder = AudioRecorder();
    _initializeWhisper();
  }
  
  Future<void> _initializeWhisper() async {
    _whisperService = WhisperService();
    
    // Check if server is available, fall back to mock if not
    final available = await _whisperService!.isServerAvailable();
    if (!available) {
      debugPrint('Termisol: Whisper server unavailable, using mock service');
      _whisperService = MockWhisperService();
    }
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
    
    // Ctrl+V: Paste
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyV) {
      _handlePaste();
      return KeyEventResult.handled;
    }
    
    // Ctrl+Z: Undo (let it pass through to terminal)
    // We'll ignore this to let the terminal handle undo
    
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
    _audioRecorder!.startRecording();
    _showFeedback('🎙️ Recording transcript... (Press Ctrl+B again to stop)');
  }
  
  /// Stop recording and process with Whisper
  void _stopRecording() async {
    _isRecording = false;
    final audioBytes = _audioRecorder!.stopRecording();
    _showFeedback('🔍 Processing transcript with Whisper...');
    
    try {
      final transcription = await _whisperService!.transcribeAudioBytes(
        audioBytes, 
        'recording_${DateTime.now().millisecondsSinceEpoch}.wav'
      );
      
      final cleanedText = WhisperService.cleanTranscription(transcription);
      
      if (cleanedText.isNotEmpty) {
        // Insert the processed text at cursor position
        session.sendRawInput(cleanedText);
        _showFeedback('✅ Transcript processed and inserted');
      } else {
        _showFeedback('❌ No speech detected');
      }
    } catch (e) {
      _showFeedback('❌ Whisper processing failed: $e');
    }
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
    if (_isRecording) {
      _audioRecorder?.stopRecording();
    }
    _audioRecorder = null;
    _whisperService = null;
  }
}

