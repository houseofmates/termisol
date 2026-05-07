import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';
import 'package:path/path.dart' as path;

/// Language Server Protocol Client - Advanced code intelligence
/// 
/// Implements comprehensive LSP support:
/// - Auto-completion with documentation
/// - Go to definition
/// - Find references
/// - Hover information
/// - Diagnostics and error checking
/// - Code formatting
/// - Refactoring support
/// - Multi-language support
class LspClient {
  bool _isInitialized = false;
  WebSocketChannel? _channel;
  String _serverPath = '';
  String _workspaceRoot = '';
  
  // LSP state
  bool _isConnected = false;
  int _messageId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, LspLanguage> _languages = {};
  
  // Capabilities
  LspCapabilities _serverCapabilities = LspCapabilities();
  LspCapabilities _clientCapabilities = LspCapabilities();
  
  // Code intelligence data
  final Map<String, List<LspDiagnostic>> _diagnostics = {};
  final Map<String, List<LspCompletion>> _completions = {};
  final Map<String, Map<String, dynamic>> _symbols = {};
  final Map<String, LspHover> _hoverInfo = {};
  
  // Event handlers
  final List<Function(List<LspDiagnostic>)> _onDiagnostics = [];
  final List<Function(List<LspCompletion>)> _onCompletions = [];
  final List<Function(LspHover)> _onHover = [];
  final List<Function(LspLocation)> _onGotoDefinition = [];
  
  LspClient();
  
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  String get serverPath => _serverPath;
  String get workspaceRoot => _workspaceRoot;
  LspCapabilities get serverCapabilities => _serverCapabilities;
  Map<String, List<LspDiagnostic>> get diagnostics => Map.unmodifiable(_diagnostics);
  Map<String, List<LspCompletion>> get completions => Map.unmodifiable(_completions);
  
  /// Initialize LSP client
  Future<void> initialize({
    required String serverPath,
    required String workspaceRoot,
    Map<String, dynamic>? clientCapabilities,
  }) async {
    if (_isInitialized) return;
    
    try {
      _serverPath = serverPath;
      _workspaceRoot = workspaceRoot;
      
      // Setup client capabilities
      if (clientCapabilities != null) {
        _clientCapabilities = LspCapabilities.fromJson(clientCapabilities!);
      } else {
        _setupDefaultClientCapabilities();
      }
      
      // Setup supported languages
      await _setupSupportedLanguages();
      
      // Connect to server
      await _connectToServer();
      
      _isInitialized = true;
      debugPrint('🧠 LSP Client initialized for $serverPath');
    } catch (e) {
      debugPrint('❌ Failed to initialize LSP Client: $e');
      rethrow;
    }
  }
  
  /// Setup default client capabilities
  void _setupDefaultClientCapabilities() {
    _clientCapabilities = LspCapabilities(
      textDocumentSync: TextDocumentSyncCapabilities(
        dynamicRegistration: false,
        willSave: true,
        willSaveWaitUntil: false,
      ),
      completionProvider: CompletionCapabilities(
        resolveProvider: false,
        triggerCharacters: ['.', ':', '(', '[', '"', "'"],
      ),
      hoverProvider: true,
      definitionProvider: true,
      referencesProvider: true,
      documentFormattingProvider: true,
      documentRangeFormattingProvider: true,
      codeActionProvider: CodeActionCapabilities(
        codeActionLiteralSupport: true,
        isPreferredSupport: true,
      ),
      workspace: WorkspaceCapabilities(
        workspaceFolders: true,
        configuration: true,
      ),
    );
  }
  
