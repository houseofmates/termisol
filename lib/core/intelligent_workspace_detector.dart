import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

/// Intelligent Workspace Auto-Detection
/// 
/// Implements smart workspace detection:
/// - Automatic project type detection
/// - Language and framework identification
/// - Build system detection
/// - Development environment setup
/// - Context-aware configuration
/// - Workspace-specific optimizations
/// - Intelligent tool recommendations
class IntelligentWorkspaceDetector {
  bool _isInitialized = false;
  String _currentWorkspace = '';
  WorkspaceProfile _currentProfile = WorkspaceProfile();
  final Map<String, WorkspaceProfile> _knownWorkspaces = {};
  final List<WorkspaceChange> _changeHistory = [];
  Timer? _watchTimer;
  
  // Event handlers
  final List<Function(WorkspaceProfile)> _onWorkspaceDetected = [];
  final List<Function(WorkspaceProfile)> _onWorkspaceChanged = [];
  final List<Function(ToolRecommendation)> _onToolRecommended = [];
  final List<Function(String)> _onLanguageDetected = [];
  
  IntelligentWorkspaceDetector();
  
  bool get isInitialized => _isInitialized;
  String get currentWorkspace => _currentWorkspace;
  WorkspaceProfile get currentProfile => _currentProfile;
  Map<String, WorkspaceProfile> get knownWorkspaces => Map.unmodifiable(_knownWorkspaces);
  List<WorkspaceChange> get changeHistory => List.unmodifiable(_changeHistory);
  
  /// Initialize workspace detector
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load known workspace profiles
      await _loadKnownWorkspaces();
      
      // Detect current workspace
      await _detectCurrentWorkspace();
      
      // Start file system watcher
      _startWorkspaceWatcher();
      
