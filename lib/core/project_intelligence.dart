import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Project Intelligence and Context - Smart project understanding
class ProjectIntelligence {
  static final ProjectIntelligence _instance = ProjectIntelligence._internal();
  factory ProjectIntelligence() => _instance;
  ProjectIntelligence._internal();

  final Map<String, ProjectContext> _projectContexts = {};
  final Map<String, ProjectMetrics> _projectMetrics = {};
  final Map<String, List<ProjectActivity>> _activityHistory = {};
  final Map<String, ProjectDependencies> _dependencies = {};
  
  bool _isInitialized = false;
  Timer? _analysisTimer;
  String? _currentProjectPath;
  
  static const Duration _analysisInterval = Duration(minutes: 2);
  static const int _maxActivityHistory = 1000;
  
  final _intelligenceController = StreamController<IntelligenceEvent>.broadcast();
  Stream<IntelligenceEvent> get events => _intelligenceController.stream;
  
  bool get isInitialized => _isInitialized;
  String? get currentProjectPath => _currentProjectPath;
  ProjectContext? get currentContext => _currentProjectPath != null ? _projectContexts[_currentProjectPath] : null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startAnalysisTimer();
    _isInitialized = true;
    debugPrint('🧠 Project Intelligence initialized');
  }

  Future<void> analyzeProject(String projectPath) async {
    try {
      final context = await _analyzeProjectContext(projectPath);
      final metrics = await _calculateProjectMetrics(projectPath);
      final dependencies = await _analyzeDependencies(projectPath);
      
      _projectContexts[projectPath] = context;
      _projectMetrics[projectPath] = metrics;
      _dependencies[projectPath] = dependencies;
      _currentProjectPath = projectPath;
      
      _intelligenceController.add(IntelligenceEvent(
        type: IntelligenceEventType.projectAnalyzed,
        data: {
          'project_path': projectPath,
          'project_type': context.type.toString(),
          'language': context.primaryLanguage,
          'files_count': metrics.totalFiles,
        },
      ));
      
      debugPrint('🧠 Analyzed project: ${context.name} (${context.type})');
      
    } catch (e) {
      debugPrint('❌ Failed to analyze project: $e');
    }
  }

  Future<void> recordActivity(ProjectActivity activity) async {
    final activities = _activityHistory.putIfAbsent(activity.projectPath, () => []);
    
    activities.add(activity);
    if (activities.length > _maxActivityHistory) {
      activities.removeAt(0);
    }
    
    // Update project metrics based on activity
    await _updateMetricsFromActivity(activity);
    
    _intelligenceController.add(IntelligenceEvent(
      type: IntelligenceEventType.activityRecorded,
      data: {
        'activity_type': activity.type.toString(),
        'project_path': activity.projectPath,
        'file_path': activity.filePath,
      },
    ));
  }

  ProjectContext? getProjectContext(String projectPath) {
    return _projectContexts[projectPath];
  }

  ProjectMetrics? getProjectMetrics(String projectPath) {
    return _projectMetrics[projectPath];
  }

  List<ProjectSuggestion> getSuggestions(String projectPath) {
    final context = _projectContexts[projectPath];
    final metrics = _projectMetrics[projectPath];
    final activities = _activityHistory[projectPath] ?? [];
    
    if (context == null || metrics == null) return [];
    
    final suggestions = <ProjectSuggestion>[];
    
    // Analyze recent activity for suggestions
    final recentActivities = activities.takeLast(20).toList();
    
    // Suggest based on project type
    suggestions.addAll(_getProjectTypeSuggestions(context));
    
    // Suggest based on code quality
    suggestions.addAll(_getCodeQualitySuggestions(metrics));
    
    // Suggest based on recent activity patterns
    suggestions.addAll(_getActivityBasedSuggestions(recentActivities));
    
    // Suggest based on dependencies
    final dependencies = _dependencies[projectPath];
    if (dependencies != null) {
      suggestions.addAll(_getDependencySuggestions(dependencies));
    }
    
    // Sort by priority
    suggestions.sort((a, b) => b.priority.compareTo(a.priority));
    
    return suggestions.take(10).toList();
  }

  Future<List<String>> getRelatedFiles(String filePath, String projectPath) async {
    final context = _projectContexts[projectPath];
    if (context == null) return [];
    
    final relatedFiles = <String>[];
    final fileDir = path.dirname(filePath);
    final fileName = path.basename(filePath);
    final fileExt = path.extension(filePath);
    
    // Files in same directory
    for (final file in context.files) {
      if (path.dirname(file.path) == fileDir && file.path != filePath) {
        relatedFiles.add(file.path);
      }
    }
    
    // Files with similar names
    for (final file in context.files) {
      final baseName = path.basenameWithoutExtension(file.path);
      final currentBaseName = path.basenameWithoutExtension(filePath);
      
      if (baseName.contains(currentBaseName) || currentBaseName.contains(baseName)) {
        if (!relatedFiles.contains(file.path)) {
          relatedFiles.add(file.path);
        }
      }
    }
    
    // Test files
    for (final file in context.files) {
      if (file.path.contains('test') || file.path.contains('spec')) {
        if (file.path.contains(currentBaseName)) {
          if (!relatedFiles.contains(file.path)) {
            relatedFiles.add(file.path);
          }
        }
      }
    }
    
    return relatedFiles.take(10).toList();
  }

  Future<List<String>> getRecommendedCommands(String projectPath) async {
    final context = _projectContexts[projectPath];
    final activities = _activityHistory[projectPath] ?? [];
    
    if (context == null) return [];
    
    final commands = <String>[];
    
    // Project type specific commands
    switch (context.type) {
      case ProjectType.nodejs:
        commands.addAll(['npm install', 'npm run dev', 'npm test', 'npm run build']);
        break;
      case ProjectType.python:
        commands.addAll(['pip install -r requirements.txt', 'python -m pytest', 'python main.py']);
        break;
      case ProjectType.rust:
        commands.addAll(['cargo build', 'cargo run', 'cargo test', 'cargo check']);
        break;
      case ProjectType.go:
        commands.addAll(['go mod tidy', 'go run .', 'go test ./...', 'go build']);
        break;
      case ProjectType.dart:
        commands.addAll(['dart pub get', 'dart run', 'dart test', 'dart build']);
        break;
      case ProjectType.java:
        commands.addAll(['mvn compile', 'mvn test', 'mvn package', 'mvn clean']);
        break;
      default:
        commands.addAll(['git status', 'ls -la']);
    }
    
    // Recently used commands
    final recentCommands = activities
        .where((a) => a.type == ActivityType.command && a.timestamp.difference(DateTime.now()).inHours < 24)
        .map((a) => a.details['command'] as String)
        .toSet()
        .toList();
    
    commands.addAll(recentCommands);
    
    return commands.toSet().toList();
  }

  Future<ProjectContext> _analyzeProjectContext(String projectPath) async {
    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) {
      throw Exception('Project directory does not exist: $projectPath');
    }
    
    final files = <ProjectFile>[];
    final projectFiles = await projectDir.list(recursive: true).toList();
    
    String primaryLanguage = 'unknown';
    ProjectType projectType = ProjectType.unknown;
    String name = path.basename(projectPath);
    
    for (final file in projectFiles) {
      if (file is File) {
        final filePath = file.path;
        final fileName = path.basename(filePath);
        final fileExt = path.extension(filePath);
        
        files.add(ProjectFile(
          path: filePath,
          name: fileName,
          extension: fileExt,
          size: await file.length(),
          lastModified: await file.lastModified(),
        ));
        
        // Detect project type and language
        if (fileName == 'package.json') {
          projectType = ProjectType.nodejs;
          primaryLanguage = 'javascript';
        } else if (fileName == 'requirements.txt' || fileName == 'pyproject.toml') {
          projectType = ProjectType.python;
          primaryLanguage = 'python';
        } else if (fileName == 'Cargo.toml') {
          projectType = ProjectType.rust;
          primaryLanguage = 'rust';
        } else if (fileName == 'go.mod') {
          projectType = ProjectType.go;
          primaryLanguage = 'go';
        } else if (fileName == 'pubspec.yaml') {
          projectType = ProjectType.dart;
          primaryLanguage = 'dart';
        } else if (fileName == 'pom.xml') {
          projectType = ProjectType.java;
          primaryLanguage = 'java';
        }
      }
    }
    
    // Check for .git directory
    final gitDir = Directory(path.join(projectPath, '.git'));
    final hasGit = await gitDir.exists();
    
    return ProjectContext(
      path: projectPath,
      name: name,
      type: projectType,
      primaryLanguage: primaryLanguage,
      files: files,
      hasGit: hasGit,
      analyzedAt: DateTime.now(),
    );
  }

  Future<ProjectMetrics> _calculateProjectMetrics(String projectPath) async {
    final context = _projectContexts[projectPath];
    if (context == null) {
      return ProjectMetrics(
        totalFiles: 0,
        totalLines: 0,
        codeFiles: 0,
        testFiles: 0,
        configFiles: 0,
        documentationFiles: 0,
        complexity: 'unknown',
        maintainabilityIndex: 0.0,
      );
    }
    
    int totalLines = 0;
    int codeFiles = 0;
    int testFiles = 0;
    int configFiles = 0;
    int documentationFiles = 0;
    
    for (final file in context.files) {
      final isCodeFile = _isCodeFile(file.extension);
      final isTestFile = _isTestFile(file.path);
      final isConfigFile = _isConfigFile(file.name);
      final isDocumentationFile = _isDocumentationFile(file.name);
      
      if (isCodeFile) codeFiles++;
      if (isTestFile) testFiles++;
      if (isConfigFile) configFiles++;
      if (isDocumentationFile) documentationFiles++;
      
      // Count lines
      try {
        final fileContent = await File(file.path).readAsString();
        totalLines += fileContent.split('\n').length;
      } catch (e) {
        // Skip files that can't be read
      }
    }
    
    // Calculate complexity based on file count and lines
    String complexity;
    if (totalLines < 1000) {
      complexity = 'simple';
    } else if (totalLines < 10000) {
      complexity = 'moderate';
    } else {
      complexity = 'complex';
    }
    
    // Calculate maintainability index (simplified)
    final maintainabilityIndex = _calculateMaintainabilityIndex(
      totalLines,
      codeFiles,
      testFiles,
      configFiles,
    );
    
    return ProjectMetrics(
      totalFiles: context.files.length,
      totalLines: totalLines,
      codeFiles: codeFiles,
      testFiles: testFiles,
      configFiles: configFiles,
      documentationFiles: documentationFiles,
      complexity: complexity,
      maintainabilityIndex: maintainabilityIndex,
    );
  }

  Future<ProjectDependencies> _analyzeDependencies(String projectPath) async {
    final dependencies = <String>[];
    final devDependencies = <String>[];
    
    // Check different dependency files
    final packageJson = File(path.join(projectPath, 'package.json'));
    if (await packageJson.exists()) {
      try {
        final content = await packageJson.readAsString();
        final packageData = jsonDecode(content) as Map<String, dynamic>;
        
        final deps = packageData['dependencies'] as Map<String, dynamic>?;
        if (deps != null) {
          dependencies.addAll(deps.keys);
        }
        
        final devDeps = packageData['devDependencies'] as Map<String, dynamic>?;
        if (devDeps != null) {
          devDependencies.addAll(devDeps.keys);
        }
      } catch (e) {
        debugPrint('❌ Failed to parse package.json: $e');
      }
    }
    
    final requirementsTxt = File(path.join(projectPath, 'requirements.txt'));
    if (await requirementsTxt.exists()) {
      try {
        final content = await requirementsTxt.readAsString();
        final lines = content.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
            final packageName = trimmed.split(RegExp(r'[<>=! ]')).first;
            if (packageName.isNotEmpty) {
              dependencies.add(packageName);
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Failed to parse requirements.txt: $e');
      }
    }
    
    return ProjectDependencies(
      dependencies: dependencies,
      devDependencies: devDependencies,
      analyzedAt: DateTime.now(),
    );
  }

  List<ProjectSuggestion> _getProjectTypeSuggestions(ProjectContext context) {
    final suggestions = <ProjectSuggestion>[];
    
    switch (context.type) {
      case ProjectType.nodejs:
        suggestions.add(ProjectSuggestion(
          type: SuggestionType.setup,
          title: 'Set up development environment',
          description: 'Run npm install to install dependencies',
          priority: 0.9,
          command: 'npm install',
        ));
        suggestions.add(ProjectSuggestion(
          type: SuggestionType.development,
          title: 'Start development server',
          description: 'Run npm run dev to start the development server',
          priority: 0.8,
          command: 'npm run dev',
        ));
        break;
      case ProjectType.python:
        suggestions.add(ProjectSuggestion(
          type: SuggestionType.setup,
          title: 'Create virtual environment',
          description: 'Set up a Python virtual environment',
          priority: 0.9,
          command: 'python -m venv venv && source venv/bin/activate',
        ));
        break;
      case ProjectType.rust:
        suggestions.add(ProjectSuggestion(
          type: SuggestionType.development,
          title: 'Check Rust code',
          description: 'Run cargo check to verify code compiles',
          priority: 0.8,
          command: 'cargo check',
        ));
        break;
    }
    
    return suggestions;
  }

  List<ProjectSuggestion> _getCodeQualitySuggestions(ProjectMetrics metrics) {
    final suggestions = <ProjectSuggestion>[];
    
    if (metrics.testFiles == 0 && metrics.codeFiles > 5) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.testing,
        title: 'Add tests',
        description: 'Consider adding unit tests for better code coverage',
        priority: 0.7,
        command: '',
      ));
    }
    
    if (metrics.documentationFiles == 0 && metrics.codeFiles > 10) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.documentation,
        title: 'Add documentation',
        description: 'Consider adding README and documentation files',
        priority: 0.6,
        command: '',
      ));
    }
    
    if (metrics.maintainabilityIndex < 50) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.refactoring,
        title: 'Improve code structure',
        description: 'Consider refactoring to improve maintainability',
        priority: 0.8,
        command: '',
      ));
    }
    
    return suggestions;
  }

  List<ProjectSuggestion> _getActivityBasedSuggestions(List<ProjectActivity> activities) {
    final suggestions = <ProjectSuggestion>[];
    
    // Analyze activity patterns
    final commandFrequency = <String, int>{};
    for (final activity in activities) {
      if (activity.type == ActivityType.command) {
        final command = activity.details['command'] as String;
        commandFrequency[command] = (commandFrequency[command] ?? 0) + 1;
      }
    }
    
    // Suggest frequently used commands
    final frequentCommands = commandFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in frequentCommands.take(3)) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.productivity,
        title: 'Frequent command: ${entry.key}',
        description: 'You use this command ${entry.value} times recently',
        priority: 0.5,
        command: entry.key,
      ));
    }
    
    return suggestions;
  }

  List<ProjectSuggestion> _getDependencySuggestions(ProjectDependencies dependencies) {
    final suggestions = <ProjectSuggestion>[];
    
    if (dependencies.dependencies.isEmpty) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.dependencies,
        title: 'Add dependencies',
        description: 'Consider adding useful dependencies for your project',
        priority: 0.4,
        command: '',
      ));
    }
    
    // Check for outdated dependencies (simplified)
    if (dependencies.dependencies.contains('express')) {
      suggestions.add(ProjectSuggestion(
        type: SuggestionType.security,
        title: 'Check for security updates',
        description: 'Review Express.js for security updates',
        priority: 0.7,
        command: 'npm audit',
      ));
    }
    
    return suggestions;
  }

  bool _isCodeFile(String extension) {
    final codeExtensions = {
      '.js', '.ts', '.jsx', '.tsx', '.py', '.rs', '.go', '.dart', '.java',
      '.cpp', '.c', '.h', '.cs', '.php', '.rb', '.swift', '.kt', '.scala',
    };
    return codeExtensions.contains(extension);
  }

  bool _isTestFile(String filePath) {
    return filePath.contains('test') || filePath.contains('spec');
  }

  bool _isConfigFile(String fileName) {
    final configFiles = {
      'package.json', 'requirements.txt', 'Cargo.toml', 'go.mod', 'pubspec.yaml',
      'pom.xml', 'build.gradle', 'webpack.config.js', '.gitignore', '.env',
    };
    return configFiles.contains(fileName);
  }

  bool _isDocumentationFile(String fileName) {
    final docFiles = {'README.md', 'CHANGELOG.md', 'LICENSE', 'CONTRIBUTING.md'};
    return docFiles.contains(fileName);
  }

  double _calculateMaintainabilityIndex(int totalLines, int codeFiles, int testFiles, int configFiles) {
    // Simplified maintainability index calculation
    final codeToTestRatio = codeFiles > 0 ? testFiles / codeFiles : 0;
    final configToCodeRatio = codeFiles > 0 ? configFiles / codeFiles : 0;
    final linesPerFile = codeFiles > 0 ? totalLines / codeFiles : 0;
    
    double score = 50.0; // Base score
    
    // Bonus for tests
    score += codeToTestRatio * 20.0;
    
    // Bonus for reasonable file sizes
    if (linesPerFile < 500) score += 10.0;
    else if (linesPerFile > 2000) score -= 10.0;
    
    // Bonus for configuration
    score += configToCodeRatio * 5.0;
    
    return math.max(0.0, math.min(100.0, score));
  }

  Future<void> _updateMetricsFromActivity(ProjectActivity activity) async {
    // Update project metrics based on activity
    if (activity.projectPath == _currentProjectPath) {
      // Re-analyze project if significant changes
      if (activity.type == ActivityType.fileCreated || activity.type == ActivityType.fileDeleted) {
        await analyzeProject(_currentProjectPath!);
      }
    }
  }

  void _startAnalysisTimer() {
    _analysisTimer = Timer.periodic(_analysisInterval, (_) {
      if (_currentProjectPath != null) {
        unawaited(analyzeProject(_currentProjectPath!));
      }
    });
  }

  Map<String, dynamic> getStatistics() {
    return {
      'analyzed_projects': _projectContexts.length,
      'current_project': _currentProjectPath,
      'total_activities': _activityHistory.values.fold(0, (sum, activities) => sum + activities.length),
      'dependencies_analyzed': _dependencies.length,
    };
  }

  Future<void> dispose() async {
    _analysisTimer?.cancel();
    _intelligenceController.close();
    _projectContexts.clear();
    _projectMetrics.clear();
    _activityHistory.clear();
    _dependencies.clear();
  }
}

