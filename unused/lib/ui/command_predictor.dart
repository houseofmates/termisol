import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/nvidia_ai_terminal_assistant.dart';

/// Command predictor with auto-completion for Termisol
/// 
/// Features:
/// - Real-time command prediction
/// - AI-powered suggestions
/// - Smart shell history with semantic search
/// - Context-aware completions
/// - Performance optimization
class TerminalCommandPredictor extends StatefulWidget {
  final Function(String) onCommandSelected;
  final Function(String) onPredictionSelected;
  final NvidiaAITerminalAssistant? aiAssistant;
  final List<String> initialHistory;
  
  const TerminalCommandPredictor({
    super.key,
    required this.onCommandSelected,
    required this.onPredictionSelected,
    this.aiAssistant,
    this.initialHistory = const [],
  });
  
  @override
  State<TerminalCommandPredictor> createState() => _TerminalCommandPredictorState();
}

class _TerminalCommandPredictorState extends State<TerminalCommandPredictor> 
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  final List<String> _commandHistory = [];
  final List<CommandSuggestion> _suggestions = [];
  final List<CommandHistoryEntry> _semanticHistory = [];
  final Map<String, int> _commandFrequency = {};
  
  bool _showSuggestions = false;
  int _selectedSuggestionIndex = -1;
  Timer? _debounceTimer;
  Timer? _aiRequestTimer;
  
  @override
  void initState() {
    super.initState();
    _commandHistory.addAll(widget.initialHistory);
    _analyzeCommandHistory();
    
    // Listen to AI assistant events
    if (widget.aiAssistant != null) {
      widget.aiAssistant!.events.listen(_handleAIEvent);
    }
  }
  
  void _analyzeCommandHistory() {
    // Analyze command frequency for better predictions
    for (final command in _commandHistory) {
      final baseCommand = _extractBaseCommand(command);
      _commandFrequency[baseCommand] = (_commandFrequency[baseCommand] ?? 0) + 1;
    }
  }
  
  String _extractBaseCommand(String command) {
    // Extract base command from full command with arguments
    final parts = command.trim().split(' ');
    if (parts.isEmpty) return '';
    return parts[0].toLowerCase();
  }
  
  void _handleAIEvent(AIAssistantEvent event) {
    if (event.type == AIAssistantEventType.inference_completed) {
      // Update suggestions when AI inference completes
      _updateSuggestionsFromAI();
    }
  }
  
  void _onTextChanged(String text) {
    // Cancel previous AI request
    _aiRequestTimer?.cancel();
    
    // Update suggestions
    _updateSuggestions(text);
    
    // Debounce AI request
    _aiRequestTimer?.cancel();
    _aiRequestTimer = Timer(const Duration(milliseconds: 300), () {
      if (text.isNotEmpty) {
        _requestAIPrediction(text);
      }
    });
  }
  
  Future<void> _requestAIPrediction(String partialCommand) async {
    if (widget.aiAssistant == null) return;
    
    try {
      final predictions = await widget.aiAssistant!.predictCommand(partialCommand);
      
      setState(() {
        _suggestions.clear();
        for (final prediction in predictions) {
          _suggestions.add(CommandSuggestion(
            command: prediction.command,
            description: prediction.description,
            confidence: prediction.confidence,
            examples: prediction.examples,
            isAI: true,
          ));
        }
        
        // Add local suggestions
        _addLocalSuggestions(partialCommand);
        
        _showSuggestions = _suggestions.isNotEmpty;
        _selectedSuggestionIndex = _suggestions.isNotEmpty ? 0 : -1;
      });
    } catch (e) {
      debugPrint('❌ AI prediction failed: $e');
    }
  }
  
  void _addLocalSuggestions(String partialCommand) {
    final baseCommand = _extractBaseCommand(partialCommand);
    
    // Add frequency-based suggestions
    final frequentCommands = _commandFrequency.entries
        .where((entry) => entry.key.startsWith(baseCommand))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in frequentCommands.take(3)) {
      _suggestions.add(CommandSuggestion(
        command: entry.key,
        description: 'Frequently used',
        confidence: 0.8,
        examples: [entry.key],
        isAI: false,
      ));
    }
    
    // Add pattern-based suggestions
    _addPatternSuggestions(partialCommand);
  }
  
  void _addPatternSuggestions(String partialCommand) {
    final patterns = [
      // Git commands
      if (partialCommand.startsWith('git')) ...[
        CommandSuggestion(command: 'git status', description: 'Show working tree status'),
        CommandSuggestion(command: 'git add .', description: 'Add all changes'),
        CommandSuggestion(command: 'git commit -m ""', description: 'Commit changes'),
        CommandSuggestion(command: 'git push', description: 'Push to remote'),
        CommandSuggestion(command: 'git log --oneline -10', description: 'Show recent commits'),
      ],
      
      // Docker commands
      if (partialCommand.startsWith('docker')) ...[
        CommandSuggestion(command: 'docker ps', description: 'List containers'),
        CommandSuggestion(command: 'docker run -it', description: 'Run interactive container'),
        CommandSuggestion(command: 'docker build', description: 'Build image'),
        CommandSuggestion(command: 'docker exec', description: 'Execute in container'),
      ],
      
      // File commands
      if (partialCommand.startsWith('ls') || partialCommand.startsWith('cd')) ...[
        CommandSuggestion(command: 'ls -la', description: 'List all files'),
        CommandSuggestion(command: 'cd ..', description: 'Go to parent directory'),
        CommandSuggestion(command: 'cd ~', description: 'Go to home directory'),
      ],
      
      // System commands
      if (partialCommand.startsWith('sudo')) ...[
        CommandSuggestion(command: 'sudo apt update', description: 'Update packages'),
        CommandSuggestion(command: 'sudo systemctl status', description: 'Check services'),
        CommandSuggestion(command: 'sudo journalctl -f', description: 'View logs'),
      ],
    ];
    
    for (final suggestion in patterns) {
      if (suggestion.command.startsWith(partialCommand)) {
        _suggestions.add(suggestion);
      }
    }
  }
  
  void _updateSuggestions(String text) {
    if (text.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _suggestions.clear();
        _selectedSuggestionIndex = -1;
      });
      return;
    }
    
    _updateSuggestions(text);
  }
  
  void _updateSuggestionsFromAI() {
    // This would be called when AI completes inference
    // Suggestions are already updated by _requestAIPrediction
  }
  
  void _selectSuggestion(int index) {
    setState(() {
      _selectedSuggestionIndex = index;
    });
    
    final suggestion = _suggestions[index];
    _controller.text = suggestion.command;
    widget.onPredictionSelected(suggestion.command);
  }
  
  void _executeCommand() {
    final command = _controller.text.trim();
    if (command.isNotEmpty) {
      // Add to history
      _commandHistory.insert(0, command);
      if (_commandHistory.length > 1000) {
        _commandHistory.removeLast();
      }
      
      // Add to semantic history
      _semanticHistory.insert(0, CommandHistoryEntry(
        command: command,
        timestamp: DateTime.now(),
        context: _extractContext(command),
      ));
      if (_semanticHistory.length > 500) {
        _semanticHistory.removeLast();
      }
      
      // Update frequency
      final baseCommand = _extractBaseCommand(command);
      _commandFrequency[baseCommand] = (_commandFrequency[baseCommand] ?? 0) + 1;
      
      widget.onCommandSelected(command);
      _controller.clear();
      
      setState(() {
        _showSuggestions = false;
        _suggestions.clear();
        _selectedSuggestionIndex = -1;
      });
    }
  }
  
  String _extractContext(String command) {
    // Extract context from command for semantic search
    final parts = command.split(' ');
    if (parts.length > 1) {
      return parts.sublist(1).join(' ');
    }
    return '';
  }
  
  List<CommandHistoryEntry> _searchSemanticHistory(String query) {
    if (query.isEmpty) return [];
    
    final lowerQuery = query.toLowerCase();
    return _semanticHistory.where((entry) {
      // Search in command and context
      return entry.command.toLowerCase().contains(lowerQuery) ||
             entry.context.toLowerCase().contains(lowerQuery);
    }).toList();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Command input with suggestions
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            border: Border.all(color: Colors.grey[700]!),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              // Search bar for semantic history
              if (_semanticHistory.isNotEmpty) _buildSearchBar(),
              
              // Command input
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                  hintText: 'Enter command or use AI prediction...',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _executeCommand(),
              ),
              
              // Suggestions dropdown
              if (_showSuggestions) _buildSuggestionsDropdown(),
            ],
          ),
        ),
        
        // Semantic history viewer
        if (_semanticHistory.isNotEmpty) _buildSemanticHistory(),
      ],
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: TextField(
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[600]!),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          hintText: 'Search command history...',
          hintStyle: TextStyle(color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
        ),
        onChanged: (query) {
          setState(() {
            // Filter semantic history
            // In a real implementation, this would update the displayed history
          });
        },
      ),
    );
  }
  
  Widget _buildSuggestionsDropdown() {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        border: Border.all(color: Colors.grey[600]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          final isSelected = index == _selectedSuggestionIndex;
          
          return InkWell(
            onTap: () => _selectSuggestion(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[700] : Colors.transparent,
              ),
              child: Row(
                children: [
                  // AI indicator
                  if (suggestion.isAI)
                    Icon(Icons.auto_awesome, color: Colors.purple[400], size: 16)
                  else
                    Icon(Icons.history, color: Colors.grey, size: 16),
                  
                  const SizedBox(width: 8),
                  
                  // Suggestion text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.command,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (suggestion.description.isNotEmpty)
                          Text(
                            suggestion.description,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        if (suggestion.confidence > 0)
                          Text(
                            '${(suggestion.confidence * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: suggestion.isAI ? Colors.purple[300] : Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildSemanticHistory() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border(top: BorderSide(color: Colors.grey[700]!)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text(
                    'COMMAND HISTORY',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _semanticHistory.clear();
                      });
                    },
                    child: const Text('Clear', style: TextStyle(color: Colors.blue)),
                  ),
                ],
              ),
            ),
            
            // History list
            Expanded(
              child: ListView.builder(
                itemCount: _semanticHistory.length,
                itemBuilder: (context, index) {
                  final entry = _semanticHistory[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[800]!),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.command,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            Text(
                              _formatTimestamp(entry.timestamp),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        if (entry.context.isNotEmpty)
                          Text(
                            entry.context,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _aiRequestTimer?.cancel();
    super.dispose();
  }
}

/// Command suggestion for auto-completion
class CommandSuggestion {
  final String command;
  final String description;
  final double confidence;
  final List<String> examples;
  final bool isAI;
  
  CommandSuggestion({
    required this.command,
    this.description = '',
    this.confidence = 0.0,
    this.examples = const [],
    this.isAI = false,
  });
}

/// Semantic command history entry
class CommandHistoryEntry {
  final String command;
  final DateTime timestamp;
  final String context;
  
  CommandHistoryEntry({
    required this.command,
    required this.timestamp,
    this.context = '',
  });
}
