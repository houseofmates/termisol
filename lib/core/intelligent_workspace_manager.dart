import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart';

/// Intelligent workspace manager with adaptive organization
/// 
/// Features:
/// - Smart workspace organization
/// - Project-based workspace management
/// - Contextual workspace switching
/// - Workspace analytics and optimization
/// - Automated workspace cleanup
class IntelligentWorkspaceManager {
  final StreamController<WorkspaceEvent> _eventController = StreamController<WorkspaceEvent>.broadcast();
  
  final Map<String, Workspace> _workspaces = {};
  final Map<String, ProjectInfo> _projects = {};
  final Map<String, WorkspaceUsage> _usageStats = {};
  final Map<String, WorkspacePattern> _patterns = {};
  final List<WorkspaceRecommendation> _recommendations = [];
  
  Timer? _analyticsTimer;
  Timer? _cleanupTimer;
  Timer? _patternAnalysisTimer;
  bool _isInitialized = false;
  String _currentWorkspace = 'default';
  late SharedPreferences _prefs;
  
  Stream<WorkspaceEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  String get currentWorkspace => _currentWorkspace;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load workspace data
      await _loadWorkspaceData();
      
      // Initialize default workspaces
      _initializeDefaultWorkspaces();
      
      // Discover projects
      await _discoverProjects();
      
      // Start analytics
      _startWorkspaceAnalytics();
      
      // Start cleanup
      _startWorkspaceCleanup();
      
      // Start pattern analysis
      _startPatternAnalysis();
      
      _isInitialized = true;
      
      _eventController.add(WorkspaceEvent(
        type: WorkspaceEventType.initialized,
        message: 'Intelligent workspace manager initialized',
        data: {
          'workspaces': _workspaces.length,
          'projects': _projects.length,
        },
      ));
      
