import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/pkm_theme.dart';
import '../core/service_registry.dart';
import 'settings_items.dart';

/// full-screen settings page with tabs and a back button.
class SettingsPage extends StatefulWidget {
  final ServiceRegistry registry;

  const SettingsPage({
    super.key,
    required this.registry,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // appearance state
  double _fontSize = 14.0;
  bool _useSystemTheme = false;
  bool _transparentBackground = false;
  double _transparency = 1.0;
  TermisolThemeMode _themeMode = TermisolThemeMode.dark;

  // terminal state
  bool _bellEnabled = true;
  bool _blinkCursor = false;
  bool _scrollOnInput = true;
  int _scrollbackLines = 10000;

  // keyboard state
  bool _useHardwareKeyboard = false;

  // advanced state
  bool _showPerformanceOverlay = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTheme();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('termisol_theme_mode');
    if (saved != null) {
      try {
        final mode = TermisolThemeMode.values.byName(saved);
        setState(() => _themeMode = mode);
        PkmTheme.themeMode.value = mode;
      } catch (_) {
        // Invalid saved theme, ignore
      }
    }
    final overlay = prefs.getBool('show_performance_overlay');
    if (overlay != null) {
      setState(() => _showPerformanceOverlay = overlay);
    }
  }

  Future<void> _savePerformanceOverlay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_performance_overlay', value);
  }

