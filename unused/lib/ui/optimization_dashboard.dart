import 'dart:async';
import 'package:flutter/material.dart';
import '../core/optimized_text_buffer.dart';
import '../core/lazy_terminal_output.dart';
import '../core/smart_auto_complete.dart';
import '../core/session_persistence.dart';
import '../core/crash_recovery.dart';
import '../core/long_command_notifier.dart';
import '../core/termisol_plugin_system.dart';

/// Optimization monitoring dashboard for Termisol
/// 
/// Features:
/// - Real-time performance metrics
/// - Memory usage monitoring
/// - Plugin management
/// - Session statistics
/// - Crash recovery status
class OptimizationDashboard extends StatefulWidget {
  final Map<String, dynamic> sessionStats;
  final Function(String) onPluginAction;
  final VoidCallback onClearCache;
  final VoidCallback onOptimizeMemory;

  const OptimizationDashboard({
    super.key,
    required this.sessionStats,
    required this.onPluginAction,
    required this.onClearCache,
    required this.onOptimizeMemory,
  });

  @override
  State<OptimizationDashboard> createState() => _OptimizationDashboardState();
}

class _OptimizationDashboardState extends State<OptimizationDashboard> {
  Timer? _updateTimer;
  Map<String, dynamic> _currentStats = {};
  bool _isOptimizing = false;

  @override
  void initState() {
    super.initState();
    _currentStats = widget.sessionStats;
    _startMonitoring();
  }

  void _startMonitoring() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() {
        _currentStats = widget.sessionStats;
      });
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 14, color: Color(0xFF7CB9FF)),
          const SizedBox(width: 8),
          const Text('optimization dashboard',
            style: TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_isOptimizing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7CB9FF)),
              ),
            ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPerformanceMetrics(),
          const SizedBox(height: 16),
          _buildMemoryUsage(),
          const SizedBox(height: 16),
          _buildSessionStats(),
          const SizedBox(height: 16),
          _buildPluginManagement(),
          const SizedBox(height: 16),
          _buildOptimizationActions(),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetrics() {
    final bufferStats = _currentStats['buffer_stats'] as BufferStats?;
    final memoryUsage = bufferStats?.memoryUsage ?? 0;
    final totalLines = bufferStats?.totalLines ?? 0;
    final usedLines = bufferStats?.usedLines ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('performance metrics', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildMetricRow('memory usage', '${(memoryUsage / 1024).toStringAsFixed(1)} KB', Colors.blue),
        _buildMetricRow('total lines', '$totalLines', Colors.green),
        _buildMetricRow('used lines', '$usedLines', Colors.orange),
        _buildMetricRow('cursor position', '${bufferStats?.cursorPosition ?? 0}', Colors.purple),
      ],
    );
  }

  Widget _buildMemoryUsage() {
    final lazyStats = _currentStats['lazy_output_stats'] as Map<String, dynamic>?;
    final totalLines = lazyStats?['total_lines'] ?? 0;
    final visibleLines = lazyStats?['visible_lines'] ?? 0;
    final isLoading = lazyStats?['is_loading'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('memory usage', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildMetricRow('total lines', '$totalLines', Colors.blue),
        _buildMetricRow('visible lines', '$visibleLines', Colors.green),
        _buildMetricRow('loading', isLoading ? 'Yes' : 'No', isLoading ? Colors.orange : Colors.green),
        _buildProgressBar('buffer usage', visibleLines / (totalLines > 0 ? totalLines : 1)),
      ],
    );
  }

  Widget _buildSessionStats() {
    final autoStats = _currentStats['auto_complete_stats'] as Map<String, dynamic>?;
    final historySize = autoStats?['history_size'] ?? 0;
    final commandFrequency = autoStats?['command_frequency'] as Map<String, int>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('session statistics', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildMetricRow('history size', '$historySize', Colors.blue),
        _buildMetricRow('frequency entries', '${commandFrequency.length}', Colors.green),
        if (commandFrequency.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text('top commands:', style: TextStyle(color: Color(0xFF666666), fontSize: 9)),
          ...commandFrequency.entries.take(3).map((entry) => 
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key, style: const TextStyle(color: Color(0xFF999999), fontSize: 9))),
                  Text('${entry.value}', style: const TextStyle(color: Color(0xFF7CB9FF), fontSize: 9)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPluginManagement() {
    final activePlugins = _currentStats['active_plugins'] as List<String>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('plugin management', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (activePlugins.isEmpty)
          const Text('no active plugins', style: TextStyle(color: Color(0xFF666666), fontSize: 9))
        else ...[
          ...activePlugins.map((plugin) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Icon(Icons.extension, size: 12, color: Color(0xFF7CB9FF)),
                const SizedBox(width: 4),
                Expanded(child: Text(plugin, style: const TextStyle(color: Color(0xFF999999), fontSize: 9))),
                TextButton(
                  onPressed: () => widget.onPluginAction(plugin),
                  child: Text('manage', style: TextStyle(color: const Color(0xFF7CB9FF), fontSize: 9)),
                ),
              ],
            ),
          )),
        ],
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2a2a2a)),
          onPressed: () => widget.onPluginAction('load'),
          child: const Text('load plugin', style: TextStyle(fontSize: 10, color: Color(0xFF999999))),
        ),
      ],
    );
  }

  Widget _buildOptimizationActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('optimization actions', style: TextStyle(color: Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7CB9FF)),
                onPressed: () async {
                  setState(() => _isOptimizing = true);
                  await widget.onOptimizeMemory();
                  setState(() => _isOptimizing = false);
                },
                child: const Text('optimize memory', style: TextStyle(fontSize: 10, color: Colors.black)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2a2a2a)),
                onPressed: widget.onClearCache,
                child: const Text('clear cache', style: TextStyle(fontSize: 10, color: Color(0xFF999999))),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
          ),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(color: color, fontSize: 9))),
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 9)),
          const SizedBox(height: 2),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF7CB9FF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