  /// Setup supported languages
  Future<void> _setupSupportedLanguages() async {
    _languages = {
      'dart': LspLanguage(
        id: 'dart',
        name: 'Dart',
        fileExtensions: ['.dart'],
        serverCommand: 'dart analysis_server',
        initializationOptions: {
          'onlyAnalyze': [_workspaceRoot],
          'enableCompletion': true,
          'enableHover': true,
          'enableSuggestionNames': true,
        },
      ),
      'python': LspLanguage(
        id: 'python',
        name: 'Python',
        fileExtensions: ['.py'],
        serverCommand: 'pylsp',
        initializationOptions: {
          'pylsp': {
            'plugins': {
              'pylsp_mypy': {'enabled': true},
              'pylsp_black': {'enabled': true},
              'pylsp_isort': {'enabled': true},
            },
          },
        },
      ),
      'javascript': LspLanguage(
        id: 'javascript',
        name: 'JavaScript',
        fileExtensions: ['.js', '.jsx'],
        serverCommand: 'typescript-language-server',
        initializationOptions: {
          'javascript': {
            'validate': {'enable': true},
            'suggest': {
              'autoImports': true,
              'completeFunctionCalls': true,
            },
          },
        },
      ),
      'typescript': LspLanguage(
        id: 'typescript',
        name: 'TypeScript',
        fileExtensions: ['.ts', '.tsx'],
        serverCommand: 'typescript-language-server',
        initializationOptions: {
          'typescript': {
            'validate': {'enable': true},
            'suggest': {
              'autoImports': true,
              'completeFunctionCalls': true,
            },
          },
        },
      ),
      'json': LspLanguage(
        id: 'json',
        name: 'JSON',
        fileExtensions: ['.json'],
        serverCommand: 'vscode-json-languageserver',
        initializationOptions: {
          'provideFormatter': true,
        },
      ),
      'html': LspLanguage(
        id: 'html',
        name: 'HTML',
        fileExtensions: ['.html', '.htm'],
        serverCommand: 'vscode-html-languageserver',
        initializationOptions: {
          'provideFormatter': true,
        },
      ),
      'css': LspLanguage(
        id: 'css',
        name: 'CSS',
        fileExtensions: ['.css', '.scss', '.sass', '.less'],
        serverCommand: 'vscode-css-languageserver',
        initializationOptions: {
          'provideFormatter': true,
        },
      ),
      'go': LspLanguage(
        id: 'go',
        name: 'Go',
        fileExtensions: ['.go'],
        serverCommand: 'gopls',
        initializationOptions: {
          'usePlaceholders': true,
        },
      ),
      'rust': LspLanguage(
        id: 'rust',
        name: 'Rust',
        fileExtensions: ['.rs'],
        serverCommand: 'rust-analyzer',
        initializationOptions: {
          'checkOnSave': {
            'command': 'clippy',
          },
        },
      ),
    };
  }
  
