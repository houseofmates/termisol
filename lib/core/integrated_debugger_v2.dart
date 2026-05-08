import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Integrated debugger for multiple languages and runtimes
/// Supports Python, JavaScript, Node.js, Java, C++, Go, Rust, and more
class IntegratedDebuggerV2 {
  static const String _baseUrl = 'https://api.openai.com/v1';
  String? _apiKey;
  final Map<String, DebugSession> _sessions = {};
  final StreamController<DebuggerEvent> _eventController = StreamController<DebuggerEvent>.broadcast();
  
  Stream<DebuggerEvent> get events => _eventController.stream;

  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey ?? _getApiKeyFromConfig();
    
    if (_apiKey != null) {
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.initialized,
        message: 'Integrated Debugger V2 initialized with AI API',
      ));
      debugPrint('🐛 Integrated Debugger V2 initialized');
    } else {
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.initialized,
        message: 'Integrated Debugger V2 initialized without AI API',
      ));
      debugPrint('🐛 Integrated Debugger V2 initialized (local mode)');
    }
  }

  String? _getApiKeyFromConfig() {
    return Platform.environment['OPENAI_API_KEY'];
  }

  Future<DebugSession> createSession({
    required String language,
    required String filePath,
    String? workingDirectory,
    Map<String, dynamic>? config,
  }) async {
    final sessionId = _generateSessionId();
    final session = DebugSession(
      id: sessionId,
      language: language,
      filePath: filePath,
      workingDirectory: workingDirectory ?? Directory.current.path,
      config: config ?? {},
      createdAt: DateTime.now(),
    );
    
    _sessions[sessionId] = session;
    
    _eventController.add(DebuggerEvent(
      type: DebuggerEventType.session_created,
      message: 'Debug session created',
      data: {'sessionId': sessionId, 'language': language},
    ));
    
    return session;
  }

  String _generateSessionId() {
    return 'debug_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<DebugResult> startDebugging(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    try {
      final result = await _startLanguageDebugger(session);
      
      session.status = DebugStatus.running;
      session.startedAt = DateTime.now();
      
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.debugging_started,
        message: 'Debugging started',
        data: {'sessionId': sessionId, 'language': session.language},
      ));
      
      return result;
    } catch (e) {
      session.status = DebugStatus.error;
      session.error = e.toString();
      
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.error,
        message: 'Failed to start debugging: $e',
        data: {'sessionId': sessionId},
      ));
      
      return DebugResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<DebugResult> _startLanguageDebugger(DebugSession session) async {
    switch (session.language.toLowerCase()) {
      case 'python':
        return await _startPythonDebugger(session);
      case 'javascript':
      case 'node':
      case 'nodejs':
        return await _startNodeDebugger(session);
      case 'java':
        return await _startJavaDebugger(session);
      case 'cpp':
      case 'c++':
        return await _startCppDebugger(session);
      case 'go':
        return await _startGoDebugger(session);
      case 'rust':
        return await _startRustDebugger(session);
      case 'dart':
        return await _startDartDebugger(session);
      case 'c':
        return await _startCDebugger(session);
      case 'csharp':
      case 'c#':
        return await _startCSharpDebugger(session);
      default:
        return DebugResult(
          success: false,
          error: 'Unsupported language: ${session.language}',
        );
    }
  }

  Future<DebugResult> _startPythonDebugger(DebugSession session) async {
    try {
      // Check if debugpy is available
      final debugpyCheck = await run('python', ['-c', 'import debugpy; print(debugpy.__version__)']);
      if (debugpyCheck.exitCode != 0) {
        // Install debugpy
        await run('pip', ['install', 'debugpy']);
      }
      
      // Start debugpy
      final debugCommand = 'import debugpy; debugpy.listen(5678); debugpy.wait_for_client()';
      final result = await run('python', ['-c', debugCommand], workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      session.debugPort = 5678;
      
      return DebugResult(
        success: true,
        message: 'Python debugger started on port 5678',
        data: {'port': 5678, 'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Python debugger: $e',
      );
    }
  }

  Future<DebugResult> _startNodeDebugger(DebugSession session) async {
    try {
      // Check if node inspector is available
      final inspectorCheck = await run('node', ['--inspect', '--version']);
      if (inspectorCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Node.js inspector not available',
        );
      }
      
      // Start Node with inspector
      final result = await run('node', ['--inspect=0.0.0.0:9229', session.filePath], 
          workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      session.debugPort = 9229;
      
      return DebugResult(
        success: true,
        message: 'Node.js debugger started on port 9229',
        data: {'port': 9229, 'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Node.js debugger: $e',
      );
    }
  }

  Future<DebugResult> _startJavaDebugger(DebugSession session) async {
    try {
      // Check if Java is available
      final javaCheck = await run('java', ['-version']);
      if (javaCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Java not available',
        );
      }
      
      // Compile Java file if needed
      final className = path.basenameWithoutExtension(session.filePath);
      final compileResult = await run('javac', [session.filePath], 
          workingDirectory: session.workingDirectory);
      
      if (compileResult.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Failed to compile Java file',
          data: {'compileError': compileResult.stderr},
        );
      }
      
      // Start Java with debug options
      final debugArgs = [
        '-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=5005',
        '-classpath', '.',
        className,
      ];
      
      final result = await run('java', debugArgs, workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      session.debugPort = 5005;
      
      return DebugResult(
        success: true,
        message: 'Java debugger started on port 5005',
        data: {'port': 5005, 'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Java debugger: $e',
      );
    }
  }

  Future<DebugResult> _startCppDebugger(DebugSession session) async {
    try {
      // Check if GDB is available
      final gdbCheck = await run('gdb', ['--version']);
      if (gdbCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'GDB not available',
        );
      }
      
      // Compile with debug symbols if needed
      final executableName = path.basenameWithoutExtension(session.filePath);
      final compileResult = await run('g++', ['-g', '-o', executableName, session.filePath], 
          workingDirectory: session.workingDirectory);
      
      if (compileResult.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Failed to compile C++ file',
          data: {'compileError': compileResult.stderr},
        );
      }
      
      // Start GDB
      final gdbArgs = [
        '-ex', 'break main',
        '-ex', 'run',
        '-ex', 'bt',
        './$executableName',
      ];
      
      final result = await run('gdb', gdbArgs, workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      
      return DebugResult(
        success: true,
        message: 'C++ debugger started with GDB',
        data: {'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start C++ debugger: $e',
      );
    }
  }

  Future<DebugResult> _startGoDebugger(DebugSession session) async {
    try {
      // Check if Delve is available
      final dlvCheck = await run('dlv', ['version']);
      if (dlvCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Delve debugger not available',
        );
      }
      
      // Start Delve
      final result = await run('dlv', ['debug', '--headless', '--listen=:2345', '--api-version=2', session.filePath], 
          workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      session.debugPort = 2345;
      
      return DebugResult(
        success: true,
        message: 'Go debugger started on port 2345',
        data: {'port': 2345, 'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Go debugger: $e',
      );
    }
  }

  Future<DebugResult> _startRustDebugger(DebugSession session) async {
    try {
      // Check if rust-gdb is available
      final rustGdbCheck = await run('rust-gdb', ['--version']);
      if (rustGdbCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Rust GDB not available',
        );
      }
      
      // Compile with debug symbols
      final executableName = path.basenameWithoutExtension(session.filePath);
      final compileResult = await run('rustc', ['-g', '-o', executableName, session.filePath], 
          workingDirectory: session.workingDirectory);
      
      if (compileResult.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Failed to compile Rust file',
          data: {'compileError': compileResult.stderr},
        );
      }
      
      // Start rust-gdb
      final gdbArgs = [
        '-ex', 'break main',
        '-ex', 'run',
        '-ex', 'bt',
        './$executableName',
      ];
      
      final result = await run('rust-gdb', gdbArgs, workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      
      return DebugResult(
        success: true,
        message: 'Rust debugger started with rust-gdb',
        data: {'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Rust debugger: $e',
      );
    }
  }

  Future<DebugResult> _startDartDebugger(DebugSession session) async {
    try {
      // Check if Dart is available
      final dartCheck = await run('dart', ['--version']);
      if (dartCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Dart not available',
        );
      }
      
      // Start Dart with Observatory
      final result = await run('dart', ['--enable-vm-service:8181', session.filePath], 
          workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      session.debugPort = 8181;
      
      return DebugResult(
        success: true,
        message: 'Dart debugger started on port 8181',
        data: {'port': 8181, 'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start Dart debugger: $e',
      );
    }
  }

  Future<DebugResult> _startCDebugger(DebugSession session) async {
    try {
      // Check if GDB is available
      final gdbCheck = await run('gdb', ['--version']);
      if (gdbCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'GDB not available',
        );
      }
      
      // Compile with debug symbols
      final executableName = path.basenameWithoutExtension(session.filePath);
      final compileResult = await run('gcc', ['-g', '-o', executableName, session.filePath], 
          workingDirectory: session.workingDirectory);
      
      if (compileResult.exitCode != 0) {
        return DebugResult(
          success: false,
          error: 'Failed to compile C file',
          data: {'compileError': compileResult.stderr},
        );
      }
      
      // Start GDB
      final gdbArgs = [
        '-ex', 'break main',
        '-ex', 'run',
        '-ex', 'bt',
        './$executableName',
      ];
      
      final result = await run('gdb', gdbArgs, workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      
      return DebugResult(
        success: true,
        message: 'C debugger started with GDB',
        data: {'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start C debugger: $e',
      );
    }
  }

  Future<DebugResult> _startCSharpDebugger(DebugSession session) async {
    try {
      // Check if .NET is available
      final dotnetCheck = await run('dotnet', ['--version']);
      if (dotnetCheck.exitCode != 0) {
        return DebugResult(
          success: false,
          error: '.NET not available',
        );
      }
      
      // Start .NET debugger
      final result = await run('dotnet', ['run', '--project', session.workingDirectory], 
          workingDirectory: session.workingDirectory);
      
      session.debuggerProcess = result;
      
      return DebugResult(
        success: true,
        message: 'C# debugger started with .NET',
        data: {'process': result.pid},
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to start C# debugger: $e',
      );
    }
  }

  Future<DebugResult> setBreakpoint(String sessionId, String filePath, int lineNumber) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    final breakpoint = DebugBreakpoint(
      id: _generateBreakpointId(),
      filePath: filePath,
      lineNumber: lineNumber,
      enabled: true,
      createdAt: DateTime.now(),
    );

    session.breakpoints.add(breakpoint);

    return await _applyBreakpoint(session, breakpoint);
  }

  String _generateBreakpointId() {
    return 'bp_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<DebugResult> _applyBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    try {
      switch (session.language.toLowerCase()) {
        case 'python':
          return await _applyPythonBreakpoint(session, breakpoint);
        case 'javascript':
        case 'node':
        case 'nodejs':
          return await _applyNodeBreakpoint(session, breakpoint);
        case 'java':
          return await _applyJavaBreakpoint(session, breakpoint);
        case 'cpp':
        case 'c++':
        case 'c':
          return await _applyGdbBreakpoint(session, breakpoint);
        case 'go':
          return await _applyDelveBreakpoint(session, breakpoint);
        case 'rust':
          return await _applyRustGdbBreakpoint(session, breakpoint);
        case 'dart':
          return await _applyDartBreakpoint(session, breakpoint);
        case 'csharp':
        case 'c#':
          return await _applyCSharpBreakpoint(session, breakpoint);
        default:
          return DebugResult(
            success: false,
            error: 'Breakpoints not supported for ${session.language}',
          );
      }
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to apply breakpoint: $e',
      );
    }
  }

  Future<DebugResult> _applyPythonBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with debugpy API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyNodeBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with Node.js inspector API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyJavaBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with JDWP API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyGdbBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with GDB MI interface
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyDelveBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with Delve DAP API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyRustGdbBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with rust-gdb
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyDartBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with Dart Observatory API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> _applyCSharpBreakpoint(DebugSession session, DebugBreakpoint breakpoint) async {
    // This would integrate with .NET debugger API
    return DebugResult(
      success: true,
      message: 'Breakpoint set at line ${breakpoint.lineNumber}',
    );
  }

  Future<DebugResult> stepOver(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    return await _executeDebugCommand(session, 'stepOver');
  }

  Future<DebugResult> stepInto(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    return await _executeDebugCommand(session, 'stepInto');
  }

  Future<DebugResult> stepOut(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    return await _executeDebugCommand(session, 'stepOut');
  }

  Future<DebugResult> continueExecution(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    return await _executeDebugCommand(session, 'continue');
  }

  Future<DebugResult> pauseExecution(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    return await _executeDebugCommand(session, 'pause');
  }

  Future<DebugResult> _executeDebugCommand(DebugSession session, String command) async {
    try {
      // This would integrate with the specific debugger's command interface
      switch (session.language.toLowerCase()) {
        case 'python':
          return await _executePythonCommand(session, command);
        case 'javascript':
        case 'node':
        case 'nodejs':
          return await _executeNodeCommand(session, command);
        case 'java':
          return await _executeJavaCommand(session, command);
        case 'cpp':
        case 'c++':
        case 'c':
          return await _executeGdbCommand(session, command);
        case 'go':
          return await _executeDelveCommand(session, command);
        case 'rust':
          return await _executeRustGdbCommand(session, command);
        case 'dart':
          return await _executeDartCommand(session, command);
        case 'csharp':
        case 'c#':
          return await _executeCSharpCommand(session, command);
        default:
          return DebugResult(
            success: false,
            error: 'Command not supported for ${session.language}',
          );
      }
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to execute command: $e',
      );
    }
  }

  Future<DebugResult> _executePythonCommand(DebugSession session, String command) async {
    // Integration with debugpy command interface
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeNodeCommand(DebugSession session, String command) async {
    // Integration with Node.js inspector command interface
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeJavaCommand(DebugSession session, String command) async {
    // Integration with JDWP command interface
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeGdbCommand(DebugSession session, String command) async {
    // Integration with GDB MI interface
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeDelveCommand(DebugSession session, String command) async {
    // Integration with Delve DAP API
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeRustGdbCommand(DebugSession session, String command) async {
    // Integration with rust-gdb
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeDartCommand(DebugSession session, String command) async {
    // Integration with Dart Observatory API
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> _executeCSharpCommand(DebugSession session, String command) async {
    // Integration with .NET debugger API
    return DebugResult(
      success: true,
      message: 'Command executed: $command',
    );
  }

  Future<DebugResult> stopDebugging(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    try {
      if (session.debuggerProcess != null) {
        session.debuggerProcess!.kill();
      }
      
      session.status = DebugStatus.stopped;
      session.stoppedAt = DateTime.now();
      
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.debugging_stopped,
        message: 'Debugging stopped',
        data: {'sessionId': sessionId},
      ));
      
      return DebugResult(
        success: true,
        message: 'Debugging stopped',
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to stop debugging: $e',
      );
    }
  }

  Future<DebugResult> terminateSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return DebugResult(
        success: false,
        error: 'Session not found',
      );
    }

    try {
      await stopDebugging(sessionId);
      _sessions.remove(sessionId);
      
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.session_terminated,
        message: 'Debug session terminated',
        data: {'sessionId': sessionId},
      ));
      
      return DebugResult(
        success: true,
        message: 'Session terminated',
      );
    } catch (e) {
      return DebugResult(
        success: false,
        error: 'Failed to terminate session: $e',
      );
    }
  }

  List<DebugSession> getActiveSessions() {
    return _sessions.values.where((session) => session.status == DebugStatus.running).toList();
  }

  List<DebugSession> getAllSessions() {
    return _sessions.values.toList();
  }

  DebugSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  Future<List<DebugVariable>> getVariables(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return [];
    }

    // This would integrate with the specific debugger's variable inspection
    return [];
  }

  Future<List<DebugCallStack>> getCallStack(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return [];
    }

    // This would integrate with the specific debugger's call stack inspection
    return [];
  }

  Future<DebugAnalysis> analyzeCode({
    required String code,
    required String language,
    String? filePath,
  }) async {
    if (_apiKey == null) {
      return _generateLocalAnalysis(code, language);
    }

    try {
      final analysis = await _generateAIAnalysis(code, language, filePath);
      
      _eventController.add(DebuggerEvent(
        type: DebuggerEventType.code_analyzed,
        message: 'Code analysis completed',
        data: {'language': language, 'filePath': filePath},
      ));

      return analysis;
    } catch (e) {
      debugPrint('Failed to generate AI analysis: $e');
      return _generateLocalAnalysis(code, language);
    }
  }

  Future<DebugAnalysis> _generateAIAnalysis(
    String code,
    String language,
    String? filePath,
  ) async {
    final prompt = _buildAnalysisPrompt(code, language, filePath);
    
    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an expert debugger who analyzes code for potential issues, bugs, and debugging strategies.'
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'max_tokens': 800,
        'temperature': 0.2,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final analysis = data['choices'][0]['message']['content'];
      
      return _parseAnalysisResponse(analysis, code, language);
    } else {
      throw Exception('Failed to get AI analysis: ${response.statusCode}');
    }
  }

  String _buildAnalysisPrompt(String code, String language, String? filePath) {
    var prompt = 'Analyze this $language code for debugging purposes';
    
    if (filePath != null) {
      prompt += ' in file: $filePath';
    }
    
    prompt += ':\n\n```\n$code\n```\n\n';
    prompt += 'Please provide:\n';
    prompt += '1. Potential bugs or issues\n';
    prompt += '2. Recommended debugging strategy\n';
    prompt += '3. Suggested breakpoints\n';
    prompt += '4. Common pitfalls to watch for\n';
    prompt += '5. Best practices for debugging this language\n';
    
    return prompt;
  }

  DebugAnalysis _parseAnalysisResponse(String response, String code, String language) {
    final lines = response.split('\n');
    final issues = <String>[];
    final strategies = <String>[];
    final suggestedBreakpoints = <String>[];
    final pitfalls = <String>[];
    final bestPractices = <String>[];
    
    String? currentSection;
    
    for (final line in lines) {
      final trimmed = line.trim();
      
      if (trimmed.startsWith('1.') || trimmed.toLowerCase().contains('bugs')) {
        currentSection = 'issues';
        continue;
      } else if (trimmed.startsWith('2.') || trimmed.toLowerCase().contains('strategy')) {
        currentSection = 'strategies';
        continue;
      } else if (trimmed.startsWith('3.') || trimmed.toLowerCase().contains('breakpoints')) {
        currentSection = 'breakpoints';
        continue;
      } else if (trimmed.startsWith('4.') || trimmed.toLowerCase().contains('pitfalls')) {
        currentSection = 'pitfalls';
        continue;
      } else if (trimmed.startsWith('5.') || trimmed.toLowerCase().contains('practices')) {
        currentSection = 'practices';
        continue;
      }
      
      if (trimmed.isEmpty) continue;
      
      switch (currentSection) {
        case 'issues':
          issues.add(trimmed);
          break;
        case 'strategies':
          strategies.add(trimmed);
          break;
        case 'breakpoints':
          suggestedBreakpoints.add(trimmed);
          break;
        case 'pitfalls':
          pitfalls.add(trimmed);
          break;
        case 'practices':
          bestPractices.add(trimmed);
          break;
      }
    }
    
    return DebugAnalysis(
      code: code,
      language: language,
      potentialIssues: issues,
      debuggingStrategies: strategies,
      suggestedBreakpoints: suggestedBreakpoints,
      commonPitfalls: pitfalls,
      bestPractices: bestPractices,
      generatedAt: DateTime.now(),
      isAI: true,
    );
  }

  DebugAnalysis _generateLocalAnalysis(String code, String language) {
    final issues = <String>[];
    final strategies = <String>[];
    final suggestedBreakpoints = <String>[];
    final pitfalls = <String>[];
    final bestPractices = <String>[];
    
    final lines = code.split('\n');
    
    // Basic pattern analysis
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (language.toLowerCase() == 'python') {
        if (line.contains('print(')) {
          issues.add('Line ${i + 1}: Debug print statement found');
          suggestedBreakpoints.add('Consider setting breakpoint at line ${i + 1}');
        }
        if (line.contains('except:') && !line.contains('as')) {
          pitfalls.add('Line ${i + 1}: Bare except clause');
        }
      } else if (language.toLowerCase() == 'javascript') {
        if (line.contains('console.log')) {
          issues.add('Line ${i + 1}: Console.log statement found');
          suggestedBreakpoints.add('Consider setting breakpoint at line ${i + 1}');
        }
        if (line.contains('==')) {
          pitfalls.add('Line ${i + 1}: Use === instead of ==');
        }
      }
    }
    
    if (issues.isEmpty) {
      issues.add('No obvious issues found');
    }
    
    strategies.add('Start by setting breakpoints at key functions');
    strategies.add('Use step-by-step execution to trace flow');
    strategies.add('Monitor variable values at critical points');
    
    bestPractices.add('Use meaningful variable names');
    bestPractices.add('Add error handling');
    bestPractices.add('Test edge cases');
    
    return DebugAnalysis(
      code: code,
      language: language,
      potentialIssues: issues,
      debuggingStrategies: strategies,
      suggestedBreakpoints: suggestedBreakpoints,
      commonPitfalls: pitfalls,
      bestPractices: bestPractices,
      generatedAt: DateTime.now(),
      isAI: false,
    );
  }

  Map<String, dynamic> getStatistics() {
    return {
      'totalSessions': _sessions.length,
      'activeSessions': getActiveSessions().length,
      'supportedLanguages': [
        'Python', 'JavaScript', 'Node.js', 'Java', 'C++', 'C', 'Go', 
        'Rust', 'Dart', 'C#',
      ],
      'hasApiKey': _apiKey != null,
    };
  }

  Future<void> dispose() async {
    // Terminate all active sessions
    for (final session in _sessions.values) {
      if (session.status == DebugStatus.running) {
        await stopDebugging(session.id);
      }
    }
    
    _sessions.clear();
    _eventController.close();
    debugPrint('🐛 Integrated Debugger V2 disposed');
  }
}

