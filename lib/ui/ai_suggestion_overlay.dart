import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ai/ai_terminal_assistant.dart';
import '../config/pkm_theme.dart';

/// AI suggestion overlay with inline error explanation and command generation.
class AiSuggestionOverlay extends StatefulWidget {
  final String currentError;
  final String currentCommand;
  final String workingDirectory;
  final VoidCallback? onDismiss;
  final Function(String)? onCommandAccept;
  final Function(String)? onExplanationAccept;

  const AiSuggestionOverlay({
    super.key,
    required this.currentError,
    required this.currentCommand,
    required this.workingDirectory,
    this.onDismiss,
    this.onCommandAccept,
    this.onExplanationAccept,
  });

  @override
  State<AiSuggestionOverlay> createState() => _AiSuggestionOverlayState();
}

class _AiSuggestionOverlayState extends State<AiSuggestionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _isLoading = false;
  String? _suggestedCommand;
  String? _explanation;
  String? _errorAnalysis;
  List<String> _alternativeCommands = [];

  final _aiAssistant = NvidiaAITerminalAssistant();

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
    _analyzeError();
  }

  @override
  void didUpdateWidget(AiSuggestionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentError != widget.currentError) {
      _analyzeError();
    }
  }

  Future<void> _analyzeError() async {
    if (widget.currentError.isEmpty) return;

    setState(() {
      _isLoading = true;
      _suggestedCommand = null;
      _explanation = null;
      _errorAnalysis = null;
      _alternativeCommands.clear();
    });

    try {
      // Analyze the error
      final analysisResponse = await _aiAssistant.processText(
        input: 'Analyze this terminal error and explain what went wrong: "${widget.currentError}"',
        capability: AICapability.system_analysis,
        contextId: 'error_analysis_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (analysisResponse.success) {
        setState(() {
          _errorAnalysis = analysisResponse.output;
        });
      }

      // Generate suggested fix
      final fixResponse = await _aiAssistant.processText(
        input: 'Suggest a command to fix this error: "${widget.currentError}". Current command was: "${widget.currentCommand}". Working directory: "${widget.workingDirectory}". Provide only the command, no explanation.',
        capability: AICapability.command_suggestion,
        contextId: 'error_fix_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (fixResponse.success) {
        final command = fixResponse.output.trim();
        if (command.isNotEmpty && !command.contains('```')) {
          setState(() {
            _suggestedCommand = command;
          });
        }
      }

      // Generate detailed explanation
      final explanationResponse = await _aiAssistant.processText(
        input: 'Explain this error in simple terms and suggest what to do: "${widget.currentError}"',
        capability: AICapability.text_generation,
        contextId: 'error_explanation_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (explanationResponse.success) {
        setState(() {
          _explanation = explanationResponse.output;
        });
      }

      // Generate alternative commands
      final alternativesResponse = await _aiAssistant.processText(
        input: 'Suggest 3 alternative commands to accomplish what was intended with: "${widget.currentCommand}" that failed with: "${widget.currentError}". Format as a JSON array of strings.',
        capability: AICapability.command_suggestion,
        contextId: 'alternatives_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (alternativesResponse.success) {
        try {
          final alternatives = alternativesResponse.output;
          final cleaned = alternatives.replaceAll('```json', '').replaceAll('```', '').trim();
          final list = List<String>.from(jsonDecode(cleaned));
          setState(() {
            _alternativeCommands = list.take(3).toList();
          });
        } catch (e) {
          debugPrint('Failed to parse alternative commands: $e');
        }
      }
    } catch (e) {
      debugPrint('AI analysis failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentError.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: PkmTheme.tabActiveBg.withOpacity(0.95),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  if (_isLoading) _buildLoadingIndicator() else _buildContent(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red.shade400,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'command failed',
              style: TextStyle(
                color: Colors.red.shade400,
                fontFamily: PkmTheme.fontUi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              color: Colors.grey,
              size: 18,
            ),
            onPressed: () {
              _animationController.reverse().then((_) {
                widget.onDismiss?.call();
              });
            },
            tooltip: 'dismiss',
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(PkmTheme.primary),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorAnalysis != null) ...[
            _buildSectionTitle('what went wrong'),
            const SizedBox(height: 8),
            _buildAnalysis(_errorAnalysis!),
            const SizedBox(height: 16),
          ],
          
          if (_suggestedCommand != null) ...[
            _buildSectionTitle('suggested fix'),
            const SizedBox(height: 8),
            _buildSuggestedCommand(_suggestedCommand!),
            const SizedBox(height: 16),
          ],
          
          if (_explanation != null) ...[
            _buildSectionTitle('explanation'),
            const SizedBox(height: 8),
            _buildExplanation(_explanation!),
            const SizedBox(height: 16),
          ],
          
          if (_alternativeCommands.isNotEmpty) ...[
            _buildSectionTitle('alternatives'),
            const SizedBox(height: 8),
            ..._alternativeCommands.map((cmd) => _buildAlternativeCommand(cmd)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: PkmTheme.primary,
        fontFamily: PkmTheme.fontUi,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        textBaseline: TextBaseline.alphabetic,
      ),
    );
  }

  Widget _buildAnalysis(String analysis) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        analysis,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontFamily: PkmTheme.fontUi,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildSuggestedCommand(String command) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PkmTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: PkmTheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: PkmTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    command,
                    style: TextStyle(
                      color: PkmTheme.primary,
                      fontFamily: PkmTheme.fontTerminal,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.copy,
                    color: PkmTheme.primary,
                    size: 16,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: command));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('command copied'),
                        backgroundColor: PkmTheme.primary,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: 'copy command',
                ),
                IconButton(
                  icon: const Icon(
                    Icons.play_arrow,
                    color: PkmTheme.primary,
                    size: 16,
                  ),
                  onPressed: () {
                    widget.onCommandAccept?.call(command);
                    _animationController.reverse().then((_) {
                      widget.onDismiss?.call();
                    });
                  },
                  tooltip: 'run command',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanation(String explanation) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.blue.shade400,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'why this happened',
                style: TextStyle(
                  color: Colors.blue.shade400,
                  fontFamily: PkmTheme.fontUi,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontFamily: PkmTheme.fontUi,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlternativeCommand(String command) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.alt_route,
              color: Colors.grey.shade400,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                command,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontFamily: PkmTheme.fontTerminal,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.play_arrow,
                color: Colors.grey.shade400,
                size: 16,
              ),
              onPressed: () {
                widget.onCommandAccept?.call(command);
                _animationController.reverse().then((_) {
                  widget.onDismiss?.call();
                });
              },
              tooltip: 'run alternative',
            ),
          ],
        ),
      ),
    );
  }
}

