import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Advanced Automation API - AI-powered script and file generation
///
/// Implements intelligent automation with AI assistance:
/// - AI-powered script generation with contextual understanding
/// - Automatic file creation with proper project structure
/// - Context-aware code completion and refactoring
/// - Multi-language support for script generation
/// - Integration with development workflows
/// - RESTful API with authentication
/// - WebSocket for real-time events
class AutomationAPI {
  bool _isInitialized = false;

  // HTTP server
  HttpServer? _httpServer;
  WebSocketServer? _webSocketServer;

  // Authentication
  final AuthenticationManager _auth = AuthenticationManager();
  final SessionManager _sessions = SessionManager();

  // AI-powered automation
  final AIScriptGenerator _aiGenerator = AIScriptGenerator();
  final AIFileGenerator _fileGenerator = AIFileGenerator();
  final ContextAnalyzer _contextAnalyzer = ContextAnalyzer();

  // API routes
  final Map<String, APIHandler> _routes = {};

  // Rate limiting
  final RateLimiter _rateLimiter = RateLimiter();

  // Event system
  final EventBus _eventBus = EventBus();

  // Configuration
  AutomationAPIConfig _config = AutomationAPIConfig();
  
  AutomationAPI();
  
  bool get isInitialized => _isInitialized;
  HttpServer? get httpServer => _httpServer;
  WebSocketServer? get webSocketServer => _webSocketServer;
  AuthenticationManager get auth => _auth;
  SessionManager get sessions => _sessions;
  
  /// Initialize advanced automation API
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load configuration
      await _loadConfiguration();

      // Initialize authentication
      await _auth.initialize(_config);

      // Initialize session manager
      await _sessions.initialize(_config);

      // Initialize AI generators
      await _aiGenerator.initialize();
      await _fileGenerator.initialize();
      await _contextAnalyzer.initialize();

      // Setup API routes
      _setupRoutes();

      // Setup event handlers
      _setupEventHandlers();

      // Start HTTP server
      await _startHTTPServer();

      // Start WebSocket server
      await _startWebSocketServer();