  /// Connect to LSP server
  Future<void> _connectToServer() async {
    try {
      // For this implementation, we'll simulate a WebSocket connection
      // In a real app, you would connect to the actual LSP server
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:$_getLspPort()'),
      );
      
      _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) => debugPrint('LSP WebSocket error: $error'),
        onDone: () => _handleServerDisconnect(),
      );
      
      // Send initialize request
      await _sendInitializeRequest();
    } catch (e) {
      debugPrint('❌ Failed to connect to LSP server: $e');
      _isConnected = false;
    }
  }
  
  /// Get LSP port for language
  int _getLspPort() {
    // In a real implementation, you would determine this dynamically
    return 8080; // Default LSP port
  }
  
  /// Send initialize request
  Future<void> _sendInitializeRequest() async {
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'initialize',
      'params': {
        'processId': pid.toString(),
        'clientInfo': {
          'name': 'termisol',
          'version': '1.0.0',
        },
        'rootUri': 'file://$_workspaceRoot',
        'capabilities': _clientCapabilities.toJson(),
        'initializationOptions': _getInitializationOptions(),
      },
    };
    
    await _sendRequest(request);
  }
  
  /// Get initialization options for current language
  Map<String, dynamic> _getInitializationOptions() {
    final language = _detectLanguageFromPath(_workspaceRoot);
    return _languages[language]?.initializationOptions ?? {};
  }
  
  /// Detect language from file path
  String _detectLanguageFromPath(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    for (final entry in _languages.entries) {
      if (entry.value.fileExtensions.contains(extension)) {
        return entry.key;
      }
    }
    
    return 'text'; // Default to plain text
  }
  
  /// Handle server message
  void _handleServerMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      
      if (data['id'] != null) {
        _handleResponse(data);
      } else if (data['method'] != null) {
        _handleNotification(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to parse LSP message: $e');
    }
  }
  
  /// Handle server response
  void _handleResponse(Map<String, dynamic> data) {
    final id = data['id'] as int;
    final completer = _pendingRequests[id];
    
    if (completer != null) {
      completer.complete(data);
      _pendingRequests.remove(id);
    }
  }
  
  /// Handle server notification
  void _handleNotification(Map<String, dynamic> data) {
    final method = data['method'] as String;
    final params = data['params'] ?? {};
    
    switch (method) {
      case 'textDocument/publishDiagnostics':
        _handleDiagnostics(params);
        break;
      case 'window/logMessage':
        _handleLogMessage(params);
        break;
      case 'window/showMessage':
        _handleShowMessage(params);
        break;
      case 'workspace/configuration':
        _handleConfigurationChange(params);
        break;
    }
  }
  
  /// Handle diagnostics notification
  void _handleDiagnostics(Map<String, dynamic> params) {
    final uri = params['uri'] as String;
    final diagnostics = (params['diagnostics'] as List?)
        ?.map((d) => LspDiagnostic.fromJson(d))
        .toList() ?? [];
    
    _diagnostics[uri] = diagnostics;
    _onDiagnostics.forEach((callback) => callback(diagnostics));
  }
  
  /// Handle log message
  void _handleLogMessage(Map<String, dynamic> params) {
    final type = params['type'] as String;
    final message = params['message'] as String;
    
    debugPrint('📝 LSP Log [$type]: $message');
  }
  
  /// Handle show message
  void _handleShowMessage(Map<String, dynamic> params) {
    final type = params['type'] as String;
    final message = params['message'] as String;
    
    debugPrint('💬 LSP Message [$type]: $message');
  }
  
  /// Handle configuration change
  void _handleConfigurationChange(Map<String, dynamic> params) {
    debugPrint('⚙️ LSP Configuration changed: $params');
  }
  
  /// Handle server disconnect
  void _handleServerDisconnect() {
    _isConnected = false;
    debugPrint('🔌 LSP Server disconnected');
    
    // Attempt reconnection
    Timer(const Duration(seconds: 5), () {
      _connectToServer();
    });
  }
  
  /// Send request to server
  Future<Map<String, dynamic>> _sendRequest(Map<String, dynamic> request) async {
    if (_channel == null) {
      throw StateError('Not connected to LSP server');
    }
    
    final completer = Completer<Map<String, dynamic>>();
    final id = request['id'] as int;
    _pendingRequests[id] = completer;
    
    _channel!.sink.add(jsonEncode(request));
    
    return completer.future.timeout(const Duration(seconds: 30));
  }
  
  /// Open document
  Future<void> openDocument(String filePath, String content) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/didOpen',
      'params': {
        'textDocument': {
          'uri': uri,
          'languageId': _detectLanguageFromPath(filePath),
          'version': 1,
          'text': content,
        },
      },
    };
    
    await _sendRequest(request);
  }
  
  /// Update document
  Future<void> updateDocument(String filePath, String content, int version) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/didChange',
      'params': {
        'textDocument': {
          'uri': uri,
          'version': version,
        },
        'contentChanges': [
          {
            'text': content,
            'range': {
              'start': {'line': 0, 'character': 0},
              'end': {'line': 999999, 'character': 999999},
            },
          },
        ],
      },
    };
    
    await _sendRequest(request);
  }
  
  /// Close document
  Future<void> closeDocument(String filePath) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/didClose',
      'params': {
        'textDocument': {
          'uri': uri,
        },
      },
    };
    
    await _sendRequest(request);
  }
  
  /// Request completions
  Future<List<LspCompletion>> requestCompletions(
    String filePath,
    int line,
    int character,
  ) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/completion',
      'params': {
        'textDocument': {
          'uri': uri,
        },
        'position': {
          'line': line,
          'character': character,
        },
        'context': {
          'triggerKind': 1, // Invoked
        },
      },
    };
    
    try {
      final response = await _sendRequest(request);
      final result = response['result'];
      
      if (result is Map && result['items'] != null) {
        final items = (result['items'] as List)
            .map((item) => LspCompletion.fromJson(item))
            .toList();
        
        _completions[uri] = items;
        _onCompletions.forEach((callback) => callback(items));
        
        return items;
      }
      
      return [];
    } catch (e) {
      debugPrint('⚠️ Failed to get completions: $e');
      return [];
    }
  }
  
  /// Request hover information
  Future<LspHover?> requestHover(
    String filePath,
    int line,
    int character,
  ) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/hover',
      'params': {
        'textDocument': {
          'uri': uri,
        },
        'position': {
          'line': line,
          'character': character,
        },
      },
    };
    
    try {
      final response = await _sendRequest(request);
      final result = response['result'];
      
      if (result != null) {
        final hover = LspHover.fromJson(result);
        _hoverInfo[uri] = hover;
        _onHover.forEach((callback) => callback(hover));
        
        return hover;
      }
      
      return null;
    } catch (e) {
      debugPrint('⚠️ Failed to get hover info: $e');
      return null;
    }
  }
  
  /// Request definition
  Future<List<LspLocation>> requestDefinition(
    String filePath,
    int line,
    int character,
  ) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/definition',
      'params': {
        'textDocument': {
          'uri': uri,
        },
        'position': {
          'line': line,
          'character': character,
        },
      },
    };
    
    try {
      final response = await _sendRequest(request);
      final result = response['result'];
      
      if (result is List) {
        final locations = (result as List)
            .map((loc) => LspLocation.fromJson(loc))
            .toList();
        
        _onGotoDefinition.forEach((callback) {
          if (locations.isNotEmpty) callback(locations.first);
        });
        
        return locations;
      }
      
      return [];
    } catch (e) {
      debugPrint('⠠️ Failed to get definition: $e');
      return [];
    }
  }
  
  /// Request references
  Future<List<LspLocation>> requestReferences(
    String filePath,
    int line,
    int character,
  ) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/references',
      'params': {
        'textDocument': {
          'uri': uri,
        },
        'position': {
          'line': line,
          'character': character,
        },
        'context': {
          'includeDeclaration': true,
        },
      },
    };
    
    try {
      final response = await _sendRequest(request);
      final result = response['result'];
      
      if (result is List) {
        return (result as List)
            .map((loc) => LspLocation.fromJson(loc))
            .toList();
      }
      
      return [];
    } catch (e) {
      debugPrint('⠠️ Failed to get references: $e');
      return [];
    }
  }
  
  /// Request formatting
  Future<String?> requestFormatting(String filePath) async {
    final uri = 'file://$filePath';
    
    final request = {
      'jsonrpc': '2.0',
      'id': _messageId++,
      'method': 'textDocument/formatting',
      'params': {
        'textDocument': {
          'uri': uri,
        },
        'options': {
          'tabSize': 2,
          'insertSpaces': true,
        },
      },
    };
    
    try {
      final response = await _sendRequest(request);
      final result = response['result'];
      
      if (result is List && result.isNotEmpty) {
        return result.first['newText'] as String?;
      }
      
      return null;
    } catch (e) {
      debugPrint('⠠️ Failed to format document: $e');
      return null;
    }
  }
  
  /// Add diagnostics listener
  void addDiagnosticsListener(Function(List<LspDiagnostic>) listener) {
    _onDiagnostics.add(listener);
  }
  
  /// Add completions listener
  void addCompletionsListener(Function(List<LspCompletion>) listener) {
    _onCompletions.add(listener);
  }
  
  /// Add hover listener
  void addHoverListener(Function(LspHover) listener) {
    _onHover.add(listener);
  }
  
  /// Add goto definition listener
  void addGotoDefinitionListener(Function(LspLocation) listener) {
    _onGotoDefinition.add(listener);
  }
  
  /// Remove diagnostics listener
  void removeDiagnosticsListener(Function(List<LspDiagnostic>) listener) {
    _onDiagnostics.remove(listener);
  }
  
  /// Remove completions listener
  void removeCompletionsListener(Function(List<LspCompletion>) listener) {
    _onCompletions.remove(listener);
  }
  
  /// Remove hover listener
  void removeHoverListener(Function(LspHover) listener) {
    _onHover.remove(listener);
  }
  
  /// Remove goto definition listener
  void removeGotoDefinitionListener(Function(LspLocation) listener) {
    _onGotoDefinition.remove(listener);
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'connected': _isConnected,
      'serverPath': _serverPath,
      'workspaceRoot': _workspaceRoot,
      'supportedLanguages': _languages.keys.toList(),
      'pendingRequests': _pendingRequests.length,
      'diagnosticsCount': _diagnostics.values.fold(0, (sum, diags) => sum + diags.length),
      'completionsCount': _completions.length,
      'hoverInfoCount': _hoverInfo.length,
    };
  }
  
  /// Dispose LSP client
  Future<void> dispose() async {
    // Send shutdown request
    if (_isConnected && _channel != null) {
      try {
        final request = {
          'jsonrpc': '2.0',
          'id': _messageId++,
          'method': 'shutdown',
        };
        
        await _sendRequest(request);
        
        // Send exit notification
        final exitNotification = {
          'jsonrpc': '2.0',
          'method': 'exit',
        };
        
        _channel!.sink.add(jsonEncode(exitNotification));
      } catch (e) {
        debugPrint('⚠️ Error during LSP shutdown: $e');
      }
    }
    
    // Close connection
    await _channel?.sink.close();
    _channel = null;
    
    // Clear data
    _pendingRequests.clear();
    _diagnostics.clear();
    _completions.clear();
    _symbols.clear();
    _hoverInfo.clear();
    _onDiagnostics.clear();
    _onCompletions.clear();
    _onHover.clear();
    _onGotoDefinition.clear();
    
    _isInitialized = false;
    _isConnected = false;
    
    debugPrint('🧠 LSP Client disposed');
  }
}

