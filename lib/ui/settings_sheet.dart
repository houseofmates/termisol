import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';
import '../core/performance_enforcer.dart';
import '../core/service_registry.dart';

/// Settings sheet for Termisol configuration
class SettingsSheet extends StatefulWidget {
  final PerformanceEnforcer? performanceEnforcer;
  
  const SettingsSheet({
    super.key, 
    this.performanceEnforcer,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool _showFps = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      color: PkmTheme.popup,
      child: Column(
        children: [
          // handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: PkmTheme.primary,
              borderRadius: BorderRadius.zero,
            ),
          ),
          // settings content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Performance section
                  _buildPerformanceSection(),
                  
                  const SizedBox(height: 20),
                  
                  // Other settings
                  Text(
                    'Other settings coming soon...',
                    style: TextStyle(
                      fontSize: 14,
                      color: PkmTheme.primary,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
        const SizedBox(height: 12),
        
        // FPS toggle
        SwitchListTile(
          title: Text(
            'Show FPS Counter',
            style: TextStyle(
              fontSize: 14,
              color: PkmTheme.text,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          subtitle: Text(
            'Display real-time FPS in settings',
            style: TextStyle(
              fontSize: 12,
              color: PkmTheme.primary,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          value: _showFps,
          onChanged: (value) {
            setState(() {
              _showFps = value;
            });
          },
          activeColor: PkmTheme.primary,
        ),
        
        // FPS display
        if (_showFps && widget.performanceEnforcer != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PkmTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: PkmTheme.primary.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.speed,
                  color: PkmTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current FPS: ${widget.performanceEnforcer!.currentFps.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PkmTheme.text,
                        fontFamily: PkmTheme.fontTerminal,
                      ),
                    ),
                    Text(
                      'Frame Time: ${widget.performanceEnforcer!.currentFrameTime.toStringAsFixed(2)}ms',
                      style: TextStyle(
                        fontSize: 12,
                        color: PkmTheme.primary,
                        fontFamily: PkmTheme.fontTerminal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
