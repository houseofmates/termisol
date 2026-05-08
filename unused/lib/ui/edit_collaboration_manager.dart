import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Manages real-time collaborative editing sessions for Termisol's Edit editor
class EditCollaborationManager {
  static const String DEFAULT_HOST = '192.168.4.250';
  static const int DEFAULT_PORT = 8765;
  static const Duration RECONNECT_DELAY = Duration(seconds: 3);
  static const Duration PING_INTERVAL = Duration(seconds: 30);
  static const Duration CONNECTION_TIMEOUT = Duration(seconds: 10);

  WebSocketChannel? _channel;
  String? _sessionId;
  String? _filePath;
  String _clientId = '';
  bool _isConnected = false;
  bool _isReconnecting = false;
  
  // Event streams
  final _connectionController = StreamController<bool>.broadcast();
  final _operationController = StreamController<EditOperation>.broadcast();
  final _clientUpdateController = StreamController<ClientUpdate>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _sessionJoinedController = StreamController<SessionJoinedEvent>.broadcast();
  
  // Periodic ping timer
  Timer? _pingTimer;
  
  // Retry mechanism
  int _retryCount = 0;
  static const int MAX_RETRY_COUNT = 5;

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<EditOperation> get operationStream => _operationController.stream;
  Stream<ClientUpdate> get clientUpdateStream => _clientUpdateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<SessionJoinedEvent> get sessionJoinedStream => _sessionJoinedController.stream;

  bool get isConnected => _isConnected;
  String? get sessionId => _sessionId;
  String? get filePath => _filePath;

  /// Connect to the collaboration bridge server
  Future<bool> connect(String filePath, {String? host, int? port}) async {
    if (_isConnected) {
      debugPrint('Already connected to collaboration server');
      return true;
    }

    final serverHost = host ?? DEFAULT_HOST;
    final serverPort = port ?? DEFAULT_PORT;
    _filePath = filePath;
    _clientId = _generateClientId();

    try {
      debugPrint('Connecting to collaboration server: ws://$serverHost:$serverPort');
      
      final uri = Uri.parse('ws://$serverHost:$serverPort');
      _channel = WebSocketChannel.connect(uri);
      
      // Set connection timeout
      await _channel!.ready.timeout(CONNECTION_TIMEOUT);
      
      _isConnected = true;
      _retryCount = 0;
      
      // Start listening for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
        cancelOnError: false,
      );
      
      // Start ping timer
      _startPingTimer();
      
      // Join session for the file
      await _joinSession(filePath);
      
      _connectionController.add(true);
      debugPrint('Connected to collaboration server successfully');
      
      return true;
    } catch (e) {
      debugPrint('Failed to connect to collaboration server: $e');
      _isConnected = false;
      _connectionController.add(false);
      _errorController.add('Connection failed: $e');
      
      // Attempt reconnection if not exceeded max retries
      if (_retryCount < MAX_RETRY_COUNT && !_isReconnecting) {
        _retryCount++;
        _isReconnecting = true;
        debugPrint('Retrying connection ($_retryCount/$MAX_RETRY_COUNT)...');
        
        await Future.delayed(RECONNECT_DELAY);
        return await connect(filePath, host: host, port: port);
      }
      
      return false;
    }
  }

  /// Disconnect from the collaboration server
  Future<void> disconnect() async {
    if (!_isConnected) return;
    
    _isReconnecting = false;
    _pingTimer?.cancel();
    
    try {
      if (_channel != null) {
        await _channel!.sink.close(status.normalClosure);
      }
    } catch (e) {
      debugPrint('Error during disconnection: $e');
    }
    
    _cleanup();
    _connectionController.add(false);
    debugPrint('Disconnected from collaboration server');
  }

  /// Send an edit operation to the server
  Future<bool> sendOperation(EditOperation operation) async {
    if (!_isConnected || _sessionId == null) {
      debugPrint('Cannot send operation: not connected or no session');
      return false;
    }

    try {
      final message = {
        'type': 'operation',
        'data': {
          'session_id': _sessionId,
          'operation': operation.toMap(),
        }
      };

      _channel!.sink.add(json.encode(message));
      debugPrint('Sent operation: ${operation.type} at ${operation.position}');
      return true;
    } catch (e) {
      debugPrint('Failed to send operation: $e');
      _errorController.add('Failed to send operation: $e');
      return false;
    }
  }

  /// Send cursor position update
  Future<bool> sendCursorPosition(int position, {TextSelection? selection}) async {
    if (!_isConnected || _sessionId == null) {
      return false;
    }

    try {
      final message = {
        'type': 'cursor_position',
        'data': {
          'session_id': _sessionId,
          'position': position,
          if (selection != null) 'selection': {
            'start': selection.start,
            'end': selection.end,
          },
        }
      };

      _channel!.sink.add(json.encode(message));
      return true;
    } catch (e) {
      debugPrint('Failed to send cursor position: $e');
      return false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = json.decode(message);
      final messageType = data['type'];
      final messageData = data['data'] ?? {};

      debugPrint('Received message type: $messageType');

      switch (messageType) {
        case 'session_joined':
          _handleSessionJoined(messageData);
          break;
        case 'operation_applied':
          _handleOperationApplied(messageData);
          break;
        case 'client_update':
          _handleClientUpdate(messageData);
          break;
        case 'client_joined':
          debugPrint('Client joined: ${messageData['client_id']}');
          break;
        case 'client_left':
          debugPrint('Client left: ${messageData['client_id']}');
          break;
        case 'pong':
          // Ping response received
          break;
        case 'error':
          _errorController.add(messageData['message'] ?? 'Unknown error');
          break;
        default:
          debugPrint('Unknown message type: $messageType');
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
      _errorController.add('Message parsing error: $e');
    }
  }

  void _handleSessionJoined(Map<String, dynamic> data) {
    _sessionId = data['session_id'];
    final fileContent = data['file_content'] ?? '';
    final activeClients = List<Map<String, dynamic>>.from(data['active_clients'] ?? []);
    final version = data['version'] ?? 0;

    final event = SessionJoinedEvent(
      sessionId: _sessionId!,
      filePath: _filePath!,
      fileContent: fileContent,
      activeClients: activeClients,
      version: version,
    );

    _sessionJoinedController.add(event);
    debugPrint('Joined session: $_sessionId with ${activeClients.length} active clients');
  }

  void _handleOperationApplied(Map<String, dynamic> data) {
    final operationData = data['operation'] ?? {};
    final clientId = data['client_id'] ?? '';
    
    // Don't apply our own operations
    if (clientId == _clientId) return;

    final operation = EditOperation.fromMap(operationData);
    _operationController.add(operation);
    debugPrint('Received operation from $clientId: ${operation.type}');
  }

  void _handleClientUpdate(Map<String, dynamic> data) {
    final clientId = data['client_id'] ?? '';
    final position = data['cursor'] ?? 0;
    final selectionData = data['selection'];
    
    // Don't process our own updates
    if (clientId == _clientId) return;

    TextSelection? selection;
    if (selectionData != null) {
      selection = TextSelection(
        baseOffset: selectionData['start'] ?? 0,
        extentOffset: selectionData['end'] ?? 0,
      );
    }

    final update = ClientUpdate(
      clientId: clientId,
      position: position,
      selection: selection,
    );

    _clientUpdateController.add(update);
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _errorController.add('WebSocket error: $error');
  }

  void _handleDisconnection() {
    debugPrint('WebSocket disconnected');
    _isConnected = false;
    _connectionController.add(false);
    
    // Attempt reconnection if not manually disconnected
    if (_isReconnecting && _retryCount < MAX_RETRY_COUNT && _filePath != null) {
      _retryCount++;
      debugPrint('Attempting reconnection ($_retryCount/$MAX_RETRY_COUNT)...');
      
      Future.delayed(RECONNECT_DELAY, () {
        if (_filePath != null) {
          connect(_filePath!);
        }
      });
    }
  }

  Future<void> _joinSession(String filePath) async {
    try {
      final message = {
        'type': 'join_session',
        'data': {
          'file_path': filePath,
          'client_id': _clientId,
          'client_type': 'human',
        }
      };

      _channel!.sink.add(json.encode(message));
      debugPrint('Sent join session request for: $filePath');
    } catch (e) {
      debugPrint('Failed to join session: $e');
      _errorController.add('Failed to join session: $e');
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(PING_INTERVAL, (timer) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(json.encode({'type': 'ping'}));
        } catch (e) {
          debugPrint('Failed to send ping: $e');
        }
      }
    });
  }

  void _cleanup() {
    _channel = null;
    _sessionId = null;
    _filePath = null;
    _isConnected = false;
    _isReconnecting = false;
    _pingTimer?.cancel();
  }

  String _generateClientId() {
    return 'termisol_${DateTime.now().millisecondsSinceEpoch}_${Platform.localHostname}';
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _connectionController.close();
    _operationController.close();
    _clientUpdateController.close();
    _errorController.close();
    _sessionJoinedController.close();
  }
}