      debugPrint('🏢 Intelligent Workspace Manager initialized');
    } catch (e) {
      debugPrint('Failed to initialize intelligent workspace manager: $e');
    }
  }
  
  Future<void> _loadWorkspaceData() async {
    try {
      final workspacesJson = _prefs.getString('workspaces');
      if (workspacesJson != null) {
        final workspacesMap = jsonDecode(workspacesJson);
        _workspaces = workspacesMap.map((key, value) => 
          MapEntry(key, Workspace.fromJson(value)));
      }
      
      final projectsJson = _prefs.getString('projects');
      if (projectsJson != null) {
        final projectsMap = jsonDecode(projectsJson);
        _projects = projectsMap.map((key, value) => 
          MapEntry(key, ProjectInfo.fromJson(value)));
      }
      
      final usageJson = _prefs.getString('workspace_usage');
      if (usageJson != null) {
        final usageMap = jsonDecode(usageJson);
        _usageStats = usageMap.map((key, value) => 
          MapEntry(key, WorkspaceUsage.fromJson(value)));
      }
      
      final patternsJson = _prefs.getString('workspace_patterns');
      if (patternsJson != null) {
        final patternsMap = jsonDecode(patternsJson);
        _patterns = patternsMap.map((key, value) => 
          MapEntry(key, WorkspacePattern.fromJson(value)));
      }
      
      _currentWorkspace = _prefs.getString('current_workspace') ?? 'default';
    } catch (e) {
      debugPrint('Failed to load workspace data: $e');
    }
  }
  
  void _initializeDefaultWorkspaces() {
    // Default workspace
    _workspaces['default'] = Workspace(
      id: 'default',
      name: 'Default',
      description: 'Default workspace for general use',
      path: Platform.environment['HOME'] ?? '',
      type: WorkspaceType.general,
      projects: [],
      tools: ['terminal', 'file_manager', 'text_editor'],
      environment: {
        'TERM': 'xterm-256color',
        'EDITOR': 'nano',
        'BROWSER': 'firefox',
      },
      layout: WorkspaceLayout.grid,
      autoCleanup: true,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
    
    // Development workspace
    _workspaces['development'] = Workspace(
      id: 'development',
      name: 'Development',
      description: 'Workspace for development projects',
      path: '${Platform.environment['HOME'] ?? ''}/Development',
      type: WorkspaceType.development,
      projects: [],
      tools: ['terminal', 'code_editor', 'git', 'docker', 'database'],
      environment: {
        'TERM': 'xterm-256color',
        'EDITOR': 'vim',
        'BROWSER': 'firefox',
        'NODE_ENV': 'development',
        'PYTHONPATH': '${Platform.environment['HOME'] ?? ''}/Development/lib',
      },
      layout: WorkspaceLayout.split,
      autoCleanup: false,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
    
    // Design workspace
    _workspaces['design'] = Workspace(
      id: 'design',
      name: 'Design',
      description: 'Workspace for design and creative work',
      path: '${Platform.environment['HOME'] ?? ''}/Design',
      type: WorkspaceType.design,
      projects: [],
      tools: ['terminal', 'file_manager', 'graphics_editor', 'image_viewer'],
      environment: {
        'TERM': 'xterm-256color',
        'EDITOR': 'nano',
        'BROWSER': 'firefox',
        'GIMP': 'enabled',
      },
      layout: WorkspaceLayout.tabs,
      autoCleanup: true,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
    
    // Research workspace
    _workspaces['research'] = Workspace(
      id: 'research',
      name: 'Research',
      description: 'Workspace for research and documentation',
      path: '${Platform.environment['HOME'] ?? ''}/Research',
      type: WorkspaceType.research,
      projects: [],
      tools: ['terminal', 'file_manager', 'browser', 'note_taking', 'pdf_viewer'],
      environment: {
        'TERM': 'xterm-256color',
        'EDITOR': 'nano',
        'BROWSER': 'firefox',
        'RESEARCH_MODE': 'enabled',
      },
      layout: WorkspaceLayout.columns,
      autoCleanup: true,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
  }
  
  Future<void> _discoverProjects() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final devDir = '$homeDir/Development';
      
      if (await Directory(devDir).exists()) {
        final result = await run('find', [devDir, '-maxdepth', '2', '-type', 'd']);
        final lines = result.stdout.split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          final dir = Directory(line);
          final dirName = dir.path.split('/').last;
          
          // Check if it's a project directory
          if (await _isProjectDirectory(dir)) {
            final projectInfo = await _analyzeProject(dir);
            _projects[projectInfo.id] = projectInfo;
          }
        }
      }
      
      await _saveWorkspaceData();
    } catch (e) {
      debugPrint('Failed to discover projects: $e');
    }
  }
  
  Future<bool> _isProjectDirectory(Directory dir) async {
    try {
      final files = await dir.list().toList();
      
      // Check for common project indicators
      final hasGit = files.any((file) => file.path.endsWith('.git'));
      final hasPackageJson = files.any((file) => file.path.endsWith('package.json'));
      final hasPubspecYaml = files.any((file) => file.path.endsWith('pubspec.yaml'));
      final hasRequirementsTxt = files.any((file) => file.path.endsWith('requirements.txt'));
      final hasCargoToml = files.any((file) => file.path.endsWith('Cargo.toml'));
      final hasGoMod = files.any((file) => file.path.endsWith('go.mod'));
      
      return hasGit || hasPackageJson || hasPubspecYaml || 
             hasRequirementsTxt || hasCargoToml || hasGoMod;
    } catch (e) {
      return false;
    }
  }
  
  Future<ProjectInfo> _analyzeProject(Directory projectDir) async {
    try {
      final dirName = projectDir.path.split('/').last;
      final files = await projectDir.list().toList();
      
      // Determine project type
      ProjectType type = ProjectType.unknown;
      String language = 'unknown';
      
      if (files.any((file) => file.path.endsWith('pubspec.yaml'))) {
        type = ProjectType.dart;
        language = 'dart';
      } else if (files.any((file) => file.path.endsWith('package.json'))) {
        type = ProjectType.javascript;
        language = 'javascript';
      } else if (files.any((file) => file.path.endsWith('requirements.txt'))) {
        type = ProjectType.python;
        language = 'python';
      } else if (files.any((file) => file.path.endsWith('Cargo.toml'))) {
        type = ProjectType.rust;
        language = 'rust';
      } else if (files.any((file) => file.path.endsWith('go.mod'))) {
        type = ProjectType.golang;
        language = 'go';
      }
      
      // Get project stats
      final stats = await _getProjectStats(projectDir);
      
      return ProjectInfo(
        id: 'project_${DateTime.now().millisecondsSinceEpoch}',
        name: dirName,
        path: projectDir.path,
        type: type,
        language: language,
        files: stats.fileCount,
        size: stats.totalSize,
        lastModified: stats.lastModified,
        createdAt: stats.createdAt,
        tags: _generateProjectTags(files, type),
        dependencies: await _getProjectDependencies(projectDir, type),
      );
    } catch (e) {
      return ProjectInfo(
        id: 'project_${DateTime.now().millisecondsSinceEpoch}',
        name: projectDir.path.split('/').last,
        path: projectDir.path,
        type: ProjectType.unknown,
        language: 'unknown',
        files: 0,
        size: 0.0,
        lastModified: DateTime.now(),
        createdAt: DateTime.now(),
        tags: [],
        dependencies: [],
      );
    }
  }
  
  Future<ProjectStats> _getProjectStats(Directory projectDir) async {
    try {
      int fileCount = 0;
      double totalSize = 0.0;
      DateTime? lastModified;
      DateTime? createdAt;
      
      await for (final entity in projectDir.list(recursive: true)) {
        if (entity is File) {
          fileCount++;
          final stat = await entity.stat();
          totalSize += stat.size;
          
          if (lastModified == null || stat.modified.isAfter(lastModified!)) {
            lastModified = stat.modified;
          }
          
          if (createdAt == null || stat.accessed.isBefore(createdAt!)) {
            createdAt = stat.accessed;
          }
        }
      }
      
      return ProjectStats(
        fileCount: fileCount,
        totalSize: totalSize / (1024 * 1024 * 1024), // Convert to GB
        lastModified: lastModified ?? DateTime.now(),
        createdAt: createdAt ?? DateTime.now(),
      );
    } catch (e) {
      return ProjectStats(
        fileCount: 0,
        totalSize: 0.0,
        lastModified: DateTime.now(),
        createdAt: DateTime.now(),
      );
    }
  }
  
  List<String> _generateProjectTags(List<FileSystemEntity> files, ProjectType type) {
    final tags = <String>[];
    
    // Add type-specific tags
    switch (type) {
      case ProjectType.dart:
        tags.addAll(['dart', 'flutter', 'mobile']);
        break;
      case ProjectType.javascript:
        tags.addAll(['javascript', 'node', 'web']);
        break;
      case ProjectType.python:
        tags.addAll(['python', 'data-science', 'ml']);
        break;
      case ProjectType.rust:
        tags.addAll(['rust', 'systems', 'performance']);
        break;
      case ProjectType.golang:
        tags.addAll(['go', 'backend', 'microservices']);
        break;
      default:
        break;
    }
    
    // Add framework-specific tags
    if (files.any((file) => file.path.contains('react'))) {
      tags.add('react');
    }
    if (files.any((file) => file.path.contains('vue'))) {
      tags.add('vue');
    }
    if (files.any((file) => file.path.contains('angular'))) {
      tags.add('angular');
    }
    
    return tags.toSet().toList();
  }
  
  Future<List<String>> _getProjectDependencies(Directory projectDir, ProjectType type) async {
    try {
      final dependencies = <String>[];
      
      switch (type) {
        case ProjectType.dart:
          final pubspecFile = File('${projectDir.path}/pubspec.yaml');
          if (await pubspecFile.exists()) {
            final content = await pubspecFile.readAsString();
            final depsMatch = RegExp(r'dependencies:\s*\n((?:\s*[\w-]+:\s*[\d.]+)+)').firstMatch(content);
            if (depsMatch != null) {
              dependencies.addAll(depsMatch.group(1)!.split('\n').where((line) => line.trim().isNotEmpty));
            }
          }
          break;
          
        case ProjectType.javascript:
          final packageJsonFile = File('${projectDir.path}/package.json');
          if (await packageJsonFile.exists()) {
            final content = await packageJsonFile.readAsString();
            final jsonContent = jsonDecode(content);
            if (jsonContent['dependencies'] != null) {
              dependencies.addAll((jsonContent['dependencies'] as Map).keys.cast<String>());
            }
          }
          break;
          
        case ProjectType.python:
          final requirementsFile = File('${projectDir.path}/requirements.txt');
          if (await requirementsFile.exists()) {
            final content = await requirementsFile.readAsString();
            dependencies.addAll(content.split('\n').where((line) => line.trim().isNotEmpty));
          }
          break;
          
        default:
          break;
      }
      
      return dependencies;
    } catch (e) {
      return [];
    }
  }
  
  void _startWorkspaceAnalytics() {
    _analyticsTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _collectWorkspaceUsage();
    });
  }
  
  void _startWorkspaceCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _performWorkspaceCleanup();
    });
  }
  
  void _startPatternAnalysis() {
    _patternAnalysisTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _analyzeWorkspacePatterns();
    });
  }
  
  Future<void> _collectWorkspaceUsage() async {
    try {
      final timestamp = DateTime.now();
      
      // Update current workspace usage
      final usage = _usageStats[_currentWorkspace] ?? WorkspaceUsage(
        workspaceId: _currentWorkspace,
        totalTime: 0.0,
        sessionCount: 0,
        lastUsed: timestamp,
        averageSessionLength: 0.0,
      );
      
      usage.totalTime += 5.0; // 5 minutes since last collection
      usage.lastUsed = timestamp;
      usage.sessionCount++;
      
      _usageStats[_currentWorkspace] = usage;
      
      // Keep only last 100 usage records per workspace
      if (_usageStats.length > 100) {
        final keys = _usageStats.keys.toList();
        // Sort by last used and remove oldest
        keys.sort((a, b) => 
            _usageStats[a]!.lastUsed.compareTo(_usageStats[b]!.lastUsed));
        
        final toRemove = keys.take(_usageStats.length - 100);
        for (final key in toRemove) {
          _usageStats.remove(key);
        }
      }
      
    } catch (e) {
      debugPrint('Failed to collect workspace usage: $e');
    }
  }
  
  Future<void> _performWorkspaceCleanup() async {
    try {
      final workspace = _workspaces[_currentWorkspace];
      if (workspace == null || !workspace.autoCleanup) return;
      
      final workspaceDir = Directory(workspace.path);
      if (!await workspaceDir.exists()) return;
      
      // Clean temporary files
      await _cleanupTempFiles(workspaceDir);
      
      // Clean old logs
      await _cleanupOldLogs(workspaceDir);
      
      // Clean cache files
      await _cleanupCacheFiles(workspaceDir);
      
      _eventController.add(WorkspaceEvent(
        type: WorkspaceEventType.cleanup_completed,
        message: 'Workspace cleanup completed: ${workspace.name}',
        data: {'workspaceId': workspace.id},
      ));
      
    } catch (e) {
      debugPrint('Failed to perform workspace cleanup: $e');
    }
  }
  
  Future<void> _cleanupTempFiles(Directory workspaceDir) async {
    try {
      final tempPatterns = ['*.tmp', '*.temp', '*.swp', '*~', '.DS_Store'];
      
      for (final pattern in tempPatterns) {
        await run('find', [workspaceDir.path, '-name', pattern, '-delete']);
      }
    } catch (e) {
      debugPrint('Failed to cleanup temp files: $e');
    }
  }
  
  Future<void> _cleanupOldLogs(Directory workspaceDir) async {
    try {
      final logFiles = await workspaceDir.list().where((entity) => 
          entity is File && entity.path.endsWith('.log')).toList();
      
      for (final logFile in logFiles) {
        final stat = await logFile.stat();
        if (DateTime.now().difference(stat.modified).inDays > 7) {
          await logFile.delete();
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup old logs: $e');
    }
  }
  
  Future<void> _cleanupCacheFiles(Directory workspaceDir) async {
    try {
      final cacheDirs = [
        Directory('${workspaceDir.path}/.cache'),
        Directory('${workspaceDir.path}/node_modules/.cache'),
        Directory('${workspaceDir.path}/.dart_tool/cache'),
      ];
      
      for (final cacheDir in cacheDirs) {
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list()) {
            if (await entity.exists()) {
              await entity.delete(recursive: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup cache files: $e');
    }
  }
  
  Future<void> _analyzeWorkspacePatterns() async {
    try {
      for (final workspaceId in _workspaces.keys) {
        final usage = _usageStats[workspaceId];
        if (usage == null) continue;
        
        // Analyze usage patterns
        final pattern = await _analyzeUsagePattern(workspaceId, usage);
        _patterns[workspaceId] = pattern;
      }
      
      // Generate recommendations
      await _generateWorkspaceRecommendations();
      
      await _saveWorkspaceData();
    } catch (e) {
      debugPrint('Failed to analyze workspace patterns: $e');
    }
  }
  
  Future<WorkspacePattern> _analyzeUsagePattern(String workspaceId, WorkspaceUsage usage) async {
    try {
      // Determine peak usage times
      final peakHour = _calculatePeakUsageHour(workspaceId);
      final averageSession = usage.totalTime / usage.sessionCount;
      
      // Determine usage frequency
      final daysSinceLastUse = DateTime.now().difference(usage.lastUsed).inDays;
      UsageFrequency frequency;
      if (daysSinceLastUse < 1) {
        frequency = UsageFrequency.daily;
      } else if (daysSinceLastUse < 7) {
        frequency = UsageFrequency.weekly;
      } else if (daysSinceLastUse < 30) {
        frequency = UsageFrequency.monthly;
      } else {
        frequency = UsageFrequency.rarely;
      }
      
      return WorkspacePattern(
        workspaceId: workspaceId,
        peakUsageHour: peakHour,
        averageSessionLength: averageSession,
        usageFrequency: frequency,
        preferredTools: await _getPreferredTools(workspaceId),
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return WorkspacePattern(
        workspaceId: workspaceId,
        peakUsageHour: 12,
        averageSessionLength: 30.0,
        usageFrequency: UsageFrequency.unknown,
        preferredTools: [],
        createdAt: DateTime.now(),
      );
    }
  }
  
  int _calculatePeakUsageHour(String workspaceId) {
    // Simplified peak hour calculation
    // In a real implementation, this would analyze actual usage timestamps
    return 14; // 2 PM as default
  }
  
  Future<List<String>> _getPreferredTools(String workspaceId) async {
    try {
      final workspace = _workspaces[workspaceId];
      if (workspace == null) return [];
      
      // Analyze which tools are most used in this workspace
      // This is a simplified implementation
      return workspace.tools.take(3).toList();
    } catch (e) {
      return [];
    }
  }
  
  Future<void> _generateWorkspaceRecommendations() async {
    try {
      _recommendations.clear();
      
      for (final pattern in _patterns.values) {
        final workspace = _workspaces[pattern.workspaceId];
        if (workspace == null) continue;
        
        // Generate recommendations based on patterns
        if (pattern.averageSessionLength > 120) { // More than 2 hours
          _recommendations.add(WorkspaceRecommendation(
            id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
            type: RecommendationType.optimize_workspace,
            title: 'Optimize ${workspace.name} Workspace',
            description: 'Your sessions in ${workspace.name} are longer than average. Consider optimizing the workspace layout.',
            priority: RecommendationPriority.medium,
            workspaceId: pattern.workspaceId,
            createdAt: DateTime.now(),
          ));
        }
        
        if (pattern.usageFrequency == UsageFrequency.daily) {
          _recommendations.add(WorkspaceRecommendation(
            id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
            type: RecommendationType.create_shortcut,
            title: 'Create Shortcut for ${workspace.name}',
            description: 'You use ${workspace.name} daily. Consider creating a desktop shortcut for quick access.',
            priority: RecommendationPriority.high,
            workspaceId: pattern.workspaceId,
            createdAt: DateTime.now(),
          ));
        }
        
        if (workspace.projects.length > 10) {
          _recommendations.add(WorkspaceRecommendation(
            id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
            type: RecommendationType.organize_projects,
            title: 'Organize Projects in ${workspace.name}',
            description: 'Consider organizing projects in ${workspace.name} into subdirectories for better management.',
            priority: RecommendationPriority.low,
            workspaceId: pattern.workspaceId,
            createdAt: DateTime.now(),
          ));
        }
      }
      
      _eventController.add(WorkspaceEvent(
        type: WorkspaceEventType.recommendations_generated,
        message: 'Generated ${_recommendations.length} workspace recommendations',
        data: {
          'recommendations': _recommendations.map((r) => r.toJson()).toList(),
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to generate workspace recommendations: $e');
    }
  }
  
  Future<void> switchWorkspace(String workspaceId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    
    try {
      _currentWorkspace = workspaceId;
      
      // Apply workspace environment
      await _applyWorkspaceEnvironment(workspace);
      
      // Update usage stats
      final usage = _usageStats[workspaceId] ?? WorkspaceUsage(
        workspaceId: workspaceId,
        totalTime: 0.0,
        sessionCount: 0,
        lastUsed: DateTime.now(),
        averageSessionLength: 0.0,
      );
      
      usage.lastUsed = DateTime.now();
      usage.sessionCount++;
      _usageStats[workspaceId] = usage;
      
      // Save current workspace
      await _prefs.setString('current_workspace', workspaceId);
      
      _eventController.add(WorkspaceEvent(
        type: WorkspaceEventType.workspace_switched,
        message: 'Switched to workspace: ${workspace.name}',
        data: {
          'workspaceId': workspaceId,
          'workspaceName': workspace.name,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to switch workspace: $e');
    }
  }
  
  Future<void> _applyWorkspaceEnvironment(Workspace workspace) async {
    try {
      // Set environment variables
      for (final entry in workspace.environment.entries) {
        await run('export', ['${entry.key}="${entry.value}"']);
      }
      
      // Change to workspace directory
      await run('cd', [workspace.path]);
      
      // Open workspace tools
      for (final tool in workspace.tools) {
        await _openWorkspaceTool(tool, workspace);
      }
      
    } catch (e) {
      debugPrint('Failed to apply workspace environment: $e');
    }
  }
  
  Future<void> _openWorkspaceTool(String tool, Workspace workspace) async {
    try {
      switch (tool) {
        case 'terminal':
          // Terminal is already open
          break;
        case 'file_manager':
          await run('nautilus', [workspace.path]);
          break;
        case 'code_editor':
          await run('code', [workspace.path]);
          break;
        case 'browser':
          await run('firefox', [workspace.path]);
          break;
        case 'git':
          await run('git', ['status'], workingDirectory: workspace.path);
          break;
        case 'docker':
          await run('docker', ['ps'], workingDirectory: workspace.path);
          break;
        case 'database':
          // Open database client
          break;
        default:
          debugPrint('Unknown workspace tool: $tool');
      }
    } catch (e) {
      debugPrint('Failed to open workspace tool: $e');
    }
  }
  
  Future<void> createWorkspace({
    required String name,
    required String description,
    required String path,
    required WorkspaceType type,
    required List<String> tools,
    Map<String, String> environment = const {},
    WorkspaceLayout layout = WorkspaceLayout.grid,
    bool autoCleanup = true,
  }) async {
    final workspaceId = 'workspace_${DateTime.now().millisecondsSinceEpoch}';
    
    final workspace = Workspace(
      id: workspaceId,
      name: name,
      description: description,
      path: path,
      type: type,
      projects: [],
      tools: tools,
      environment: environment,
      layout: layout,
      autoCleanup: autoCleanup,
      createdAt: DateTime.now(),
      lastUsed: DateTime.now(),
    );
    
    _workspaces[workspaceId] = workspace;
    await _saveWorkspaceData();
    
    _eventController.add(WorkspaceEvent(
      type: WorkspaceEventType.workspace_created,
      message: 'Workspace created: $name',
      data: {
        'workspaceId': workspaceId,
        'workspaceName': name,
      },
    ));
  }
  
  Future<void> addProjectToWorkspace({
    required String workspaceId,
    required String projectPath,
  }) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) return;
    
    try {
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) return;
      
      final projectInfo = await _analyzeProject(projectDir);
      _projects[projectInfo.id] = projectInfo;
      
      // Add project to workspace
      if (!workspace.projects.contains(projectInfo.id)) {
        workspace.projects.add(projectInfo.id);
      }
      
      await _saveWorkspaceData();
      
      _eventController.add(WorkspaceEvent(
        type: WorkspaceEventType.project_added,
        message: 'Project added to workspace: ${projectInfo.name}',
        data: {
          'projectId': projectInfo.id,
          'projectName': projectInfo.name,
          'workspaceId': workspaceId,
        },
      ));
      
    } catch (e) {
      debugPrint('Failed to add project to workspace: $e');
    }
  }
  
  Future<void> _saveWorkspaceData() async {
    try {
      final workspacesMap = _workspaces.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('workspaces', jsonEncode(workspacesMap));
      
      final projectsMap = _projects.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('projects', jsonEncode(projectsMap));
      
      final usageMap = _usageStats.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('workspace_usage', jsonEncode(usageMap));
      
      final patternsMap = _patterns.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('workspace_patterns', jsonEncode(patternsMap));
    } catch (e) {
      debugPrint('Failed to save workspace data: $e');
    }
  }
  
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'currentWorkspace': _currentWorkspace,
      'totalWorkspaces': _workspaces.length,
      'totalProjects': _projects.length,
      'totalUsageStats': _usageStats.length,
      'totalPatterns': _patterns.length,
      'totalRecommendations': _recommendations.length,
      'projectsByType': _getProjectsByType(),
      'workspacesByType': _getWorkspacesByType(),
    };
  }
  
  Map<String, int> _getProjectsByType() {
    final typeCount = <String, int>{};
    
    for (final project in _projects.values) {
      final typeName = project.type.name;
      typeCount[typeName] = (typeCount[typeName] ?? 0) + 1;
    }
    
    return typeCount;
  }
  
  Map<String, int> _getWorkspacesByType() {
    final typeCount = <String, int>{};
    
    for (final workspace in _workspaces.values) {
      final typeName = workspace.type.name;
      typeCount[typeName] = (typeCount[typeName] ?? 0) + 1;
    }
    
    return typeCount;
  }
  
  Future<void> dispose() async {
    _analyticsTimer?.cancel();
    _cleanupTimer?.cancel();
    _patternAnalysisTimer?.cancel();
    
    await _saveWorkspaceData();
    
    _eventController.close();
    debugPrint('🏢 Intelligent Workspace Manager disposed');
  }
}

// Data models
class Workspace {
  final String id;
  final String name;
  final String description;
  final String path;
  final WorkspaceType type;
  final List<String> projects;
  final List<String> tools;
  final Map<String, String> environment;
  final WorkspaceLayout layout;
  final bool autoCleanup;
  final DateTime createdAt;
  final DateTime lastUsed;
  
  Workspace({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
    required this.type,
    required this.projects,
    required this.tools,
    required this.environment,
    required this.layout,
    required this.autoCleanup,
    required this.createdAt,
    required this.lastUsed,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'path': path,
    'type': type.name,
    'projects': projects,
    'tools': tools,
    'environment': environment,
    'layout': layout.name,
    'autoCleanup': autoCleanup,
    'createdAt': createdAt.toIso8601String(),
    'lastUsed': lastUsed.toIso8601String(),
  };
  
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    path: json['path'],
    type: WorkspaceType.values.firstWhere((t) => t.name == json['type'], orElse: () => WorkspaceType.general),
    projects: (json['projects'] as List<dynamic>?)?.cast<String>() ?? [],
    tools: (json['tools'] as List<dynamic>?)?.cast<String>() ?? [],
    environment: Map<String, String>.from(json['environment'] ?? {}),
    layout: WorkspaceLayout.values.firstWhere((l) => l.name == json['layout'], orElse: () => WorkspaceLayout.grid),
    autoCleanup: json['autoCleanup'] ?? true,
    createdAt: DateTime.parse(json['createdAt']),
    lastUsed: DateTime.parse(json['lastUsed']),
  );
}

class ProjectInfo {
  final String id;
  final String name;
  final String path;
  final ProjectType type;
  final String language;
  final int files;
  final double size;
  final DateTime lastModified;
  final DateTime createdAt;
  final List<String> tags;
  final List<String> dependencies;
  
  ProjectInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.language,
    required this.files,
    required this.size,
    required this.lastModified,
    required this.createdAt,
    required this.tags,
    required this.dependencies,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'type': type.name,
    'language': language,
    'files': files,
    'size': size,
    'lastModified': lastModified.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'tags': tags,
    'dependencies': dependencies,
  };
  
  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
    id: json['id'],
    name: json['name'],
    path: json['path'],
    type: ProjectType.values.firstWhere((t) => t.name == json['type'], orElse: () => ProjectType.unknown),
    language: json['language'],
    files: json['files'] ?? 0,
    size: json['size']?.toDouble() ?? 0.0,
    lastModified: DateTime.parse(json['lastModified']),
    createdAt: DateTime.parse(json['createdAt']),
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    dependencies: (json['dependencies'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

class WorkspaceUsage {
  final String workspaceId;
  double totalTime;
  int sessionCount;
  DateTime lastUsed;
  double averageSessionLength;
  
  WorkspaceUsage({
    required this.workspaceId,
    required this.totalTime,
    required this.sessionCount,
    required this.lastUsed,
    required this.averageSessionLength,
  });
  
  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'totalTime': totalTime,
    'sessionCount': sessionCount,
    'lastUsed': lastUsed.toIso8601String(),
    'averageSessionLength': averageSessionLength,
  };
  
  factory WorkspaceUsage.fromJson(Map<String, dynamic> json) => WorkspaceUsage(
    workspaceId: json['workspaceId'],
    totalTime: json['totalTime']?.toDouble() ?? 0.0,
    sessionCount: json['sessionCount'] ?? 0,
    lastUsed: DateTime.parse(json['lastUsed']),
    averageSessionLength: json['averageSessionLength']?.toDouble() ?? 0.0,
  );
}

class WorkspacePattern {
  final String workspaceId;
  final int peakUsageHour;
  final double averageSessionLength;
  final UsageFrequency usageFrequency;
  final List<String> preferredTools;
  final DateTime createdAt;
  
  WorkspacePattern({
    required this.workspaceId,
    required this.peakUsageHour,
    required this.averageSessionLength,
    required this.usageFrequency,
    required this.preferredTools,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'peakUsageHour': peakUsageHour,
    'averageSessionLength': averageSessionLength,
    'usageFrequency': usageFrequency.name,
    'preferredTools': preferredTools,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory WorkspacePattern.fromJson(Map<String, dynamic> json) => WorkspacePattern(
    workspaceId: json['workspaceId'],
    peakUsageHour: json['peakUsageHour'] ?? 12,
    averageSessionLength: json['averageSessionLength']?.toDouble() ?? 30.0,
    usageFrequency: UsageFrequency.values.firstWhere((f) => f.name == json['usageFrequency'], orElse: () => UsageFrequency.unknown),
    preferredTools: (json['preferredTools'] as List<dynamic>?)?.cast<String>() ?? [],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class WorkspaceRecommendation {
  final String id;
  final RecommendationType type;
  final String title;
  final String description;
  final RecommendationPriority priority;
  final String workspaceId;
  final DateTime createdAt;
  
  WorkspaceRecommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.priority,
    required this.workspaceId,
    required this.createdAt,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'priority': priority.name,
    'workspaceId': workspaceId,
    'createdAt': createdAt.toIso8601String(),
  };
  
  factory WorkspaceRecommendation.fromJson(Map<String, dynamic> json) => WorkspaceRecommendation(
    id: json['id'],
    type: RecommendationType.values.firstWhere((t) => t.name == json['type'], orElse: () => RecommendationType.optimize_workspace),
    title: json['title'],
    description: json['description'],
    priority: RecommendationPriority.values.firstWhere((p) => p.name == json['priority'], orElse: () => RecommendationPriority.medium),
    workspaceId: json['workspaceId'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class ProjectStats {
  final int fileCount;
  final double totalSize;
  final DateTime lastModified;
  final DateTime createdAt;
  
  ProjectStats({
    required this.fileCount,
    required this.totalSize,
    required this.lastModified,
    required this.createdAt,
  });
}

enum WorkspaceType {
  general,
  development,
  design,
  research,
  gaming,
}

enum WorkspaceLayout {
  grid,
  tabs,
  columns,
  floating,
}

enum ProjectType {
  unknown,
  dart,
  javascript,
  python,
  rust,
  golang,
  java,
  cpp,
}

enum UsageFrequency {
  unknown,
  rarely,
  monthly,
  weekly,
  daily,
}

enum RecommendationType {
  optimize_workspace,
  create_shortcut,
  organize_projects,
  add_tool,
  cleanup_workspace,
}

enum RecommendationPriority {
  low,
  medium,
  high,
  critical,
}

enum WorkspaceEventType {
  initialized,
  workspace_created,
  workspace_switched,
  project_added,
  cleanup_completed,
  recommendations_generated,
  error,
}

class WorkspaceEvent {
  final WorkspaceEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  WorkspaceEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}
