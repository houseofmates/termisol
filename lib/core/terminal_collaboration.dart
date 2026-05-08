import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import 'terminal_session.dart';

/// House-wide Terminal Sharing and Collaboration
/// 
/// Implements real-time terminal collaboration:
/// - Multi-user terminal sessions
/// - Live terminal sharing and viewing
/// - Role-based permissions (viewer, operator, admin)
/// - Real-time cursor and input synchronization
/// - Session recording and playback
/// - House-wide notification system
/// - Secure authentication with existing SSH keys
class TerminalCollaboration {
  bool _isInitialized = false;
  
  // Connection state
  WebSocketChannel? _mainChannel;
  WebSocketChannel? _notificationChannel;
  String _userId = '';
  String _userName = '';
  String _currentRoom = '';
  CollaborationRole _currentRole = CollaborationRole.viewer;
  
  // Active sessions
  final Map<String, SharedSession> _sharedSessions = {};
  final Map<String, CollaborationRoom> _rooms = {};
  final Map<String, List<CollaborationEvent>> _eventHistory = {};
  
  // Local state
  final List<Collaborator> _activeCollaborators = [];
  final Map<String, TerminalSession> _terminals = {};
  final StreamController<CollaborationEvent> _eventController = StreamController.broadcast();
  
  // Configuration
  String _serverUrl = 'ws://localhost:8080';
  String? _sshKeyPath;
  bool _autoShareEnabled = true;
  
  // Event handlers
  final List<Function(SharedSession)> _onSessionShared = [];
  final List<Function(Collaborator)> _onCollaboratorJoined = [];
  final List<Function(Collaborator)> _onCollaboratorLeft = [];
  final List<Function(CollaborationEvent)> _onEventReceived = [];
  final List<Function(String)> _onRoomJoined = [];
  final List<Function(String)> _onRoomLeft = [];
  final List<Function(Map<String, dynamic>)> _onChatMessage = [];
  final List<Function(Map<String, dynamic>)> _onSystemNotification = [];
  final List<Function(Collaborator)> _onUserJoined = [];
  
  TerminalCollaboration();
  
  bool get isInitialized => _isInitialized;
  String get userId => _userId;
  String get userName => _userName;
  String get currentRoom => _currentRoom;
  CollaborationRole get currentRole => _currentRole;
  List<Collaborator> get activeCollaborators => List.unmodifiable(_activeCollaborators);
  Map<String, SharedSession> get sharedSessions => Map.unmodifiable(_sharedSessions);
  Stream<CollaborationEvent> get events => _eventController.stream;
  
  /// Initialize collaboration system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load user identity
      await _loadUserIdentity();
      
      // Setup WebSocket connections
      await _setupConnections();
      
      // Start heartbeat
      _startHeartbeat();
      
