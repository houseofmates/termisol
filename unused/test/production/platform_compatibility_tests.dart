import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/terminal_session.dart';
import '../../lib/core/device_capabilities.dart';

/// Comprehensive multi-platform compatibility testing
/// Tests platform-specific issues, path handling, shell differences, etc.
void main() {
  group('Platform Compatibility Tests', () {
    late Directory testTempDir;
    
    setUp(() async {
      testTempDir = await Directory.systemTemp.createTemp('termisol_platform_test_');
    });
    
    tearDown(() async {
      if (await testTempDir.exists()) {
        await testTempDir.delete(recursive: true);
      }
    });

    test('handles Windows path separators', () async {
      final session = TerminalSession(
        id: 'test-windows-paths',
        name: 'Windows Paths Test',
      );
      
      await session.start();
      
      // Test Windows-style paths (even on Unix for compatibility)
      final windowsPaths = [
        'C:\\Users\\User\\Documents\\file.txt',
        'D:\\Program Files\\App\\config.json',
        'C:\\Program Files (x86)\\App\\data.bin',
        '..\\..\\parent\\directory',
        '.\\current\\directory',
      ];
      
      for (final path in windowsPaths) {
        // Should handle Windows paths without crashing
        session.sendToBackend(utf8.encode('echo "Testing path: $path"\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles Unix path separators', () async {
      final session = TerminalSession(
        id: 'test-unix-paths',
        name: 'Unix Paths Test',
      );
      
      await session.start();
      
      // Test Unix-style paths
      final unixPaths = [
        '/home/user/documents/file.txt',
        '/usr/local/bin/app',
        '/var/log/system.log',
        '../../parent/directory',
        './current/directory',
        '~/.config/app/settings.json',
      ];
      
      for (final path in unixPaths) {
        // Should handle Unix paths correctly
        session.sendToBackend(utf8.encode('echo "Testing path: $path"\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles platform-specific shell commands', () async {
      final session = TerminalSession(
        id: 'test-shell-commands',
        name: 'Shell Commands Test',
      );
      
      await session.start();
      
      // Test platform-specific commands
      final commands = Platform.isWindows ? [
        'dir',
        'type nul',
        'echo %PATH%',
        'where python',
        'powershell -Command "Get-Location"',
      ] : [
        'ls -la',
        'cat /dev/null',
        'echo $PATH',
        'which python3',
        'pwd',
      ];
      
      for (final command in commands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles environment variable differences', () async {
      final session = TerminalSession(
        id: 'test-env-vars',
        name: 'Environment Variables Test',
      );
      
      await session.start();
      
      // Test different environment variable formats
      final envVars = Platform.isWindows ? [
        '%USERPROFILE%',
        '%APPDATA%',
        '%TEMP%',
        '%PATH%',
        '%COMSPEC%',
      ] : [
        '$HOME',
        '$HOME/.config',
        '/tmp',
        '$PATH',
        '$SHELL',
      ];
      
      for (final envVar in envVars) {
        session.sendToBackend(utf8.encode('echo "Env var: $envVar"\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles different line endings', () async {
      final session = TerminalSession(
        id: 'test-line-endings',
        name: 'Line Endings Test',
      );
      
      await session.start();
      
      // Test different line ending formats
      final lineEndings = [
        'Unix line ending\n',
        'Windows line ending\r\n',
        'Old Mac line ending\r',
        'Mixed endings\n\r\n\r',
      ];
      
      for (final ending in lineEndings) {
        session.sendToBackend(utf8.encode('echo "Testing$endingline endings"'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles file permission differences', () async {
      final session = TerminalSession(
        id: 'test-file-permissions',
        name: 'File Permissions Test',
      );
      
      await session.start();
      
      // Test file permission commands
      final permissionCommands = Platform.isWindows ? [
        'icacls test.txt',
        'attrib +R test.txt',
        'net share',
      ] : [
        'ls -la',
        'chmod 755 test.sh',
        'chown user:group test.txt',
        'umask',
      ];
      
      for (final command in permissionCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles different terminal capabilities', () async {
      final session = TerminalSession(
        id: 'test-terminal-capabilities',
        name: 'Terminal Capabilities Test',
      );
      
      await session.start();
      
      // Test terminal capability queries
      final capabilityCommands = [
        'echo $TERM',
        'tput cols',
        'tput lines',
        'echo $COLORTERM',
      ];
      
      for (final command in capabilityCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles platform-specific special characters', () async {
      final session = TerminalSession(
        id: 'test-special-chars',
        name: 'Special Characters Test',
      );
      
      await session.start();
      
      // Test platform-specific special characters in paths and commands
      final specialChars = Platform.isWindows ? [
        'file with spaces.txt',
        'file&with&amps.txt',
        'file(with)parentheses.txt',
        'file[with]brackets.txt',
        'file{with}braces.txt',
      ] : [
        'file with spaces.txt',
        'file\'with\'quotes.txt',
        'file\$with\$dollars.txt',
        'file@with@ats.txt',
        'file#with#hashes.txt',
      ];
      
      for (final filename in specialChars) {
        session.sendToBackend(utf8.encode('echo "Testing: $filename"\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles different encoding scenarios', () async {
      final session = TerminalSession(
        id: 'test-encoding',
        name: 'Encoding Test',
      );
      
      await session.start();
      
      // Test different character encodings
      final testStrings = [
        'ASCII: Hello World',
        'UTF-8: Hëllo Wörld 🌍',
        'Latin-1: Café résumé',
        'CJK: 你好世界 こんにちは 안녕하세요',
        'Emoji: 🚀🔥💻🎯',
        'Math: ∑∏∫∆∇∂',
      ];
      
      for (final testString in testStrings) {
        session.sendToBackend(utf8.encode('echo "$testString"\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles device capability detection', () async {
      final capabilities = DeviceCapabilities();
      
      // Test capability detection on current platform
      expect(capabilities.platform, isNotNull);
      expect(capabilities.platform, isA<String>());
      
      // Test platform-specific capabilities
      if (Platform.isLinux) {
        expect(capabilities.hasLinuxPTY, isA<bool>());
      }
      
      if (Platform.isWindows) {
        expect(capabilities.hasWindowsConPTY, isA<bool>());
      }
      
      if (Platform.isMacOS) {
        expect(capabilities.hasMacOSPTY, isA<bool>());
      }
    });

    test('handles cross-platform shell detection', () async {
      final session = TerminalSession(
        id: 'test-shell-detection',
        name: 'Shell Detection Test',
      );
      
      await session.start();
      
      // Test shell detection commands
      final shellCommands = [
        'echo $SHELL',
        'echo $0',
        'ps -p $$ -o comm=',
        'which bash',
        'which zsh',
        'which fish',
      ];
      
      // Add Windows-specific commands
      if (Platform.isWindows) {
        shellCommands.addAll([
          'echo %COMSPEC%',
          'powershell -Command "Get-Process -Id \$PID | Select-Object ProcessName"',
        ]);
      }
      
      for (final command in shellCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles platform-specific terminal features', () async {
      final session = TerminalSession(
        id: 'test-terminal-features',
        name: 'Terminal Features Test',
      );
      
      await session.start();
      
      // Test terminal feature detection
      final featureCommands = [
        'echo $TERM',
        'echo $COLORTERM',
        'tput colors',
        'tput setaf 1; echo Red; tput sgr0',
      ];
      
      for (final command in featureCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      
      await session.disposeSession();
    });

    test('handles different package managers', () async {
      final session = TerminalSession(
        id: 'test-package-managers',
        name: 'Package Managers Test',
      );
      
      await session.start();
      
      // Test different package manager commands
      final packageCommands = Platform.isWindows ? [
        'winget --version',
        'choco --version',
        'scoop --version',
        'npm --version',
        'pip --version',
      ] : Platform.isMacOS ? [
        'brew --version',
        'port version',
        'npm --version',
        'pip --version',
      ] : [
        'apt --version',
        'dnf --version',
        'pacman --version',
        'npm --version',
        'pip --version',
      ];
      
      for (final command in packageCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles filesystem differences', () async {
      final session = TerminalSession(
        id: 'test-filesystem',
        name: 'Filesystem Test',
      );
      
      await session.start();
      
      // Test filesystem commands
      final fsCommands = Platform.isWindows ? [
        'vol',
        'dir',
        'fsutil fsinfo drives',
        'wmic logicaldisk get size,freespace,caption',
      ] : [
        'df -h',
        'ls -la',
        'mount',
        'uname -a',
      ];
      
      for (final command in fsCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles network configuration differences', () async {
      final session = TerminalSession(
        id: 'test-network',
        name: 'Network Test',
      );
      
      await session.start();
      
      // Test network commands
      final networkCommands = Platform.isWindows ? [
        'ipconfig',
        'netstat -an',
        'ping -n 1 localhost',
        'nslookup localhost',
      ] : [
        'ip addr',
        'netstat -tuln',
        'ping -c 1 localhost',
        'nslookup localhost',
      ];
      
      for (final command in networkCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles process management differences', () async {
      final session = TerminalSession(
        id: 'test-process-mgmt',
        name: 'Process Management Test',
      );
      
      await session.start();
      
      // Test process management commands
      final processCommands = Platform.isWindows ? [
        'tasklist',
        'wmic process get Name,ProcessId',
        'powershell -Command "Get-Process | Select-Object Name,Id"',
      ] : [
        'ps aux',
        'pgrep -l bash',
        'pstree',
        'top -b -n 1',
      ];
      
      for (final command in processCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles system information differences', () async {
      final session = TerminalSession(
        id: 'test-sysinfo',
        name: 'System Info Test',
      );
      
      await session.start();
      
      // Test system information commands
      final sysinfoCommands = Platform.isWindows ? [
        'systeminfo',
        'ver',
        'echo %PROCESSOR_ARCHITECTURE%',
        'wmic cpu get Name',
      ] : [
        'uname -a',
        'lscpu',
        'free -h',
        'uptime',
      ];
      
      for (final command in sysinfoCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });

    test('handles terminal resize on different platforms', () async {
      final session = TerminalSession(
        id: 'test-resize-cross-platform',
        name: 'Cross-Platform Resize Test',
      );
      
      await session.start();
      
      // Test different terminal sizes
      final sizes = [
        [80, 24],   // Standard
        [120, 40],  // Large
        [40, 12],   // Small
        [132, 43],  // VT100
        [255, 255], // Maximum
      ];
      
      for (final size in sizes) {
        session.terminal.resize(size[0], size[1]);
        session.sendToBackend(utf8.encode('echo "Resized to ${size[0]}x${size[1]}"\n'));
        await Future.delayed(Duration(milliseconds: 20));
      }
      
      await session.disposeSession();
    });

    test('handles clipboard differences', () async {
      final session = TerminalSession(
        id: 'test-clipboard',
        name: 'Clipboard Test',
      );
      
      await session.start();
      
      // Test clipboard commands
      final clipboardCommands = Platform.isWindows ? [
        'echo "test" | clip',
        'powershell -Command "Get-Clipboard"',
      ] : Platform.isMacOS ? [
        'echo "test" | pbcopy',
        'pbpaste',
      ] : [
        'echo "test" | xclip -selection clipboard',
        'xclip -selection clipboard -o',
      ];
      
      for (final command in clipboardCommands) {
        session.sendToBackend(utf8.encode('$command\n'));
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      await session.disposeSession();
    });
  });
}
