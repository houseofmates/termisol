import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';

/// settings sheet for termisol configuration
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
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
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'settings functionality coming soon...',
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
}
