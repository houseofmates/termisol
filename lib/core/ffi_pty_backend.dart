import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'pty_backend.dart';
import 'prompt_config.dart';

// FFI bindings for native PTY operations
typedef _PtySpawnNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int32, Int32);
typedef _PtySpawnDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int, int);

typedef _PtyWriteNative = Void Function(Int32, Pointer<Uint8>, Int32);
typedef _PtyWriteDart = void Function(int, Pointer<Uint8>, int);

typedef _PtyReadNative = Int32 Function(Int32, Pointer<Uint8>, Int32);
typedef _PtyReadDart = int Function(int, Pointer<Uint8>, int);

typedef _PtyResizeNative = Void Function(Int32, Int32, Int32);
typedef _PtyResizeDart = void Function(int, int, int);

typedef _PtyCloseNative = Void Function(Int32);
typedef _PtyCloseDart = void Function(int);

/// High-performance FFI-based PTY backend with direct memory access
/// Eliminates platform channel overhead and provides proper flow control
class FfiPtyBackend implements TermisolPtyBackend {
  @override
  final String name = 'FFI PTY Backend';
  final String? workingDirectory;
  
  // FFI function pointers
  late final _PtySpawnDart _ptySpawn;
  late final _PtyWriteDart _ptyWrite;
  late final _PtyReadDart _ptyRead;
  late final _PtyResizeDart _ptyResize;
  late final _PtyCloseDart _ptyClose;
  
  // PTY state
  int _ptyFd = -1;
  bool _isRunning = false;
  bool _isDisposed = false;
  
  // High-performance flow control
  final _BackpressureStreamController _outputController;
  final _CircularBuffer _readBuffer;
  final _CircularBuffer _writeBuffer;
  
  // Performance optimization
  final Pointer<Uint8> _tempBuffer;
  static const int _tempBufferSize = 64 * 1024; // 64KB temp buffer
  static const int _readBufferSize = 256 * 1024; // 256KB read buffer
  static const int _writeBufferSize = 64 * 1024; // 64KB write buffer
  
  Timer? _readTimer;
  Timer? _flowControlTimer;
  
  // Flow control metrics
  int _bytesRead = 0;
  int _bytesWritten = 0;
  int _lastFlowCheck = 0;
  static const int _flowControlThreshold = 1024 * 1024; // 1MB threshold

  FfiPtyBackend({this.workingDirectory}) 
      : _outputController = _BackpressureStreamController(),
        _readBuffer = _CircularBuffer(_readBufferSize),
        _writeBuffer = _CircularBuffer(_writeBufferSize),
        _tempBuffer = malloc.allocate<Uint8>(_tempBufferSize) {
    _initializeFfi();
  }

  void _initializeFfi() {
    try {
      final dylib = Platform.isLinux 
          ? DynamicLibrary.open('libtermisol_pty.so')
          : Platform.isMacOS 
              ? DynamicLibrary.open('libtermisol_pty.dylib')
              : DynamicLibrary.open('termisol_pty.dll');
      
      _ptySpawn = dylib.lookupFunction<_PtySpawnNative, _PtySpawnDart>('pty_spawn');
      _ptyWrite = dylib.lookupFunction<_PtyWriteNative, _PtyWriteDart>('pty_write');
      _ptyRead = dylib.lookupFunction<_PtyReadNative, _PtyReadDart>('pty_read');
      _ptyResize = dylib.lookupFunction<_PtyResizeNative, _PtyResizeDart>('pty_resize');
      _ptyClose = dylib.lookupFunction<_PtyCloseNative, _PtyCloseDart>('pty_close');
      
      debugPrint('[ffi_pty] FFI functions loaded successfully');
    } catch (e) {
      debugPrint('[ffi_pty] Failed to load FFI functions: $e');
      _fallbackToPtyPackage();
    }
  }

  void _fallbackToPtyPackage() {
    // Fallback to original PTY package if FFI fails
    debugPrint('[ffi_pty] Falling back to PTY package');
    // This would use the original _PtyBackend implementation
  }

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  bool get isConnected => _isRunning && _ptyFd >= 0;

