import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class SmartWorkspaceManagement {
  static const String _configFile = '/home/house/.termisol_workspace_config.json';
  static const String _workspacesFile = '/home/house/.termisol_workspaces.json';
  static const int _maxWorkspaces = 50;
  static const int _maxProjects = 200;
  static const int _maxTemplates = 100;
  
  final Map<String, Workspace> _workspaces = {};
  final Map<String, Project> _projects = {};
  final Map<String, WorkspaceTemplate> _templates = {};
  final Map<String, WorkspaceActivity> _activities = {};
  final Map<String, WorkspaceRule> _rules = {};
  
  String? _activeWorkspace;
  String? _activeProject;
  Timer? _activityTimer;
  Timer? _cleanupTimer;
  int _totalWorkspaces = 0;
  int _totalProjects = 0;
  int _totalTemplates = 0;
  int _totalRules = 0;
  
  final StreamController<WorkspaceEvent> _workspaceController = 
      StreamController<WorkspaceEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _loadWorkspaces();
    _loadProjects();
    _loadTemplates();
    _loadRules();
    _initializeDefaultTemplates();
    _startTimers();
    _detectCurrentWorkspace();
    developer.log('🏢 Smart Workspace Management initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('🏢 No existing workspace configuration found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      _activeWorkspace = data['active_workspace'];
      _activeProject = data['active_project'];
      
      developer.log('🏢 Loaded workspace configuration');
      
    } catch (e) {
      developer.log('🏢 Failed to load workspace configuration: $e');
    }
  }

  void _loadWorkspaces() {
    try {
      final file = File(_workspacesFile);
      if (!file.existsSync()) {
        developer.log('🏢 No existing workspaces found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['workspaces']) {
        final workspace = Workspace.fromJson(entry);
        _workspaces[workspace.id] = workspace;
        _totalWorkspaces++;
      }
      
      developer.log('🏢 Loaded ${_workspaces.length} workspaces');
      
    } catch (e) {
      developer.log('🏢 Failed to load workspaces: $e');
    }
  }

  void _loadProjects() {
    try {
      final file = File('${_workspacesFile}.projects');
      if (!file.existsSync()) {
        developer.log('🏢 No existing projects found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['projects']) {
        final project = Project.fromJson(entry);
        _projects[project.id] = project;
        _totalProjects++;
      }
      
      developer.log('🏢 Loaded ${_projects.length} projects');
      
    } catch (e) {
      developer.log('🏢 Failed to load projects: $e');
    }
  }

  void _loadTemplates() {
    try {
      final file = File('${_workspacesFile}.templates');
      if (!file.existsSync()) {
        developer.log('🏢 No existing templates found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['templates']) {
        final template = WorkspaceTemplate.fromJson(entry);
        _templates[template.id] = template;
        _totalTemplates++;
      }
      
      developer.log('🏢 Loaded ${_templates.length} templates');
      
    } catch (e) {
      developer.log('🏢 Failed to load templates: $e');
    }
  }

  void _loadRules() {
    try {
      final file = File('${_workspacesFile}.rules');
      if (!file.existsSync()) {
        developer.log('🏢 No existing rules found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['rules']) {
        final rule = WorkspaceRule.fromJson(entry);
        _rules[rule.id] = rule;
        _totalRules++;
      }
      
      developer.log('🏢 Loaded ${_rules.length} rules');
      
    } catch (e) {
      developer.log('🏢 Failed to load rules: $e');
    }
  }

  void _initializeDefaultTemplates() {
    if (_templates.isEmpty) {
      final defaultTemplates = [
        // Development workspace
        WorkspaceTemplate(
          id: 'development',
          name: 'Development Workspace',
          description: 'Workspace for software development',
          type: WorkspaceType.development,
          config: {
            'terminal_panes': 4,
            'layout': 'grid_2x2',
            'tools': ['git', 'code', 'debugger', 'test_runner'],
            'environment': {
              'PATH': '\$PATH:/usr/local/go/bin:/usr/local/bin',
              'GOPATH': '\$HOME/go',
              'NODE_PATH': '\$HOME/.nvm/versions/node/current/lib/node_modules',
            },
            'auto_commands': [
              'git status',
              'npm install',
              'flutter pub get',
            ],
          },
          projects: [],
          createdAt: DateTime.now(),
          isDefault: true,
        ),
        
        // Data science workspace
        WorkspaceTemplate(
          id: 'data_science',
          name: 'Data Science Workspace',
          description: 'Workspace for data analysis and machine learning',
          type: WorkspaceType.data_science,
          config: {
            'terminal_panes': 3,
            'layout': 'main_sidebar',
            'tools': ['jupyter', 'python', 'pandas', 'matplotlib'],
            'environment': {
              'PYTHONPATH': '\$HOME/.local/lib/python3.9/site-packages',
              'JUPYTER_PATH': '\$HOME/.local/share/jupyter',
              'CONDA_DEFAULT_ENV': 'base',
            },
            'auto_commands': [
              'jupyter notebook',
              'python -m pip install -r requirements.txt',
            ],
          },
          projects: [],
          createdAt: DateTime.now(),
          isDefault: true,
        ),
        
        // System administration workspace
        WorkspaceTemplate(
          id: 'sysadmin',
          name: 'System Administration',
          description: 'Workspace for system administration tasks',
          type: WorkspaceType.system_administration,
          config: {
            'terminal_panes': 6,
            'layout': 'grid_3x2',
            'tools': ['htop', 'systemd', 'docker', 'kubectl', 'vim'],
            'environment': {
              'EDITOR': 'vim',
              'SUDO_EDITOR': 'vim',
              'DOCKER_HOST': 'unix:///var/run/docker.sock',
            },
            'auto_commands': [
              'sudo systemctl status',
              'docker ps',
              'kubectl get pods',
            ],
          },
          projects: [],
          createdAt: DateTime.now(),
          isDefault: true,
        ),
        
        // Design workspace
        WorkspaceTemplate(
          id: 'design',
          name: 'Design Workspace',
          description: 'Workspace for design and creative work',
          type: WorkspaceType.design,
          config: {
            'terminal_panes': 2,
            'layout': 'horizontal_stack',
            'tools': ['figma', 'photoshop', 'illustrator', 'blender'],
            'environment': {
              'DISPLAY': ':0',
              'GDK_BACKEND': 'x11',
            },
            'auto_commands': [
              'figma --help',
              'xdg-open .',
            ],
          },
          projects: [],
          createdAt: DateTime.now(),
          isDefault: true,
        ),
        
        // Research workspace
        WorkspaceTemplate(
          id: 'research',
          name: 'Research Workspace',
          description: 'Workspace for research and documentation',
          type: WorkspaceType.research,
          config: {
            'terminal_panes': 3,
            'layout': 'vertical_stack',
            'tools': ['zotero', 'latex', 'pandoc', 'firefox'],
            'environment': {
              'BIBINPUTS': '\$HOME/references',
              'TEXMFHOME': '\$HOME/.texmf',
            },
            'auto_commands': [
              'pdflatex main.tex',
              'firefox references.bib',
            ],
          },
          projects: [],
          createdAt: DateTime.now(),
          isDefault: true,
        ),
      ];
      
      for (final template in defaultTemplates) {
        _templates[template.id] = template;
        _totalTemplates++;
      }
      
      _saveTemplates();
      developer.log('🏢 Initialized ${defaultTemplates.length} default templates');
    }
  }

  void _startTimers() {
    _activityTimer = Timer.periodic(
      Duration(minutes: 5),
      (_) => _trackActivity(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(hours: 1),
      (_) => _performCleanup(),
    );
  }

  Future<void> _detectCurrentWorkspace() async {
    final currentDir = Directory.current.path;
    
    // Find workspace that contains current directory
    for (final workspace in _workspaces.values) {
      if (currentDir.startsWith(workspace.path)) {
        await setActiveWorkspace(workspace.id);
        break;
      }
    }
  }

  Future<String> createWorkspace({
    required String name,
    required String path,
    WorkspaceType? type,
    Map<String, dynamic>? config,
    String? templateId,
  }) async {
    if (_workspaces.length >= _maxWorkspaces) {
      throw Exception('Maximum workspaces reached: $_maxWorkspaces');
    }
    
    final workspaceId = _generateWorkspaceId();
    
    // Apply template if specified
    Map<String, dynamic> workspaceConfig = config ?? {};
    if (templateId != null) {
      final template = _templates[templateId];
      if (template != null) {
        workspaceConfig = Map.from(template.config);
        workspaceConfig.addAll(config ?? {});
      }
    }
    
    final workspace = Workspace(
      id: workspaceId,
      name: name,
      path: path,
      type: type ?? WorkspaceType.custom,
      config: workspaceConfig,
      projects: [],
      isActive: false,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 0,
      totalActivityTime: Duration.zero,
    );
    
    _workspaces[workspaceId] = workspace;
    _totalWorkspaces++;
    
    // Create workspace directory if it doesn't exist
    await Directory(path).create(recursive: true);
    
    developer.log('🏢 Created workspace: $name ($path)');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.workspaceCreated,
      workspaceId: workspaceId,
      workspaceName: name,
    ));
    
    await _saveWorkspaces();
    
    return workspaceId;
  }

  Future<String> createProject({
    required String workspaceId,
    required String name,
    required String path,
    ProjectType? type,
    Map<String, dynamic>? config,
  }) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) {
      throw Exception('Workspace not found: $workspaceId');
    }
    
    if (_projects.length >= _maxProjects) {
      throw Exception('Maximum projects reached: $_maxProjects');
    }
    
    final projectId = _generateProjectId();
    
    final project = Project(
      id: projectId,
      workspaceId: workspaceId,
      name: name,
      path: path,
      type: type ?? ProjectType.custom,
      config: config ?? {},
      isActive: false,
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 0,
      tags: [],
      dependencies: [],
      buildCommands: [],
      testCommands: [],
    );
    
    _projects[projectId] = project;
    _totalProjects++;
    
    // Add project to workspace
    workspace.projects.add(projectId);
    
    // Create project directory if it doesn't exist
    await Directory(path).create(recursive: true);
    
    developer.log('🏢 Created project: $name in workspace $workspaceId');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.projectCreated,
      workspaceId: workspaceId,
      projectId: projectId,
      projectName: name,
    ));
    
    await _saveWorkspaces();
    await _saveProjects();
    
    return projectId;
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) {
      throw Exception('Workspace not found: $workspaceId');
    }
    
    // Deactivate previous workspace
    if (_activeWorkspace != null) {
      final prevWorkspace = _workspaces[_activeWorkspace!];
      if (prevWorkspace != null) {
        prevWorkspace!.isActive = false;
      }
    }
    
    // Activate new workspace
    workspace.isActive = true;
    workspace.lastAccessed = DateTime.now();
    workspace.accessCount++;
    
    _activeWorkspace = workspaceId;
    
    // Change to workspace directory
    await Directory.current = Directory(workspace.path);
    
    // Apply workspace environment
    await _applyWorkspaceEnvironment(workspace);
    
    // Execute auto commands
    await _executeAutoCommands(workspace);
    
    developer.log('🏢 Set active workspace: ${workspace.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.workspaceActivated,
      workspaceId: workspaceId,
      workspaceName: workspace.name,
    ));
    
    await _saveWorkspaces();
    await _saveConfiguration();
  }

  Future<void> setActiveProject(String projectId) async {
    final project = _projects[projectId];
    if (project == null) {
      throw Exception('Project not found: $projectId');
    }
    
    // Deactivate previous project
    if (_activeProject != null) {
      final prevProject = _projects[_activeProject!];
      if (prevProject != null) {
        prevProject!.isActive = false;
      }
    }
    
    // Activate new project
    project.isActive = true;
    project.lastAccessed = DateTime.now();
    project.accessCount++;
    
    _activeProject = projectId;
    
    // Change to project directory
    await Directory.current = Directory(project.path);
    
    // Apply project environment
    await _applyProjectEnvironment(project);
    
    developer.log('🏢 Set active project: ${project.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.projectActivated,
      workspaceId: project.workspaceId,
      projectId: projectId,
      projectName: project.name,
    ));
    
    await _saveProjects();
    await _saveConfiguration();
  }

  Future<void> _applyWorkspaceEnvironment(Workspace workspace) async {
    final environment = workspace.config['environment'] as Map<String, dynamic>? ?? {};
    
    for (final entry in environment.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // Set environment variable
      Platform.environment[key] = value.toString();
    }
    
    developer.log('🏢 Applied workspace environment for ${workspace.name}');
  }

  Future<void> _applyProjectEnvironment(Project project) async {
    final environment = project.config['environment'] as Map<String, dynamic>? ?? {};
    
    for (final entry in environment.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // Set environment variable
      Platform.environment[key] = value.toString();
    }
    
    developer.log('🏢 Applied project environment for ${project.name}');
  }

  Future<void> _executeAutoCommands(Workspace workspace) async {
    final autoCommands = workspace.config['auto_commands'] as List<String>? ?? [];
    
    for (final command in autoCommands) {
      try {
        final parts = command.split(' ');
        final cmd = parts.first;
        final args = parts.skip(1).toList();
        
        await Process.run(cmd, args);
        developer.log('🏢 Executed auto command: $command');
      } catch (e) {
        developer.log('🏢 Failed to execute auto command $command: $e');
      }
    }
  }

  Future<void> switchToProject(String projectId) async {
    final project = _projects[projectId];
    if (project == null) {
      throw Exception('Project not found: $projectId');
    }
    
    // Switch to project's workspace first if needed
    if (_activeWorkspace != project.workspaceId) {
      await setActiveWorkspace(project.workspaceId);
    }
    
    // Then switch to project
    await setActiveProject(projectId);
  }

  Future<void> updateWorkspace({
    required String workspaceId,
    String? name,
    String? path,
    Map<String, dynamic>? config,
  }) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) {
      throw Exception('Workspace not found: $workspaceId');
    }
    
    if (name != null) workspace.name = name!;
    if (path != null) workspace.path = path!;
    if (config != null) workspace.config.addAll(config!);
    
    workspace.lastAccessed = DateTime.now();
    
    developer.log('🏢 Updated workspace: ${workspace.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.workspaceUpdated,
      workspaceId: workspaceId,
      workspaceName: workspace.name,
    ));
    
    await _saveWorkspaces();
  }

  Future<void> updateProject({
    required String projectId,
    String? name,
    String? path,
    Map<String, dynamic>? config,
    List<String>? tags,
    List<String>? dependencies,
    List<String>? buildCommands,
    List<String>? testCommands,
  }) async {
    final project = _projects[projectId];
    if (project == null) {
      throw Exception('Project not found: $projectId');
    }
    
    if (name != null) project.name = name!;
    if (path != null) project.path = path!;
    if (config != null) project.config.addAll(config!);
    if (tags != null) project.tags = tags!;
    if (dependencies != null) project.dependencies = dependencies!;
    if (buildCommands != null) project.buildCommands = buildCommands!;
    if (testCommands != null) project.testCommands = testCommands!;
    
    project.lastAccessed = DateTime.now();
    
    developer.log('🏢 Updated project: ${project.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.projectUpdated,
      workspaceId: project.workspaceId,
      projectId: projectId,
      projectName: project.name,
    ));
    
    await _saveProjects();
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final workspace = _workspaces.remove(workspaceId);
    if (workspace == null) {
      throw Exception('Workspace not found: $workspaceId');
    }
    
    // Delete all projects in this workspace
    final projectsToDelete = _projects.values
        .where((project) => project.workspaceId == workspaceId)
        .toList();
    
    for (final project in projectsToDelete) {
      _projects.remove(project.id);
      _totalProjects--;
    }
    
    _totalWorkspaces--;
    
    // Update active workspace if needed
    if (_activeWorkspace == workspaceId) {
      _activeWorkspace = null;
      _activeProject = null;
    }
    
    developer.log('🏢 Deleted workspace: ${workspace.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.workspaceDeleted,
      workspaceId: workspaceId,
      workspaceName: workspace.name,
    ));
    
    await _saveWorkspaces();
    await _saveProjects();
    await _saveConfiguration();
  }

  Future<void> deleteProject(String projectId) async {
    final project = _projects.remove(projectId);
    if (project == null) {
      throw Exception('Project not found: $projectId');
    }
    
    // Remove project from workspace
    final workspace = _workspaces[project.workspaceId];
    if (workspace != null) {
      workspace.projects.remove(projectId);
    }
    
    _totalProjects--;
    
    // Update active project if needed
    if (_activeProject == projectId) {
      _activeProject = null;
    }
    
    developer.log('🏢 Deleted project: ${project.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.projectDeleted,
      workspaceId: project.workspaceId,
      projectId: projectId,
      projectName: project.name,
    ));
    
    await _saveProjects();
    await _saveConfiguration();
  }

  Future<String> createTemplate({
    required String name,
    required String description,
    required WorkspaceType type,
    required Map<String, dynamic> config,
  }) async {
    if (_templates.length >= _maxTemplates) {
      throw Exception('Maximum templates reached: $_maxTemplates');
    }
    
    final templateId = _generateTemplateId();
    
    final template = WorkspaceTemplate(
      id: templateId,
      name: name,
      description: description,
      type: type,
      config: config,
      projects: [],
      createdAt: DateTime.now(),
      isDefault: false,
    );
    
    _templates[templateId] = template;
    _totalTemplates++;
    
    developer.log('🏢 Created template: $name');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.templateCreated,
      templateId: templateId,
      templateName: name,
    ));
    
    await _saveTemplates();
    
    return templateId;
  }

  Future<String> createRule({
    required String name,
    required String description,
    required WorkspaceRuleType type,
    required Map<String, dynamic> conditions,
    required Map<String, dynamic> actions,
  }) async {
    final ruleId = _generateRuleId();
    
    final rule = WorkspaceRule(
      id: ruleId,
      name: name,
      description: description,
      type: type,
      conditions: conditions,
      actions: actions,
      enabled: true,
      triggerCount: 0,
      lastTriggered: null,
      createdAt: DateTime.now(),
    );
    
    _rules[ruleId] = rule;
    _totalRules++;
    
    developer.log('🏢 Created rule: $name');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.ruleCreated,
      ruleId: ruleId,
      ruleName: name,
    ));
    
    await _saveRules();
    
    return ruleId;
  }

  Future<void> _trackActivity() async {
    if (_activeWorkspace == null) return;
    
    final workspace = _workspaces[_activeWorkspace!];
    if (workspace == null) return;
    
    // Record activity
    final activityId = _generateActivityId();
    final activity = WorkspaceActivity(
      id: activityId,
      workspaceId: _activeWorkspace!,
      projectId: _activeProject,
      type: ActivityType.usage,
      duration: Duration(minutes: 5), // Activity tracking interval
      timestamp: DateTime.now(),
      metadata: {
        'current_directory': Directory.current.path,
        'active_terminal_panes': workspace.config['terminal_panes'] ?? 1,
      },
    );
    
    _activities[activityId] = activity;
    
    // Update workspace activity time
    workspace.totalActivityTime += Duration(minutes: 5);
    
    // Check and apply rules
    await _checkAndApplyRules();
    
    // Clean old activities
    _cleanOldActivities();
  }

  Future<void> _checkAndApplyRules() async {
    if (_activeWorkspace == null) return;
    
    final workspace = _workspaces[_activeWorkspace!];
    final project = _activeProject != null ? _projects[_activeProject!] : null;
    
    for (final rule in _rules.values) {
      if (!rule.enabled) continue;
      
      final shouldTrigger = await _evaluateRule(rule, workspace, project);
      if (shouldTrigger) {
        await _applyRule(rule, workspace, project);
      }
    }
  }

  Future<bool> _evaluateRule(
    WorkspaceRule rule,
    Workspace? workspace,
    Project? project,
  ) async {
    final conditions = rule.conditions;
    
    switch (rule.type) {
      case WorkspaceRuleType.time_based:
        return _evaluateTimeBasedRule(conditions);
      case WorkspaceRuleType.activity_based:
        return _evaluateActivityBasedRule(conditions, workspace);
      case WorkspaceRuleType.project_based:
        return _evaluateProjectBasedRule(conditions, project);
      case WorkspaceRuleType.directory_based:
        return _evaluateDirectoryBasedRule(conditions);
      case WorkspaceRuleType.system_based:
        return _evaluateSystemBasedRule(conditions);
    }
    
    return false;
  }

  bool _evaluateTimeBasedRule(Map<String, dynamic> conditions) {
    final now = DateTime.now();
    
    // Check time range
    if (conditions.containsKey('start_time') && conditions.containsKey('end_time')) {
      final startTime = _parseTime(conditions['start_time']);
      final endTime = _parseTime(conditions['end_time']);
      
      if (startTime != null && endTime != null) {
        final currentTime = Duration(hours: now.hour, minutes: now.minute);
        return currentTime >= startTime! && currentTime <= endTime!;
      }
    }
    
    // Check day of week
    if (conditions.containsKey('days')) {
      final days = (conditions['days'] as List).cast<String>();
      final currentDay = now.weekday.toString();
      return days.contains(currentDay);
    }
    
    return false;
  }

  Duration? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        return Duration(hours: hours, minutes: minutes);
      }
    } catch (e) {
      developer.log('🏢 Failed to parse time: $timeStr');
    }
    
    return null;
  }

  bool _evaluateActivityBasedRule(Map<String, dynamic> conditions, Workspace? workspace) {
    if (workspace == null) return false;
    
    // Check activity time threshold
    if (conditions.containsKey('min_activity_time')) {
      final minActivityTime = Duration(minutes: conditions['min_activity_time']);
      return workspace.totalActivityTime >= minActivityTime;
    }
    
    // Check access count
    if (conditions.containsKey('min_access_count')) {
      final minAccessCount = conditions['min_access_count'];
      return workspace.accessCount >= minAccessCount;
    }
    
    return false;
  }

  bool _evaluateProjectBasedRule(Map<String, dynamic> conditions, Project? project) {
    if (project == null) return false;
    
    // Check project type
    if (conditions.containsKey('project_types')) {
      final projectTypes = (conditions['project_types'] as List).cast<String>();
      return projectTypes.contains(project.type.name);
    }
    
    // Check project tags
    if (conditions.containsKey('project_tags')) {
      final requiredTags = (conditions['project_tags'] as List).cast<String>();
      return requiredTags.every((tag) => project.tags.contains(tag));
    }
    
    return false;
  }

  bool _evaluateDirectoryBasedRule(Map<String, dynamic> conditions) {
    final currentDir = Directory.current.path;
    
    // Check directory patterns
    if (conditions.containsKey('directory_patterns')) {
      final patterns = (conditions['directory_patterns'] as List).cast<String>();
      return patterns.any((pattern) => RegExp(pattern).hasMatch(currentDir));
    }
    
    // Check file patterns
    if (conditions.containsKey('file_patterns')) {
      final patterns = (conditions['file_patterns'] as List).cast<String>();
      try {
        final files = Directory(currentDir).listSync();
        return files.any((file) => 
            patterns.any((pattern) => RegExp(pattern).hasMatch(file.path))));
      } catch (e) {
        // Ignore directory listing errors
      }
    }
    
    return false;
  }

  bool _evaluateSystemBasedRule(Map<String, dynamic> conditions) {
    // Check system load
    if (conditions.containsKey('max_cpu_usage')) {
      // Simplified CPU check - in practice would use system monitoring
      return false; // Placeholder
    }
    
    // Check memory usage
    if (conditions.containsKey('max_memory_usage')) {
      // Simplified memory check - in practice would use system monitoring
      return false; // Placeholder
    }
    
    return false;
  }

  Future<void> _applyRule(
    WorkspaceRule rule,
    Workspace workspace,
    Project? project,
  ) async {
    rule.triggerCount++;
    rule.lastTriggered = DateTime.now();
    
    final actions = rule.actions;
    
    // Execute actions
    for (final entry in actions.entries) {
      final action = entry.key;
      final params = entry.value as Map<String, dynamic>;
      
      switch (action) {
        case 'switch_workspace':
          if (params['workspace_id'] != null) {
            await setActiveWorkspace(params['workspace_id']);
          }
          break;
          
        case 'switch_project':
          if (params['project_id'] != null) {
            await switchToProject(params['project_id']);
          }
          break;
          
        case 'execute_command':
          if (params['command'] != null) {
            final command = params['command'];
            final parts = command.split(' ');
            final cmd = parts.first;
            final args = parts.skip(1).toList();
            
            await Process.run(cmd, args);
          }
          break;
          
        case 'send_notification':
          if (params['message'] != null) {
            // Send notification (simplified)
            developer.log('🏢 Rule notification: ${params['message']}');
          }
          break;
          
        case 'create_file':
          if (params['path'] != null && params['content'] != null) {
            final file = File(params['path']);
            await file.parent.create(recursive: true);
            await file.writeAsString(params['content']);
          }
          break;
      }
    }
    
    developer.log('🏢 Applied rule: ${rule.name}');
    
    _emitEvent(WorkspaceEvent(
      type: WorkspaceEventType.ruleTriggered,
      ruleId: rule.id,
      ruleName: rule.name,
    ));
    
    await _saveRules();
  }

  void _cleanOldActivities() {
    final cutoffTime = DateTime.now().subtract(Duration(days: 7));
    
    final toRemove = <String>[];
    for (final entry in _activities.entries) {
      if (entry.value.timestamp.isBefore(cutoffTime)) {
        toRemove.add(entry.key);
      }
    }
    
    for (final key in toRemove) {
      _activities.remove(key);
    }
    
    if (toRemove.isNotEmpty) {
      developer.log('🏢 Cleaned ${toRemove.length} old activities');
    }
  }

  Future<void> _performCleanup() async {
    // Clean inactive workspaces
    final cutoffDate = DateTime.now().subtract(Duration(days: 30));
    
    final toRemoveWorkspaces = <String>[];
    for (final entry in _workspaces.entries) {
      if (entry.value.lastAccessed.isBefore(cutoffDate) && 
          !entry.value.isActive) {
        toRemoveWorkspaces.add(entry.key);
      }
    }
    
    for (final workspaceId in toRemoveWorkspaces) {
      await deleteWorkspace(workspaceId);
    }
    
    // Clean old activities
    _cleanOldActivities();
    
    developer.log('🏢 Performed workspace cleanup');
  }

  Future<void> _saveWorkspaces() async {
    try {
      final file = File(_workspacesFile);
      
      final workspacesData = _workspaces.values.map((workspace) => workspace.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'workspaces': workspacesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏢 Failed to save workspaces: $e');
    }
  }

  Future<void> _saveProjects() async {
    try {
      final file = File('${_workspacesFile}.projects');
      
      final projectsData = _projects.values.map((project) => project.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'projects': projectsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏢 Failed to save projects: $e');
    }
  }

  Future<void> _saveTemplates() async {
    try {
      final file = File('${_workspacesFile}.templates');
      
      final templatesData = _templates.values.map((template) => template.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'templates': templatesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏢 Failed to save templates: $e');
    }
  }

  Future<void> _saveRules() async {
    try {
      final file = File('${_workspacesFile}.rules');
      
      final rulesData = _rules.values.map((rule) => rule.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'rules': rulesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏢 Failed to save rules: $e');
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final file = File(_configFile);
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'active_workspace': _activeWorkspace,
        'active_project': _activeProject,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🏢 Failed to save configuration: $e');
    }
  }

  Workspace? getWorkspace(String workspaceId) {
    return _workspaces[workspaceId];
  }

  List<Workspace> getWorkspaces() {
    return _workspaces.values.toList();
  }

  Project? getProject(String projectId) {
    return _projects[projectId];
  }

  List<Project> getProjects({String? workspaceId}) {
    var projects = _projects.values.toList();
    
    if (workspaceId != null) {
      projects = projects.where((project) => project.workspaceId == workspaceId).toList();
    }
    
    return projects;
  }

  WorkspaceTemplate? getTemplate(String templateId) {
    return _templates[templateId];
  }

  List<WorkspaceTemplate> getTemplates() {
    return _templates.values.toList();
  }

  WorkspaceRule? getRule(String ruleId) {
    return _rules[ruleId];
  }

  List<WorkspaceRule> getRules() {
    return _rules.values.toList();
  }

  String? getActiveWorkspace() {
    return _activeWorkspace;
  }

  String? getActiveProject() {
    return _activeProject;
  }

  List<WorkspaceActivity> getActivities({String? workspaceId, DateTime? since}) {
    var activities = _activities.values.toList();
    
    if (workspaceId != null) {
      activities = activities.where((activity) => activity.workspaceId == workspaceId).toList();
    }
    
    if (since != null) {
      activities = activities.where((activity) => activity.timestamp.isAfter(since!)).toList();
    }
    
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return activities;
  }

  WorkspaceStats getStats() {
    return WorkspaceStats(
      totalWorkspaces: _totalWorkspaces,
      activeWorkspaces: _workspaces.values.where((w) => w.isActive).length,
      totalProjects: _totalProjects,
      activeProjects: _projects.values.where((p) => p.isActive).length,
      totalTemplates: _totalTemplates,
      totalRules: _totalRules,
      activeRules: _rules.values.where((r) => r.enabled).length,
      totalActivities: _activities.length,
      activeWorkspace: _activeWorkspace,
      activeProject: _activeProject,
      mostUsedWorkspace: _getMostUsedWorkspace(),
      mostUsedProject: _getMostUsedProject(),
    );
  }

  String? _getMostUsedWorkspace() {
    if (_workspaces.isEmpty) return null;
    
    return _workspaces.values
        .reduce((a, b) => a.accessCount > b.accessCount ? a : b)
        .id;
  }

  String? _getMostUsedProject() {
    if (_projects.isEmpty) return null;
    
    return _projects.values
        .reduce((a, b) => a.accessCount > b.accessCount ? a : b)
        .id;
  }

  String _generateWorkspaceId() {
    return 'workspace_${DateTime.now().millisecondsSinceEpoch}_$_totalWorkspaces';
  }

  String _generateProjectId() {
    return 'project_${DateTime.now().millisecondsSinceEpoch}_$_totalProjects';
  }

  String _generateTemplateId() {
    return 'template_${DateTime.now().millisecondsSinceEpoch}_$_totalTemplates';
  }

  String _generateRuleId() {
    return 'rule_${DateTime.now().millisecondsSinceEpoch}_$_totalRules';
  }

  String _generateActivityId() {
    return 'activity_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(WorkspaceEvent event) {
    _workspaceController.add(event);
  }

  Stream<WorkspaceEvent> get workspaceEventStream => _workspaceController.stream;

  void dispose() {
    _activityTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _workspaces.clear();
    _projects.clear();
    _templates.clear();
    _activities.clear();
    _rules.clear();
    _workspaceController.close();
    
    developer.log('🏢 Smart Workspace Management disposed');
  }
}

class Workspace {
  final String id;
  final String name;
  final String path;
  final WorkspaceType type;
  final Map<String, dynamic> config;
  final List<String> projects;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int accessCount;
  final Duration totalActivityTime;

  Workspace({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.config,
    required this.projects,
    required this.isActive,
    required this.createdAt,
    required this.lastAccessed,
    required this.accessCount,
    required this.totalActivityTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'type': type.name,
      'config': config,
      'projects': projects,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'last_accessed': lastAccessed.toIso8601String(),
      'access_count': accessCount,
      'total_activity_time': totalActivityTime.inMilliseconds,
    };
  }

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      type: WorkspaceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => WorkspaceType.custom,
      ),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      projects: List<String>.from(json['projects'] ?? []),
      isActive: json['is_active'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      lastAccessed: DateTime.parse(json['last_accessed']),
      accessCount: json['access_count'] ?? 0,
      totalActivityTime: Duration(milliseconds: json['total_activity_time'] ?? 0),
    );
  }
}

class Project {
  final String id;
  final String workspaceId;
  final String name;
  final String path;
  final ProjectType type;
  final Map<String, dynamic> config;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int accessCount;
  final List<String> tags;
  final List<String> dependencies;
  final List<String> buildCommands;
  final List<String> testCommands;

  Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.type,
    required this.config,
    required this.isActive,
    required this.createdAt,
    required this.lastAccessed,
    required this.accessCount,
    required this.tags,
    required this.dependencies,
    required this.buildCommands,
    required this.testCommands,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'name': name,
      'path': path,
      'type': type.name,
      'config': config,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'last_accessed': lastAccessed.toIso8601String(),
      'access_count': accessCount,
      'tags': tags,
      'dependencies': dependencies,
      'build_commands': buildCommands,
      'test_commands': testCommands,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      workspaceId: json['workspace_id'],
      name: json['name'],
      path: json['path'],
      type: ProjectType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => ProjectType.custom,
      ),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      isActive: json['is_active'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      lastAccessed: DateTime.parse(json['last_accessed']),
      accessCount: json['access_count'] ?? 0,
      tags: List<String>.from(json['tags'] ?? []),
      dependencies: List<String>.from(json['dependencies'] ?? []),
      buildCommands: List<String>.from(json['build_commands'] ?? []),
      testCommands: List<String>.from(json['test_commands'] ?? []),
    );
  }
}