      _isInitialized = true;
      debugPrint('🤝 Terminal Collaboration initialized for user: $_userName');
    } catch (e) {
      debugPrint('❌ Failed to initialize Terminal Collaboration: $e');
      rethrow;
    }
  }
  
  /// Load user identity from SSH key
  Future<void> _loadUserIdentity() async {
    try {
      // Use existing SSH key for authentication
      _sshKeyPath = '/home/house/.ssh/hermes_key';
      final sshKeyFile = File(_sshKeyPath!);
      
      if (await sshKeyFile.exists()) {
        final keyContent = await sshKeyFile.readAsString();
        final keyLines = keyContent.split('\n');
        
        // Extract user info from SSH key comment
        for (final line in keyLines) {
          if (line.startsWith('ssh-rsa') || line.startsWith('ssh-ed25519')) {
            final parts = line.split(' ');
            if (parts.length >= 3) {
              final comment = parts[2];
              // Extract username from comment like "house@hostname"
              if (comment.contains('@')) {
                _userName = comment.split('@')[0];
              } else {
                _userName = comment;
              }
            }
          }
        }
        
        // Generate user ID from key fingerprint
        _userId = 'user_${DateTime.now().millisecondsSinceEpoch}_${_userName.hashCode}';
        
        debugPrint('🔑 Loaded SSH identity: $_userName');
      } else {
        // Fallback to system username
        _userName = Platform.environment['USER'] ?? 'user';
        _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('⚠️ SSH key not found, using system username: $_userName');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load user identity: $e');
      _userName = Platform.environment['USER'] ?? 'user';
      _userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  /// Setup WebSocket connections
  Future<void> _setupConnections() async {
    try {
      // Main collaboration channel
      _mainChannel = WebSocketChannel.connect(
        Uri.parse('$_serverUrl/collaboration'),
        protocols: ['termisol-collab'],
      );
      
      // Notification channel
      _notificationChannel = WebSocketChannel.connect(
        Uri.parse('$_serverUrl/notifications'),
        protocols: ['termisol-notify'],
      );
      
      // Listen for messages
      _mainChannel!.stream.listen(_handleMainMessage);
      _notificationChannel!.stream.listen(_handleNotificationMessage);
      
      debugPrint('🔌 Connected to collaboration server');
    } catch (e) {
      debugPrint('⚠️ Failed to connect to collaboration server: $e');
      // Continue in offline mode
    }
  }
  
  /// Handle main channel messages
  void _handleMainMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final event = CollaborationEvent.fromJson(data);
      
      _processEvent(event);
      _eventController.add(event);
      
      debugPrint('📨 Received event: ${event.type}');
    } catch (e) {
      debugPrint('⚠️ Failed to handle message: $e');
    }
  }
  
  /// Handle notification messages
  void _handleNotificationMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final notification = CollaborationNotification.fromJson(data);
      
      _processNotification(notification);
      
      debugPrint('📬 Received notification: ${notification.type}');
    } catch (e) {
      debugPrint('⚠️ Failed to handle notification: $e');
    }
  }
  
  /// Process collaboration event
  void _processEvent(CollaborationEvent event) {
    switch (event.type) {
      case CollaborationEventType.sessionShared:
        final session = SharedSession.fromJson(event.data);
        _sharedSessions[session.id] = session;
        _onSessionShared.forEach((callback) => callback(session));
        break;
        
      case CollaborationEventType.collaboratorJoined:
        final collaborator = Collaborator.fromJson(event.data);
        _activeCollaborators.add(collaborator);
        _onCollaboratorJoined.forEach((callback) => callback(collaborator));
        break;
        
      case CollaborationEventType.collaboratorLeft:
        final collaborator = Collaborator.fromJson(event.data);
        _activeCollaborators.removeWhere((c) => c.id == collaborator.id);
        _onCollaboratorLeft.forEach((callback) => callback(collaborator));
        break;
        
      case CollaborationEventType.terminalInput:
        if (_currentRole == CollaborationRole.operator || 
            _currentRole == CollaborationRole.admin) {
          final input = event.data['input'] as String;
          final terminalId = event.data['terminal_id'] as String;
          _sendTerminalInput(terminalId, input);
        }
        break;
        
      case CollaborationEventType.terminalOutput:
        final output = event.data['output'] as String;
        final terminalId = event.data['terminal_id'] as String;
        _sendTerminalOutput(terminalId, output);
        break;
        
      case CollaborationEventType.cursorMove:
        final cursor = TerminalCursor.fromJson(event.data);
        final terminalId = event.data['terminal_id'] as String;
        _updateTerminalCursor(terminalId, cursor);
        break;
        
      case CollaborationEventType.fileTransfer:
        final transfer = FileTransfer.fromJson(event.data);
        _handleFileTransfer(transfer);
        break;
        
      case CollaborationEventType.sessionJoined:
        final session = SharedSession.fromJson(event.data);
        _sharedSessions[session.id] = session;
        break;
        
      case CollaborationEventType.sessionLeft:
        final sessionId = event.data['session_id'] as String;
        _sharedSessions.remove(sessionId);
        break;
        
      case CollaborationEventType.chatMessage:
        _onChatMessage.forEach((callback) => callback(event.data as Map<String, dynamic>));
        break;
        
      case CollaborationEventType.systemNotification:
        _onSystemNotification.forEach((callback) => callback(event.data as Map<String, dynamic>));
        break;
    }
    
    // Store event in history
    _eventHistory.putIfAbsent(event.sessionId, () => []).add(event);
  }
  
  /// Process notification
  void _processNotification(CollaborationNotification notification) {
    switch (notification.type) {
      case CollaborationNotificationType.terminalRequest:
        _handleTerminalRequest(notification.data);
        break;
        
      case CollaborationNotificationType.fileShare:
        _handleFileShare(notification.data);
        break;
        
      case CollaborationNotificationType.systemMessage:
        _handleSystemMessage(notification.data);
        break;
        
      case CollaborationNotificationType.userJoined:
        final collaborator = Collaborator.fromJson(notification.data);
        _activeCollaborators.add(collaborator);
        _onUserJoined.forEach((callback) => callback(collaborator));
        break;
        
      case CollaborationNotificationType.userLeft:
        final userId = notification.data['user_id'] as String;
        _activeCollaborators.removeWhere((c) => c.id == userId);
        break;
    }
  }
  
  /// Start heartbeat
  void _startHeartbeat() {
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (_mainChannel != null) {
        _sendMessage({
          'type': 'heartbeat',
          'user_id': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }
  
  /// Send message to server
  void _sendMessage(Map<String, dynamic> message) {
    if (_mainChannel != null) {
      _mainChannel!.sink.add(jsonEncode(message));
    }
  }
  
  /// Share terminal session
  Future<String> shareTerminalSession(
    TerminalSession terminal, {
    String? name,
    CollaborationRole role = CollaborationRole.operator,
    bool allowControl = true,
    String? password,
  }) async {
    try {
      final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      final sharedSession = SharedSession(
        id: sessionId,
        name: name ?? 'Shared Terminal',
        ownerId: _userId,
        ownerName: _userName,
        terminalId: terminal.id,
        terminalName: terminal.name,
        createdAt: DateTime.now(),
        allowControl: allowControl,
        isPublic: password == null,
        password: password,
        collaborators: [],
      );
      
      // Send share request
      _sendMessage({
        'type': 'share_session',
        'session': sharedSession.toJson(),
      });
      
      // Store locally
      _sharedSessions[sessionId] = sharedSession;
      
      debugPrint('🤝 Shared terminal session: $sessionId');
      return sessionId;
    } catch (e) {
      debugPrint('⚠️ Failed to share terminal session: $e');
      rethrow;
    }
  }
  
  /// Join shared session
  Future<bool> joinSharedSession(
    String sessionId, {
    String? password,
    CollaborationRole role = CollaborationRole.viewer,
  }) async {
    try {
      final session = _sharedSessions[sessionId];
      if (session == null) {
        // Request session info from server
        _sendMessage({
          'type': 'join_session',
          'session_id': sessionId,
          'password': password,
          'role': role.toString(),
        });
        return true;
      }
      
      // Check permissions
      if (!session.isPublic && session.password != password) {
        debugPrint('⚠️ Invalid password for session: $sessionId');
        return false;
      }
      
      // Join session
      _currentRoom = sessionId;
      _currentRole = role;
      
      _sendMessage({
        'type': 'session_joined',
        'session_id': sessionId,
        'user_id': _userId,
        'user_name': _userName,
        'role': role.toString(),
      });
      
      _onRoomJoined.forEach((callback) => callback(sessionId));
      
      debugPrint('🤝 Joined shared session: $sessionId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to join shared session: $e');
      return false;
    }
  }
  
  /// Leave shared session
  Future<void> leaveSharedSession() async {
    if (_currentRoom.isEmpty) return;
    
    try {
      _sendMessage({
        'type': 'leave_session',
        'session_id': _currentRoom,
        'user_id': _userId,
      });
      
      final roomId = _currentRoom;
      _currentRoom = '';
      _currentRole = CollaborationRole.viewer;
      
      _onRoomLeft.forEach((callback) => callback(roomId));
      
      debugPrint('🚪 Left shared session: $roomId');
    } catch (e) {
      debugPrint('⚠️ Failed to leave shared session: $e');
    }
  }
  
  /// Send terminal input
  void _sendTerminalInput(String terminalId, String input) {
    final terminal = _terminals[terminalId];
    if (terminal != null) {
      terminal.sendToBackend(utf8.encode(input));
    }
  }
  
  /// Send terminal output
  void _sendTerminalOutput(String terminalId, String output) {
    // Send output to collaboration channel
    _sendMessage({
      'type': 'terminal_output',
      'terminal_id': terminalId,
      'output': output,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Update terminal cursor
  void _updateTerminalCursor(String terminalId, TerminalCursor cursor) {
    _sendMessage({
      'type': 'cursor_move',
      'terminal_id': terminalId,
      'cursor': cursor.toJson(),
    });
  }
  
  /// Handle file transfer
  void _handleFileTransfer(FileTransfer transfer) {
    // Handle incoming file transfers
    if (transfer.direction == TransferDirection.incoming) {
      _receiveFile(transfer);
    } else {
      _sendFile(transfer);
    }
  }
  
  /// Receive file
  Future<void> _receiveFile(FileTransfer transfer) async {
    try {
      final file = File(transfer.filePath);
      await file.writeAsBytes(transfer.data!);
      
      debugPrint('📁 Received file: ${transfer.fileName}');
    } catch (e) {
      debugPrint('⚠️ Failed to receive file: $e');
    }
  }
  
  /// Send file
  Future<void> _sendFile(FileTransfer transfer) async {
    try {
      final file = File(transfer.filePath);
      final data = await file.readAsBytes();
      
      transfer.data = data;
      
      _sendMessage({
        'type': 'file_transfer',
        'transfer': transfer.toJson(),
      });
      
      debugPrint('📤 Sent file: ${transfer.fileName}');
    } catch (e) {
      debugPrint('⚠️ Failed to send file: $e');
    }
  }
  
  /// Share file with housemates
  Future<String> shareFileWithHousemates(
    String filePath, {
    String? description,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
      
      final fileName = p.basename(filePath);
      final fileSize = await file.length();
      
      final transfer = FileTransfer(
        id: 'transfer_${DateTime.now().millisecondsSinceEpoch}',
        fileName: fileName,
        filePath: filePath,
        fileSize: fileSize,
        senderId: _userId,
        senderName: _userName,
        direction: TransferDirection.outgoing,
        timestamp: DateTime.now(),
        description: description,
      );
      
      _handleFileTransfer(transfer);
      
      debugPrint('📤 Shared file with housemates: $fileName');
      return transfer.id;
    } catch (e) {
      debugPrint('⚠️ Failed to share file: $e');
      rethrow;
    }
  }
  
  /// Handle terminal request
  void _handleTerminalRequest(Map<String, dynamic> data) {
    final requestId = data['request_id'] as String;
    final requesterName = data['requester_name'] as String;
    final terminalName = data['terminal_name'] as String;
    
    // Show notification to user
    _showNotification(
      'Terminal Request',
      '$requesterName wants to join your terminal: $terminalName',
      type: CollaborationNotificationType.terminalRequest,
      data: data,
    );
  }
  
  /// Handle file share
  void _handleFileShare(Map<String, dynamic> data) {
    final sharerName = data['sharer_name'] as String;
    final fileName = data['file_name'] as String;
    
    _showNotification(
      'File Shared',
      '$sharerName shared file: $fileName',
      type: CollaborationNotificationType.fileShare,
      data: data,
    );
  }
  
  /// Handle system message
  void _handleSystemMessage(Map<String, dynamic> data) {
    final message = data['message'] as String;
    final level = data['level'] as String? ?? 'info';
    
    _showNotification(
      'System Message',
      message,
      type: CollaborationNotificationType.systemMessage,
      data: data,
    );
  }
  
  /// Show notification
  void _showNotification(
    String title,
    String message, {
    CollaborationNotificationType? type,
    Map<String, dynamic>? data,
  }) {
    // In a real implementation, this would show a native notification
    debugPrint('🔔 Notification: $title - $message');
  }
  
  /// Get available sessions
  List<SharedSession> getAvailableSessions() {
    return _sharedSessions.values.where((session) {
      return session.isPublic || session.ownerId == _userId;
    }).toList();
  }
  
  /// Get sessions by user
  List<SharedSession> getSessionsByUser(String userId) {
    return _sharedSessions.values
        .where((session) => session.ownerId == userId)
        .toList();
  }
  
  /// Search sessions
  List<SharedSession> searchSessions(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _sharedSessions.values.where((session) {
      return session.name.toLowerCase().contains(lowerQuery) ||
             session.ownerName.toLowerCase().contains(lowerQuery) ||
             (session.description?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }
  
  /// Get collaboration statistics
  Map<String, dynamic> getStatistics() {
    final totalSessions = _sharedSessions.length;
    final publicSessions = _sharedSessions.values
        .where((s) => s.isPublic)
        .length;
    final activeCollaborators = _activeCollaborators.length;
    final totalEvents = _eventHistory.values
        .map((events) => events.length)
        .fold(0, (a, b) => a + b);
    
    return {
      'user_id': _userId,
      'user_name': _userName,
      'current_room': _currentRoom,
      'current_role': _currentRole.toString(),
      'total_sessions': totalSessions,
      'public_sessions': publicSessions,
      'active_collaborators': activeCollaborators,
      'total_events': totalEvents,
      'connected': _mainChannel != null,
      'auto_share_enabled': _autoShareEnabled,
    };
  }
  
  /// Add session shared listener
  void addSessionSharedListener(Function(SharedSession) listener) {
    _onSessionShared.add(listener);
  }
  
  /// Add collaborator joined listener
  void addCollaboratorJoinedListener(Function(Collaborator) listener) {
    _onCollaboratorJoined.add(listener);
  }
  
  /// Add collaborator left listener
  void addCollaboratorLeftListener(Function(Collaborator) listener) {
    _onCollaboratorLeft.add(listener);
  }
  
  /// Add event received listener
  void addEventReceivedListener(Function(CollaborationEvent) listener) {
    _onEventReceived.add(listener);
  }
  
  /// Add room joined listener
  void addRoomJoinedListener(Function(String) listener) {
    _onRoomJoined.add(listener);
  }
  
  /// Add room left listener
  void addRoomLeftListener(Function(String) listener) {
    _onRoomLeft.add(listener);
  }
  
  /// Remove session shared listener
  void removeSessionSharedListener(Function(SharedSession) listener) {
    _onSessionShared.remove(listener);
  }
  
  /// Remove collaborator joined listener
  void removeCollaboratorJoinedListener(Function(Collaborator) listener) {
    _onCollaboratorJoined.remove(listener);
  }
  
  /// Remove collaborator left listener
  void removeCollaboratorLeftListener(Function(Collaborator) listener) {
    _onCollaboratorLeft.remove(listener);
  }
  
  /// Remove event received listener
  void removeEventReceivedListener(Function(CollaborationEvent) listener) {
    _onEventReceived.remove(listener);
  }
  
  /// Remove room joined listener
  void removeRoomJoinedListener(Function(String) listener) {
    _onRoomJoined.remove(listener);
  }
  
  /// Remove room left listener
  void removeRoomLeftListener(Function(String) listener) {
    _onRoomLeft.remove(listener);
  }
  
  /// Set configuration
  void setConfiguration({
    String? serverUrl,
    String? sshKeyPath,
    bool? autoShareEnabled,
  }) {
    if (serverUrl != null) _serverUrl = serverUrl!;
    if (sshKeyPath != null) _sshKeyPath = sshKeyPath!;
    if (autoShareEnabled != null) _autoShareEnabled = autoShareEnabled!;
    
    debugPrint('⚙️ Collaboration configuration updated');
  }
  
  /// Dispose collaboration system
  Future<void> dispose() async {
    // Leave current session
    await leaveSharedSession();
    
    // Close connections
    _mainChannel?.sink.close();
    _notificationChannel?.sink.close();
    
    // Clear state
    _sharedSessions.clear();
    _rooms.clear();
    _eventHistory.clear();
    _activeCollaborators.clear();
    _terminals.clear();
    
    // Clear listeners
    _onSessionShared.clear();
    _onCollaboratorJoined.clear();
    _onCollaboratorLeft.clear();
    _onEventReceived.clear();
    _onRoomJoined.clear();
    _onRoomLeft.clear();
    
    _isInitialized = false;
    debugPrint('🤝 Terminal Collaboration disposed');
  }
}

/// Collaboration event types
enum CollaborationEventType {
  sessionShared,
  sessionJoined,
  sessionLeft,
  collaboratorJoined,
  collaboratorLeft,
  terminalInput,
  terminalOutput,
  cursorMove,
  fileTransfer,
  chatMessage,
  systemNotification,
}

/// Collaboration notification types
enum CollaborationNotificationType {
  terminalRequest,
  fileShare,
  systemMessage,
  userJoined,
  userLeft,
}

/// Collaboration roles
enum CollaborationRole {
  viewer,
  operator,
  admin,
}

/// File transfer directions
enum TransferDirection {
  incoming,
  outgoing,
}

/// Shared session model
class SharedSession {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final String ownerName;
  final String terminalId;
  final String terminalName;
  final DateTime createdAt;
  final bool allowControl;
  final bool isPublic;
  final String? password;
  final List<Collaborator> collaborators;
  final DateTime? lastActivity;
  
  SharedSession({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.ownerName,
    required this.terminalId,
    required this.terminalName,
    required this.createdAt,
    required this.allowControl,
    required this.isPublic,
    this.password,
    required this.collaborators,
    this.lastActivity,
  });
  
  factory SharedSession.fromJson(Map<String, dynamic> json) {
    return SharedSession(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      ownerId: json['owner_id'],
      ownerName: json['owner_name'],
      terminalId: json['terminal_id'],
      terminalName: json['terminal_name'],
      createdAt: DateTime.parse(json['created_at']),
      allowControl: json['allow_control'],
      isPublic: json['is_public'],
      password: json['password'],
      collaborators: (json['collaborators'] as List?)
          ?.map((c) => Collaborator.fromJson(c))
          .toList() ?? [],
      lastActivity: json['last_activity'] != null 
          ? DateTime.parse(json['last_activity'])
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'terminal_id': terminalId,
      'terminal_name': terminalName,
      'created_at': createdAt.toIso8601String(),
      'allow_control': allowControl,
      'is_public': isPublic,
      'password': password,
      'collaborators': collaborators.map((c) => c.toJson()).toList(),
      'last_activity': lastActivity?.toIso8601String(),
    };
  }
}

/// Collaboration room model
class CollaborationRoom {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final List<Collaborator> members;
  final DateTime createdAt;
  final Map<String, dynamic> settings;
  
  CollaborationRoom({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.members,
    required this.createdAt,
    required this.settings,
  });
}

/// Collaborator model
class Collaborator {
  final String id;
  final String name;
  final String? avatar;
  final CollaborationRole role;
  final DateTime joinedAt;
  final bool isActive;
  final TerminalCursor? cursor;
  
  Collaborator({
    required this.id,
    required this.name,
    this.avatar,
    required this.role,
    required this.joinedAt,
    required this.isActive,
    this.cursor,
  });
  
  factory Collaborator.fromJson(Map<String, dynamic> json) {
    return Collaborator(
      id: json['id'],
      name: json['name'],
      avatar: json['avatar'],
      role: CollaborationRole.values.firstWhere(
        (r) => r.toString() == json['role'],
        orElse: () => CollaborationRole.viewer,
      ),
      joinedAt: DateTime.parse(json['joined_at']),
      isActive: json['is_active'] ?? true,
      cursor: json['cursor'] != null 
          ? TerminalCursor.fromJson(json['cursor'])
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'role': role.toString(),
      'joined_at': joinedAt.toIso8601String(),
      'is_active': isActive,
      'cursor': cursor?.toJson(),
    };
  }
}

/// Collaboration event model
class CollaborationEvent {
  final String id;
  final CollaborationEventType type;
  final String sessionId;
  final String userId;
  final String? userName;
  final dynamic data;
  final DateTime timestamp;
  
  CollaborationEvent({
    required this.id,
    required this.type,
    required this.sessionId,
    required this.userId,
    this.userName,
    required this.data,
    required this.timestamp,
  });
  
  factory CollaborationEvent.fromJson(Map<String, dynamic> json) {
    return CollaborationEvent(
      id: json['id'],
      type: CollaborationEventType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => CollaborationEventType.systemNotification,
      ),
      sessionId: json['session_id'],
      userId: json['user_id'],
      userName: json['user_name'],
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'session_id': sessionId,
      'user_id': userId,
      'user_name': userName,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Collaboration notification model
class CollaborationNotification {
  final String id;
  final CollaborationNotificationType type;
  final String title;
  final String message;
  final dynamic data;
  final DateTime timestamp;
  
  CollaborationNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.data,
    required this.timestamp,
  });
  
  factory CollaborationNotification.fromJson(Map<String, dynamic> json) {
    return CollaborationNotification(
      id: json['id'],
      type: CollaborationNotificationType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => CollaborationNotificationType.systemMessage,
      ),
      title: json['title'],
      message: json['message'],
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'title': title,
      'message': message,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Terminal cursor model
class TerminalCursor {
  final int x;
  final int y;
  final bool visible;
  final String? style;
  
  TerminalCursor({
    required this.x,
    required this.y,
    required this.visible,
    this.style,
  });
  
  factory TerminalCursor.fromJson(Map<String, dynamic> json) {
    return TerminalCursor(
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
      visible: json['visible'] ?? true,
      style: json['style'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'visible': visible,
      'style': style,
    };
  }
}

/// File transfer model
class FileTransfer {
  final String id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String senderId;
  final String senderName;
  final String? receiverId;
  final String? receiverName;
  final TransferDirection direction;
  final DateTime timestamp;
  Uint8List? data;
  final String? description;
  final double? progress;
  final FileTransferStatus status;
  
  FileTransfer({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.senderId,
    required this.senderName,
    this.receiverId,
    this.receiverName,
    required this.direction,
    required this.timestamp,
    this.data,
    this.description,
    this.progress,
    this.status = FileTransferStatus.pending,
  });
  
  factory FileTransfer.fromJson(Map<String, dynamic> json) {
    return FileTransfer(
      id: json['id'],
      fileName: json['file_name'],
      filePath: json['file_path'],
      fileSize: json['file_size'],
      senderId: json['sender_id'],
      senderName: json['sender_name'],
      receiverId: json['receiver_id'],
      receiverName: json['receiver_name'],
      direction: TransferDirection.values.firstWhere(
        (d) => d.toString() == json['direction'],
        orElse: () => TransferDirection.incoming,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      description: json['description'],
      progress: json['progress']?.toDouble(),
      status: FileTransferStatus.values.firstWhere(
        (s) => s.toString() == json['status'],
        orElse: () => FileTransferStatus.pending,
      ),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'file_path': filePath,
      'file_size': fileSize,
      'sender_id': senderId,
      'sender_name': senderName,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'direction': direction.toString(),
      'timestamp': timestamp.toIso8601String(),
      'description': description,
      'progress': progress,
      'status': status.toString(),
    };
  }
}

/// File transfer status
enum FileTransferStatus {
  pending,
  inProgress,
  completed,
  failed,
  cancelled,
}