      _isInitialized = true;
      debugPrint('🤖 Advanced Automation API initialized on port ${_config.httpPort}');
    } catch (e) {
      debugPrint('❌ Failed to initialize Automation API: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/automation_api_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = AutomationAPIConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load automation API config: $e');
    }
  }
  
  /// Setup API routes
  void _setupRoutes() {
    // Authentication routes
    _routes['POST /auth/login'] = _handleLogin;
    _routes['POST /auth/logout'] = _handleLogout;
    _routes['POST /auth/refresh'] = _handleTokenRefresh;
    _routes['GET /auth/me'] = _handleGetUserInfo;
    
    // Terminal routes
    _routes['POST /terminal/create'] = _handleCreateTerminal;
    _routes['DELETE /terminal/:id'] = _handleDeleteTerminal;
    _routes['GET /terminal/:id'] = _handleGetTerminal;
    _routes['POST /terminal/:id/execute'] = _handleExecuteCommand;
    _routes['POST /terminal/:id/resize'] = _handleResizeTerminal;
    _routes['GET /terminal/:id/buffer'] = _handleGetBuffer;
    _routes['POST /terminal/:id/clear'] = _handleClearBuffer;
    
    // File system routes
    _routes['GET /fs/list'] = _handleListFiles;
    _routes['GET /fs/read'] = _handleReadFile;
    _routes['POST /fs/write'] = _handleWriteFile;
    _routes['DELETE /fs/delete'] = _handleDeleteFile;
    _routes['POST /fs/mkdir'] = _handleCreateDirectory;
    _routes['POST /fs/copy'] = _handleCopyFile;
    _routes['POST /fs/move'] = _handleMoveFile;
    _routes['GET /fs/stat'] = _handleGetFileStats;
    
    // Search routes
    _routes['POST /search/text'] = _handleTextSearch;
    _routes['POST /search/regex'] = _handleRegexSearch;
    _routes['POST /search/fuzzy'] = _handleFuzzySearch;
    
    // Git routes
    _routes['GET /git/status'] = _handleGitStatus;
    _routes['POST /git/commit'] = _handleGitCommit;
    _routes['POST /git/push'] = _handleGitPush;
    _routes['POST /git/pull'] = _handleGitPull;
    _routes['GET /git/log'] = _handleGitLog;
    _routes['GET /git/branches'] = _handleGitBranches;
    
    // System routes
    _routes['GET /system/info'] = _handleGetSystemInfo;
    _routes['GET /system/processes'] = _handleGetProcesses;
    _routes['POST /system/command'] = _handleSystemCommand;
    
    // Configuration routes
    _routes['GET /config'] = _handleGetConfig;
    _routes['POST /config'] = _handleUpdateConfig;
    _routes['GET /config/schema'] = _handleGetConfigSchema;
    
    // Session routes
    _routes['GET /sessions'] = _handleGetSessions;
    _routes['POST /sessions'] = _handleCreateSession;
    _routes['DELETE /sessions/:id'] = _handleDeleteSession;
    _routes['POST /sessions/:id/restore'] = _handleRestoreSession;

    // AI Automation routes
    _routes['POST /ai/generate-script'] = _handleGenerateScript;
    _routes['POST /ai/generate-file'] = _handleGenerateFile;
    _routes['POST /ai/analyze-context'] = _handleAnalyzeContext;
    _routes['POST /ai/complete-code'] = _handleCompleteCode;
    _routes['POST /ai/refactor-code'] = _handleRefactorCode;
    _routes['GET /ai/templates'] = _handleGetTemplates;
    _routes['POST /ai/execute-workflow'] = _handleExecuteWorkflow;
    
    debugPrint('🛣️ API routes setup: ${_routes.length} routes');
  }
  
  /// Setup event handlers
  void _setupEventHandlers() {
    _eventBus.on('terminal.created', _handleTerminalCreated);
    _eventBus.on('terminal.destroyed', _handleTerminalDestroyed);
    _eventBus.on('command.executed', _handleCommandExecuted);
    _eventBus.on('file.modified', _handleFileModified);
    _eventBus.on('git.status.changed', _handleGitStatusChanged);
    
    debugPrint('📡 Event handlers setup');
  }
  
  /// Start HTTP server
  Future<void> _startHTTPServer() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _config.httpPort,
      );
      
      await for (final request in _httpServer!) {
        _handleRequest(request);
      }
      
      debugPrint('🌐 HTTP server started on port ${_config.httpPort}');
    } catch (e) {
      debugPrint('❌ Failed to start HTTP server: $e');
    }
  }
  
  /// Start WebSocket server
  Future<void> _startWebSocketServer() async {
    try {
      _webSocketServer = await WebSocketServer.bind(
        InternetAddress.anyIPv4,
        _config.webSocketPort,
      );
      
      await for (final socket in _webSocketServer!) {
        _handleWebSocketConnection(socket);
      }
      
      debugPrint('🔌 WebSocket server started on port ${_config.webSocketPort}');
    } catch (e) {
      debugPrint('❌ Failed to start WebSocket server: $e');
    }
  }
  
  /// Handle HTTP request
  Future<void> _handleRequest(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Rate limiting
      final clientIP = request.connectionInfo?.remoteAddress.address;
      if (!_rateLimiter.allowRequest(clientIP)) {
        _sendErrorResponse(request, 429, 'Too Many Requests');
        return;
      }
      
      // CORS handling
      if (request.method == 'OPTIONS') {
        _sendCORSResponse(request);
        return;
      }
      
      // Find route handler
      final handler = _findRouteHandler(request);
      if (handler == null) {
        _sendErrorResponse(request, 404, 'Not Found');
        return;
      }
      
      // Authentication check
      if (!_isPublicRoute(request.uri.path) && !await _auth.authenticateRequest(request)) {
        _sendErrorResponse(request, 401, 'Unauthorized');
        return;
      }
      
      // Execute handler
      final response = await handler(request);
      
      // Send response
      request.response
        ..statusCode = response.statusCode
        ..headers.contentType = ContentType.json.mimeType
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        ..headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        ..write(response.body);
      
      // Log request
      _logRequest(request, response, stopwatch.elapsedMicroseconds);
    } catch (e) {
      debugPrint('⚠️ Error handling request: $e');
      _sendErrorResponse(request, 500, 'Internal Server Error');
    }
  }
  
  /// Find route handler
  APIHandler? _findRouteHandler(HttpRequest request) {
    final method = request.method;
    final path = request.uri.path;
    
    for (final entry in _routes.entries) {
      final routeMethod = entry.key.split(' ')[0];
      final routePath = entry.key.split(' ')[1];
      
      if (routeMethod == method && _pathMatches(routePath, path)) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  /// Check if path matches route
  bool _pathMatches(String routePattern, String path) {
    // Simple path matching (would be enhanced with proper routing)
    if (routePattern.contains(':')) {
      // Parameterized route
      final routeParts = routePattern.split('/');
      final pathParts = path.split('/');
      
      if (routeParts.length != pathParts.length) return false;
      
      for (int i = 0; i < routeParts.length; i++) {
        if (!routeParts[i].startsWith(':') && routeParts[i] != pathParts[i]) {
          return false;
        }
      }
      
      return true;
    } else {
      // Exact match
      return routePattern == path;
    }
  }
  
  /// Check if route is public
  bool _isPublicRoute(String path) {
    final publicRoutes = [
      '/auth/login',
      '/auth/refresh',
      '/system/info',
      '/config/schema',
    ];
    
    return publicRoutes.contains(path);
  }
  
  /// Send CORS response
  void _sendCORSResponse(HttpRequest request) {
    request.response
      ..statusCode = 200
      ..headers.add('Access-Control-Allow-Origin', '*')
      ..headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
      ..headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
      ..headers.add('Access-Control-Max-Age', '86400')
      ..close();
  }
  
  /// Send error response
  void _sendErrorResponse(HttpRequest request, int statusCode, String message) {
    final errorResponse = {
      'error': true,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json.mimeType
      ..headers.add('Access-Control-Allow-Origin', '*')
      ..write(jsonEncode(errorResponse))
      ..close();
  }
  
  /// Handle WebSocket connection
  void _handleWebSocketConnection(WebSocket socket) {
    debugPrint('🔌 WebSocket connection established');
    
    socket.listen(
      (data) {
        _handleWebSocketMessage(socket, data);
      },
      onDone: () {
        debugPrint('🔌 WebSocket connection closed');
      },
      onError: (error) {
        debugPrint('⚠️ WebSocket error: $error');
      },
    );
  }
  
  /// Handle WebSocket message
  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final message = jsonDecode(data as String);
      final type = message['type'] as String;
      
      switch (type) {
        case 'auth':
          _handleWebSocketAuth(socket, message);
          break;
        case 'terminal':
          _handleWebSocketTerminal(socket, message);
          break;
        case 'subscribe':
          _handleWebSocketSubscribe(socket, message);
          break;
        default:
          debugPrint('⚠️ Unknown WebSocket message type: $type');
      }
    } catch (e) {
      debugPrint('⚠️ Error handling WebSocket message: $e');
    }
  }
  
  /// Handle WebSocket authentication
  void _handleWebSocketAuth(WebSocket socket, Map<String, dynamic> message) {
    final token = message['token'] as String?;
    if (token == null) {
      _sendWebSocketError(socket, 'Token required');
      return;
    }
    
    final session = _sessions.validateToken(token);
    if (session == null) {
      _sendWebSocketError(socket, 'Invalid token');
      return;
    }
    
    _sendWebSocketSuccess(socket, 'Authenticated successfully');
  }
  
  /// Handle WebSocket terminal
  void _handleWebSocketTerminal(WebSocket socket, Map<String, dynamic> message) {
    final action = message['action'] as String?;
    
    switch (action) {
      case 'create':
        _handleWebSocketCreateTerminal(socket, message);
        break;
      case 'execute':
        _handleWebSocketExecuteCommand(socket, message);
        break;
      case 'resize':
        _handleWebSocketResizeTerminal(socket, message);
        break;
      default:
        debugPrint('⚠️ Unknown terminal action: $action');
    }
  }
  
  /// Handle WebSocket subscribe
  void _handleWebSocketSubscribe(WebSocket socket, Map<String, dynamic> message) {
    final events = message['events'] as List<String>?;
    if (events == null) return;
    
    // Subscribe to events
    for (final event in events) {
      // Implementation would subscribe to specific events
      debugPrint('🔔 Subscribed to event: $event');
    }
    
    _sendWebSocketSuccess(socket, 'Subscribed to events');
  }
  
  /// Send WebSocket success
  void _sendWebSocketSuccess(WebSocket socket, String message) {
    final response = {
      'type': 'success',
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    socket.add(jsonEncode(response));
  }
  
  /// Send WebSocket error
  void _sendWebSocketError(WebSocket socket, String message) {
    final response = {
      'type': 'error',
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    socket.add(jsonEncode(response));
  }
  
  // API Handlers
  
  /// Handle login
  Future<APIResponse> _handleLogin(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final username = body['username'] as String?;
    final password = body['password'] as String?;
    
    if (username == null || password == null) {
      return APIResponse(400, {'error': 'Username and password required'});
    }
    
    final session = await _auth.authenticate(username, password);
    if (session == null) {
      return APIResponse(401, {'error': 'Invalid credentials'});
    }
    
    return APIResponse(200, {
      'token': session.token,
      'refreshToken': session.refreshToken,
      'expiresAt': session.expiresAt.toIso8601String(),
      'user': session.user,
    });
  }
  
  /// Handle logout
  Future<APIResponse> _handleLogout(HttpRequest request) async {
    final token = _extractTokenFromRequest(request);
    if (token != null) {
      await _auth.invalidateToken(token);
    }
    
    return APIResponse(200, {'message': 'Logged out successfully'});
  }
  
  /// Handle token refresh
  Future<APIResponse> _handleTokenRefresh(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final refreshToken = body['refreshToken'] as String?;
    
    if (refreshToken == null) {
      return APIResponse(400, {'error': 'Refresh token required'});
    }
    
    final session = await _auth.refreshToken(refreshToken);
    if (session == null) {
      return APIResponse(401, {'error': 'Invalid refresh token'});
    }
    
    return APIResponse(200, {
      'token': session.token,
      'expiresAt': session.expiresAt.toIso8601String(),
    });
  }
  
  /// Handle get user info
  Future<APIResponse> _handleGetUserInfo(HttpRequest request) async {
    final token = _extractTokenFromRequest(request);
    final session = token != null ? _sessions.validateToken(token) : null;
    
    if (session == null) {
      return APIResponse(401, {'error': 'Invalid token'});
    }
    
    return APIResponse(200, {
      'user': session.user,
      'permissions': session.permissions,
    });
  }
  
  /// Handle create terminal
  Future<APIResponse> _handleCreateTerminal(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);
    
    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }
    
    // Create terminal logic would go here
    final terminalId = 'terminal_${DateTime.now().millisecondsSinceEpoch}';
    
    return APIResponse(200, {
      'id': terminalId,
      'status': 'created',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
  
  /// Handle execute command
  Future<APIResponse> _handleExecuteCommand(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);
    
    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }
    
    final command = body['command'] as String?;
    if (command == null) {
      return APIResponse(400, {'error': 'Command required'});
    }
    
    // Execute command logic would go here
    final result = await _executeCommand(command);
    
    return APIResponse(200, {
      'command': command,
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
      'executedAt': DateTime.now().toIso8601String(),
    });
  }
  
  /// Execute command
  Future<CommandResult> _executeCommand(String command) async {
    try {
      final result = await Process.run('bash', ['-c', command], runInShell: true);
      
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout as String,
        stderr: result.stderr as String,
      );
    } catch (e) {
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }
  
  /// Parse request body
  Future<Map<String, dynamic>> _parseRequestBody(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ Failed to parse request body: $e');
      return {};
    }
  }
  
  /// Extract token from request
  String? _extractTokenFromRequest(HttpRequest request) {
    final authHeader = request.headers.value('authorization');
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    
    // Check query parameter
    final tokenParam = request.uri.queryParameters['token'];
    if (tokenParam != null) {
      return tokenParam;
    }
    
    return null;
  }
  
  /// Get session from request
  Future<Session?> _getSessionFromRequest(HttpRequest request) async {
    final token = _extractTokenFromRequest(request);
    return token != null ? _sessions.validateToken(token) : null;
  }
  
  /// Log request
  void _logRequest(HttpRequest request, APIResponse response, int microseconds) {
    final logEntry = {
      'method': request.method,
      'path': request.uri.path,
      'statusCode': response.statusCode,
      'duration': microseconds,
      'timestamp': DateTime.now().toIso8601String(),
      'clientIP': request.connectionInfo?.remoteAddress.address,
    };
    
    debugPrint('📋 API Request: ${logEntry['method']} ${logEntry['path']} -> ${logEntry['statusCode']} (${logEntry['duration']}μs)');
  }
  
  /// Event handlers
  void _handleTerminalCreated(dynamic event) {
    _eventBus.emit('terminal.created', event);
  }
  
  void _handleTerminalDestroyed(dynamic event) {
    _eventBus.emit('terminal.destroyed', event);
  }
  
  void _handleCommandExecuted(dynamic event) {
    _eventBus.emit('command.executed', event);
  }
  
  void _handleFileModified(dynamic event) {
    _eventBus.emit('file.modified', event);
  }
  
  void _handleGitStatusChanged(dynamic event) {
    _eventBus.emit('git.status.changed', event);
  }
  
  /// Get API statistics
  APIStatistics getStatistics() {
    return APIStatistics(
      httpServerRunning: _httpServer != null,
      webSocketServerRunning: _webSocketServer != null,
      activeSessions: _sessions.activeCount,
      totalRequests: _rateLimiter.totalRequests,
      blockedRequests: _rateLimiter.blockedRequests,
      routesCount: _routes.length,
      uptime: _isInitialized ? DateTime.now().difference(_startTime) : Duration.zero,
    );
  }
  
  /// Handle AI script generation
  Future<APIResponse> _handleGenerateScript(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final description = body['description'] as String?;
    final language = body['language'] as String? ?? 'bash';
    final context = body['context'] as Map<String, dynamic>? ?? {};

    if (description == null || description.isEmpty) {
      return APIResponse(400, {'error': 'Script description required'});
    }

    try {
      final script = await _aiGenerator.generateScript(
        description: description,
        language: language,
        context: context,
      );

      return APIResponse(200, {
        'script': script,
        'language': language,
        'generatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to generate script: $e'});
    }
  }

  /// Handle AI file generation
  Future<APIResponse> _handleGenerateFile(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final description = body['description'] as String?;
    final filename = body['filename'] as String?;
    final language = body['language'] as String? ?? 'dart';
    final projectContext = body['projectContext'] as Map<String, dynamic>? ?? {};

    if (description == null || filename == null) {
      return APIResponse(400, {'error': 'File description and filename required'});
    }

    try {
      final fileContent = await _fileGenerator.generateFile(
        description: description,
        filename: filename,
        language: language,
        projectContext: projectContext,
      );

      return APIResponse(200, {
        'filename': filename,
        'content': fileContent,
        'language': language,
        'generatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to generate file: $e'});
    }
  }

  /// Handle context analysis
  Future<APIResponse> _handleAnalyzeContext(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final files = body['files'] as List<String>? ?? [];
    final projectPath = body['projectPath'] as String?;

    try {
      final context = await _contextAnalyzer.analyzeProjectContext(
        files: files,
        projectPath: projectPath,
      );

      return APIResponse(200, {
        'context': context,
        'analyzedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to analyze context: $e'});
    }
  }

  /// Handle code completion
  Future<APIResponse> _handleCompleteCode(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final code = body['code'] as String?;
    final language = body['language'] as String? ?? 'dart';
    final cursorPosition = body['cursorPosition'] as int?;
    final context = body['context'] as Map<String, dynamic>? ?? {};

    if (code == null) {
      return APIResponse(400, {'error': 'Code snippet required'});
    }

    try {
      final completions = await _aiGenerator.completeCode(
        code: code,
        language: language,
        cursorPosition: cursorPosition,
        context: context,
      );

      return APIResponse(200, {
        'completions': completions,
        'language': language,
        'completedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to complete code: $e'});
    }
  }

  /// Handle code refactoring
  Future<APIResponse> _handleRefactorCode(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final code = body['code'] as String?;
    final operation = body['operation'] as String?;
    final language = body['language'] as String? ?? 'dart';
    final context = body['context'] as Map<String, dynamic>? ?? {};

    if (code == null || operation == null) {
      return APIResponse(400, {'error': 'Code and operation required'});
    }

    try {
      final refactoredCode = await _aiGenerator.refactorCode(
        code: code,
        operation: operation,
        language: language,
        context: context,
      );

      return APIResponse(200, {
        'originalCode': code,
        'refactoredCode': refactoredCode,
        'operation': operation,
        'language': language,
        'refactoredAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to refactor code: $e'});
    }
  }

  /// Handle get templates
  Future<APIResponse> _handleGetTemplates(HttpRequest request) async {
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    try {
      final templates = await _aiGenerator.getTemplates();

      return APIResponse(200, {
        'templates': templates,
        'count': templates.length,
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to get templates: $e'});
    }
  }

  /// Handle workflow execution
  Future<APIResponse> _handleExecuteWorkflow(HttpRequest request) async {
    final body = await _parseRequestBody(request);
    final session = await _getSessionFromRequest(request);

    if (session == null) {
      return APIResponse(401, {'error': 'Authentication required'});
    }

    final workflow = body['workflow'] as Map<String, dynamic>?;
    final context = body['context'] as Map<String, dynamic>? ?? {};

    if (workflow == null) {
      return APIResponse(400, {'error': 'Workflow definition required'});
    }

    try {
      final result = await _aiGenerator.executeWorkflow(
        workflow: workflow,
        context: context,
      );

      return APIResponse(200, {
        'workflow': workflow,
        'result': result,
        'executedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return APIResponse(500, {'error': 'Failed to execute workflow: $e'});
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      // Close HTTP server
      await _httpServer?.close();

      // Close WebSocket server
      await _webSocketServer?.close();

      // Dispose managers
      _auth.dispose();
      _sessions.dispose();
      _rateLimiter.dispose();
      _eventBus.dispose();

      // Dispose AI components
      await _aiGenerator.dispose();
      await _fileGenerator.dispose();
      await _contextAnalyzer.dispose();

      _isInitialized = false;
      debugPrint('🤖 Advanced Automation API disposed');
    } catch (e) {
      debugPrint('⚠️ Failed to dispose Automation API: $e');
    }
  }
}

/// Authentication manager
class AuthenticationManager {
  final Map<String, User> _users = {};
  final Map<String, Session> _sessions = {};
  AutomationAPIConfig? _config;
  
  AuthenticationManager();
  
  Future<void> initialize(AutomationAPIConfig config) async {
    _config = config;
    await _loadUsers();
    debugPrint('🔐 Authentication manager initialized');
  }
  
  Future<void> _loadUsers() async {
    try {
      final usersFile = File('${Platform.environment['HOME']}/.termisol/api_users.json');
      if (await usersFile.exists()) {
        final content = await usersFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        for (final entry in data.entries) {
          _users[entry.key] = User.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load users: $e');
    }
  }
  
  Future<Session?> authenticate(String username, String password) async {
    final user = _users[username];
    if (user == null) return null;
    
    // Simple password check (would use proper hashing in production)
    if (user.password != password) return null;
    
    final session = Session(
      id: 'session_${DateTime.now().millisecondsSinceEpoch}',
      userId: user.id,
      username: user.username,
      token: _generateToken(),
      refreshToken: _generateToken(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
      permissions: user.permissions,
      createdAt: DateTime.now(),
    );
    
    _sessions[session.id] = session;
    return session;
  }
  
  Future<bool> authenticateRequest(HttpRequest request) async {
    final token = _extractTokenFromRequest(request);
    if (token == null) return false;
    
    final session = _sessions.values.firstWhere(
      (s) => s.token == token,
      orElse: () => Session.invalid(),
    );
    
    return session.isValid && !session.isExpired;
  }
  
  String _extractTokenFromRequest(HttpRequest request) {
    final authHeader = request.headers.value('authorization');
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    return null;
  }
  
  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => Random().nextInt(256));
    return base64.encode(bytes);
  }
  
  Future<void> invalidateToken(String token) async {
    _sessions.removeWhere((id, session) => session.token == token);
  }
  
  Future<Session?> refreshToken(String refreshToken) async {
    final session = _sessions.values.firstWhere(
      (s) => s.refreshToken == refreshToken,
      orElse: () => Session.invalid(),
    );
    
    if (session.isExpired) return null;
    
    // Create new session with same user
    final newSession = Session(
      id: session.id,
      userId: session.userId,
      username: session.username,
      token: _generateToken(),
      refreshToken: _generateToken(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
      permissions: session.permissions,
      createdAt: DateTime.now(),
    );
    
    _sessions[session.id] = newSession;
    return newSession;
  }
  
  void dispose() {
    _users.clear();
    _sessions.clear();
  }
}

/// Session manager
class SessionManager {
  final Map<String, Session> _sessions = {};
  AutomationAPIConfig? _config;
  
  SessionManager();
  
  Future<void> initialize(AutomationAPIConfig config) async {
    _config = config;
    debugPrint('📋 Session manager initialized');
  }
  
  Session? validateToken(String token) {
    return _sessions.values.firstWhere(
      (s) => s.token == token,
      orElse: () => Session.invalid(),
    );
  }
  
  int get activeCount => _sessions.values.where((s) => s.isValid && !s.isExpired).length;
  
  void cleanup() {
    final now = DateTime.now();
    final expiredSessions = <String>[];
    
    for (final entry in _sessions.entries) {
      if (entry.value.expiresAt.isBefore(now)) {
        expiredSessions.add(entry.key);
      }
    }
    
    for (final id in expiredSessions) {
      _sessions.remove(id);
    }
  }
  
  void dispose() {
    _sessions.clear();
  }
}

/// Rate limiter
class RateLimiter {
  final Map<String, List<DateTime>> _requests = {};
  final Map<String, int> _blocked = {};
  int _totalRequests = 0;
  int _blockedRequests = 0;
  
  RateLimiter();
  
  bool allowRequest(String? clientIP) {
    if (clientIP == null) return true;
    
    final now = DateTime.now();
    _totalRequests++;
    
    // Clean old requests
    _cleanupOldRequests(clientIP, now);
    
    // Check rate limit
    final recentRequests = _requests[clientIP] ?? [];
    if (recentRequests.length >= 100) { // 100 requests per minute
      _blockedRequests++;
      _blocked[clientIP] = (_blocked[clientIP] ?? 0) + 1;
      return false;
    }
    
    recentRequests.add(now);
    _requests[clientIP] = recentRequests;
    return true;
  }
  
  void _cleanupOldRequests(String clientIP, DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    final requests = _requests[clientIP] ?? [];
    requests.removeWhere((time) => time.isBefore(cutoff));
  }
  
  int get totalRequests => _totalRequests;
  int get blockedRequests => _blockedRequests;
  
  void dispose() {
    _requests.clear();
    _blocked.clear();
  }
}

/// Event bus
class EventBus {
  final Map<String, List<Function>> _listeners = {};
  
  void on(String event, Function handler) {
    _listeners.putIfAbsent(event, () => []).add(handler);
  }
  
  void emit(String event, dynamic data) {
    final handlers = _listeners[event];
    if (handlers != null) {
      for (final handler in handlers) {
        try {
          handler(data);
        } catch (e) {
          debugPrint('⚠️ Event handler error: $e');
        }
      }
    }
  }
  
  void dispose() {
    _listeners.clear();
  }
}

/// Data structures
class APIResponse {
  final int statusCode;
  final Map<String, dynamic> body;
  
  APIResponse(this.statusCode, this.body);
}

class User {
  final String id;
  final String username;
  final String password;
  final List<String> permissions;
  
  User({
    required this.id,
    required this.username,
    required this.password,
    required this.permissions,
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      permissions: List<String>.from(json['permissions'] as List? ?? []),
    );
  }
}

class Session {
  final String id;
  final String userId;
  final String username;
  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final List<String> permissions;
  final DateTime createdAt;
  
  Session({
    required this.id,
    required this.userId,
    required this.username,
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.permissions,
    required this.createdAt,
  });
  
  bool get isValid => id.isNotEmpty;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  
  factory Session.invalid() {
    return Session(
      id: '',
      userId: '',
      username: '',
      token: '',
      refreshToken: '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
      permissions: [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  
  CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class APIStatistics {
  final bool httpServerRunning;
  final bool webSocketServerRunning;
  final int activeSessions;
  final int totalRequests;
  final int blockedRequests;
  final int routesCount;
  final Duration uptime;
  
  APIStatistics({
    required this.httpServerRunning,
    required this.webSocketServerRunning,
    required this.activeSessions,
    required this.totalRequests,
    required this.blockedRequests,
    required this.routesCount,
    required this.uptime,
  });
}

/// Configuration
class AutomationAPIConfig {
  final int httpPort;
  final int webSocketPort;
  final bool enableAuthentication;
  final bool enableRateLimiting;
  final int maxRequestsPerMinute;
  final Duration sessionTimeout;
  final List<String> allowedOrigins;
  final bool enableCORS;
  
  AutomationAPIConfig({
    this.httpPort = 8080,
    this.webSocketPort = 8081,
    this.enableAuthentication = true,
    this.enableRateLimiting = true,
    this.maxRequestsPerMinute = 100,
    this.sessionTimeout = const Duration(hours: 24),
    this.allowedOrigins = const ['*'],
    this.enableCORS = true,
  });
  
  factory AutomationAPIConfig.fromJson(Map<String, dynamic> json) {
    return AutomationAPIConfig(
      httpPort: json['httpPort'] as int? ?? 8080,
      webSocketPort: json['webSocketPort'] as int? ?? 8081,
      enableAuthentication: json['enableAuthentication'] as bool? ?? true,
      enableRateLimiting: json['enableRateLimiting'] as bool? ?? true,
      maxRequestsPerMinute: json['maxRequestsPerMinute'] as int? ?? 100,
      sessionTimeout: Duration(hours: json['sessionTimeoutHours'] as int? ?? 24),
      allowedOrigins: List<String>.from(json['allowedOrigins'] as List? ?? ['*']),
      enableCORS: json['enableCORS'] as bool? ?? true,
    );
  }
}

// Type alias for API handler
typedef APIHandler = Future<APIResponse> Function(HttpRequest);

/// AI Script Generator - Generates scripts with contextual understanding
class AIScriptGenerator {
  bool _isInitialized = false;
  final Map<String, ScriptTemplate> _templates = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadScriptTemplates();
    _isInitialized = true;
    debugPrint('🤖 AI Script Generator initialized');
  }

  Future<void> _loadScriptTemplates() async {
    // Load script templates for different languages and use cases
    _templates['bash'] = ScriptTemplate(
      language: 'bash',
      patterns: [
        'file_operations',
        'system_admin',
        'data_processing',
        'automation',
      ],
      examples: {
        'backup': '#!/bin/bash\n# Automated backup script\necho "Starting backup..."\n# Add backup logic here',
        'cleanup': '#!/bin/bash\n# System cleanup script\necho "Cleaning up system..."\n# Add cleanup logic here',
      },
    );

    _templates['python'] = ScriptTemplate(
      language: 'python',
      patterns: [
        'data_analysis',
        'web_scraping',
        'automation',
        'file_processing',
      ],
      examples: {
        'data_processor': '#!/usr/bin/env python3\n# Data processing script\nimport sys\n\ndef main():\n    print("Processing data...")\n    # Add processing logic here\n\nif __name__ == "__main__":\n    main()',
      },
    );

    debugPrint('📋 Loaded ${_templates.length} script templates');
  }

  Future<String> generateScript({
    required String description,
    required String language,
    required Map<String, dynamic> context,
  }) async {
    try {
      // This would use NVIDIA AI to generate the script
      // For now, return a template-based script

      final template = _templates[language];
      if (template == null) {
        throw Exception('Unsupported language: $language');
      }

      final script = _generateScriptFromTemplate(description, template, context);
      return script;
    } catch (e) {
      throw Exception('Script generation failed: $e');
    }
  }

  Future<List<String>> completeCode({
    required String code,
    required String language,
    int? cursorPosition,
    required Map<String, dynamic> context,
  }) async {
    try {
      // This would use AI to generate code completions
      // For now, return basic completions
      return [
        'print("Hello World");',
        'if (condition) {',
        'for (var item in items) {',
      ];
    } catch (e) {
      return [];
    }
  }

  Future<String> refactorCode({
    required String code,
    required String operation,
    required String language,
    required Map<String, dynamic> context,
  }) async {
    try {
      // This would use AI to refactor code
      // For now, return the original code
      return code;
    } catch (e) {
      return code;
    }
  }

  Future<Map<String, dynamic>> executeWorkflow({
    required Map<String, dynamic> workflow,
    required Map<String, dynamic> context,
  }) async {
    try {
      // Execute a workflow of AI operations
      final result = <String, dynamic>{};
      final steps = workflow['steps'] as List<dynamic>? ?? [];

      for (final step in steps) {
        final stepMap = step as Map<String, dynamic>;
        final operation = stepMap['operation'] as String;
        final params = stepMap['params'] as Map<String, dynamic>? ?? {};

        // Execute each step
        switch (operation) {
          case 'generate_script':
            result[stepMap['id'] as String] = await generateScript(
              description: params['description'] as String,
              language: params['language'] as String,
              context: context,
            );
            break;
          case 'generate_file':
            result[stepMap['id'] as String] = await _fileGenerator.generateFile(
              description: params['description'] as String,
              filename: params['filename'] as String,
              language: params['language'] as String,
              projectContext: context,
            );
            break;
        }
      }

      return result;
    } catch (e) {
      throw Exception('Workflow execution failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    return _templates.values.map((template) => {
      'language': template.language,
      'patterns': template.patterns,
      'examples': template.examples,
    }).toList();
  }

  String _generateScriptFromTemplate(
    String description,
    ScriptTemplate template,
    Map<String, dynamic> context,
  ) {
    final buffer = StringBuffer();

    // Add shebang for scripts
    if (template.language == 'bash') {
      buffer.writeln('#!/bin/bash');
    } else if (template.language == 'python') {
      buffer.writeln('#!/usr/bin/env python3');
    }

    buffer.writeln('# Auto-generated script: $description');
    buffer.writeln('# Generated at: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');

    // Add basic structure based on description
    if (description.toLowerCase().contains('backup')) {
      buffer.writeln('echo "Starting backup process..."');
      buffer.writeln('# Add backup logic here');
    } else if (description.toLowerCase().contains('cleanup')) {
      buffer.writeln('echo "Starting cleanup process..."');
      buffer.writeln('# Add cleanup logic here');
    } else {
      buffer.writeln('echo "Executing: $description"');
      buffer.writeln('# Add script logic here');
    }

    return buffer.toString();
  }

  Future<void> dispose() async {
    _templates.clear();
    _isInitialized = false;
    debugPrint('🤖 AI Script Generator disposed');
  }
}

/// AI File Generator - Generates files with project context
class AIFileGenerator {
  bool _isInitialized = false;
  final Map<String, FileTemplate> _fileTemplates = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadFileTemplates();
    _isInitialized = true;
    debugPrint('📄 AI File Generator initialized');
  }

  Future<void> _loadFileTemplates() async {
    _fileTemplates['dart'] = FileTemplate(
      language: 'dart',
      extensions: ['.dart'],
      structure: {
        'class': 'class {Name} {\n  // Properties\n  \n  // Constructor\n  {Name}();\n  \n  // Methods\n}',
        'widget': 'import \'package:flutter/material.dart\';\n\nclass {Name} extends StatelessWidget {\n  const {Name}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return const Placeholder();\n  }\n}',
      },
    );

    _fileTemplates['python'] = FileTemplate(
      language: 'python',
      extensions: ['.py'],
      structure: {
        'class': 'class {Name}:\n    """{Name} class"""\n    \n    def __init__(self):\n        pass\n    \n    def method(self):\n        pass',
        'script': '#!/usr/bin/env python3\n"""{Name} script"""\n\nimport sys\n\ndef main():\n    print("Hello from {Name}")\n\nif __name__ == "__main__":\n    main()',
      },
    );

    debugPrint('📋 Loaded ${_fileTemplates.length} file templates');
  }

  Future<String> generateFile({
    required String description,
    required String filename,
    required String language,
    required Map<String, dynamic> projectContext,
  }) async {
    try {
      final template = _fileTemplates[language];
      if (template == null) {
        throw Exception('Unsupported language: $language');
      }

      final content = _generateFileFromTemplate(description, filename, template, projectContext);
      return content;
    } catch (e) {
      throw Exception('File generation failed: $e');
    }
  }

  String _generateFileFromTemplate(
    String description,
    String filename,
    FileTemplate template,
    Map<String, dynamic> projectContext,
  ) {
    final buffer = StringBuffer();

    // Extract class name from filename
    final className = filename.split('.').first.replaceAll('_', '').toUpperCase() +
                     filename.split('.').first.substring(1);

    // Add file header
    buffer.writeln('// Auto-generated file: $filename');
    buffer.writeln('// Description: $description');
    buffer.writeln('// Generated at: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');

    // Generate content based on description
    if (description.toLowerCase().contains('widget') && language == 'dart') {
      buffer.writeln(template.structure['widget']?.replaceAll('{Name}', className) ?? '');
    } else if (description.toLowerCase().contains('class')) {
      buffer.writeln(template.structure['class']?.replaceAll('{Name}', className) ?? '');
    } else if (description.toLowerCase().contains('script') && language == 'python') {
      buffer.writeln(template.structure['script']?.replaceAll('{Name}', className) ?? '');
    } else {
      // Generate meaningful file content based on description
      final content = _generateFileContent(description, filename, language);
      buffer.writeln(content);
    }

    return buffer.toString();
  }

  /// Generate meaningful file content based on description
  String _generateFileContent(String description, String filename, String language) {
    final lowerDescription = description.toLowerCase();
    
    if (lowerDescription.contains('hello') || lowerDescription.contains('greeting')) {
      switch (language) {
        case 'dart':
          return '''void main() {
  print('Hello from $filename!');
}''';
        case 'python':
          return '''def main():
    print("Hello from $filename!")

if __name__ == "__main__":
    main()''';
        case 'javascript':
          return '''console.log("Hello from $filename!");''';
        default:
          return '// Hello from $filename\nprint("Hello!");';
      }
    } else if (lowerDescription.contains('config') || lowerDescription.contains('configuration')) {
      switch (language) {
        case 'json':
          return '''{
  "name": "$filename",
  "version": "1.0.0",
  "description": "$description"
}''';
        case 'yaml':
          return '''name: $filename
version: 1.0.0
description: $description''';
        default:
          return '// Configuration for $filename\n// TODO: Add config options';
      }
    } else if (lowerDescription.contains('test') || lowerDescription.contains('spec')) {
      switch (language) {
        case 'dart':
          return '''import 'package:test/test.dart';

void main() {
  test('$filename test', () {
    // TODO: Add test implementation
    expect(true, isTrue);
  });
}''';
        case 'python':
          return '''import unittest

class Test${filename.replaceAll('.', '')}(unittest.TestCase):
    def test_something(self):
        # TODO: Add test implementation
        self.assertTrue(True)

if __name__ == '__main__':
    unittest.main()''';
        default:
          return '// Test file for $filename\n// TODO: Add test cases';
      }
    } else {
      // Generic implementation based on language
      switch (language) {
        case 'dart':
          return '''class $filename {
  // TODO: Implement class functionality
  
  $filename();
  
  void method() {
    // TODO: Add method implementation
  }
}''';
        case 'python':
          return '''class ${filename.replaceAll('.py', '')}:
    """TODO: Add class documentation"""
    
    def __init__(self):
        # TODO: Add initialization
        pass
    
    def method(self):
        # TODO: Add method implementation
        pass''';
        case 'javascript':
          return '''class ${filename.replaceAll('.js', '')} {
  // TODO: Implement class functionality
  
  constructor() {
    // TODO: Add initialization
  }
  
  method() {
    // TODO: Add method implementation
  }
}''';
        default:
          return '// Implementation for $filename\n// Based on: $description\n// TODO: Add specific logic';
      }
    }
  }

  Future<void> dispose() async {
    _fileTemplates.clear();
    _isInitialized = false;
    debugPrint('📄 AI File Generator disposed');
  }
}

/// Context Analyzer - Analyzes project context for AI generation
class ContextAnalyzer {
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _isInitialized = true;
    debugPrint('🔍 Context Analyzer initialized');
  }

  Future<Map<String, dynamic>> analyzeProjectContext({
    required List<String> files,
    String? projectPath,
  }) async {
    try {
      final context = <String, dynamic>{};

      // Analyze file types
      final extensions = <String, int>{};
      for (final file in files) {
        final ext = file.split('.').last;
        extensions[ext] = (extensions[ext] ?? 0) + 1;
      }
      context['fileTypes'] = extensions;

      // Analyze project structure
      if (projectPath != null) {
        context['projectStructure'] = await _analyzeProjectStructure(projectPath);
      }

      // Analyze common patterns
      context['patterns'] = await _analyzePatterns(files);

      return context;
    } catch (e) {
      return {'error': 'Context analysis failed: $e'};
    }
  }

  Future<Map<String, dynamic>> _analyzeProjectStructure(String projectPath) async {
    // Analyze project structure (simplified)
    return {
      'hasPubspec': false, // Would check for pubspec.yaml
      'hasPackageJson': false, // Would check for package.json
      'hasCargoToml': false, // Would check for Cargo.toml
    };
  }

  Future<Map<String, dynamic>> _analyzePatterns(List<String> files) async {
    // Analyze common patterns in files (simplified)
    return {
      'frameworks': [],
      'languages': [],
      'patterns': [],
    };
  }

  Future<void> dispose() async {
    _isInitialized = false;
    debugPrint('🔍 Context Analyzer disposed');
  }
}

/// Script Template
class ScriptTemplate {
  final String language;
  final List<String> patterns;
  final Map<String, String> examples;

  ScriptTemplate({
    required this.language,
    required this.patterns,
    required this.examples,
  });
}

/// File Template
class FileTemplate {
  final String language;
  final List<String> extensions;
  final Map<String, String> structure;

  FileTemplate({
    required this.language,
    required this.extensions,
    required this.structure,
  });
}