  Future<void> _saveTheme(TermisolThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('termisol_theme_mode', mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PkmTheme.background,
      appBar: AppBar(
        backgroundColor: PkmTheme.tabActiveBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: PkmTheme.primary),
          tooltip: 'back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'settings',
          style: TextStyle(
            color: PkmTheme.primary,
            fontFamily: PkmTheme.fontUi,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: PkmTheme.primary,
          labelColor: PkmTheme.primary,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(
            fontFamily: PkmTheme.fontUi,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: PkmTheme.fontUi,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.palette_outlined), text: 'appearance'),
            Tab(icon: Icon(Icons.terminal_outlined), text: 'terminal'),
            Tab(icon: Icon(Icons.keyboard_outlined), text: 'keyboard'),
            Tab(icon: Icon(Icons.tune_outlined), text: 'advanced'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAppearanceTab(),
          _buildTerminalTab(),
          _buildKeyboardTab(),
          _buildAdvancedTab(),
        ],
      ),
    );
  }

  Widget _buildAppearanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('theme'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: TermisolThemeMode.values.map((mode) {
              return ChoiceChip(
                label: Text(
                  mode.name,
                  style: TextStyle(
                    color: _themeMode == mode ? Colors.black : Colors.white,
                    fontFamily: PkmTheme.fontUi,
                    fontSize: 13,
                  ),
                ),
                selected: _themeMode == mode,
                selectedColor: PkmTheme.primary,
                backgroundColor: PkmTheme.tabInactiveBg,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _themeMode = mode);
                    PkmTheme.themeMode.value = mode;
                    _saveTheme(mode);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          _sectionTitle('font'),
          SettingsSlider(
            label: 'font size',
            value: _fontSize,
            min: 8,
            max: 32,
            divisions: 24,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          const SizedBox(height: 8),
          _infoRow('font family', 'Droid Sans Mono'),
          const SizedBox(height: 24),

          _sectionTitle('colors'),
          SettingsToggle(
            label: 'use colors from system theme',
            value: _useSystemTheme,
            onChanged: (v) => setState(() => _useSystemTheme = v),
          ),
          SettingsToggle(
            label: 'use transparent background',
            value: _transparentBackground,
            onChanged: (v) => setState(() => _transparentBackground = v),
          ),
          if (_transparentBackground)
            SettingsSlider(
              label: 'transparency',
              value: _transparency,
              min: 0.1,
              max: 1.0,
              divisions: 18,
              onChanged: (v) => setState(() => _transparency = v),
            ),
          const SizedBox(height: 16),

          _sectionTitle('palette preview'),
          const SizedBox(height: 8),
          _palettePreview(),
        ],
      ),
    );
  }

  Widget _buildTerminalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('behavior'),
          SettingsToggle(
            label: 'enable bell',
            value: _bellEnabled,
            onChanged: (v) => setState(() => _bellEnabled = v),
          ),
          SettingsToggle(
            label: 'blink cursor',
            value: _blinkCursor,
            onChanged: (v) => setState(() => _blinkCursor = v),
          ),
          SettingsToggle(
            label: 'scroll on input',
            value: _scrollOnInput,
            onChanged: (v) => setState(() => _scrollOnInput = v),
          ),
          const SizedBox(height: 24),

          _sectionTitle('scrollback'),
          SettingsSlider(
            label: 'scrollback lines',
            value: _scrollbackLines.toDouble(),
            min: 1000,
            max: 50000,
            divisions: 49,
            onChanged: (v) => setState(() => _scrollbackLines = v.toInt()),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('input'),
          SettingsToggle(
            label: 'hardware keyboard only',
            value: _useHardwareKeyboard,
            onChanged: (v) => setState(() => _useHardwareKeyboard = v),
          ),
          const SizedBox(height: 24),

          _sectionTitle('shortcuts'),
          const SizedBox(height: 8),
          _shortcutRow('ctrl + =', 'zoom in'),
          _shortcutRow('ctrl + -', 'zoom out'),
          _shortcutRow('ctrl + 0', 'reset zoom'),
          _shortcutRow('ctrl + shift + c', 'copy'),
          _shortcutRow('ctrl + shift + v', 'paste'),
          _shortcutRow('ctrl + c', 'sigint'),
          _shortcutRow('ctrl + shift + p', 'command palette'),
          _shortcutRow('ctrl + shift + f', 'search'),
        ],
      ),
    );
  }

  Widget _buildAdvancedTab() {
    final healthReport = widget.registry.healthReport();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggle(
            label: 'show performance overlay',
            value: _showPerformanceOverlay,
            onChanged: (v) {
              setState(() => _showPerformanceOverlay = v);
              _savePerformanceOverlay(v);
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('diagnostics'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PkmTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: PkmTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: PkmTheme.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'service health report',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PkmTheme.text,
                        fontFamily: PkmTheme.fontTerminal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...healthReport.entries.map((entry) {
                  final map = entry.value as Map<String, dynamic>;
                  final status = map['health'] as String?;
                  final enabled = map['enabled'] as bool?;

                  Color statusColor;
                  IconData statusIcon;

                  if (enabled != true) {
                    statusColor = Colors.grey;
                    statusIcon = Icons.block;
                  } else if (status == 'healthy') {
                    statusColor = Colors.green;
                    statusIcon = Icons.check_circle;
                  } else if (status == 'failed') {
                    statusColor = Colors.red;
                    statusIcon = Icons.error;
                  } else if (status == 'initializing') {
                    statusColor = Colors.yellow;
                    statusIcon = Icons.hourglass_empty;
                  } else {
                    statusColor = Colors.orange;
                    statusIcon = Icons.warning;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          statusIcon,
                          color: statusColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: PkmTheme.text,
                              fontFamily: PkmTheme.fontTerminal,
                            ),
                          ),
                        ),
                        Text(
                          status?.toUpperCase() ?? 'UNKNOWN',
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontFamily: PkmTheme.fontTerminal,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _sectionTitle('about'),
          const SizedBox(height: 8),
          _infoRow('version', '1.0.0'),
          _infoRow('flutter', '3.29.0+'),
          _infoRow('xterm', '4.0.0'),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: PkmTheme.primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: PkmTheme.fontUi,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: PkmTheme.fontTerminal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String keys, String action) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade800),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: PkmTheme.fontTerminal,
              ),
            ),
          ),
          Text(
            action,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
        ],
      ),
    );
  }

  Widget _palettePreview() {
    const colors = [
      Color(0xFF000000), Color(0xFFFF0000), Color(0xFF00CC00),
      Color(0xFFCCCC00), Color(0xFF0000FF), Color(0xFFFF00FF),
      Color(0xFF00CCCC), Color(0xFFE5E5E5),
    ];
    const brightColors = [
      Color(0xFF808080), Color(0xFFFF0000), Color(0xFF00FF00),
      Color(0xFFFFFF00), Color(0xFF6666FF), Color(0xFFFF00FF),
      Color(0xFF00FFFF), Color(0xFFFFFFFF),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0a),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: colors.map((c) => _colorSwatch(c)).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: brightColors.map((c) => _colorSwatch(c)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade700),
      ),
    );
  }
}