      _isInitialized = true;
      debugPrint('🔍 Intelligent Workspace Detector initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Workspace Detector: $e');
      rethrow;
    }
  }
  
  /// Load known workspace profiles
  Future<void> _loadKnownWorkspaces() async {
    try {
      final profilesFile = File('${Platform.environment['HOME']}/.termisol/workspace_profiles.json');
      
      if (await profilesFile.exists()) {
        final content = await profilesFile.readAsString();
        final data = jsonDecode(content);
        
        final profilesData = data['profiles'] as List? ?? [];
        for (final profileData in profilesData) {
          final profile = WorkspaceProfile.fromJson(profileData);
          _knownWorkspaces[profile.path] = profile;
        }
        
        debugPrint('🔍 Loaded ${_knownWorkspaces.length} workspace profiles');
      } else {
        // Create default profiles
        await _createDefaultProfiles();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load workspace profiles: $e');
      await _createDefaultProfiles();
    }
  }
  
  /// Create default workspace profiles
  Future<void> _createDefaultProfiles() async {
    final defaultProfiles = [
      // Flutter projects
      WorkspaceProfile(
        path: '/home/house/vibecode',
        name: 'Vibecode',
        type: WorkspaceType.flutter,
        languages: ['dart', 'javascript', 'typescript'],
        frameworks: ['flutter', 'react'],
        buildSystem: BuildSystem.npm,
        description: 'Flutter web application with React components',
        tools: ['flutter', 'npm', 'node', 'git'],
        commands: {
          'run': 'flutter run',
          'build': 'flutter build',
          'test': 'flutter test',
          'clean': 'flutter clean',
        },
      ),
      
      // Termisol projects
      WorkspaceProfile(
        path: '/home/house/termisol',
        name: 'Termisol',
        type: WorkspaceType.flutter,
        languages: ['dart'],
        frameworks: ['flutter'],
        buildSystem: BuildSystem.flutter,
        description: 'Flutter terminal emulator application',
        tools: ['flutter', 'dart', 'git'],
        commands: {
          'run': 'flutter run',
          'build': 'flutter build apk',
          'test': 'flutter test',
          'clean': 'flutter clean',
        },
      ),
      
      // General development
      WorkspaceProfile(
        path: '/home/house/workspace',
        name: 'Workspace',
        type: WorkspaceType.general,
        languages: ['python', 'javascript', 'go', 'rust'],
        frameworks: [],
        buildSystem: BuildSystem.make,
        description: 'General development workspace',
        tools: ['git', 'make', 'gcc', 'python3'],
        commands: {
          'build': 'make',
          'test': 'make test',
          'clean': 'make clean',
        },
      ),
      
      // Home directory
      WorkspaceProfile(
        path: '/home/house',
        name: 'Home',
        type: WorkspaceType.personal,
        languages: ['bash', 'python'],
        frameworks: [],
        buildSystem: BuildSystem.none,
        description: 'Personal home directory',
        tools: ['git', 'vim', 'nano'],
        commands: {
          'edit': 'vim',
          'list': 'ls -la',
        },
      ),
    ];
    
    for (final profile in defaultProfiles) {
      _knownWorkspaces[profile.path] = profile;
    }
    
    await _saveWorkspaceProfiles();
  }
  
  /// Save workspace profiles
  Future<void> _saveWorkspaceProfiles() async {
    try {
      final profilesData = _knownWorkspaces.values.map((p) => p.toJson()).toList();
      final data = {
        'version': '1.0',
        'profiles': profilesData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final profilesFile = File('${Platform.environment['HOME']}/.termisol/workspace_profiles.json');
      await profilesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save workspace profiles: $e');
    }
  }
  
  /// Detect current workspace
  Future<void> _detectCurrentWorkspace() async {
    try {
      final currentDir = Directory.current;
      
      // Check if we're in a known workspace
      if (_knownWorkspaces.containsKey(currentDir.path)) {
        _currentWorkspace = currentDir.path;
        _currentProfile = _knownWorkspaces[currentDir.path]!;
        _onWorkspaceDetected.forEach((callback) => callback(_currentProfile));
        return;
      }
      
      // Analyze current directory to create profile
      final profile = await _analyzeWorkspace(currentDir);
      
      _currentWorkspace = currentDir.path;
      _currentProfile = profile;
      _knownWorkspaces[currentDir.path] = profile;
      
      await _saveWorkspaceProfiles();
      
      _onWorkspaceDetected.forEach((callback) => callback(_currentProfile));
      debugPrint('🔍 Detected workspace: ${profile.name} (${profile.type})');
    } catch (e) {
      debugPrint('⚠️ Failed to detect current workspace: $e');
    }
  }
  
  /// Analyze workspace directory
  Future<WorkspaceProfile> _analyzeWorkspace(Directory directory) async {
    final profile = WorkspaceProfile(
      path: directory.path,
      name: path.basename(directory.path),
      type: WorkspaceType.general,
      languages: [],
      frameworks: [],
      buildSystem: BuildSystem.none,
      description: 'Auto-detected workspace',
      tools: [],
      commands: {},
    );
    
    // Detect project type from files
    await _detectProjectType(directory, profile);
    
    // Detect languages from file extensions
    await _detectLanguages(directory, profile);
    
    // Detect frameworks from configuration files
    await _detectFrameworks(directory, profile);
    
    // Detect build system
    await _detectBuildSystem(directory, profile);
    
    // Detect tools from PATH and local files
    await _detectTools(directory, profile);
    
    // Generate intelligent commands
    await _generateCommands(directory, profile);
    
    return profile;
  }
  
  /// Detect project type
  Future<void> _detectProjectType(Directory directory, WorkspaceProfile profile) async {
    try {
      final files = await directory.list().toList();
      final fileNames = files.map((f) => path.basename(f.path)).toList();
      
      // Flutter/Dart projects
      if (fileNames.contains('pubspec.yaml')) {
        profile.type = WorkspaceType.flutter;
        profile.description = 'Flutter/Dart project';
        
        // Check if it's a Flutter app or package
        final pubspecFile = File(path.join(directory.path, 'pubspec.yaml'));
        if (await pubspecFile.exists()) {
          final content = await pubspecFile.readAsString();
          if (content.contains('flutter:') || content.contains('sdk: flutter')) {
            profile.description = 'Flutter application';
          } else {
            profile.description = 'Dart package';
          }
        }
        return;
      }
      
      // Node.js projects
      if (fileNames.contains('package.json')) {
        profile.type = WorkspaceType.nodejs;
        profile.description = 'Node.js project';
        return;
      }
      
      // Python projects
      if (fileNames.contains('requirements.txt') || 
          fileNames.contains('setup.py') || 
          fileNames.contains('pyproject.toml')) {
        profile.type = WorkspaceType.python;
        profile.description = 'Python project';
        return;
      }
      
      // Rust projects
      if (fileNames.contains('Cargo.toml')) {
        profile.type = WorkspaceType.rust;
        profile.description = 'Rust project';
        return;
      }
      
      // Go projects
      if (fileNames.contains('go.mod')) {
        profile.type = WorkspaceType.go;
        profile.description = 'Go project';
        return;
      }
      
      // Git repositories
      if (fileNames.contains('.git')) {
        profile.description = 'Git repository';
      }
      
      // Docker projects
      if (fileNames.contains('Dockerfile') || fileNames.contains('docker-compose.yml')) {
        profile.description = 'Docker project';
      }
      
    } catch (e) {
      debugPrint('⚠️ Failed to detect project type: $e');
    }
  }
  
  /// Detect programming languages
  Future<void> _detectLanguages(Directory directory, WorkspaceProfile profile) async {
    try {
      final languageCounts = <String, int>{};
      
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();
          
          switch (extension) {
            case '.dart':
              languageCounts['dart'] = (languageCounts['dart'] ?? 0) + 1;
              break;
            case '.py':
              languageCounts['python'] = (languageCounts['python'] ?? 0) + 1;
              break;
            case '.js':
              languageCounts['javascript'] = (languageCounts['javascript'] ?? 0) + 1;
              break;
            case '.ts':
              languageCounts['typescript'] = (languageCounts['typescript'] ?? 0) + 1;
              break;
            case '.go':
              languageCounts['go'] = (languageCounts['go'] ?? 0) + 1;
              break;
            case '.rs':
              languageCounts['rust'] = (languageCounts['rust'] ?? 0) + 1;
              break;
            case '.java':
              languageCounts['java'] = (languageCounts['java'] ?? 0) + 1;
              break;
            case '.cpp':
            case '.cc':
              languageCounts['cpp'] = (languageCounts['cpp'] ?? 0) + 1;
              break;
            case '.c':
              languageCounts['c'] = (languageCounts['c'] ?? 0) + 1;
              break;
          }
        }
      }
      
      // Sort by frequency and take top 3
      final sortedLanguages = languageCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..take(3);
      
      profile.languages = sortedLanguages.map((e) => e.key).toList();
      
      // Notify language detection
      for (final language in profile.languages) {
        _onLanguageDetected.forEach((callback) => callback(language));
      }
      
    } catch (e) {
      debugPrint('⚠️ Failed to detect languages: $e');
    }
  }
  
  /// Detect frameworks
  Future<void> _detectFrameworks(Directory directory, WorkspaceProfile profile) async {
    try {
      final frameworks = <String>[];
      
      // Check for framework-specific files
      await for (final entity in directory.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path).toLowerCase();
          
          if (fileName == 'pubspec.yaml') {
            frameworks.add('flutter');
          } else if (fileName == 'package.json') {
            final packageFile = File(entity.path);
            final content = await packageFile.readAsString();
            final packageData = jsonDecode(content);
            
            if (packageData['dependencies']?['react'] != null) {
              frameworks.add('react');
            }
            if (packageData['dependencies']?['vue'] != null) {
              frameworks.add('vue');
            }
            if (packageData['dependencies']?['angular'] != null) {
              frameworks.add('angular');
            }
          } else if (fileName == 'composer.json') {
            frameworks.add('laravel'); // Could be other PHP frameworks
          } else if (fileName == 'gemfile') {
            frameworks.add('rails');
          }
        }
      }
      
      profile.frameworks = frameworks;
    } catch (e) {
      debugPrint('⚠️ Failed to detect frameworks: $e');
    }
  }
  
  /// Detect build system
  Future<void> _detectBuildSystem(Directory directory, WorkspaceProfile profile) async {
    try {
      final files = await directory.list().toList();
      final fileNames = files.map((f) => path.basename(f.path)).toList();
      
      if (fileNames.contains('Makefile')) {
        profile.buildSystem = BuildSystem.make;
      } else if (fileNames.contains('CMakeLists.txt')) {
        profile.buildSystem = BuildSystem.cmake;
      } else if (fileNames.contains('build.gradle') || fileNames.contains('gradlew')) {
        profile.buildSystem = BuildSystem.gradle;
      } else if (fileNames.contains('package.json')) {
        profile.buildSystem = BuildSystem.npm;
      } else if (fileNames.contains('Cargo.toml')) {
        profile.buildSystem = BuildSystem.cargo;
      } else if (fileNames.contains('meson.build')) {
        profile.buildSystem = BuildSystem.meson;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detect build system: $e');
    }
  }
  
  /// Detect available tools
  Future<void> _detectTools(Directory directory, WorkspaceProfile profile) async {
    try {
      final tools = <String>[];
      
      // Check for common development tools
      final commonTools = [
        'git', 'npm', 'yarn', 'pip', 'cargo', 'go', 'flutter', 'dart',
        'python', 'python3', 'node', 'gcc', 'make', 'cmake', 'docker',
        'vim', 'nvim', 'emacs', 'code', 'subl', 'atom',
      ];
      
      for (final tool in commonTools) {
        try {
          final result = await Process.run('which', [tool]);
          if (result.exitCode == 0) {
            tools.add(tool);
          }
        } catch (e) {
          // Tool not found
        }
      }
      
      // Check for local tools
      final localTools = ['flutter', 'dart'];
      for (final tool in localTools) {
        if (tools.contains(tool)) continue;
        
        try {
          final result = await Process.run(tool, ['--version']);
          if (result.exitCode == 0) {
            tools.add(tool);
          }
        } catch (e) {
          // Tool not available
        }
      }
      
      profile.tools = tools;
    } catch (e) {
      debugPrint('⚠️ Failed to detect tools: $e');
    }
  }
  
  /// Generate intelligent commands
  Future<void> _generateCommands(Directory directory, WorkspaceProfile profile) async {
    try {
      final commands = <String, String>{};
      
      // Generate commands based on workspace type
      switch (profile.type) {
        case WorkspaceType.flutter:
          commands.addAll({
            'run': 'flutter run',
            'build': 'flutter build',
            'test': 'flutter test',
            'clean': 'flutter clean',
            'pub': 'flutter pub get',
            'upgrade': 'flutter upgrade',
            'analyze': 'flutter analyze',
            'format': 'dart format .',
            'doctor': 'flutter doctor',
          });
          break;
          
        case WorkspaceType.nodejs:
          commands.addAll({
            'install': 'npm install',
            'run': 'npm run',
            'build': 'npm run build',
            'test': 'npm test',
            'clean': 'npm run clean',
            'start': 'npm start',
            'dev': 'npm run dev',
          });
          break;
          
        case WorkspaceType.python:
          commands.addAll({
            'install': 'pip install -r requirements.txt',
            'run': 'python main.py',
            'test': 'python -m pytest',
            'venv': 'python -m venv venv',
            'activate': 'source venv/bin/activate',
            'freeze': 'pip freeze',
          });
          break;
          
        case WorkspaceType.rust:
          commands.addAll({
            'build': 'cargo build',
            'run': 'cargo run',
            'test': 'cargo test',
            'clean': 'cargo clean',
            'check': 'cargo check',
            'doc': 'cargo doc',
          });
          break;
          
        case WorkspaceType.go:
          commands.addAll({
            'build': 'go build',
            'run': 'go run main.go',
            'test': 'go test',
            'mod': 'go mod tidy',
            'get': 'go get',
          });
          break;
      }
      
      profile.commands = commands;
    } catch (e) {
      debugPrint('⚠️ Failed to generate commands: $e');
    }
  }
  
  /// Start workspace watcher
  void _startWorkspaceWatcher() {
    _watchTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final currentDir = Directory.current;
      
      if (currentDir.path != _currentWorkspace) {
        final oldProfile = _currentProfile;
        await _detectCurrentWorkspace();
        
        final change = WorkspaceChange(
          from: oldProfile.path,
          to: _currentProfile.path,
          fromName: oldProfile.name,
          toName: _currentProfile.name,
          timestamp: DateTime.now(),
        );
        
        _changeHistory.add(change);
        _onWorkspaceChanged.forEach((callback) => callback(_currentProfile));
        
        debugPrint('🔄 Workspace changed: ${oldProfile.name} → ${_currentProfile.name}');
      }
    });
  }
  
  /// Get tool recommendations
  List<ToolRecommendation> getToolRecommendations() {
    final recommendations = <ToolRecommendation>[];
    
    // Recommend missing tools based on workspace type
    switch (_currentProfile.type) {
      case WorkspaceType.flutter:
        if (!_currentProfile.tools.contains('flutter')) {
          recommendations.add(ToolRecommendation(
            tool: 'flutter',
            reason: 'Flutter SDK is essential for Flutter development',
            priority: RecommendationPriority.critical,
            installCommand: 'sudo snap install flutter --classic',
          ));
        }
        if (!_currentProfile.tools.contains('dart')) {
          recommendations.add(ToolRecommendation(
            tool: 'dart',
            reason: 'Dart SDK is required for Flutter development',
            priority: RecommendationPriority.critical,
            installCommand: 'sudo apt install dart',
          ));
        }
        break;
        
      case WorkspaceType.nodejs:
        if (!_currentProfile.tools.contains('node')) {
          recommendations.add(ToolRecommendation(
            tool: 'node',
            reason: 'Node.js is required for this project',
            priority: RecommendationPriority.critical,
            installCommand: 'sudo apt install nodejs npm',
          ));
        }
        break;
        
      case WorkspaceType.python:
        if (!_currentProfile.tools.contains('python3')) {
          recommendations.add(ToolRecommendation(
            tool: 'python3',
            reason: 'Python 3 is required for this project',
            priority: RecommendationPriority.critical,
            installCommand: 'sudo apt install python3 python3-pip',
          ));
        }
        break;
    }
    
    // Recommend general development tools
    final generalTools = [
      ('git', 'Version control is essential for development'),
      ('vim', 'Powerful terminal editor'),
      ('code', 'VS Code editor'),
    ];
    
    for (final tool in generalTools) {
      if (!_currentProfile.tools.contains(tool.$1)) {
        recommendations.add(ToolRecommendation(
          tool: tool.$1,
          reason: tool.$2,
          priority: RecommendationPriority.recommended,
          installCommand: 'sudo apt install ${tool.$1}',
        ));
      }
    }
    
    // Notify about recommendations
    for (final recommendation in recommendations) {
      _onToolRecommended.forEach((callback) => callback(recommendation));
    }
    
    return recommendations;
  }
  
  /// Get workspace statistics
  Map<String, dynamic> getWorkspaceStatistics() {
    return {
      'current_workspace': _currentWorkspace,
      'workspace_type': _currentProfile.type.toString(),
      'workspace_name': _currentProfile.name,
      'languages': _currentProfile.languages,
      'frameworks': _currentProfile.frameworks,
      'build_system': _currentProfile.buildSystem.toString(),
      'available_tools': _currentProfile.tools,
      'total_commands': _currentProfile.commands.length,
      'known_workspaces': _knownWorkspaces.length,
      'change_history_count': _changeHistory.length,
    };
  }
  
  /// Update workspace profile
  Future<void> updateWorkspaceProfile(WorkspaceProfile profile) async {
    _knownWorkspaces[profile.path] = profile;
    
    if (profile.path == _currentWorkspace) {
      _currentProfile = profile;
    }
    
    await _saveWorkspaceProfiles();
  }
  
  /// Add custom workspace profile
  Future<void> addWorkspaceProfile(WorkspaceProfile profile) async {
    _knownWorkspaces[profile.path] = profile;
    await _saveWorkspaceProfiles();
  }
  
  /// Remove workspace profile
  Future<void> removeWorkspaceProfile(String path) async {
    _knownWorkspaces.remove(path);
    await _saveWorkspaceProfiles();
  }
  
  /// Search workspaces
  List<WorkspaceProfile> searchWorkspaces(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _knownWorkspaces.values.where((profile) {
      return profile.name.toLowerCase().contains(lowerQuery) ||
             profile.description.toLowerCase().contains(lowerQuery) ||
             profile.languages.any((lang) => lang.toLowerCase().contains(lowerQuery)) ||
             profile.frameworks.any((fw) => fw.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Get workspace by path
  WorkspaceProfile? getWorkspaceByPath(String path) {
    return _knownWorkspaces[path];
  }
  
  /// Add workspace detected listener
  void addWorkspaceDetectedListener(Function(WorkspaceProfile) listener) {
    _onWorkspaceDetected.add(listener);
  }
  
  /// Add workspace changed listener
  void addWorkspaceChangedListener(Function(WorkspaceProfile) listener) {
    _onWorkspaceChanged.add(listener);
  }
  
  /// Add tool recommended listener
  void addToolRecommendedListener(Function(ToolRecommendation) listener) {
    _onToolRecommended.add(listener);
  }
  
  /// Add language detected listener
  void addLanguageDetectedListener(Function(String) listener) {
    _onLanguageDetected.add(listener);
  }
  
  /// Remove workspace detected listener
  void removeWorkspaceDetectedListener(Function(WorkspaceProfile) listener) {
    _onWorkspaceDetected.remove(listener);
  }
  
  /// Remove workspace changed listener
  void removeWorkspaceChangedListener(Function(WorkspaceProfile) listener) {
    _onWorkspaceChanged.remove(listener);
  }
  
  /// Remove tool recommended listener
  void removeToolRecommendedListener(Function(ToolRecommendation) listener) {
    _onToolRecommended.remove(listener);
  }
  
  /// Remove language detected listener
  void removeLanguageDetectedListener(Function(String) listener) {
    _onLanguageDetected.remove(listener);
  }
  
  /// Dispose workspace detector
  Future<void> dispose() async {
    _watchTimer?.cancel();
    
    // Save final state
    await _saveWorkspaceProfiles();
    
    // Clear listeners
    _onWorkspaceDetected.clear();
    _onWorkspaceChanged.clear();
    _onToolRecommended.clear();
    _onLanguageDetected.clear();
    
    _isInitialized = false;
    debugPrint('🔍 Intelligent Workspace Detector disposed');
  }
}

/// Workspace types
enum WorkspaceType {
  flutter,
  nodejs,
  python,
  rust,
  go,
  java,
  cpp,
  general,
  personal,
}

/// Build systems
enum BuildSystem {
  none,
  make,
  cmake,
  gradle,
  npm,
  cargo,
  meson,
  flutter,
}

/// Recommendation priorities
enum RecommendationPriority {
  critical,
  recommended,
  optional,
}

/// Workspace profile model
class WorkspaceProfile {
  final String path;
  final String name;
  final String description;
  final WorkspaceType type;
  final List<String> languages;
  final List<String> frameworks;
  final BuildSystem buildSystem;
  final List<String> tools;
  final Map<String, String> commands;
  final DateTime? lastModified;
  final Map<String, dynamic>? metadata;
  
  WorkspaceProfile({
    required this.path,
    required this.name,
    required this.description,
    required this.type,
    required this.languages,
    required this.frameworks,
    required this.buildSystem,
    required this.tools,
    required this.commands,
    this.lastModified,
    this.metadata,
  });
  
  factory WorkspaceProfile.fromJson(Map<String, dynamic> json) {
    return WorkspaceProfile(
      path: json['path'],
      name: json['name'],
      description: json['description'],
      type: WorkspaceType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => WorkspaceType.general,
      ),
      languages: List<String>.from(json['languages'] ?? []),
      frameworks: List<String>.from(json['frameworks'] ?? []),
      buildSystem: BuildSystem.values.firstWhere(
        (b) => b.toString() == json['build_system'],
        orElse: () => BuildSystem.none,
      ),
      tools: List<String>.from(json['tools'] ?? []),
      commands: Map<String, String>.from(json['commands'] ?? {}),
      lastModified: json['last_modified'] != null 
          ? DateTime.parse(json['last_modified'])
          : null,
      metadata: json['metadata'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'description': description,
      'type': type.toString(),
      'languages': languages,
      'frameworks': frameworks,
      'build_system': buildSystem.toString(),
      'tools': tools,
      'commands': commands,
      'last_modified': lastModified?.toIso8601String(),
      'metadata': metadata,
    };
  }
  
  WorkspaceProfile copyWith({
    String? path,
    String? name,
    String? description,
    WorkspaceType? type,
    List<String>? languages,
    List<String>? frameworks,
    BuildSystem? buildSystem,
    List<String>? tools,
    Map<String, String>? commands,
    DateTime? lastModified,
    Map<String, dynamic>? metadata,
  }) {
    return WorkspaceProfile(
      path: path ?? this.path,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      languages: languages ?? this.languages,
      frameworks: frameworks ?? this.frameworks,
      buildSystem: buildSystem ?? this.buildSystem,
      tools: tools ?? this.tools,
      commands: commands ?? this.commands,
      lastModified: lastModified ?? this.lastModified,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Workspace change event
class WorkspaceChange {
  final String from;
  final String to;
  final String fromName;
  final String toName;
  final DateTime timestamp;
  
  WorkspaceChange({
    required this.from,
    required this.to,
    required this.fromName,
    required this.toName,
    required this.timestamp,
  });
}

/// Tool recommendation model
class ToolRecommendation {
  final String tool;
  final String reason;
  final RecommendationPriority priority;
  final String? installCommand;
  final String? version;
  final String? website;
  
  ToolRecommendation({
    required this.tool,
    required this.reason,
    required this.priority,
    this.installCommand,
    this.version,
    this.website,
  });
}