/// LSP capabilities class
class LspCapabilities {
  TextDocumentSyncCapabilities? textDocumentSync;
  CompletionCapabilities? completionProvider;
  bool? hoverProvider;
  bool? definitionProvider;
  bool? referencesProvider;
  bool? documentFormattingProvider;
  bool? documentRangeFormattingProvider;
  CodeActionCapabilities? codeActionProvider;
  WorkspaceCapabilities? workspace;
  
  LspCapabilities({
    this.textDocumentSync,
    this.completionProvider,
    this.hoverProvider,
    this.definitionProvider,
    this.referencesProvider,
    this.documentFormattingProvider,
    this.documentRangeFormattingProvider,
    this.codeActionProvider,
    this.workspace,
  });
  
  factory LspCapabilities.fromJson(Map<String, dynamic> json) {
    return LspCapabilities(
      textDocumentSync: json['textDocumentSync'] != null
          ? TextDocumentSyncCapabilities.fromJson(json['textDocumentSync'])
          : null,
      completionProvider: json['completionProvider'] != null
          ? CompletionCapabilities.fromJson(json['completionProvider'])
          : null,
      hoverProvider: json['hoverProvider'],
      definitionProvider: json['definitionProvider'],
      referencesProvider: json['referencesProvider'],
      documentFormattingProvider: json['documentFormattingProvider'],
      documentRangeFormattingProvider: json['documentRangeFormattingProvider'],
      codeActionProvider: json['codeActionProvider'] != null
          ? CodeActionCapabilities.fromJson(json['codeActionProvider'])
          : null,
      workspace: json['workspace'] != null
          ? WorkspaceCapabilities.fromJson(json['workspace'])
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'textDocumentSync': textDocumentSync?.toJson(),
      'completionProvider': completionProvider?.toJson(),
      'hoverProvider': hoverProvider,
      'definitionProvider': definitionProvider,
      'referencesProvider': referencesProvider,
      'documentFormattingProvider': documentFormattingProvider,
      'documentRangeFormattingProvider': documentRangeFormattingProvider,
      'codeActionProvider': codeActionProvider?.toJson(),
      'workspace': workspace?.toJson(),
    };
  }
}