/// Natural language command generator widget.
class NaturalLanguageCommandGenerator extends StatefulWidget {
  final String workingDirectory;
  final Function(String)? onCommandGenerated;

  const NaturalLanguageCommandGenerator({
    super.key,
    required this.workingDirectory,
    this.onCommandGenerated,
  });

  @override
  State<NaturalLanguageCommandGenerator> createState() => _NaturalLanguageCommandGeneratorState();
}

class _NaturalLanguageCommandGeneratorState extends State<NaturalLanguageCommandGenerator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isGenerating = false;
  String? _generatedCommand;
  List<String> _suggestions = [];

  final _aiAssistant = NvidiaAITerminalAssistant();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _generateCommand() async {
    final input = _textController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _generatedCommand = null;
      _suggestions.clear();
    });

    try {
      final response = await _aiAssistant.processText(
        input: 'Convert this natural language request to a terminal command: "$input". Working directory: "${widget.workingDirectory}". Return only the command, no explanation.',
        capability: AICapability.command_suggestion,
        contextId: 'nl_command_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (response.success) {
        final command = response.output.trim();
        if (command.isNotEmpty && !command.contains('```')) {
          setState(() {
            _generatedCommand = command;
          });
        }
      }

      // Generate alternatives
      final altResponse = await _aiAssistant.processText(
        input: 'Suggest 3 alternative commands for: "$input". Format as a JSON array of strings.',
        capability: AICapability.command_suggestion,
        contextId: 'nl_alternatives_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (altResponse.success) {
        try {
          final alternatives = altResponse.output;
          final cleaned = alternatives.replaceAll('```json', '').replaceAll('```', '').trim();
          final list = List<String>.from(jsonDecode(cleaned));
          setState(() {
            _suggestions = list.take(3).toList();
          });
        } catch (e) {
          debugPrint('Failed to parse alternatives: $e');
        }
      }
    } catch (e) {
      debugPrint('Command generation failed: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PkmTheme.tabActiveBg.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PkmTheme.primary.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology,
                  color: PkmTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'natural language command',
                  style: TextStyle(
                    color: PkmTheme.primary,
                    fontFamily: PkmTheme.fontUi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              focusNode: _focusNode,
              style: TextStyle(
                color: Colors.white,
                fontFamily: PkmTheme.fontUi,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'describe what you want to do...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontFamily: PkmTheme.fontUi,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.black.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(PkmTheme.primary),
                          ),
                        )
                      : Icon(
                          Icons.send,
                          color: PkmTheme.primary,
                          size: 18,
                        ),
                  onPressed: _isGenerating ? null : _generateCommand,
                ),
              ),
              onSubmitted: (_) => _generateCommand(),
            ),
            if (_generatedCommand != null) ...[
              const SizedBox(height: 12),
              _buildGeneratedCommand(_generatedCommand!),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._suggestions.map((cmd) => _buildSuggestion(cmd)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratedCommand(String command) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PkmTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PkmTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: PkmTheme.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              command,
              style: TextStyle(
                color: PkmTheme.primary,
                fontFamily: PkmTheme.fontTerminal,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.copy,
              color: PkmTheme.primary,
              size: 16,
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
            },
            tooltip: 'copy',
          ),
          IconButton(
            icon: const Icon(
              Icons.play_arrow,
              color: PkmTheme.primary,
              size: 16,
            ),
            onPressed: () {
              widget.onCommandGenerated?.call(command);
              _textController.clear();
              setState(() {
                _generatedCommand = null;
                _suggestions.clear();
              });
            },
            tooltip: 'run',
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestion(String command) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.alt_route,
              color: Colors.grey.shade400,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                command,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontFamily: PkmTheme.fontTerminal,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.play_arrow,
                color: Colors.grey.shade400,
                size: 16,
              ),
              onPressed: () {
                widget.onCommandGenerated?.call(command);
                _textController.clear();
                setState(() {
                  _generatedCommand = null;
                  _suggestions.clear();
                });
              },
              tooltip: 'run',
            ),
          ],
        ),
      ),
    );
  }
}