import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class AdvancedShellIntegration {
  static const String _shellConfigFile = '/home/house/.termisol_shell_config.json';
  static const String _completionFile = '/home/house/.termisol_completions.json';
  static const String _historyFile = '/home/house/.termisol_shell_history.json';
  static const int _maxCompletions = 10000;
  static const int _maxHistory = 50000;
  static const int _maxHooks = 100;
  
  final Map<String, ShellConfig> _shellConfigs = {};
  final Map<String, List<CompletionItem>> _completions = {};
  final Map<String, List<HistoryEntry>> _history = {};
  final Map<String, List<ShellHook>> _hooks = {};
  final Map<String, ShellSession> _sessions = {};
  
  Timer? _cleanupTimer;
  String? _activeShell;
  int _totalCompletions = 0;
  int _totalHistory = 0;
  int _totalHooks = 0;
  int _totalSessions = 0;
  
  final StreamController<ShellEvent> _shellController = 
      StreamController<ShellEvent>.broadcast();

  void initialize() {
    _detectAvailableShells();
    _loadConfiguration();
    _loadCompletions();
    _loadHistory();
    _loadHooks();
    _startTimers();
    developer.log('🐚 Advanced Shell Integration initialized');
  }

  void _detectAvailableShells() {
    final availableShells = <String>[];
    
    // Check for common shells
    final shellsToCheck = [
      'zsh',
      'fish',
      'bash',
      'powershell',
      'cmd',
      'nu',
    ];
    
    for (final shell in shellsToCheck) {
      try {
        final result = await Process.run('which', [shell]);
        if (result.exitCode == 0) {
          availableShells.add(shell);
          developer.log('🐚 Found shell: $shell');
        }
      } catch (e) {
        developer.log('🐚 Failed to check for $shell: $e');
      }
    }
    
    // Initialize configs for available shells
    for (final shell in availableShells) {
      if (!_shellConfigs.containsKey(shell)) {
        _shellConfigs[shell] = _createDefaultShellConfig(shell);
      }
    }
    
    // Set default active shell
    if (_activeShell == null && availableShells.isNotEmpty) {
      _activeShell = availableShells.first;
      
      // Prefer zsh or fish if available
      if (availableShells.contains('zsh')) {
        _activeShell = 'zsh';
      } else if (availableShells.contains('fish')) {
        _activeShell = 'fish';
      }
      
      developer.log('🐚 Set active shell: $_activeShell');
    }
  }

  void _loadConfiguration() {
    try {
      final file = File(_shellConfigFile);
      if (!file.existsSync()) {
        developer.log('🐚 No existing shell configuration found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['configs']) {
        final config = ShellConfig.fromJson(entry);
        _shellConfigs[config.shellName] = config;
      }
      
      _activeShell = data['active_shell'];
      
      developer.log('🐚 Loaded shell configuration: ${_shellConfigs.length} shells');
      
    } catch (e) {
      developer.log('🐚 Failed to load shell configuration: $e');
    }
  }

  void _loadCompletions() {
    try {
      final file = File(_completionFile);
      if (!file.existsSync()) {
        developer.log('🐚 No existing completions found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['completions']) {
        final completions = (entry['items'] as List)
            .map((item) => CompletionItem.fromJson(item))
            .toList();
        
        _completions[entry['shell_name']] = completions;
        _totalCompletions += completions.length;
      }
      
      developer.log('🐚 Loaded ${_completions.values.fold(0, (sum, list) => sum + list.length)} completions');
      
    } catch (e) {
      developer.log('🐚 Failed to load completions: $e');
    }
  }

  void _loadHistory() {
    try {
      final file = File(_historyFile);
      if (!file.existsSync()) {
        developer.log('🐚 No existing shell history found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['history']) {
        final history = (entry['items'] as List)
            .map((item) => HistoryEntry.fromJson(item))
            .toList();
        
        _history[entry['shell_name']] = history;
        _totalHistory += history.length;
      }
      
      developer.log('🐚 Loaded ${_history.values.fold(0, (sum, list) => sum + list.length)} history entries');
      
    } catch (e) {
      developer.log('🐚 Failed to load history: $e');
    }
  }

  void _loadHooks() {
    try {
      final file = File('${_shellConfigFile}.hooks');
      if (!file.existsSync()) {
        developer.log('🐚 No existing shell hooks found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['hooks']) {
        final hooks = (entry['items'] as List)
            .map((item) => ShellHook.fromJson(item))
            .toList();
        
        _hooks[entry['shell_name']] = hooks;
        _totalHooks += hooks.length;
      }
      
      developer.log('🐚 Loaded ${_hooks.values.fold(0, (sum, list) => sum + list.length)} shell hooks');
      
    } catch (e) {
      developer.log('🐚 Failed to load shell hooks: $e');
    }
  }

  ShellConfig _createDefaultShellConfig(String shellName) {
    switch (shellName) {
      case 'zsh':
        return ShellConfig(
          shellName: 'zsh',
          executable: 'zsh',
          configFiles: [
            '${Platform.environment['HOME']}/.zshrc',
            '${Platform.environment['HOME']}/.zprofile',
          ],
          completionScript: _generateZshCompletionScript(),
          historyFile: '${Platform.environment['HOME']}/.zsh_history',
          promptFormat: '%n@%m:%~$ ',
          customAliases: {},
          customFunctions: {},
          integrationEnabled: true,
          autoLoadCompletions: true,
          historySize: 10000,
          completionStyle: 'fuzzy',
          keyBindings: {},
        );
        
      case 'fish':
        return ShellConfig(
          shellName: 'fish',
          executable: 'fish',
          configFiles: [
            '${Platform.environment['HOME']}/.config/fish/config.fish',
            '${Platform.environment['HOME']}/.config/fish/functions',
          ],
          completionScript: _generateFishCompletionScript(),
          historyFile: '${Platform.environment['HOME']}/.local/share/fish/fish_history',
          promptFormat: 'fish_prompt_default',
          customAliases: {},
          customFunctions: {},
          integrationEnabled: true,
          autoLoadCompletions: true,
          historySize: 10000,
          completionStyle: 'fuzzy',
          keyBindings: {},
        );
        
      case 'bash':
        return ShellConfig(
          shellName: 'bash',
          executable: 'bash',
          configFiles: [
            '${Platform.environment['HOME']}/.bashrc',
            '${Platform.environment['HOME']}/.bash_profile',
          ],
          completionScript: _generateBashCompletionScript(),
          historyFile: '${Platform.environment['HOME']}/.bash_history',
          promptFormat: '\\u@\\h:\\w\\$ ',
          customAliases: {},
          customFunctions: {},
          integrationEnabled: true,
          autoLoadCompletions: true,
          historySize: 1000,
          completionStyle: 'basic',
          keyBindings: {},
        );
        
      case 'powershell':
        return ShellConfig(
          shellName: 'powershell',
          executable: 'powershell',
          configFiles: [
            '${Platform.environment['USERPROFILE']}/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1',
          ],
          completionScript: _generatePowerShellCompletionScript(),
          historyFile: '${Platform.environment['USERPROFILE']}/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLineConsoleHost_history.txt',
          promptFormat: 'PS>',
          customAliases: {},
          customFunctions: {},
          integrationEnabled: true,
          autoLoadCompletions: true,
          historySize: 1000,
          completionStyle: 'fuzzy',
          keyBindings: {},
        );
        
      default:
        return ShellConfig(
          shellName: shellName,
          executable: shellName,
          configFiles: [],
          completionScript: '',
          historyFile: '',
          promptFormat: '$ ',
          customAliases: {},
          customFunctions: {},
          integrationEnabled: false,
          autoLoadCompletions: false,
          historySize: 1000,
          completionStyle: 'basic',
          keyBindings: {},
        );
    }
  }

  String _generateZshCompletionScript() {
    return '''
# ZSH completion integration for Termisol
_termisol_completion() {
  local compline
  local -a completions
  COMPREPLY=()
  
  # Get current word
  local words
  words=(${(z)words[CURRENT])
  words=(\${words[CURRENT]%%\n})
  
  # Add Termisol-specific completions
  completions=(
    "git" "docker" "flutter" "npm" "yarn" 
    "pip" "python" "node" "java" "kotlin"
    "cargo" "rust" "go" "golang"
    "vim" "nano" "code" "emacs"
    "ls" "cd" "mkdir" "rm" "cp" "mv"
    "grep" "find" "sed" "awk" "sort"
    "ps" "kill" "top" "htop"
    "ssh" "scp" "rsync"
  )
  
  # Generate completions
  for cmd in \$completions; do
    if [[ "\$words" == *"\$cmd"* ]]; then
      COMPREPLY+=("\$cmd")
    fi
  done
  
  # Add file completions
  if [[ "\$words" == *".* ]]; then
    local files=(*./*(.N))
    COMPREPLY+=(\${files[@]})
  fi
  
  # Add directory completions
  if [[ "\$words" == *"/"* ]]; then
    local dirs=(*(/)
    COMPREPLY+=(\${dirs[@]})
  fi
  
  # Return completions
  printf '%s\\n' "\${COMPREPLY[@]}"
}

# Hook into zsh completion system
autoload -U compinit
compinit -C _termisol_completion
''';
  }

  String _generateFishCompletionScript() {
    return '''
# Fish completion integration for Termisol
function _termisol_completion
  set -l completions
  set -l command (commandline -po)
  
  # Get current word
  set -l words (commandline -po)
  set words (string split -m " " -- \$words)
  
  # Add Termisol-specific completions
  set completions git docker flutter npm yarn pip python node java kotlin cargo rust golang vim nano code emacs ls cd mkdir rm cp mv grep find sed awk sort ps kill top htop ssh scp rsync
  
  # Generate completions
  for cmd in \$completions
    if string match -q "*\$cmd*" -- \$words
      set -a completions \$cmd
    end
  end
  
  # Add file completions
  if string match -q "*. *" -- \$words
    set -l files (ls -d *)
    set -a completions \$files
  end
  
  # Add directory completions
  if string match -q "*/ *" -- \$words
    set -l dirs (ls -d */)
    set -a completions \$dirs
  end
  
  # Return completions
  for completion in \$completions
    echo \$completion
  end
end

# Hook into fish completion system
complete -c _termisol_completion -d "Complete Termisol commands"
''';
  }

  String _generateBashCompletionScript() {
    return '''
# Bash completion integration for Termisol
_termisol_completion() {
  local cur prev words
  COMPREPLY=()
  
  # Get current word
  cur=\${COMP_WORDS[COMP_CWORD]}
  prev=\${COMP_WORDS[COMP_CWORD-1]}
  
  # Add Termisol-specific completions
  local completions=(
    "git" "docker" "flutter" "npm" "yarn" 
    "pip" "python" "node" "java" "kotlin"
    "cargo" "rust" "go" "golang"
    "vim" "nano" "code" "emacs"
    "ls" "cd" "mkdir" "rm" "cp" "mv"
    "grep" "find" "sed" "awk" "sort"
    "ps" "kill" "top" "htop"
    "ssh" "scp" "rsync"
  )
  
  # Generate completions
  for cmd in \${completions[@]}; do
    if [[ "\$cur" == "\$cmd"* ]]; then
      COMPREPLY+=("\$cmd")
    fi
  done
  
  # Add file completions
  if [[ "\$cur" == *"."* ]]; then
    local files=(*./*)
    COMPREPLY+=(\${files[@]})
  fi
  
  # Add directory completions
  if [[ "\$cur" == *"/"* ]]; then
    local dirs=(*/)
    COMPREPLY+=(\${dirs[@]})
  fi
  
  # Return completions
  printf '%s\\n' "\${COMPREPLY[@]}"
}

# Hook into bash completion system
complete -F _termisol_completion
''';
  }

  String _generatePowerShellCompletionScript() {
    return '''
# PowerShell completion integration for Termisol
function _termisol_completion {
  param($commandName, $wordToComplete, $commandAst, $cursorPosition)
  
  # Add Termisol-specific completions
  $completions = @(
    "git", "docker", "flutter", "npm", "yarn",
    "pip", "python", "node", "java", "kotlin",
    "cargo", "rust", "go", "golang",
    "vim", "nano", "code", "emacs",
    "ls", "cd", "mkdir", "rm", "cp", "mv",
    "grep", "find", "sed", "awk", "sort",
    "ps", "kill", "top", "htop",
    "ssh", "scp", "rsync"
  )
  
  # Generate completions
  foreach ($cmd in $completions) {
    if ($wordToComplete -like "*$cmd*") {
      $cmd
    }
  }
}

# Hook into PowerShell completion system
Register-ArgumentCompleter -CommandName '_termisol_completion' -ScriptBlock $function:_termisol_completion
''';
  }

  void _startTimers() {
    _cleanupTimer = Timer.periodic(
      Duration(hours: 1),
      (_) => _performCleanup(),
    );
  }

  Future<List<CompletionItem>> getCompletions({
    required String shellName,
    required String input,
    CompletionType? type,
    int? limit,
  }) async {
    final completions = _completions[shellName] ?? [];
    final inputLower = input.toLowerCase();
    
    // Filter completions based on input
    final filtered = completions.where((completion) {
      switch (type ?? CompletionType.fuzzy) {
        case CompletionType.exact:
          return completion.text.toLowerCase() == inputLower;
        case CompletionType.prefix:
          return completion.text.toLowerCase().startsWith(inputLower);
        case CompletionType.fuzzy:
          return _calculateFuzzyScore(inputLower, completion.text.toLowerCase()) > 0.5;
        case CompletionType.semantic:
          return _calculateSemanticScore(inputLower, completion.text.toLowerCase()) > 0.3;
      }
    }).toList();
    
    // Sort by score
    filtered.sort((a, b) => b.score.compareTo(a.score));
    
    // Apply limit
    if (limit != null && limit! > 0) {
      return filtered.take(limit!).toList();
    }
    
    return filtered;
  }

  double _calculateFuzzyScore(String input, String completion) {
    // Simple fuzzy matching score
    if (completion == input) return 1.0;
    if (completion.startsWith(input)) return 0.8;
    
    // Levenshtein distance
    final distance = _levenshteinDistance(input, completion);
    final maxLength = math.max(input.length, completion.length);
    
    if (maxLength == 0) return 0.0;
    
    return 1.0 - (distance / maxLength);
  }

  int _levenshteinDistance(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
      }
    }
    
    return matrix[a.length][b.length];
  }

  double _calculateSemanticScore(String input, String completion) {
    // Simplified semantic scoring based on common patterns
    final inputWords = input.split(RegExp(r'\W+'));
    final completionWords = completion.split(RegExp(r'\W+'));
    
    if (inputWords.isEmpty || completionWords.isEmpty) return 0.0;
    
    // Check if completion contains all input words
    int matchingWords = 0;
    for (final word in inputWords) {
      if (completionWords.any((compWord) => compWord.contains(word))) {
        matchingWords++;
      }
    }
    
    return matchingWords / inputWords.length;
  }

  Future<void> addCompletion({
    required String shellName,
    required String text,
    String? description,
    String? category,
    String? command,
    List<String>? arguments,
    int? priority,
    Map<String, dynamic>? metadata,
  }) async {
    final completions = _completions[shellName] ?? [];
    
    if (completions.length >= _maxCompletions) {
      // Remove oldest completions
      final toRemove = completions.take(completions.length - _maxCompletions + 100);
      completions.removeRange(0, toRemove.length);
      _totalCompletions -= toRemove.length;
    }
    
    final completion = CompletionItem(
      id: _generateCompletionId(),
      text: text,
      description: description ?? '',
      category: category ?? 'custom',
      command: command,
      arguments: arguments ?? [],
      priority: priority ?? 5,
      metadata: metadata ?? {},
      usageCount: 0,
      lastUsed: null,
      createdAt: DateTime.now(),
    );
    
    completions.add(completion);
    _totalCompletions++;
    
    _completions[shellName] = completions;
    
    developer.log('🐚 Added completion for $shellName: $text');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.completionAdded,
      shellName: shellName,
      completionId: completion.id,
      text: text,
    ));
    
    await _saveCompletions();
  }

  Future<void> addHistoryEntry({
    required String shellName,
    required String command,
    String? workingDirectory,
    int? exitCode,
    Duration? executionTime,
    Map<String, dynamic>? context,
  }) async {
    final history = _history[shellName] ?? [];
    
    if (history.length >= _maxHistory) {
      // Remove oldest entries
      final toRemove = history.take(history.length - _maxHistory + 1000);
      history.removeRange(0, toRemove.length);
      _totalHistory -= toRemove.length;
    }
    
    final entry = HistoryEntry(
      id: _generateHistoryId(),
      command: command,
      workingDirectory: workingDirectory ?? Directory.current.path,
      exitCode: exitCode ?? 0,
      executionTime: executionTime ?? Duration.zero,
      context: context ?? {},
      timestamp: DateTime.now(),
    );
    
    history.add(entry);
    _totalHistory++;
    
    _history[shellName] = history;
    
    developer.log('🐚 Added history entry for $shellName: $command');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.historyAdded,
      shellName: shellName,
      historyId: entry.id,
      command: command,
    ));
    
    await _saveHistory();
  }

  Future<void> addHook({
    required String shellName,
    required String name,
    required ShellHookType type,
    required String script,
    String? description,
    bool? enabled,
    Map<String, dynamic>? config,
  }) async {
    final hooks = _hooks[shellName] ?? [];
    
    if (hooks.length >= _maxHooks) {
      throw Exception('Maximum hooks reached: $_maxHooks');
    }
    
    final hook = ShellHook(
      id: _generateHookId(),
      name: name,
      type: type,
      script: script,
      description: description ?? '',
      enabled: enabled ?? true,
      config: config ?? {},
      createdAt: DateTime.now(),
      lastTriggered: null,
      triggerCount: 0,
    );
    
    hooks.add(hook);
    _totalHooks++;
    
    _hooks[shellName] = hooks;
    
    developer.log('🐚 Added hook for $shellName: $name');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.hookAdded,
      shellName: shellName,
      hookId: hook.id,
      hookName: name,
    ));
    
    await _saveHooks();
  }

  Future<void> executeHook({
    required String shellName,
    required String hookId,
    Map<String, dynamic>? context,
  }) async {
    final hooks = _hooks[shellName] ?? [];
    final hook = hooks.firstWhere((h) => h.id == hookId);
    
    if (hook == null) {
      throw Exception('Hook not found: $hookId');
    }
    
    if (!hook.enabled) {
      throw Exception('Hook is disabled: $hookId');
    }
    
    try {
      developer.log('🐚 Executing hook: ${hook.name} for $shellName');
      
      hook.lastTriggered = DateTime.now();
      hook.triggerCount++;
      
      // Execute hook script
      final result = await Process.run(
        _shellConfigs[shellName]?.executable ?? shellName,
        ['-c', hook.script],
        environment: context ?? {},
      );
      
      developer.log('🐚 Hook executed: ${hook.name} (exit code: ${result.exitCode})');
      
      _emitEvent(ShellEvent(
        type: ShellEventType.hookExecuted,
        shellName: shellName,
        hookId: hookId,
        hookName: hook.name,
        exitCode: result.exitCode,
        output: result.stdout,
      ));
      
    } catch (e) {
      developer.log('🐚 Hook execution failed: ${hook.name} - $e');
      
      _emitEvent(ShellEvent(
        type: ShellEventType.hookExecutionFailed,
        shellName: shellName,
        hookId: hookId,
        hookName: hook.name,
        error: e.toString(),
      ));
    }
  }

  Future<String> createSession({
    required String shellName,
    String? workingDirectory,
    Map<String, dynamic>? environment,
    List<String>? startupCommands,
  }) async {
    final sessionId = _generateSessionId();
    
    final session = ShellSession(
      id: sessionId,
      shellName: shellName,
      workingDirectory: workingDirectory ?? Directory.current.path,
      environment: environment ?? {},
      startupCommands: startupCommands ?? [],
      process: null,
      isActive: false,
      createdAt: DateTime.now(),
      lastActivity: DateTime.now(),
    );
    
    _sessions[sessionId] = session;
    _totalSessions++;
    
    developer.log('🐚 Created shell session: $sessionId for $shellName');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.sessionCreated,
      shellName: shellName,
      sessionId: sessionId,
    ));
    
    await _saveSessions();
    
    return sessionId;
  }

  Future<void> startSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final config = _shellConfigs[session.shellName];
    if (config == null) {
      throw Exception('Shell config not found: ${session.shellName}');
    }
    
    try {
      developer.log('🐚 Starting shell session: $sessionId');
      
      // Start shell process
      final process = await Process.start(
        config.executable,
        ['-i'],
        workingDirectory: session.workingDirectory,
        environment: {
          ...Platform.environment,
          ...session.environment,
          'TERMISOL_SESSION_ID': sessionId,
        },
      );
      
      session.process = process;
      session.isActive = true;
      session.lastActivity = DateTime.now();
      
      // Execute startup commands
      for (final command in session.startupCommands) {
        process.stdin.writeln(command);
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      // Setup hooks
      await _setupSessionHooks(sessionId);
      
      developer.log('🐚 Shell session started: $sessionId');
      
      _emitEvent(ShellEvent(
        type: ShellEventType.sessionStarted,
        shellName: session.shellName,
        sessionId: sessionId,
      ));
      
      await _saveSessions();
      
    } catch (e) {
      session.isActive = false;
      session.process = null;
      
      developer.log('🐚 Failed to start shell session: $sessionId - $e');
      
      _emitEvent(ShellEvent(
        type: ShellEventType.sessionStartFailed,
        shellName: session.shellName,
        sessionId: sessionId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _setupSessionHooks(String sessionId) async {
    final session = _sessions[sessionId];
    final hooks = _hooks[session.shellName] ?? [];
    
    if (session == null || hooks.isEmpty) return;
    
    // Setup pre-command hooks
    for (final hook in hooks.where((h) => h.type == ShellHookType.preCommand)) {
      if (hook.enabled) {
        await _executeHook(shellName: session.shellName, hookId: hook.id);
      }
    }
  }

  Future<void> stopSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    if (session.process != null) {
      session.process!.kill();
      session.process = null;
    }
    
    session.isActive = false;
    session.lastActivity = DateTime.now();
    
    developer.log('🐚 Stopped shell session: $sessionId');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.sessionStopped,
      shellName: session.shellName,
      sessionId: sessionId,
    ));
    
    await _saveSessions();
  }

  Future<void> sendCommand({
    required String sessionId,
    required String command,
  }) async {
    final session = _sessions[sessionId];
    if (session == null || session.process == null) {
      throw Exception('Session not active: $sessionId');
    }
    
    session.process!.stdin.writeln(command);
    session.lastActivity = DateTime.now();
    
    developer.log('🐚 Sent command to session $sessionId: $command');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.commandSent,
      shellName: session.shellName,
      sessionId: sessionId,
      command: command,
    ));
  }

  Future<void> _performCleanup() async {
    // Clean old completions
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    
    for (final entry in _completions.entries) {
      final shellName = entry.key;
      final completions = entry.value;
      
      final initialCount = completions.length;
      completions.removeWhere((completion) => 
          completion.createdAt.isBefore(cutoffDate) && 
          completion.usageCount == 0);
      
      final removedCount = initialCount - completions.length;
      if (removedCount > 0) {
        _totalCompletions -= removedCount;
        developer.log('🐚 Cleaned $removedCount old completions for $shellName');
      }
    }
    
    // Clean old history
    for (final entry in _history.entries) {
      final shellName = entry.key;
      final history = entry.value;
      
      final initialCount = history.length;
      history.removeWhere((entry) => 
          entry.timestamp.isBefore(cutoffDate));
      
      final removedCount = initialCount - history.length;
      if (removedCount > 0) {
        _totalHistory -= removedCount;
        developer.log('🐚 Cleaned $removedCount old history entries for $shellName');
      }
    }
    
    // Clean inactive sessions
    final inactiveSessions = <String>[];
    for (final entry in _sessions.entries) {
      final session = entry.value;
      if (!session.isActive && 
          DateTime.now().difference(session.lastActivity).inHours > 24) {
        inactiveSessions.add(entry.key);
      }
    }
    
    for (final sessionId in inactiveSessions) {
      final session = _sessions[sessionId]!;
      if (session.process != null) {
        session.process!.kill();
        session.process = null;
      }
      
      _sessions.remove(sessionId);
      _totalSessions--;
    }
    
    if (inactiveSessions.isNotEmpty) {
      developer.log('🐚 Cleaned ${inactiveSessions.length} inactive sessions');
    }
    
    await _saveCompletions();
    await _saveHistory();
    await _saveHooks();
    await _saveSessions();
  }

  Future<void> _saveCompletions() async {
    try {
      final file = File(_completionFile);
      
      final completionsData = <String, dynamic>{};
      for (final entry in _completions.entries) {
        completionsData[entry.key] = {
          'items': entry.value.map((completion) => completion.toJson()).toList(),
        };
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'completions': completionsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🐚 Failed to save completions: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final file = File(_historyFile);
      
      final historyData = <String, dynamic>{};
      for (final entry in _history.entries) {
        historyData[entry.key] = {
          'items': entry.value.map((history) => history.toJson()).toList(),
        };
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'history': historyData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🐚 Failed to save history: $e');
    }
  }

  Future<void> _saveHooks() async {
    try {
      final file = File('${_shellConfigFile}.hooks');
      
      final hooksData = <String, dynamic>{};
      for (final entry in _hooks.entries) {
        hooksData[entry.key] = {
          'items': entry.value.map((hook) => hook.toJson()).toList(),
        };
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'hooks': hooksData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🐚 Failed to save hooks: $e');
    }
  }

  Future<void> _saveSessions() async {
    try {
      final file = File('${_shellConfigFile}.sessions');
      
      final sessionsData = _sessions.values.map((session) => session.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'sessions': sessionsData,
        'active_shell': _activeShell,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🐚 Failed to save sessions: $e');
    }
  }

  Future<void> setActiveShell(String shellName) async {
    if (!_shellConfigs.containsKey(shellName)) {
      throw Exception('Shell not found: $shellName');
    }
    
    _activeShell = shellName;
    
    developer.log('🐚 Set active shell: $shellName');
    
    _emitEvent(ShellEvent(
      type: ShellEventType.activeShellChanged,
      shellName: shellName,
    ));
    
    await _saveConfiguration();
  }

  Future<void> _saveConfiguration() async {
    try {
      final file = File(_shellConfigFile);
      
      final configsData = _shellConfigs.values.map((config) => config.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'configs': configsData,
        'active_shell': _activeShell,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🐚 Failed to save shell configuration: $e');
    }
  }

  ShellConfig? getShellConfig(String shellName) {
    return _shellConfigs[shellName];
  }

  List<ShellConfig> getShellConfigs() {
    return _shellConfigs.values.toList();
  }

  String? getActiveShell() {
    return _activeShell;
  }

  List<CompletionItem> getCompletions(String shellName) {
    return _completions[shellName] ?? [];
  }

  List<HistoryEntry> getHistory(String shellName, {int? limit}) {
    final history = _history[shellName] ?? [];
    final sortedHistory = history..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null && limit! > 0) {
      return sortedHistory.take(limit!).toList();
    }
    
    return sortedHistory;
  }

  List<ShellHook> getHooks(String shellName) {
    return _hooks[shellName] ?? [];
  }

  ShellSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  List<ShellSession> getSessions() {
    return _sessions.values.toList();
  }

  ShellIntegrationStats getStats() {
    return ShellIntegrationStats(
      totalShells: _shellConfigs.length,
      totalCompletions: _totalCompletions,
      totalHistory: _totalHistory,
      totalHooks: _totalHooks,
      totalSessions: _totalSessions,
      activeSessions: _sessions.values.where((s) => s.isActive).length,
      activeShell: _activeShell,
    );
  }

  String _generateCompletionId() {
    return 'completion_${DateTime.now().millisecondsSinceEpoch}_$_totalCompletions';
  }

  String _generateHistoryId() {
    return 'history_${DateTime.now().millisecondsSinceEpoch}_$_totalHistory';
  }

  String _generateHookId() {
    return 'hook_${DateTime.now().millisecondsSinceEpoch}_$_totalHooks';
  }

  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_$_totalSessions';
  }

  void _emitEvent(ShellEvent event) {
    _shellController.add(event);
  }

  Stream<ShellEvent> get shellEventStream => _shellController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    
    // Stop all active sessions
    for (final session in _sessions.values) {
      if (session.process != null) {
        session.process!.kill();
      }
    }
    
    _shellConfigs.clear();
    _completions.clear();
    _history.clear();
    _hooks.clear();
    _sessions.clear();
    _shellController.close();
    
    developer.log('🐚 Advanced Shell Integration disposed');
  }
}

class ShellConfig {
  final String shellName;
  final String executable;
  final List<String> configFiles;
  final String completionScript;
  final String historyFile;
  final String promptFormat;
  final Map<String, String> customAliases;
  final Map<String, String> customFunctions;
  final bool integrationEnabled;
  final bool autoLoadCompletions;
  final int historySize;
  final String completionStyle;
  final Map<String, String> keyBindings;

  ShellConfig({
    required this.shellName,
    required this.executable,
    required this.configFiles,
    required this.completionScript,
    required this.historyFile,
    required this.promptFormat,
    required this.customAliases,
    required this.customFunctions,
    required this.integrationEnabled,
    required this.autoLoadCompletions,
    required this.historySize,
    required this.completionStyle,
    required this.keyBindings,
  });

  Map<String, dynamic> toJson() {
    return {
      'shell_name': shellName,
      'executable': executable,
      'config_files': configFiles,
      'completion_script': completionScript,
      'history_file': historyFile,
      'prompt_format': promptFormat,
      'custom_aliases': customAliases,
      'custom_functions': customFunctions,
      'integration_enabled': integrationEnabled,
      'auto_load_completions': autoLoadCompletions,
      'history_size': historySize,
      'completion_style': completionStyle,
      'key_bindings': keyBindings,
    };
  }

  factory ShellConfig.fromJson(Map<String, dynamic> json) {
    return ShellConfig(
      shellName: json['shell_name'],
      executable: json['executable'],
      configFiles: List<String>.from(json['config_files'] ?? []),
      completionScript: json['completion_script'] ?? '',
      historyFile: json['history_file'] ?? '',
      promptFormat: json['prompt_format'] ?? '',
      customAliases: Map<String, String>.from(json['custom_aliases'] ?? {}),
      customFunctions: Map<String, String>.from(json['custom_functions'] ?? {}),
      integrationEnabled: json['integration_enabled'] ?? false,
      autoLoadCompletions: json['auto_load_completions'] ?? false,
      historySize: json['history_size'] ?? 1000,
      completionStyle: json['completion_style'] ?? 'basic',
      keyBindings: Map<String, String>.from(json['key_bindings'] ?? {}),
    );
  }
}

class CompletionItem {
  final String id;
  final String text;
  final String description;
  final String category;
  final String? command;
  final List<String> arguments;
  final int priority;
  final Map<String, dynamic> metadata;
  final int usageCount;
  final DateTime? lastUsed;
  final DateTime createdAt;

  CompletionItem({
    required this.id,
    required this.text,
    required this.description,
    required this.category,
    this.command,
    required this.arguments,
    required this.priority,
    required this.metadata,
    required this.usageCount,
    this.lastUsed,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'description': description,
      'category': category,
      'command': command,
      'arguments': arguments,
      'priority': priority,
      'metadata': metadata,
      'usage_count': usageCount,
      'last_used': lastUsed?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CompletionItem.fromJson(Map<String, dynamic> json) {
    return CompletionItem(
      id: json['id'],
      text: json['text'],
      description: json['description'],
      category: json['category'],
      command: json['command'],
      arguments: List<String>.from(json['arguments'] ?? []),
      priority: json['priority'] ?? 5,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      usageCount: json['usage_count'] ?? 0,
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class HistoryEntry {
  final String id;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final Duration executionTime;
  final Map<String, dynamic> context;
  final DateTime timestamp;

  HistoryEntry({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.executionTime,
    required this.context,
    required this.timestamp,
  });
}

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'execution_time': executionTime.inMilliseconds,
      'context': context,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'],
      command: json['command'],
      workingDirectory: json['working_directory'],
      exitCode: json['exit_code'],
      executionTime: Duration(milliseconds: json['execution_time']),
      context: Map<String, dynamic>.from(json['context'] ?? {}),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class ShellHook {
  final String id;
  final String name;
  final ShellHookType type;
  final String script;
  final String description;
  final bool enabled;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  final DateTime? lastTriggered;
  final int triggerCount;

  ShellHook({
    required this.id,
    required this.name,
    required this.type,
    required this.script,
    required this.description,
    required this.enabled,
    required this.config,
    required this.createdAt,
    this.lastTriggered,
    required this.triggerCount,
  });
}

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'script': script,
      'description': description,
      'enabled': enabled,
      'config': config,
      'created_at': createdAt.toIso8601String(),
      'last_triggered': lastTriggered?.toIso8601String(),
      'trigger_count': triggerCount,
    };
  }

  factory ShellHook.fromJson(Map<String, dynamic> json) {
    return ShellHook(
      id: json['id'],
      name: json['name'],
      type: ShellHookType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ShellHookType.preCommand,
      ),
      script: json['script'],
      description: json['description'],
      enabled: json['enabled'] ?? true,
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      lastTriggered: json['last_triggered'] != null ? DateTime.parse(json['last_triggered']) : null,
      triggerCount: json['trigger_count'] ?? 0,
    );
  }
}

class ShellSession {
  final String id;
  final String shellName;
  final String workingDirectory;
  final Map<String, dynamic> environment;
  final List<String> startupCommands;
  final Process? process;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastActivity;

  ShellSession({
    required this.id,
    required this.shellName,
    required this.workingDirectory,
    required this.environment,
    required this.startupCommands,
    this.process,
    required this.isActive,
    required this.createdAt,
    required this.lastActivity,
  });
}

Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shell_name': shellName,
      'working_directory': workingDirectory,
      'environment': environment,
      'startup_commands': startupCommands,
      'process': null, // Process objects can't be serialized
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'last_activity': lastActivity.toIso8601String(),
    };
  }