/// LSP language configuration
class LspLanguage {
  final String id;
  final String name;
  final List<String> fileExtensions;
  final String serverCommand;
  final Map<String, dynamic> initializationOptions;
  
  LspLanguage({
    required this.id,
    required this.name,
    required this.fileExtensions,
    required this.serverCommand,
    required this.initializationOptions,
  });
}

/// Text document sync capabilities
class TextDocumentSyncCapabilities {
  final bool dynamicRegistration;
  final bool willSave;
  final bool willSaveWaitUntil;
  
  TextDocumentSyncCapabilities({
    required this.dynamicRegistration,
    required this.willSave,
    required this.willSaveWaitUntil,
  });
  
  factory TextDocumentSyncCapabilities.fromJson(Map<String, dynamic> json) {
    return TextDocumentSyncCapabilities(
      dynamicRegistration: json['dynamicRegistration'] ?? false,
      willSave: json['willSave'] ?? false,
      willSaveWaitUntil: json['willSaveWaitUntil'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'dynamicRegistration': dynamicRegistration,
      'willSave': willSave,
      'willSaveWaitUntil': willSaveWaitUntil,
    };
  }
}

/// Completion capabilities
class CompletionCapabilities {
  final bool resolveProvider;
  final List<String> triggerCharacters;
  