class WorkspaceTemplate {
  final String id;
  final String name;
  final String description;
  final WorkspaceType type;
  final Map<String, dynamic> config;
  final List<String> projects;
  final DateTime createdAt;
  final bool isDefault;

  WorkspaceTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.config,
    required this.projects,
    required this.createdAt,
    required this.isDefault,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'config': config,
      'projects': projects,
      'created_at': createdAt.toIso8601String(),
      'is_default': isDefault,
    };
  }

  factory WorkspaceTemplate.fromJson(Map<String, dynamic> json) {
    return WorkspaceTemplate(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: WorkspaceType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => WorkspaceType.custom,
      ),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      projects: List<String>.from(json['projects'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
      isDefault: json['is_default'] ?? false,
    );
  }
}

class WorkspaceRule {
  final String id;
  final String name;
  final String description;
  final WorkspaceRuleType type;
  final Map<String, dynamic> conditions;
  final Map<String, dynamic> actions;
  final bool enabled;
  final int triggerCount;
  final DateTime? lastTriggered;
  final DateTime createdAt;

  WorkspaceRule({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.conditions,
    required this.actions,
    required this.enabled,
    required this.triggerCount,
    this.lastTriggered,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'conditions': conditions,
      'actions': actions,
      'enabled': enabled,
      'trigger_count': triggerCount,
      'last_triggered': lastTriggered?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory WorkspaceRule.fromJson(Map<String, dynamic> json) {
    return WorkspaceRule(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: WorkspaceRuleType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => WorkspaceRuleType.time_based,
      ),
      conditions: Map<String, dynamic>.from(json['conditions'] ?? {}),
      actions: Map<String, dynamic>.from(json['actions'] ?? {}),
      enabled: json['enabled'] ?? true,
      triggerCount: json['trigger_count'] ?? 0,
      lastTriggered: json['last_triggered'] != null ? DateTime.parse(json['last_triggered']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class WorkspaceActivity {
  final String id;
  final String workspaceId;
  final String? projectId;
  final ActivityType type;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  WorkspaceActivity({
    required this.id,
    required this.workspaceId,
    this.projectId,
    required this.type,
    required this.duration,
    required this.timestamp,
    required this.metadata,
  });
}

enum WorkspaceType {
  custom,
  development,
  data_science,
  system_administration,
  design,
  research,
  testing,
  documentation,
}

enum ProjectType {
  custom,
  web_development,
  mobile_development,
  desktop_development,
  backend_development,
  data_science,
  machine_learning,
  devops,
  testing,
  documentation,
}

enum WorkspaceRuleType {
  time_based,
  activity_based,
  project_based,
  directory_based,
  system_based,
}

enum ActivityType {
  usage,
  build,
  test,
  debug,
  meeting,
  research,
}

enum WorkspaceEventType {
  workspaceCreated,
  workspaceActivated,
  workspaceUpdated,
  workspaceDeleted,
  projectCreated,
  projectActivated,
  projectUpdated,
  projectDeleted,
  templateCreated,
  ruleCreated,
  ruleTriggered,
}

class WorkspaceEvent {
  final WorkspaceEventType type;
  final String? workspaceId;
  final String? workspaceName;
  final String? projectId;
  final String? projectName;
  final String? templateId;
  final String? templateName;
  final String? ruleId;
  final String? ruleName;

  WorkspaceEvent({
    required this.type,
    this.workspaceId,
    this.workspaceName,
    this.projectId,
    this.projectName,
    this.templateId,
    this.templateName,
    this.ruleId,
    this.ruleName,
  });
}

class WorkspaceStats {
  final int totalWorkspaces;
  final int activeWorkspaces;
  final int totalProjects;
  final int activeProjects;
  final int totalTemplates;
  final int totalRules;
  final int activeRules;
  final int totalActivities;
  final String? activeWorkspace;
  final String? activeProject;
  final String? mostUsedWorkspace;
  final String? mostUsedProject;

  WorkspaceStats({
    required this.totalWorkspaces,
    required this.activeWorkspaces,
    required this.totalProjects,
    required this.activeProjects,
    required this.totalTemplates,
    required this.totalRules,
    required this.activeRules,
    required this.totalActivities,
    required this.activeWorkspace,
    required this.activeProject,
    this.mostUsedWorkspace,
    this.mostUsedProject,
  });
}