/// Represents an edit operation
class EditOperation {
  final String type; // insert, delete, replace
  final int position;
  final String content;
  final int length;
  final String? clientId;

  EditOperation({
    required this.type,
    required this.position,
    this.content = '',
    this.length = 0,
    this.clientId,
  });

  factory EditOperation.insert(int position, String content) {
    return EditOperation(
      type: 'insert',
      position: position,
      content: content,
    );
  }

  factory EditOperation.delete(int position, int length) {
    return EditOperation(
      type: 'delete',
      position: position,
      length: length,
    );
  }

  factory EditOperation.replace(int position, String content, int length) {
    return EditOperation(
      type: 'replace',
      position: position,
      content: content,
      length: length,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'position': position,
      'content': content,
      'length': length,
    };
  }

  factory EditOperation.fromMap(Map<String, dynamic> map) {
    return EditOperation(
      type: map['type'] ?? '',
      position: map['position'] ?? 0,
      content: map['content'] ?? '',
      length: map['length'] ?? 0,
      clientId: map['client_id'],
    );
  }

  @override
  String toString() {
    return 'EditOperation(type: $type, position: $position, length: $length)';
  }
}

/// Represents a client update
class ClientUpdate {
  final String clientId;
  final int position;
  final TextSelection? selection;

  ClientUpdate({
    required this.clientId,
    required this.position,
    this.selection,
  });
}

/// Represents a session joined event
class SessionJoinedEvent {
  final String sessionId;
  final String filePath;
  final String fileContent;
  final List<Map<String, dynamic>> activeClients;
  final int version;

  SessionJoinedEvent({
    required this.sessionId,
    required this.filePath,
    required this.fileContent,
    required this.activeClients,
    required this.version,
  });
}