  CompletionCapabilities({
    required this.resolveProvider,
    required this.triggerCharacters,
  });
  
  factory CompletionCapabilities.fromJson(Map<String, dynamic> json) {
    return CompletionCapabilities(
      resolveProvider: json['resolveProvider'] ?? false,
      triggerCharacters: List<String>.from(json['triggerCharacters'] ?? []),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'resolveProvider': resolveProvider,
      'triggerCharacters': triggerCharacters,
    };
  }
}

/// Code action capabilities
class CodeActionCapabilities {
  final bool codeActionLiteralSupport;
  final bool isPreferredSupport;
  
  CodeActionCapabilities({
    required this.codeActionLiteralSupport,
    required this.isPreferredSupport,
  });
  
  factory CodeActionCapabilities.fromJson(Map<String, dynamic> json) {
    return CodeActionCapabilities(
      codeActionLiteralSupport: json['codeActionLiteralSupport'] ?? false,
      isPreferredSupport: json['isPreferredSupport'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'codeActionLiteralSupport': codeActionLiteralSupport,
      'isPreferredSupport': isPreferredSupport,
    };
  }
}

/// Workspace capabilities
class WorkspaceCapabilities {
  final bool workspaceFolders;
  final bool configuration;
  
  WorkspaceCapabilities({
    required this.workspaceFolders,
    required this.configuration,
  });
  
  factory WorkspaceCapabilities.fromJson(Map<String, dynamic> json) {
    return WorkspaceCapabilities(
      workspaceFolders: json['workspaceFolders'] ?? false,
      configuration: json['configuration'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'workspaceFolders': workspaceFolders,
      'configuration': configuration,
    };
  }
}

/// LSP diagnostic
class LspDiagnostic {
  final LspRange range;
  final LspDiagnosticSeverity severity;
  final String? code;
  final String? source;
  final String message;
  final List<LspDiagnosticTag>? tags;
  final List<LspDiagnosticRelatedInformation>? relatedInformation;
  
  LspDiagnostic({
    required this.range,
    required this.severity,
    this.code,
    this.source,
    required this.message,
    this.tags,
    this.relatedInformation,
  });
  
  factory LspDiagnostic.fromJson(Map<String, dynamic> json) {
    return LspDiagnostic(
      range: LspRange.fromJson(json['range']),
      severity: LspDiagnosticSeverity.values[json['severity'] ?? 1],
      code: json['code'],
      source: json['source'],
      message: json['message'],
      tags: json['tags'] != null
          ? (json['tags'] as List)
              .map((t) => LspDiagnosticTag.values[t])
              .where((t) => t != null)
              .cast<LspDiagnosticTag>()
              .toList()
          : null,
      relatedInformation: json['relatedInformation'] != null
          ? (json['relatedInformation'] as List)
              .map((info) => LspDiagnosticRelatedInformation.fromJson(info))
              .toList()
          : null,
    );
  }
}

/// LSP range
class LspRange {
  final LspPosition start;
  final LspPosition end;
  
  LspRange({
    required this.start,
    required this.end,
  });
  
  factory LspRange.fromJson(Map<String, dynamic> json) {
    return LspRange(
      start: LspPosition.fromJson(json['start']),
      end: LspPosition.fromJson(json['end']),
    );
  }
}

/// LSP position
class LspPosition {
  final int line;
  final int character;
  
  LspPosition({
    required this.line,
    required this.character,
  });
  
