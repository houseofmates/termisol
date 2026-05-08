import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Project-specific templates and snippets for personal code generation
/// 
/// Features:
/// - Project-specific code templates
/// - AI-generated snippets based on user's style
/// - Intelligent refactoring suggestions
/// - Personalized code patterns
/// - Template management and organization
class ProjectTemplates {
  final NvidiaAITerminalAssistant? aiAssistant;
  final StreamController<TemplateEvent> _eventController = StreamController<TemplateEvent>.broadcast();
  
  final Map<String, ProjectTemplate> _templates = {};
  final Map<String, List<CodeSnippet>> _snippets = {};
  final Map<String, RefactoringPattern> _refactoringPatterns = {};
  final Map<String, UserCodeStyle> _userCodeStyles = {};
  
  Timer? _analysisTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<TemplateEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  ProjectTemplates({this.aiAssistant});
  
  /// Initialize project templates system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadPersistedData();
      
      // Initialize default templates
      _initializeDefaultTemplates();
      
      // Start analysis timer
      _analysisTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        _analyzeUserPatterns();
      });
      
      _isInitialized = true;
      
      _eventController.add(TemplateEvent(
        type: TemplateEventType.initialized,
        message: 'Project templates system initialized',
        data: {'templates_count': _templates.length},
      ));
    } catch (e) {
      _eventController.add(TemplateEvent(
        type: TemplateEventType.error,
        message: 'Failed to initialize templates: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  void _initializeDefaultTemplates() {
    // Initialize templates for different project types
    _templates['development'] = ProjectTemplate(
      id: 'development',
      name: 'Development Project',
      description: 'Template for development projects',
      icon: Icons.code,
      color: Colors.blue[600]!,
      snippets: [
        CodeSnippet(
          id: 'flutter_widget',
          name: 'Flutter Widget',
          code: '''import 'package:flutter/material.dart';

class \${class_name} extends StatelessWidget {
  const \${class_name}({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('Hello World'),
    );
  }
}''',
          language: 'dart',
          description: 'Basic Flutter widget template',
          variables: ['class_name'],
        ),
        CodeSnippet(
          id: 'git_init',
          name: 'Git Repository Setup',
          code: '''# Initialize Git repository
git init
git add .
git commit -m "Initial commit"
git remote add origin \${remote_url}
git push -u origin main''',
          language: 'bash',
          description: 'Initialize and push Git repository',
          variables: ['remote_url'],
        ),
        CodeSnippet(
          id: 'dockerfile',
          name: 'Dockerfile',
          code: '''FROM \${base_image}

WORKDIR /app
COPY . .
RUN \${build_command}

EXPOSE \${port}

CMD ["\${run_command}"]''',
          language: 'dockerfile',
          description: 'Docker container template',
          variables: ['base_image', 'build_command', 'port', 'run_command'],
        ),
      ],
    );
    
    _templates['server_233'] = ProjectTemplate(
      id: 'server_233',
      name: 'Server .233',
      description: 'Template for server projects on .233',
      icon: Icons.dns,
      color: Colors.red[600]!,
      snippets: [
        CodeSnippet(
          id: 'nginx_config',
          name: 'Nginx Configuration',
          code: '''server {
    listen 80;
    server_name \${domain_name};
    root /var/www/\${project_name};
    
    location / {
        try_files \$uri \$uri/ = \$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
}''',
          language: 'nginx',
          description: 'Nginx server configuration',
          variables: ['domain_name', 'project_name'],
        ),
        CodeSnippet(
          id: 'systemd_service',
          name: 'Systemd Service',
          code: '''[Unit]
Description=\${service_name}
After=network.target

[Service]
Type=forking
User=\${user_name}
Group=\${group_name}
WorkingDirectory=\${working_directory}
ExecStart=\${exec_command}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target''',
          language: 'systemd',
          description: 'Systemd service configuration',
          variables: ['service_name', 'user_name', 'group_name', 'working_directory', 'exec_command'],
        ),
      ],
    );
    
    _templates['server_250'] = ProjectTemplate(
      id: 'server_250',
      name: 'Server .250',
      description: 'Template for server projects on .250',
      icon: Icons.dns,
      color: Colors.blue[600]!,
      snippets: [
        CodeSnippet(
          id: 'postgres_connection',
          name: 'PostgreSQL Connection',
          code: '''import psycopg2
import os

# Database connection
conn = psycopg2.connect(
    host="\${host}",
    database="\${database}",
    user="\${user}",
    password="\${password}",
    port=\${port}
)

# Create cursor
cursor = conn.cursor()

# Execute query
cursor.execute("\${query}")

# Fetch results
results = cursor.fetchall()

# Close connection
conn.close()''',
          language: 'python',
          description: 'PostgreSQL database connection',
          variables: ['host', 'database', 'user', 'password', 'port', 'query'],
        ),
        CodeSnippet(
          id: 'api_endpoint',
          name: 'API Endpoint',
          code: '''from flask import Flask, jsonify, request
import psycopg2

app = Flask(__name__)

@app.route('/\${endpoint}', methods=['\${method}'])
def \${function_name}():
    try:
        conn = psycopg2.connect(
            host="\${host}",
            database="\${database}",
            user="\${user}",
            password="\${password}"
        )
        cursor = conn.cursor()
        
        cursor.execute("\${query}")
        results = cursor.fetchall()
        
        conn.close()
        
        return jsonify({"status": "success", "data": results})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=\${port})''',
          language: 'python',
          description: 'Flask API endpoint',
          variables: ['endpoint', 'method', 'function_name', 'host', 'database', 'user', 'password', 'query', 'port'],
        ),
      ],
    );
  }
  
  /// Generate personalized code snippet
  Future<CodeSnippet> generatePersonalizedSnippet({
    required String templateId,
    required Map<String, String> variables,
    String? projectId,
  }) async {
    try {
      // Get template
      final template = _getTemplate(templateId, projectId);
      if (template == null) {
        throw Exception('Template not found: $templateId');
      }
      
      // Find matching snippet
      final snippet = template.snippets.firstWhere(
        (s) => s.id == templateId,
        orElse: () => throw Exception('Snippet not found: $templateId'),
      );
      
      // Generate personalized code
      final personalizedCode = _substituteVariables(snippet.code, variables);
      
      // Apply user code style
      final styledCode = await _applyUserCodeStyle(personalizedCode, projectId);
      
      // Create personalized snippet
      final personalizedSnippet = CodeSnippet(
        id: snippet.id,
        name: snippet.name,
        code: styledCode,
        language: snippet.language,
        description: snippet.description,
        variables: snippet.variables,
        isPersonalized: true,
        generatedAt: DateTime.now(),
        projectId: projectId,
      );
      
      _eventController.add(TemplateEvent(
        type: TemplateEventType.snippet_generated,
        message: 'Personalized snippet generated',
        data: {'snippet': personalizedSnippet.toJson()},
      ));
      
      return personalizedSnippet;
    } catch (e) {
      _eventController.add(TemplateEvent(
        type: TemplateEventType.error,
        message: 'Failed to generate snippet: $e',
        data: {'error': e.toString()},
      ));
      rethrow;
    }
  }
  
  String _substituteVariables(String code, Map<String, String> variables) {
    var result = code;
    
    for (final entry in variables.entries) {
      result = result.replaceAll('\${${entry.key}}', entry.value);
    }
    
    return result;
  }
  
  Future<String> _applyUserCodeStyle(String code, String? projectId) async {
    if (aiAssistant == null) return code;
    
    try {
      // Get user's code style preferences
      final userStyle = _getUserCodeStyle(projectId);
      
      final prompt = '''Apply my personal coding style to this code:

Code:
$code

My coding style preferences:
- Indentation: ${userStyle.indentation}
- Line endings: ${userStyle.lineEndings}
- Naming convention: ${userStyle.namingConvention}
- Comment style: ${userStyle.commentStyle}
- Code organization: ${userStyle.codeOrganization}

Return only the styled code, no explanations.''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      // Extract styled code from AI response
      final styledCode = _extractCodeFromResponse(response);
      
      return styledCode;
    } catch (e) {
      debugPrint('❌ Failed to apply user code style: $e');
      return code;
    }
  }
  
  String _extractCodeFromResponse(String response) {
    // Extract code block from AI response
    final codeBlockRegex = RegExp(r'```(?:\w+)?\n?([\s\S]*?)\n?```');
    final match = codeBlockRegex.firstMatch(response);
    
    if (match != null) {
      return match.group(1) ?? '';
    }
    
    // Fallback: return response as-is
    return response;
  }
  
  /// Get intelligent refactoring suggestions
  Future<List<RefactoringSuggestion>> getRefactoringSuggestions({
    required String code,
    required String language,
    String? projectId,
  }) async {
    try {
      // Analyze code for refactoring opportunities
      final suggestions = <RefactoringSuggestion>[];
      
      // Pattern-based refactoring
      suggestions.addAll(_getPatternBasedRefactoring(code, language));
      
      // AI-powered refactoring
      if (aiAssistant != null) {
        final aiSuggestions = await _getAIRefactoringSuggestions(code, language, projectId);
        suggestions.addAll(aiSuggestions);
      }
      
      // Sort by confidence
      suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
      
      _eventController.add(TemplateEvent(
        type: TemplateEventType.refactoring_suggestions_generated,
        message: 'Refactoring suggestions generated',
        data: {'suggestions_count': suggestions.length},
      ));
      
      return suggestions.take(10).toList();
    } catch (e) {
      _eventController.add(TemplateEvent(
        type: TemplateEventType.error,
        message: 'Failed to generate refactoring suggestions: $e',
        data: {'error': e.toString()},
      ));
      return [];
    }
  }
  
  List<RefactoringSuggestion> _getPatternBasedRefactoring(String code, String language) {
    final suggestions = <RefactoringSuggestion>[];
    
    switch (language.toLowerCase()) {
      case 'dart':
        suggestions.addAll(_getDartRefactoring(code));
        break;
      case 'python':
        suggestions.addAll(_getPythonRefactoring(code));
        break;
      case 'javascript':
        suggestions.addAll(_getJavaScriptRefactoring(code));
        break;
      case 'typescript':
        suggestions.addAll(_getTypeScriptRefactoring(code));
        break;
    }
    
    return suggestions;
  }
  
  List<RefactoringSuggestion> _getDartRefactoring(String code) {
    final suggestions = <RefactoringSuggestion>[];
    
    // Extract method refactoring
    if (code.contains('class ') && code.contains('{')) {
      final methodRegex = RegExp(r'^\s*\w+\s+\w+\([^)]*)\s*{');
      final matches = methodRegex.allMatches(code);
      
      for (final match in matches.take(5)) {
        suggestions.add(RefactoringSuggestion(
          type: RefactoringType.extract_method,
          description: 'Extract method: ${match.group(1)}',
          originalCode: match.group(0)!,
          suggestedCode: '''  \${match.group(1)}() {
    // Add your method implementation here
  }''',
          confidence: 0.7,
          lineNumbers: _getLineNumbers(code, match.group(0)!),
        ));
      }
    }
    
    return suggestions;
  }
  
  List<RefactoringSuggestion> _getPythonRefactoring(String code) {
    final suggestions = <RefactoringSuggestion>[];
    
    // List comprehension refactoring
    if (code.contains('for ') && code.contains(' in ') && code.contains(':')) {
      suggestions.add(RefactoringSuggestion(
        type: RefactoringType.list_comprehension,
        description: 'Use list comprehension',
        originalCode: code,
        suggestedCode: '''# Replace for loop with list comprehension
result = [item for item in iterable if condition]''',
          confidence: 0.8,
          lineNumbers: _getLineNumbers(code, code),
        ));
    }
    
    return suggestions;
  }
  
  List<RefactoringSuggestion> _getJavaScriptRefactoring(String code) {
    final suggestions = <RefactoringSuggestion>[];
    
    // Arrow function refactoring
    if (code.contains('function(') && code.contains('return')) {
      suggestions.add(RefactoringSuggestion(
        type: RefactoringType.arrow_function,
        description: 'Convert to arrow function',
        originalCode: code,
        suggestedCode: '''// Convert to arrow function
const \${function_name} = (\${params}) => \${return_value};''',
          confidence: 0.6,
          lineNumbers: _getLineNumbers(code, code),
        ));
    }
    
    return suggestions;
  }
  
  List<RefactoringSuggestion> _getTypeScriptRefactoring(String code) {
    final suggestions = <RefactoringSuggestion>[];
    
    // Interface extraction
    if (code.contains('interface ') && code.contains('implements')) {
      suggestions.add(RefactoringSuggestion(
        type: RefactoringType.extract_interface,
        description: 'Extract interface',
        originalCode: code,
        suggestedCode: '''// Extract interface
interface \${interface_name} {
  \${properties}
}''',
          confidence: 0.7,
          lineNumbers: _getLineNumbers(code, code),
        ));
    }
    
    return suggestions;
  }
  
  Future<List<RefactoringSuggestion>> _getAIRefactoringSuggestions(
    String code,
    String language,
    String? projectId,
  ) async {
    if (aiAssistant == null) return [];
    
    try {
      final prompt = '''Analyze this code and provide refactoring suggestions:

Code:
$code

Language: $language
Project: ${projectId ?? 'None'}

My coding preferences:
- Clean, readable code
- Extract methods when > 20 lines
- Use modern language features
- Follow SOLID principles
- Add appropriate comments

Provide 3-5 specific refactoring suggestions with:
1. Type of refactoring
2. Original code snippet
3. Suggested refactored code
4. Explanation of benefits
5. Confidence level (0.0-1.0)

Use these NVIDIA AI models:
- deepseek-ai/deepseek-v4-pro for comprehensive analysis
- moonshotai/kimi-k2.6 for optimization strategies
- z-ai/glm-5.1 for technical solutions''';
      
      final response = await aiAssistant!.explainCommand(prompt);
      
      // Parse AI response into suggestions
      final suggestions = _parseAIRefactoringResponse(response);
      
      return suggestions;
    } catch (e) {
      debugPrint('❌ AI refactoring failed: $e');
      return [];
    }
  }
  
  List<RefactoringSuggestion> _parseAIRefactoringResponse(String response) {
    final suggestions = <RefactoringSuggestion>[];
    final lines = response.split('\n');
    
    RefactoringSuggestion? currentSuggestion;
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      if (line.toLowerCase().contains('refactoring type:')) {
        if (currentSuggestion != null) {
          suggestions.add(currentSuggestion);
        }
        currentSuggestion = null;
      } else if (line.toLowerCase().contains('original code:')) {
        currentSuggestion?.originalCode = line.split('original code:')[1].trim();
      } else if (line.toLowerCase().contains('suggested code:')) {
        currentSuggestion?.suggestedCode = line.split('suggested code:')[1].trim();
      } else if (line.toLowerCase().contains('explanation:')) {
        currentSuggestion?.description = line.split('explanation:')[1].trim();
      } else if (line.toLowerCase().contains('confidence:')) {
        final confidenceStr = line.split('confidence:')[1].trim();
        currentSuggestion?.confidence = double.tryParse(confidenceStr) ?? 0.5;
      }
    }
    
    if (currentSuggestion != null) {
      suggestions.add(currentSuggestion);
    }
    
    return suggestions;
  }
  
  List<int> _getLineNumbers(String fullCode, String snippet) {
    final lines = fullCode.split('\n');
    final snippetLines = snippet.split('\n');
    
    if (snippetLines.isEmpty) return [];
    
    final firstLine = fullCode.indexOf(snippetLines.first);
    final lastLine = fullCode.indexOf(snippetLines.last);
    
    final startLine = fullCode.substring(0, firstLine).split('\n').length;
    final endLine = fullCode.substring(0, lastLine).split('\n').length;
    
    return List.generate(endLine - startLine + 1, (index) => startLine + index);
  }
  
  /// Save user code style preference
  Future<void> saveUserCodeStyle({
    required String projectId,
    required UserCodeStyle style,
  }) async {
    try {
      _userCodeStyles[projectId] = style;
      await _persistUserCodeStyles();
      
      _eventController.add(TemplateEvent(
        type: TemplateEventType.style_saved,
        message: 'User code style saved',
        data: {'project': projectId, 'style': style.toJson()},
      ));
    } catch (e) {
      _eventController.add(TemplateEvent(
        type: TemplateEventType.error,
        message: 'Failed to save user code style: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Get user code style
  UserCodeStyle _getUserCodeStyle(String? projectId) {
    if (projectId == null) return _getDefaultCodeStyle();
    
    return _userCodeStyles[projectId] ?? _getDefaultCodeStyle();
  }
  
  UserCodeStyle _getDefaultCodeStyle() {
    return UserCodeStyle(
      indentation: '2 spaces',
      lineEndings: 'LF',
      namingConvention: 'camelCase',
      commentStyle: 'docstring',
      codeOrganization: 'single_responsibility',
    );
  }
  
  ProjectTemplate _getTemplate(String templateId, String? projectId) {
    if (projectId != null && _templates.containsKey(projectId)) {
      return _templates[projectId]!;
    }
    
    return _templates[templateId];
  }
  
  /// Analyze user patterns
  void _analyzeUserPatterns() {
    // This would analyze user's coding patterns and update templates
    // Implementation would track:
    // - Frequently used patterns
    // - Preferred code organization
    // - Common refactoring types
    // - Style preferences evolution
    
    _eventController.add(TemplateEvent(
      type: TemplateEventType.patterns_analyzed,
      message: 'User patterns analyzed',
      data: {},
    ));
  }
  
  /// Get template statistics
  Map<String, dynamic> getTemplateStatistics() {
    return {
      'is_initialized': _isInitialized,
      'templates_count': _templates.length,
      'snippets_count': _snippets.values.fold(0, (sum, snippets) => sum + snippets.length),
      'refactoring_patterns_count': _refactoringPatterns.length,
      'user_code_styles_count': _userCodeStyles.length,
      'project_coverage': _templates.keys.toList(),
    };
  }
  
  /// Load persisted data
  Future<void> _loadPersistedData() async {
    try {
      // Load templates
      final templatesJson = _prefs.getString('project_templates') ?? '{}';
      final templatesMap = jsonDecode(templatesJson) as Map;
      _templates.clear();
      for (final entry in templatesMap.entries) {
        _templates[entry.key] = ProjectTemplate.fromJson(entry.value);
      }
      
      // Load snippets
      final snippetsJson = _prefs.getString('code_snippets') ?? '{}';
      final snippetsMap = jsonDecode(snippetsJson) as Map;
      _snippets.clear();
      for (final entry in snippetsMap.entries) {
        _snippets[entry.key] = (entry.value as List)
            .map((item) => CodeSnippet.fromJson(item))
            .toList();
      }
      
      // Load refactoring patterns
      final refactoringJson = _prefs.getString('refactoring_patterns') ?? '{}';
      final refactoringMap = jsonDecode(refactoringJson) as Map;
      _refactoringPatterns.clear();
      for (final entry in refactoringMap.entries) {
        _refactoringPatterns[entry.key] = RefactoringPattern.fromJson(entry.value);
      }
      
      // Load user code styles
      final stylesJson = _prefs.getString('user_code_styles') ?? '{}';
      final stylesMap = jsonDecode(stylesJson) as Map;
      _userCodeStyles.clear();
      for (final entry in stylesMap.entries) {
        _userCodeStyles[entry.key] = UserCodeStyle.fromJson(entry.value);
      }
      
    } catch (e) {
      debugPrint('❌ Failed to load persisted data: $e');
    }
  }
  
  /// Persist data
  Future<void> _persistData() async {
    try {
      // Save templates
      final templatesJson = jsonEncode(_templates.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('project_templates', templatesJson);
      
      // Save snippets
      final snippetsJson = jsonEncode(_snippets.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())));
      await _prefs.setString('code_snippets', snippetsJson);
      
      // Save refactoring patterns
      final refactoringJson = jsonEncode(_refactoringPatterns.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('refactoring_patterns', refactoringJson);
      
      // Save user code styles
      final stylesJson = jsonEncode(_userCodeStyles.map((k, v) => MapEntry(k, v.toJson())));
      await _prefs.setString('user_code_styles', stylesJson);
      
    } catch (e) {
      debugPrint('❌ Failed to persist data: $e');
    }
  }
  
  /// Dispose
  void dispose() {
    _analysisTimer?.cancel();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Project template
class ProjectTemplate {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final List<CodeSnippet> snippets;
  
  ProjectTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.snippets,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon.codePoint.toString(),
    'color': color.value,
    'snippets': snippets.map((s) => s.toJson()).toList(),
  };
  
  factory ProjectTemplate.fromJson(Map<String, dynamic> json) {
    return ProjectTemplate(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      icon: IconData(int.parse(json['icon'])),
      color: Color(int.parse(json['color'])),
      snippets: (json['snippets'] as List)
          .map((s) => CodeSnippet.fromJson(s))
          .toList(),
    );
  }
}

/// Code snippet
class CodeSnippet {
  final String id;
  final String name;
  final String code;
  final String language;
  final String description;
  final List<String> variables;
  final bool isPersonalized;
  final DateTime? generatedAt;
  final String? projectId;
  
  CodeSnippet({
    required this.id,
    required this.name,
    required this.code,
    required this.language,
    required this.description,
    required this.variables,
    this.isPersonalized = false,
    this.generatedAt,
    this.projectId,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'language': language,
    'description': description,
    'variables': variables,
    'is_personalized': isPersonalized,
    'generated_at': generatedAt?.toIso8601String(),
    'project_id': projectId,
  };
  
  factory CodeSnippet.fromJson(Map<String, dynamic> json) {
    return CodeSnippet(
      id: json['id'],
      name: json['name'],
      code: json['code'],
      language: json['language'],
      description: json['description'],
      variables: List<String>.from(json['variables'] ?? []),
      isPersonalized: json['is_personalized'] ?? false,
      generatedAt: json['generated_at'] != null ? DateTime.parse(json['generated_at']) : null,
      projectId: json['project_id'],
    );
  }
}

/// Refactoring suggestion
class RefactoringSuggestion {
  final RefactoringType type;
  final String description;
  final String originalCode;
  final String suggestedCode;
  final double confidence;
  final List<int> lineNumbers;
  
  RefactoringSuggestion({
    required this.type,
    required this.description,
    required this.originalCode,
    required this.suggestedCode,
    required this.confidence,
    required this.lineNumbers,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.toString(),
    'description': description,
    'original_code': originalCode,
    'suggested_code': suggestedCode,
    'confidence': confidence,
    'line_numbers': lineNumbers,
  };
}

/// Refactoring pattern
class RefactoringPattern {
  final String id;
  final RefactoringType type;
  final String pattern;
  final String replacement;
  final double confidence;
  final DateTime lastUsed;
  
  RefactoringPattern({
    required this.id,
    required this.type,
    required this.pattern,
    required this.replacement,
    required this.confidence,
    required this.lastUsed,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toString(),
    'pattern': pattern,
    'replacement': replacement,
    'confidence': confidence,
    'last_used': lastUsed.toIso8601String(),
  };
  
  factory RefactoringPattern.fromJson(Map<String, dynamic> json) {
    return RefactoringPattern(
      id: json['id'],
      type: RefactoringType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => RefactoringType.extract_method,
      ),
      pattern: json['pattern'],
      replacement: json['replacement'],
      confidence: json['confidence'],
      lastUsed: DateTime.parse(json['last_used']),
    );
  }
}

/// User code style
class UserCodeStyle {
  final String indentation;
  final String lineEndings;
  final String namingConvention;
  final String commentStyle;
  final String codeOrganization;
  
  UserCodeStyle({
    required this.indentation,
    required this.lineEndings,
    required this.namingConvention,
    required this.commentStyle,
    required this.codeOrganization,
  });
  
  Map<String, dynamic> toJson() => {
    'indentation': indentation,
    'line_endings': lineEndings,
    'naming_convention': namingConvention,
    'comment_style': commentStyle,
    'code_organization': codeOrganization,
  };
  
  factory UserCodeStyle.fromJson(Map<String, dynamic> json) {
    return UserCodeStyle(
      indentation: json['indentation'],
      lineEndings: json['line_endings'],
      namingConvention: json['naming_convention'],
      commentStyle: json['comment_style'],
      codeOrganization: json['code_organization'],
    );
  }
}

/// Refactoring types
enum RefactoringType {
  extract_method,
  list_comprehension,
  arrow_function,
  extract_interface,
  rename_variable,
  inline_function,
  simplify_condition,
  extract_class,
  optimize_imports,
}

/// Template event types
enum TemplateEventType {
  initialized,
  snippet_generated,
  refactoring_suggestions_generated,
  style_saved,
  patterns_analyzed,
  error,
}

/// Template event
class TemplateEvent {
  final TemplateEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  TemplateEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