factory ShellSession.fromJson(Map<String, dynamic> json) {
    return ShellSession(
      id: json['id'],
      shellName: json['shell_name'],
      workingDirectory: json['working_directory'],
      environment: Map<String, dynamic>.from(json['environment'] ?? {}),
      startupCommands: List<String>.from(json['startup_commands'] ?? []),
      process: null,
      isActive: json['is_active'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      lastActivity: DateTime.parse(json['last_activity']),
    );
  }
}

enum CompletionType {
  exact,
  prefix,
  fuzzy,
  semantic,
}

enum ShellHookType {
  preCommand,
  postCommand,
  prePrompt,
  postPrompt,
  directoryChange,
}

enum ShellEventType {
  completionAdded,
  historyAdded,
  hookAdded,
  hookExecuted,
  hookExecutionFailed,
  sessionCreated,
  sessionStarted,
  sessionStartFailed,
  sessionStopped,
  commandSent,
  activeShellChanged,
}

class ShellEvent {
  final ShellEventType type;
  final String? shellName;
  final String? sessionId;
  final String? completionId;
  final String? text;
  final String? hookId;
  final String? hookName;
  final int? exitCode;
  final String? output;
  final String? error;
  final String? command;

  ShellEvent({
    required this.type,
    this.shellName,
    this.sessionId,
    this.completionId,
    this.text,
    this.hookId,
    this.hookName,
    this.exitCode,
    this.output,
    this.error,
    this.command,
  });
}

class ShellIntegrationStats {
  final int totalShells;
  final int totalCompletions;
  final int totalHistory;
  final int totalHooks;
  final int totalSessions;
  final int activeSessions;
  final String? activeShell;

  ShellIntegrationStats({
    required this.totalShells,
    required this.totalCompletions,
    required this.totalHistory,
    required this.totalHooks,
    required this.totalSessions,
    required this.activeSessions,
    required this.activeShell,
  });
}