  factory LspPosition.fromJson(Map<String, dynamic> json) {
    return LspPosition(
      line: json['line'] ?? 0,
      character: json['character'] ?? 0,
    );
  }
}

/// LSP diagnostic severity
enum LspDiagnosticSeverity {
  error,
  warning,
  information,
  hint,
}

/// LSP diagnostic tag
enum LspDiagnosticTag {
  unnecessary,
  deprecated,
}

/// LSP diagnostic related information
class LspDiagnosticRelatedInformation {
  final LspRange location;
  final String message;
  
  LspDiagnosticRelatedInformation({
    required this.location,
    required this.message,
  });
  
  factory LspDiagnosticRelatedInformation.fromJson(Map<String, dynamic> json) {
    return LspDiagnosticRelatedInformation(
      location: LspRange.fromJson(json['location']),
      message: json['message'],
    );
  }
}

/// LSP completion
class LspCompletion {
  final String label;
  final LspCompletionItemKind kind;
  final String? detail;
  final LspCompletionDocumentation? documentation;
  final bool? deprecated;
  final bool? preselect;
  final String? sortText;
  final String? filterText;
  final LspTextEdit? textEdit;
  final String? insertText;
  
  LspCompletion({
    required this.label,
    required this.kind,
    this.detail,
    this.documentation,
    this.deprecated,
    this.preselect,
    this.sortText,
    this.filterText,
    this.textEdit,
    this.insertText,
  });
  
  factory LspCompletion.fromJson(Map<String, dynamic> json) {
    return LspCompletion(
      label: json['label'] ?? '',
      kind: LspCompletionItemKind.values[json['kind'] ?? 1],
      detail: json['detail'],
      documentation: json['documentation'] != null
          ? LspCompletionDocumentation.fromJson(json['documentation'])
          : null,
      deprecated: json['deprecated'],
      preselect: json['preselect'],
      sortText: json['sortText'],
      filterText: json['filterText'],
      textEdit: json['textEdit'] != null
          ? LspTextEdit.fromJson(json['textEdit'])
          : null,
      insertText: json['insertText'],
    );
  }
}

/// LSP completion item kind
enum LspCompletionItemKind {
  text,
  method,
  function,
  constructor,
  field,
  variable,
  class_,
  interface,
  module,
  property,
  unit,
  value,
  enum,
  keyword,
  snippet,
  color,
  file,
  reference,
  folder,
  enumMember,
  constant,
  struct,
  event,
  operator,
  typeParameter,
}

/// LSP completion documentation
class LspCompletionDocumentation {
  final String? value;
  final String? kind;
  
  LspCompletionDocumentation({
    this.value,
    this.kind,
  });
  
  factory LspCompletionDocumentation.fromJson(Map<String, dynamic> json) {
    return LspCompletionDocumentation(
      value: json['value'],
      kind: json['kind'],
    );
  }
}

/// LSP text edit
class LspTextEdit {
  final LspRange range;
  final String newText;
  
  LspTextEdit({
    required this.range,
    required this.newText,
  });
  
  factory LspTextEdit.fromJson(Map<String, dynamic> json) {
    return LspTextEdit(
      range: LspRange.fromJson(json['range']),
      newText: json['newText'],
    );
  }
}

/// LSP hover
class LspHover {
  final List<LspMarkedString> contents;
  final LspRange? range;
  
  LspHover({
    required this.contents,
    this.range,
  });
  
  factory LspHover.fromJson(Map<String, dynamic> json) {
    return LspHover(
      contents: (json['contents'] is List)
          ? (json['contents'] as List)
              .map((c) => LspMarkedString.fromJson(c))
              .toList()
          : [LspMarkedString.fromJson(json['contents'])],
      range: json['range'] != null ? LspRange.fromJson(json['range']) : null,
    );
  }
}

/// LSP marked string
class LspMarkedString {
  final String? value;
  final String? language;
  
  LspMarkedString({
    this.value,
    this.language,
  });
  
  factory LspMarkedString.fromJson(Map<String, dynamic> json) {
    return LspMarkedString(
      value: json['value'],
      language: json['language'],
    );
  }
}

/// LSP location
class LspLocation {
  final LspRange range;
  final String uri;
  
  LspLocation({
    required this.range,
    required this.uri,
  });
  
  factory LspLocation.fromJson(Map<String, dynamic> json) {
    return LspLocation(
      range: LspRange.fromJson(json['range']),
      uri: json['uri'],
    );
  }
}