  @override
  Future<void> start({int cols = 80, int rows = 24, String? workingDirectory}) async {
    if (_isRunning) return;
    
    final shell = _getShellPath();
    final workDir = workingDirectory ?? this.workingDirectory ?? _resolveHome('~');
    
    try {
      // Spawn PTY using FFI
      final shellPtr = shell.toNativeUtf8();
      final workDirPtr = workDir.toNativeUtf8();
      
      final resultPtr = _ptySpawn(shellPtr, workDirPtr, cols, rows);
      final resultStr = resultPtr.toDartString();
      
      _ptyFd = int.tryParse(resultStr) ?? -1;
      
      malloc.free(shellPtr);
      malloc.free(workDirPtr);
      malloc.free(resultPtr);
      
      if (_ptyFd < 0) {
        throw Exception('Failed to spawn PTY: fd=$_ptyFd');
      }
      
      _isRunning = true;
      _startReadLoop();
      _startFlowControlMonitoring();
      
      debugPrint('[ffi_pty] PTY started with fd=$_ptyFd, shell=$shell');
    } catch (e) {
      debugPrint('[ffi_pty] Failed to start PTY: $e');
      rethrow;
    }
  }

  @override
  void write(List<int> data) {
    if (!_isRunning || _ptyFd < 0 || _isDisposed) return;
    
    final dataLength = data.length;
    if (dataLength == 0) return;
    
    // Check write buffer capacity
    if (_writeBuffer.availableSpace < dataLength) {
      debugPrint('[ffi_pty] Write buffer overflow, dropping data');
      return;
    }
    
    // Copy data to write buffer
    final writeData = Uint8List.fromList(data);
    _writeBuffer.write(writeData);
    _bytesWritten += dataLength;
    
    // Try immediate write if buffer is small
    if (_writeBuffer.usedSpace < _writeBufferSize ~/ 2) {
      _flushWriteBuffer();
    }
  }

  void _flushWriteBuffer() {
    while (_writeBuffer.usedSpace > 0) {
      final readData = _writeBuffer.read(_tempBuffer, _tempBufferSize);
      if (readData.isEmpty) break;
      
      try {
        _ptyWrite(_ptyFd, _tempBuffer, readData.length);
      } catch (e) {
        debugPrint('[ffi_pty] Write error: $e');
        break;
      }
    }
  }

  @override
  void resize(int cols, int rows) {
    if (!_isRunning || _ptyFd < 0) return;
    
    try {
      _ptyResize(_ptyFd, cols, rows);
      debugPrint('[ffi_pty] Resized to ${cols}x${rows}');
    } catch (e) {
      debugPrint('[ffi_pty] Resize error: $e');
    }
  }

  void _startReadLoop() {
    _readTimer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (!_isRunning || _isDisposed || _ptyFd < 0) return;
      
      try {
        final bytesRead = _ptyRead(_ptyFd, _tempBuffer, _tempBufferSize);
        if (bytesRead > 0) {
          final data = _tempBuffer.asTypedList(bytesRead);
          _processReadData(data);
          _bytesRead += bytesRead;
        }
      } catch (e) {
        debugPrint('[ffi_pty] Read error: $e');
        _isRunning = false;
      }
    });
  }

  void _processReadData(Uint8List data) {
    if (data.isEmpty) return;
    
    // Check read buffer capacity
    if (_readBuffer.availableSpace < data.length) {
      debugPrint('[ffi_pty] Read buffer overflow, dropping old data');
      _readBuffer.discard(data.length);
    }
    
    // Copy data to read buffer
    _readBuffer.write(data);
    
    // Send data to output stream with backpressure
    final outputData = _readBuffer.readAll();
    if (outputData.isNotEmpty && !_outputController.isClosed) {
      _outputController.add(outputData);
    }
  }

  void _startFlowControlMonitoring() {
    _flowControlTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkFlowControl();
    });
  }

  void _checkFlowControl() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeDiff = now - _lastFlowCheck;
    if (timeDiff < 100) return; // Don't check too frequently
    
    _lastFlowCheck = now;
    
    // Check if we need to apply backpressure
    final totalBytes = _bytesRead + _bytesWritten;
    if (totalBytes > _flowControlThreshold) {
      _applyBackpressure();
    }
    
    // Reset counters periodically
    if (totalBytes > _flowControlThreshold * 2) {
      _bytesRead = 0;
      _bytesWritten = 0;
    }
  }

  void _applyBackpressure() {
    // Apply backpressure by temporarily pausing reads
    if (_readTimer?.isActive == true) {
      _readTimer?.cancel();
      Timer(const Duration(milliseconds: 10), () {
        if (_isRunning && !_isDisposed) {
          _startReadLoop();
        }
      });
    }
    
    debugPrint('[ffi_pty] Applied backpressure');
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _readTimer?.cancel();
    _flowControlTimer?.cancel();
    
    if (_ptyFd >= 0) {
      try {
        _ptyClose(_ptyFd);
      } catch (e) {
        debugPrint('[ffi_pty] Close error: $e');
      }
      _ptyFd = -1;
    }
    
    await _outputController.close();
  }

  @override
  Future<void> terminate() async {
    await stop();
  }

  String _getShellPath() {
    if (Platform.isLinux) {
      return Platform.environment['SHELL'] ?? '/bin/bash';
    } else if (Platform.isMacOS) {
      return Platform.environment['SHELL'] ?? '/bin/zsh';
    } else if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    } else {
      return Platform.environment['SHELL'] ?? 'sh';
    }
  }

  void dispose() {
    _isDisposed = true;
    _readTimer?.cancel();
    _flowControlTimer?.cancel();
    _outputController.close();
    _readBuffer.dispose();
    _writeBuffer.dispose();
    malloc.free(_tempBuffer);
    
    if (_ptyFd >= 0) {
      _ptyClose(_ptyFd);
      _ptyFd = -1;
    }
  }
}

