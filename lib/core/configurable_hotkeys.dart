import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class ConfigurableHotkeys {
  static const String _configFile = '/home/house/.termisol_hotkeys.json';
  static const int _maxHotkeys = 100;
  static const int _maxCommands = 200;
  
  final Map<String, Hotkey> _hotkeys = {};
  final Map<String, Command> _commands = {};
  final Map<String, HotkeyProfile> _profiles = {};
  final Map<String, List<HotkeyBinding>> _bindings = {};
  
  String? _currentProfile;
  int _totalHotkeys = 0;
  int _totalCommands = 0;
  
  final StreamController<HotkeyEvent> _hotkeyController = 
      StreamController<HotkeyEvent>.broadcast();

  void initialize() {
    _loadConfigurations();
    _initializeDefaultHotkeys();
    _initializeDefaultCommands();
    _initializeDefaultProfiles();
    developer.log('⌨️ Configurable Hotkeys initialized');
  }

  void _loadConfigurations() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('⌨️ No existing hotkeys configuration found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load hotkeys
      for (final entry in data['hotkeys']) {
        final hotkey = Hotkey.fromJson(entry);
        _hotkeys[hotkey.id] = hotkey;
        _totalHotkeys++;
      }
      
      // Load commands
      for (final entry in data['commands']) {
        final command = Command.fromJson(entry);
        _commands[command.id] = command;
        _totalCommands++;
      }
      
      // Load profiles
      for (final entry in data['profiles']) {
        final profile = HotkeyProfile.fromJson(entry);
        _profiles[profile.id] = profile;
      }
      
      // Load bindings
      for (final entry in data['bindings']) {
        final profileId = entry['profile_id'];
        final bindings = (entry['bindings'] as List)
            .map((binding) => HotkeyBinding.fromJson(binding))
            .toList();
        
        _bindings[profileId] = bindings;
      }
      
      _currentProfile = data['current_profile'] ?? 'default';
      
      developer.log('⌨️ Loaded configuration: $_totalHotkeys hotkeys, $_totalCommands commands');
      
    } catch (e) {
      developer.log('⌨️ Failed to load hotkeys configuration: $e');
    }
  }

  void _initializeDefaultHotkeys() {
    // Terminal hotkeys
    _createDefaultHotkey(
      id: 'copy',
      name: 'Copy',
      key: 'Ctrl+C',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'copy_selection',
      category: HotkeyCategory.terminal,
      description: 'Copy selected text',
    );
    
    _createDefaultHotkey(
      id: 'paste',
      name: 'Paste',
      key: 'Ctrl+V',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'paste_clipboard',
      category: HotkeyCategory.terminal,
      description: 'Paste from clipboard',
    );
    
    _createDefaultHotkey(
      id: 'new_tab',
      name: 'New Tab',
      key: 'Ctrl+T',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'create_tab',
      category: HotkeyCategory.terminal,
      description: 'Create new terminal tab',
    );
    
    _createDefaultHotkey(
      id: 'close_tab',
      name: 'Close Tab',
      key: 'Ctrl+W',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'close_tab',
      category: HotkeyCategory.terminal,
      description: 'Close current terminal tab',
    );
    
    _createDefaultHotkey(
      id: 'switch_tab_next',
      name: 'Next Tab',
      key: 'Ctrl+Tab',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'switch_tab_next',
      category: HotkeyCategory.terminal,
      description: 'Switch to next tab',
    );
    
    _createDefaultHotkey(
      id: 'switch_tab_prev',
      name: 'Previous Tab',
      key: 'Ctrl+Shift+Tab',
      modifiers: ['Ctrl', 'Shift'],
      keyEvent: 'keydown',
      action: 'switch_tab_prev',
      category: HotkeyCategory.terminal,
      description: 'Switch to previous tab',
    );
    
    // Navigation hotkeys
    _createDefaultHotkey(
      id: 'up',
      name: 'Cursor Up',
      key: 'ArrowUp',
      modifiers: [],
      keyEvent: 'keydown',
      action: 'cursor_up',
      category: HotkeyCategory.navigation,
      description: 'Move cursor up',
    );
    
    _createDefaultHotkey(
      id: 'down',
      name: 'Cursor Down',
      key: 'ArrowDown',
      modifiers: [],
      keyEvent: 'keydown',
      action: 'cursor_down',
      category: HotkeyCategory.navigation,
      description: 'Move cursor down',
    );
    
    _createDefaultHotkey(
      id: 'left',
      name: 'Cursor Left',
      key: 'ArrowLeft',
      modifiers: [],
      keyEvent: 'keydown',
      action: 'cursor_left',
      category: HotkeyCategory.navigation,
      description: 'Move cursor left',
    );
    
    _createDefaultHotkey(
      id: 'right',
      name: 'Cursor Right',
      key: 'ArrowRight',
      modifiers: [],
      keyEvent: 'keydown',
      action: 'cursor_right',
      category: HotkeyCategory.navigation,
      description: 'Move cursor right',
    );
    
    // System hotkeys
    _createDefaultHotkey(
      id: 'fullscreen',
      name: 'Toggle Fullscreen',
      key: 'F11',
      modifiers: [],
      keyEvent: 'keydown',
      action: 'toggle_fullscreen',
      category: HotkeyCategory.system,
      description: 'Toggle fullscreen mode',
    );
    
    _createDefaultHotkey(
      id: 'settings',
      name: 'Open Settings',
      key: 'Ctrl+,',
      modifiers: ['Ctrl'],
      keyEvent: 'keydown',
      action: 'open_settings',
      category: HotkeyCategory.system,
      description: 'Open settings dialog',
    );
    
    developer.log('⌨️ Initialized default hotkeys');
  }

  void _createDefaultHotkey({
    required String id,
    required String name,
    required String key,
    required List<String> modifiers,
    required String keyEvent,
    required String action,
    required HotkeyCategory category,
    required String description,
  }) {
    if (!_hotkeys.containsKey(id)) {
      final hotkey = Hotkey(
        id: id,
        name: name,
        key: key,
        modifiers: modifiers,
        keyEvent: keyEvent,
        action: action,
        category: category,
        description: description,
        enabled: true,
        global: false,
        createdAt: DateTime.now(),
      );
      
      _hotkeys[id] = hotkey;
      _totalHotkeys++;
    }
  }

  void _initializeDefaultCommands() {
    // Terminal commands
    _createDefaultCommand(
      id: 'clear',
      name: 'Clear Terminal',
      command: 'clear',
      category: CommandCategory.terminal,
      description: 'Clear terminal screen',
      icon: '🧹',
    );
    
    _createDefaultCommand(
      id: 'ls',
      name: 'List Files',
      command: 'ls -la',
      category: CommandCategory.terminal,
      description: 'List files in long format',
      icon: '📁',
    );
    
    _createDefaultCommand(
      id: 'cd_home',
      name: 'Go Home',
      command: 'cd ~',
      category: CommandCategory.terminal,
      description: 'Change to home directory',
      icon: '🏠',
    );
    
    _createDefaultCommand(
      id: 'git_status',
      name: 'Git Status',
      command: 'git status',
      category: CommandCategory.git,
      description: 'Show git repository status',
      icon: '🔀',
    );
    
    _createDefaultCommand(
      id: 'git_add_all',
      name: 'Git Add All',
      command: 'git add .',
      category: CommandCategory.git,
      description: 'Add all changes to git',
      icon: '➕',
    );
    
    _createDefaultCommand(
      id: 'git_commit',
      name: 'Git Commit',
      command: 'git commit -m "Auto commit from Termisol"',
      category: CommandCategory.git,
      description: 'Commit changes with default message',
      icon: '💾',
    );
    
    _createDefaultCommand(
      id: 'git_push',
      name: 'Git Push',
      command: 'git push',
      category: CommandCategory.git,
      description: 'Push changes to remote',
      icon: '⬆️',
    );
    
    // System commands
    _createDefaultCommand(
      id: 'backup',
      name: 'Create Backup',
      command: '/backup',
      category: CommandCategory.system,
      description: 'Create system backup',
      icon: '💾',
    );
    
    _createDefaultCommand(
      id: 'restart_termisol',
      name: 'Restart Termisol',
      command: 'pkill termisol && termisol',
      category: CommandCategory.system,
      description: 'Restart Termisol application',
      icon: '🔄',
    );
    
    // Development commands
    _createDefaultCommand(
      id: 'flutter_run',
      name: 'Run Flutter',
      command: 'flutter run',
      category: CommandCategory.development,
      description: 'Run Flutter application',
      icon: '🦋',
    );
    
    _createDefaultCommand(
      id: 'npm_install',
      name: 'NPM Install',
      command: 'npm install',
      category: CommandCategory.development,
      description: 'Install npm dependencies',
      icon: '📦',
    );
    
    developer.log('⌨️ Initialized default commands');
  }

  void _createDefaultCommand({
    required String id,
    required String name,
    required String command,
    required CommandCategory category,
    required String description,
    required String icon,
  }) {
    if (!_commands.containsKey(id)) {
      final cmd = Command(
        id: id,
        name: name,
        command: command,
        category: category,
        description: description,
        icon: icon,
        enabled: true,
        requiresConfirmation: false,
        createdAt: DateTime.now(),
      );
      
      _commands[id] = cmd;
      _totalCommands++;
    }
  }

  void _initializeDefaultProfiles() {
    // Default profile
    if (!_profiles.containsKey('default')) {
      final defaultProfile = HotkeyProfile(
        id: 'default',
        name: 'Default',
        description: 'Default hotkey configuration',
        bindings: [
          HotkeyBinding(
            hotkeyId: 'copy',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'paste',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'new_tab',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'close_tab',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'fullscreen',
            commandId: null,
            enabled: true,
          ),
        ],
        isActive: true,
        createdAt: DateTime.now(),
      );
      
      _profiles['default'] = defaultProfile;
      _currentProfile = 'default';
      _bindings['default'] = defaultProfile.bindings;
    }
    
    // Developer profile
    if (!_profiles.containsKey('developer')) {
      final developerProfile = HotkeyProfile(
        id: 'developer',
        name: 'Developer',
        description: 'Developer-focused hotkey configuration',
        bindings: [
          HotkeyBinding(
            hotkeyId: 'copy',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'paste',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'new_tab',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'close_tab',
            commandId: null,
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'git_status',
            commandId: 'git_status',
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'git_commit',
            commandId: 'git_commit',
            enabled: true,
          ),
          HotkeyBinding(
            hotkeyId: 'flutter_run',
            commandId: 'flutter_run',
            enabled: true,
          ),
        ],
        isActive: false,
        createdAt: DateTime.now(),
      );
      
      _profiles['developer'] = developerProfile;
      _bindings['developer'] = developerProfile.bindings;
    }
    
    developer.log('⌨️ Initialized default profiles');
  }

  Future<String> createHotkey({
    required String name,
    required String key,
    required List<String> modifiers,
    required String action,
    String? commandId,
    HotkeyCategory? category,
    String? description,
    bool? enabled,
    bool? global,
  }) async {
    if (_hotkeys.length >= _maxHotkeys) {
      throw Exception('Maximum hotkeys reached: $_maxHotkeys');
    }
    
    final hotkeyId = _generateHotkeyId();
    
    final hotkey = Hotkey(
      id: hotkeyId,
      name: name,
      key: key,
      modifiers: modifiers,
      keyEvent: 'keydown',
      action: action,
      category: category ?? HotkeyCategory.custom,
      description: description ?? 'Custom hotkey',
      enabled: enabled ?? true,
      global: global ?? false,
      createdAt: DateTime.now(),
    );
    
    _hotkeys[hotkeyId] = hotkey;
    _totalHotkeys++;
    
    // Add to current profile if specified
    if (commandId != null && _currentProfile != null) {
      await _addBindingToProfile(_currentProfile!, hotkeyId, commandId!);
    }
    
    developer.log('⌨️ Created hotkey: $name ($key)');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.hotkeyCreated,
      hotkeyId: hotkeyId,
      hotkeyName: name,
    ));
    
    await _saveConfigurations();
    
    return hotkeyId;
  }

  Future<String> createCommand({
    required String name,
    required String command,
    CommandCategory? category,
    String? description,
    String? icon,
    bool? enabled,
    bool? requiresConfirmation,
  }) async {
    if (_commands.length >= _maxCommands) {
      throw Exception('Maximum commands reached: $_maxCommands');
    }
    
    final commandId = _generateCommandId();
    
    final cmd = Command(
      id: commandId,
      name: name,
      command: command,
      category: category ?? CommandCategory.custom,
      description: description ?? 'Custom command',
      icon: icon ?? '⚙️',
      enabled: enabled ?? true,
      requiresConfirmation: requiresConfirmation ?? false,
      createdAt: DateTime.now(),
    );
    
    _commands[commandId] = cmd;
    _totalCommands++;
    
    developer.log('⌨️ Created command: $name');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.commandCreated,
      commandId: commandId,
      commandName: name,
    ));
    
    await _saveConfigurations();
    
    return commandId;
  }

  Future<String> createProfile({
    required String name,
    required String description,
    List<HotkeyBinding>? bindings,
  }) async {
    final profileId = _generateProfileId();
    
    final profile = HotkeyProfile(
      id: profileId,
      name: name,
      description: description,
      bindings: bindings ?? [],
      isActive: false,
      createdAt: DateTime.now(),
    );
    
    _profiles[profileId] = profile;
    _bindings[profileId] = profile.bindings;
    
    developer.log('⌨️ Created profile: $name');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.profileCreated,
      profileId: profileId,
      profileName: name,
    ));
    
    await _saveConfigurations();
    
    return profileId;
  }

  Future<void> updateHotkey(String hotkeyId, {
    String? name,
    String? key,
    List<String>? modifiers,
    String? action,
    HotkeyCategory? category,
    String? description,
    bool? enabled,
    bool? global,
  }) async {
    final hotkey = _hotkeys[hotkeyId];
    if (hotkey == null) {
      throw Exception('Hotkey not found: $hotkeyId');
    }
    
    if (name != null) hotkey.name = name!;
    if (key != null) hotkey.key = key!;
    if (modifiers != null) hotkey.modifiers = modifiers!;
    if (action != null) hotkey.action = action!;
    if (category != null) hotkey.category = category!;
    if (description != null) hotkey.description = description!;
    if (enabled != null) hotkey.enabled = enabled!;
    if (global != null) hotkey.global = global!;
    
    developer.log('⌨️ Updated hotkey: $hotkeyId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.hotkeyUpdated,
      hotkeyId: hotkeyId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> updateCommand(String commandId, {
    String? name,
    String? command,
    CommandCategory? category,
    String? description,
    String? icon,
    bool? enabled,
    bool? requiresConfirmation,
  }) async {
    final cmd = _commands[commandId];
    if (cmd == null) {
      throw Exception('Command not found: $commandId');
    }
    
    if (name != null) cmd.name = name!;
    if (command != null) cmd.command = command!;
    if (category != null) cmd.category = category!;
    if (description != null) cmd.description = description!;
    if (icon != null) cmd.icon = icon!;
    if (enabled != null) cmd.enabled = enabled!;
    if (requiresConfirmation != null) cmd.requiresConfirmation = requiresConfirmation!;
    
    developer.log('⌨️ Updated command: $commandId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.commandUpdated,
      commandId: commandId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> deleteHotkey(String hotkeyId) async {
    final hotkey = _hotkeys.remove(hotkeyId);
    if (hotkey == null) {
      throw Exception('Hotkey not found: $hotkeyId');
    }
    
    // Remove from all profiles
    for (final profile in _profiles.values) {
      profile.bindings.removeWhere((binding) => binding.hotkeyId == hotkeyId);
    }
    
    _totalHotkeys--;
    
    developer.log('⌨️ Deleted hotkey: $hotkeyId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.hotkeyDeleted,
      hotkeyId: hotkeyId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> deleteCommand(String commandId) async {
    final command = _commands.remove(commandId);
    if (command == null) {
      throw Exception('Command not found: $commandId');
    }
    
    // Remove from all profiles
    for (final profile in _profiles.values) {
      for (final binding in profile.bindings) {
        if (binding.commandId == commandId) {
          binding.commandId = null;
        }
      }
    }
    
    _totalCommands--;
    
    developer.log('⌨️ Deleted command: $commandId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.commandDeleted,
      commandId: commandId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> deleteProfile(String profileId) async {
    if (profileId == 'default') {
      throw Exception('Cannot delete default profile');
    }
    
    final profile = _profiles.remove(profileId);
    if (profile == null) {
      throw Exception('Profile not found: $profileId');
    }
    
    _bindings.remove(profileId);
    
    // Switch to default if this was active
    if (_currentProfile == profileId) {
      await switchProfile('default');
    }
    
    developer.log('⌨️ Deleted profile: $profileId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.profileDeleted,
      profileId: profileId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> switchProfile(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) {
      throw Exception('Profile not found: $profileId');
    }
    
    // Deactivate current profile
    if (_currentProfile != null) {
      final currentProfile = _profiles[_currentProfile!];
      if (currentProfile != null) {
        currentProfile.isActive = false;
      }
    }
    
    // Activate new profile
    profile.isActive = true;
    _currentProfile = profileId;
    
    developer.log('⌨️ Switched to profile: $profileId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.profileSwitched,
      profileId: profileId,
      previousProfileId: _currentProfile,
    ));
    
    await _saveConfigurations();
  }

  Future<void> _addBindingToProfile(String profileId, String hotkeyId, String commandId) async {
    final profile = _profiles[profileId];
    if (profile == null) {
      throw Exception('Profile not found: $profileId');
    }
    
    final binding = HotkeyBinding(
      hotkeyId: hotkeyId,
      commandId: commandId,
      enabled: true,
    );
    
    profile.bindings.add(binding);
    _bindings[profileId] = profile.bindings;
    
    await _saveConfigurations();
  }

  Future<void> bindHotkeyToCommand({
    required String hotkeyId,
    required String commandId,
    String? profileId,
  }) async {
    final targetProfileId = profileId ?? _currentProfile ?? 'default';
    
    final profile = _profiles[targetProfileId];
    if (profile == null) {
      throw Exception('Profile not found: $targetProfileId');
    }
    
    // Find existing binding for this hotkey
    final existingBinding = profile.bindings
        .where((binding) => binding.hotkeyId == hotkeyId)
        .firstOrNull;
    
    if (existingBinding != null) {
      existingBinding.commandId = commandId;
    } else {
      final binding = HotkeyBinding(
        hotkeyId: hotkeyId,
        commandId: commandId,
        enabled: true,
      );
      
      profile.bindings.add(binding);
    }
    
    _bindings[targetProfileId] = profile.bindings;
    
    developer.log('⌨️ Bound hotkey $hotkeyId to command $commandId in profile $targetProfileId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.bindingCreated,
      hotkeyId: hotkeyId,
      commandId: commandId,
      profileId: targetProfileId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> unbindHotkey(String hotkeyId, {String? profileId}) async {
    final targetProfileId = profileId ?? _currentProfile ?? 'default';
    
    final profile = _profiles[targetProfileId];
    if (profile == null) {
      throw Exception('Profile not found: $targetProfileId');
    }
    
    profile.bindings.removeWhere((binding) => binding.hotkeyId == hotkeyId);
    _bindings[targetProfileId] = profile.bindings;
    
    developer.log('⌨️ Unbound hotkey: $hotkeyId from profile $targetProfileId');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.bindingDeleted,
      hotkeyId: hotkeyId,
      profileId: targetProfileId,
    ));
    
    await _saveConfigurations();
  }

  Future<void> executeCommand(String commandId, {Map<String, dynamic>? context}) async {
    final command = _commands[commandId];
    if (command == null) {
      throw Exception('Command not found: $commandId');
    }
    
    if (!command.enabled) {
      throw Exception('Command is disabled: $commandId');
    }
    
    if (command.requiresConfirmation) {
      // In a real implementation, this would show a confirmation dialog
      developer.log('⌨️ Command requires confirmation: $commandId');
    }
    
    try {
      developer.log('⌨️ Executing command: ${command.name} (${command.command})');
      
      // Execute the command
      final process = await Process.start('bash', ['-c', command.command]);
      
      // Handle output
      process.stdout.transform(utf8.decoder).listen((output) {
        developer.log('⌨️ Command output: $output');
      });
      
      process.stderr.transform(utf8.decoder).listen((error) {
        developer.log('⌨️ Command error: $error');
      });
      
      await process.exitCode;
      
      _emitEvent(HotkeyEvent(
        type: HotkeyEventType.commandExecuted,
        commandId: commandId,
        commandName: command.name,
      ));
      
    } catch (e) {
      developer.log('⌨️ Failed to execute command: $commandId - $e');
      
      _emitEvent(HotkeyEvent(
        type: HotkeyEventType.commandExecutionFailed,
        commandId: commandId,
        commandName: command.name,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> handleHotkeyPress(String key, List<String> modifiers) async {
    // Find matching hotkey
    final matchingHotkey = _hotkeys.values
        .where((hotkey) => 
            hotkey.key == key &&
            _listsEqual(hotkey.modifiers, modifiers) &&
            hotkey.enabled)
        .firstOrNull;
    
    if (matchingHotkey == null) {
      return;
    }
    
    developer.log('⌨️ Hotkey pressed: ${matchingHotkey.name} ($key)');
    
    // Check if hotkey is bound to a command in current profile
    final currentBindings = _bindings[_currentProfile] ?? [];
    final binding = currentBindings
        .where((b) => b.hotkeyId == matchingHotkey.id && b.enabled)
        .firstOrNull;
    
    if (binding != null && binding.commandId != null) {
      await executeCommand(binding.commandId!);
    } else {
      // Execute hotkey action directly
      _emitEvent(HotkeyEvent(
        type: HotkeyEventType.hotkeyPressed,
        hotkeyId: matchingHotkey.id,
        hotkeyName: matchingHotkey.name,
        key: key,
        modifiers: modifiers,
      ));
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Hotkey? getHotkey(String hotkeyId) {
    return _hotkeys[hotkeyId];
  }

  Command? getCommand(String commandId) {
    return _commands[commandId];
  }

  HotkeyProfile? getProfile(String profileId) {
    return _profiles[profileId];
  }

  List<Hotkey> getHotkeys({HotkeyCategory? category}) {
    final hotkeys = _hotkeys.values.toList();
    
    if (category != null) {
      return hotkeys.where((hotkey) => hotkey.category == category).toList();
    }
    
    return hotkeys;
  }

  List<Command> getCommands({CommandCategory? category}) {
    final commands = _commands.values.toList();
    
    if (category != null) {
      return commands.where((command) => command.category == category).toList();
    }
    
    return commands;
  }

  List<HotkeyProfile> getProfiles() {
    return _profiles.values.toList();
  }

  List<HotkeyBinding> getCurrentProfileBindings() {
    return _bindings[_currentProfile] ?? [];
  }

  String? getCurrentProfile() {
    return _currentProfile;
  }

  Future<void> exportConfiguration(String filePath) async {
    final config = {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'hotkeys': _hotkeys.values.map((h) => h.toJson()).toList(),
      'commands': _commands.values.map((c) => c.toJson()).toList(),
      'profiles': _profiles.values.map((p) => p.toJson()).toList(),
      'bindings': _bindings.entries.map((entry) => {
        'profile_id': entry.key,
        'bindings': entry.value.map((b) => b.toJson()).toList(),
      }).toList(),
      'current_profile': _currentProfile,
    };
    
    final file = File(filePath);
    await file.writeAsString(jsonEncode(config));
    
    developer.log('⌨️ Exported configuration to: $filePath');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.configurationExported,
      filePath: filePath,
    ));
  }

  Future<void> importConfiguration(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final data = jsonDecode(content);
    
    // Clear existing configuration
    _hotkeys.clear();
    _commands.clear();
    _profiles.clear();
    _bindings.clear();
    _totalHotkeys = 0;
    _totalCommands = 0;
    
    // Import hotkeys
    for (final entry in data['hotkeys']) {
      final hotkey = Hotkey.fromJson(entry);
      _hotkeys[hotkey.id] = hotkey;
      _totalHotkeys++;
    }
    
    // Import commands
    for (final entry in data['commands']) {
      final command = Command.fromJson(entry);
      _commands[command.id] = command;
      _totalCommands++;
    }
    
    // Import profiles
    for (final entry in data['profiles']) {
      final profile = HotkeyProfile.fromJson(entry);
      _profiles[profile.id] = profile;
    }
    
    // Import bindings
    for (final entry in data['bindings']) {
      final profileId = entry['profile_id'];
      final bindings = (entry['bindings'] as List)
          .map((binding) => HotkeyBinding.fromJson(binding))
          .toList();
      
      _bindings[profileId] = bindings;
    }
    
    _currentProfile = data['current_profile'] ?? 'default';
    
    await _saveConfigurations();
    
    developer.log('⌨️ Imported configuration from: $filePath');
    
    _emitEvent(HotkeyEvent(
      type: HotkeyEventType.configurationImported,
      filePath: filePath,
    ));
  }

  Future<void> _saveConfigurations() async {
    try {
      final file = File(_configFile);
      
      final config = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'hotkeys': _hotkeys.values.map((h) => h.toJson()).toList(),
        'commands': _commands.values.map((c) => c.toJson()).toList(),
        'profiles': _profiles.values.map((p) => p.toJson()).toList(),
        'bindings': _bindings.entries.map((entry) => {
          'profile_id': entry.key,
          'bindings': entry.value.map((b) => b.toJson()).toList(),
        }).toList(),
        'current_profile': _currentProfile,
      };
      
      await file.writeAsString(jsonEncode(config));
      
    } catch (e) {
      developer.log('⌨️ Failed to save configurations: $e');
    }
  }

  String _generateHotkeyId() {
    return 'hotkey_${DateTime.now().millisecondsSinceEpoch}_$_totalHotkeys';
  }

  String _generateCommandId() {
    return 'cmd_${DateTime.now().millisecondsSinceEpoch}_$_totalCommands';
  }

  String _generateProfileId() {
    return 'profile_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(HotkeyEvent event) {
    _hotkeyController.add(event);
  }

  Stream<HotkeyEvent> get hotkeyEventStream => _hotkeyController.stream;

  HotkeyStats getStats() {
    return HotkeyStats(
      totalHotkeys: _totalHotkeys,
      totalCommands: _totalCommands,
      totalProfiles: _profiles.length,
      currentProfile: _currentProfile,
      enabledHotkeys: _hotkeys.values.where((h) => h.enabled).length,
      enabledCommands: _commands.values.where((c) => c.enabled).length,
      activeBindings: (_bindings[_currentProfile] ?? []).where((b) => b.enabled).length,
    );
  }

  void dispose() {
    _hotkeys.clear();
    _commands.clear();
    _profiles.clear();
    _bindings.clear();
    _hotkeyController.close();
    
    developer.log('⌨️ Configurable Hotkeys disposed');
  }
}

class Hotkey {
  final String id;
  String name;
  final String key;
  final List<String> modifiers;
  final String keyEvent;
  final String action;
  final HotkeyCategory category;
  final String description;
  bool enabled;
  final bool global;
  final DateTime createdAt;

  Hotkey({
    required this.id,
    required this.name,
    required this.key,
    required this.modifiers,
    required this.keyEvent,
    required this.action,
    required this.category,
    required this.description,
    required this.enabled,
    required this.global,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'key': key,
      'modifiers': modifiers,
      'key_event': keyEvent,
      'action': action,
      'category': category.name,
      'description': description,
      'enabled': enabled,
      'global': global,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Hotkey.fromJson(Map<String, dynamic> json) {
    return Hotkey(
      id: json['id'],
      name: json['name'],
      key: json['key'],
      modifiers: List<String>.from(json['modifiers']),
      keyEvent: json['key_event'],
      action: json['action'],
      category: HotkeyCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => HotkeyCategory.custom,
      ),
      description: json['description'],
      enabled: json['enabled'] ?? true,
      global: json['global'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Command {
  final String id;
  String name;
  final String command;
  final CommandCategory category;
  final String description;
  final String icon;
  bool enabled;
  final bool requiresConfirmation;
  final DateTime createdAt;

  Command({
    required this.id,
    required this.name,
    required this.command,
    required this.category,
    required this.description,
    required this.icon,
    required this.enabled,
    required this.requiresConfirmation,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'category': category.name,
      'description': description,
      'icon': icon,
      'enabled': enabled,
      'requires_confirmation': requiresConfirmation,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      id: json['id'],
      name: json['name'],
      command: json['command'],
      category: CommandCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => CommandCategory.custom,
      ),
      description: json['description'],
      icon: json['icon'] ?? '⚙️',
      enabled: json['enabled'] ?? true,
      requiresConfirmation: json['requires_confirmation'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class HotkeyProfile {
  final String id;
  String name;
  final String description;
  List<HotkeyBinding> bindings;
  bool isActive;
  final DateTime createdAt;

  HotkeyProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.bindings,
    required this.isActive,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'bindings': bindings.map((b) => b.toJson()).toList(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory HotkeyProfile.fromJson(Map<String, dynamic> json) {
    return HotkeyProfile(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      bindings: (json['bindings'] as List)
          .map((binding) => HotkeyBinding.fromJson(binding))
          .toList(),
      isActive: json['is_active'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class HotkeyBinding {
  final String hotkeyId;
  final String? commandId;
  bool enabled;

  HotkeyBinding({
    required this.hotkeyId,
    this.commandId,
    required this.enabled,
  });

  Map<String, dynamic> toJson() {
    return {
      'hotkey_id': hotkeyId,
      'command_id': commandId,
      'enabled': enabled,
    };
  }

  factory HotkeyBinding.fromJson(Map<String, dynamic> json) {
    return HotkeyBinding(
      hotkeyId: json['hotkey_id'],
      commandId: json['command_id'],
      enabled: json['enabled'] ?? true,
    );
  }
}

enum HotkeyCategory {
  terminal,
  navigation,
  system,
  git,
  development,
  custom,
}

enum CommandCategory {
  terminal,
  git,
  system,
  development,
  custom,
}

enum HotkeyEventType {
  hotkeyCreated,
  hotkeyUpdated,
  hotkeyDeleted,
  hotkeyPressed,
  commandCreated,
  commandUpdated,
  commandDeleted,
  commandExecuted,
  commandExecutionFailed,
  profileCreated,
  profileUpdated,
  profileDeleted,
  profileSwitched,
  bindingCreated,
  bindingDeleted,
  configurationExported,
  configurationImported,
}

class HotkeyEvent {
  final HotkeyEventType type;
  final String? hotkeyId;
  final String? hotkeyName;
  final String? commandId;
  final String? commandName;
  final String? profileId;
  final String? previousProfileId;
  final String? key;
  final List<String>? modifiers;
  final String? error;
  final String? filePath;

  HotkeyEvent({
    required this.type,
    this.hotkeyId,
    this.hotkeyName,
    this.commandId,
    this.commandName,
    this.profileId,
    this.previousProfileId,
    this.key,
    this.modifiers,
    this.error,
    this.filePath,
  });
}

class HotkeyStats {
  final int totalHotkeys;
  final int totalCommands;
  final int totalProfiles;
  final String? currentProfile;
  final int enabledHotkeys;
  final int enabledCommands;
  final int activeBindings;

  HotkeyStats({
    required this.totalHotkeys,
    required this.totalCommands,
    required this.totalProfiles,
    this.currentProfile,
    required this.enabledHotkeys,
    required this.enabledCommands,
    required this.activeBindings,
  });
}