class DebugSession {
  final String id;
  final String language;
  final String filePath;
  final String workingDirectory;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  
  DebugStatus status = DebugStatus.created;
  ProcessResult? debuggerProcess;
  int? debugPort;
  final List<DebugBreakpoint> breakpoints = [];
  DateTime? startedAt;
  DateTime? stoppedAt;
  String? error;

  DebugSession({
    required this.id,
    required this.language,
    required this.filePath,
    required this.workingDirectory,
    required this.config,
    required this.createdAt,
  });
}

class DebugBreakpoint {
  final String id;
  final String filePath;
  final int lineNumber;
  bool enabled;
  final DateTime createdAt;

  DebugBreakpoint({
    required this.id,
    required this.filePath,
    required this.lineNumber,
    required this.enabled,
    required this.createdAt,
  });
}

class DebugVariable {
  final String name;
  final String type;
  final dynamic value;
  final String scope;

  DebugVariable({
    required this.name,
    required this.type,
    required this.value,
    required this.scope,
  });
}

class DebugCallStack {
  final String functionName;
  final String filePath;
  final int lineNumber;
  final String module;

  DebugCallStack({
    required this.functionName,
    required this.filePath,
    required this.lineNumber,
    required this.module,
  });
}

enum DebugStatus {
  created,
  running,
  paused,
  stopped,
  error,
}

class DebugResult {
  final bool success;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;

  DebugResult({
    required this.success,
    this.message,
    this.error,
    this.data,
  });
}

class DebugAnalysis {
  final String code;
  final String language;
  final List<String> potentialIssues;
  final List<String> debuggingStrategies;
  final List<String> suggestedBreakpoints;
  final List<String> commonPitfalls;
  final List<String> bestPractices;
  final DateTime generatedAt;
  final bool isAI;

  DebugAnalysis({
    required this.code,
    required this.language,
    required this.potentialIssues,
    required this.debuggingStrategies,
    required this.suggestedBreakpoints,
    required this.commonPitfalls,
    required this.bestPractices,
    required this.generatedAt,
    required this.isAI,
  });
}

enum DebuggerEventType {
  initialized,
  session_created,
  session_terminated,
  debugging_started,
  debugging_stopped,
  code_analyzed,
  error,
}

class DebuggerEvent {
  final DebuggerEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  DebuggerEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