class ProjectContext {
  final String path;
  final String name;
  final ProjectType type;
  final String primaryLanguage;
  final List<ProjectFile> files;
  final bool hasGit;
  final DateTime analyzedAt;
  
  ProjectContext({
    required this.path,
    required this.name,
    required this.type,
    required this.primaryLanguage,
    required this.files,
    required this.hasGit,
    required this.analyzedAt,
  });
}

class ProjectFile {
  final String path;
  final String name;
  final String extension;
  final int size;
  final DateTime lastModified;
  
  ProjectFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.lastModified,
  });
}

class ProjectMetrics {
  final int totalFiles;
  final int totalLines;
  final int codeFiles;
  final int testFiles;
  final int configFiles;
  final int documentationFiles;
  final String complexity;
  final double maintainabilityIndex;
  
  ProjectMetrics({
    required this.totalFiles,
    required this.totalLines,
    required this.codeFiles,
    required this.testFiles,
    required this.configFiles,
    required this.documentationFiles,
    required this.complexity,
    required this.maintainabilityIndex,
  });
}

class ProjectDependencies {
  final List<String> dependencies;
  final List<String> devDependencies;
  final DateTime analyzedAt;
  
  ProjectDependencies({
    required this.dependencies,
    required this.devDependencies,
    required this.analyzedAt,
  });
}

class ProjectActivity {
  final String projectPath;
  final ActivityType type;
  final String filePath;
  final Map<String, dynamic> details;
  final DateTime timestamp;
  
  ProjectActivity({
    required this.projectPath,
    required this.type,
    required this.filePath,
    required this.details,
    required this.timestamp,
  });
}

class ProjectSuggestion {
  final SuggestionType type;
  final String title;
  final String description;
  final double priority;
  final String command;
  
  ProjectSuggestion({
    required this.type,
    required this.title,
    required this.description,
    required this.priority,
    required this.command,
  });
}

class IntelligenceEvent {
  final IntelligenceEventType type;
  final Map<String, dynamic>? data;
  
  IntelligenceEvent({
    required this.type,
    this.data,
  });
}

enum ProjectType {
  unknown,
  nodejs,
  python,
  rust,
  go,
  dart,
  java,
  flutter,
}

enum ActivityType {
  fileCreated,
  fileModified,
  fileDeleted,
  command,
  navigation,
}

enum SuggestionType {
  setup,
  development,
  testing,
  documentation,
  refactoring,
  dependencies,
  security,
  productivity,
}

enum IntelligenceEventType {
  projectAnalyzed,
  activityRecorded,
}