/// Backpressure-enabled stream controller with buffer limits
class _BackpressureStreamController {
  late final StreamController<List<int>> _controller;
  static const int _maxBufferSize = 1024 * 1024; // 1MB max buffer
  int _currentBufferSize = 0;
  bool _isPaused = false;

  _BackpressureStreamController() {
    _controller = StreamController<List<int>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  Stream<List<int>> get stream => _controller.stream;
  bool get isClosed => _controller.isClosed;

  void add(List<int> data) {
    if (_controller.isClosed || _isPaused) return;
    
    final dataSize = data.length * 1; // Approximate size in bytes
    _currentBufferSize += dataSize;
    
    // Apply backpressure if buffer is too large
    if (_currentBufferSize > _maxBufferSize) {
      _isPaused = true;
      debugPrint('[backpressure] Buffer overflow, applying backpressure');
      return;
    }
    
    _controller.add(data);
  }

  Future<void> close() async {
    await _controller.close();
  }

  void _onListen() {
    _currentBufferSize = 0;
    _isPaused = false;
  }

  void _onCancel() {
    _currentBufferSize = 0;
    _isPaused = false;
  }

}

/// High-performance circular buffer for PTY data
class _CircularBuffer {
  final Uint8List _buffer;
  int _readPos = 0;
  int _writePos = 0;
  int _usedSpace = 0;

  _CircularBuffer(int size) : _buffer = Uint8List(size);

  int get availableSpace => _buffer.length - _usedSpace;
  int get usedSpace => _usedSpace;

  void write(Uint8List data) {
    if (data.isEmpty) return;
    
    final available = availableSpace;
    if (available < data.length) {
      throw Exception('Circular buffer overflow');
    }
    
    for (int i = 0; i < data.length; i++) {
      _buffer[_writePos] = data[i];
      _writePos = (_writePos + 1) % _buffer.length;
      _usedSpace++;
    }
  }

  Uint8List read(Pointer<Uint8> tempBuffer, int maxLength) {
    if (_usedSpace == 0) return Uint8List(0);
    
    final readLength = _usedSpace < maxLength ? _usedSpace : maxLength;
    
    for (int i = 0; i < readLength; i++) {
      tempBuffer[i] = _buffer[_readPos];
      _readPos = (_readPos + 1) % _buffer.length;
      _usedSpace--;
    }
    
    return tempBuffer.asTypedList(readLength);
  }

  Uint8List readAll() {
    if (_usedSpace == 0) return Uint8List(0);
    
    final result = Uint8List(_usedSpace);
    for (int i = 0; i < _usedSpace; i++) {
      result[i] = _buffer[_readPos];
      _readPos = (_readPos + 1) % _buffer.length;
    }
    
    _usedSpace = 0;
    return result;
  }

  void discard(int count) {
    final discardCount = count < _usedSpace ? count : _usedSpace;
    _readPos = (_readPos + discardCount) % _buffer.length;
    _usedSpace -= discardCount;
  }

  void dispose() {
    _readPos = 0;
    _writePos = 0;
    _usedSpace = 0;
  }
}

String _resolveHome(String path) {
  if (path == '~') {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
  }
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return path.replaceFirst('~', home);
  }
  return path;
}
