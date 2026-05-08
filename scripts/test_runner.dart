#!/usr/bin/env dart

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as test;

/// Automated Testing Pipeline for Termisol
/// 
/// This script runs comprehensive tests including:
/// - Unit tests
/// - Integration tests  
/// - Performance tests
/// - Error handling validation
/// - Memory leak detection
/// - Security vulnerability scanning
class AutomatedTestPipeline {
  static const String _projectRoot = Platform.environment['TERMISOL_REPO_DIR'] ?? (Platform.environment['HOME'] ?? '/home/user') + '/termisol';
  static const String _testResultsDir = '$_projectRoot/test_results';
  static const String _reportsDir = '$_projectRoot/reports';
  
  final TestResults _results = TestResults();
  final List<String> _failedTests = [];
  
  Future<void> runFullTestSuite() async {
    debugPrint('🚀 Starting Termisol Automated Test Pipeline');
    debugPrint('=' * 60);
    
    final stopwatch = Stopwatch()..start();
    
    try {
      await _setupEnvironment();
      await _runUnitTests();
      await _runIntegrationTests();
      await _runPerformanceTests();
      await _runErrorHandlingTests();
      await _runSecurityTests();
      await _runMemoryLeakTests();
      await _generateReports();
      await _cleanup();
      
      stopwatch.stop();
      
      _printSummary(stopwatch);
      
      if (_failedTests.isNotEmpty) {
        debugPrint('\n❌ Test Pipeline Completed with Failures');
        debugPrint('Failed tests: ${_failedTests.join(', ')}');
        exit(1);
      } else {
        debugPrint('\n✅ Test Pipeline Completed Successfully');
        exit(0);
      }
    } catch (e) {
      debugPrint('\n💥 Test Pipeline Failed: $e');
      exit(1);
    }
  }
  
  Future<void> _setupEnvironment() async {
    debugPrint('🔧 Setting up test environment...');
    
    // Create directories
    await Directory(_testResultsDir).create(recursive: true);
    await Directory(_reportsDir).create(recursive: true);
    
    // Set environment variables
    Platform.environment['FLUTTER_TEST'] = 'true';
    Platform.environment['TERMISOL_TEST_MODE'] = 'true';
    
    debugPrint('✅ Test environment ready');
  }
  
  Future<void> _runUnitTests() async {
    print('\n🧪 Running Unit Tests...');
    
    final testFiles = [
      '$_projectRoot/test/unit/advanced_terminal_protocol_test.dart',
      '$_projectRoot/test/unit/quantum_terminal_engine_test.dart',
      '$_projectRoot/test/unit/clipboard_manager_test.dart',
      '$_projectRoot/test/unit/config_test.dart',
      '$_projectRoot/test/unit/shortcut_manager_test.dart',
      '$_projectRoot/test/unit/tab_manager_test.dart',
    ];
    
    for (final testFile in testFiles) {
      if (await File(testFile).exists()) {
        await _runTestFile(testFile, 'unit');
      } else {
        print('⚠️ Unit test file not found: $testFile');
      }
    }
    
    print('✅ Unit tests completed');
  }
  
  Future<void> _runIntegrationTests() async {
    print('\n🔗 Running Integration Tests...');
    
    final testFiles = [
      '$_projectRoot/test/integration/comprehensive_feature_integration_test.dart',
      '$_projectRoot/test/integration/app_flow_test.dart',
    ];
    
    for (final testFile in testFiles) {
      if (await File(testFile).exists()) {
        await _runTestFile(testFile, 'integration');
      } else {
        print('⚠️ Integration test file not found: $testFile');
      }
    }
    
    print('✅ Integration tests completed');
  }
  
  Future<void> _runPerformanceTests() async {
    print('\n⚡ Running Performance Tests...');
    
    final testFiles = [
      '$_projectRoot/test/performance/comprehensive_performance_test.dart',
    ];
    
    for (final testFile in testFiles) {
      if (await File(testFile).exists()) {
        await _runTestFile(testFile, 'performance');
      } else {
        print('⚠️ Performance test file not found: $testFile');
      }
    }
    
    print('✅ Performance tests completed');
  }
  
  Future<void> _runErrorHandlingTests() async {
    print('\n🛡️ Running Error Handling Tests...');
    
    // Custom error handling validation
    await _validateErrorHandling();
    
    print('✅ Error handling tests completed');
  }
  
  Future<void> _runSecurityTests() async {
    print('\n🔒 Running Security Tests...');
    
    // Security vulnerability scanning
    await _scanForVulnerabilities();
    await _validateInputSanitization();
    await _checkDataExposure();
    
    print('✅ Security tests completed');
  }
  
  Future<void> _runMemoryLeakTests() async {
    print('\n💧 Running Memory Leak Tests...');
    
    final testFiles = [
      '$_projectRoot/test/memory_leak_detector.dart',
    ];
    
    for (final testFile in testFiles) {
      if (await File(testFile).exists()) {
        await _runTestFile(testFile, 'memory');
      } else {
        print('⚠️ Memory leak test file not found: $testFile');
      }
    }
    
    print('✅ Memory leak tests completed');
  }
  
  Future<void> _runTestFile(String testFile, String category) async {
    print('  📋 Running $testFile...');
    
    final stopwatch = Stopwatch()..start();
    final result = await Process.run('dart', [
      'test',
      testFile,
      '--reporter=json',
      '--timeout=300s',
    ]);
    
    stopwatch.stop();
    
    if (result.exitCode == 0) {
      print('  ✅ ${testFile.split('/').last} (${stopwatch.elapsedMilliseconds}ms)');
      _results.addSuccess(category, testFile, stopwatch.elapsedMilliseconds);
    } else {
      print('  ❌ ${testFile.split('/').last} (${stopwatch.elapsedMilliseconds}ms)');
      print('     Error: ${result.stderr}');
      _failedTests.add(testFile);
      _results.addFailure(category, testFile, stopwatch.elapsedMilliseconds, result.stderr);
    }
    
    // Save detailed results
    await _saveTestResult(testFile, category, result);
  }
  
  Future<void> _validateErrorHandling() async {
    print('  🔍 Validating error handling patterns...');
    
    final sourceFiles = await _getSourceFiles();
    
    for (final file in sourceFiles) {
      final content = await file.readAsString();
      final issues = <String>[];
      
      // Check for proper error handling
      if (content.contains('Future<') && !content.contains('try') && !content.contains('catch')) {
        issues.add('Missing error handling for async operations');
      }
      
      if (content.contains('int.parse(') && !content.contains('tryParse')) {
        issues.add('Using int.parse without error handling');
      }
      
      if (content.contains('double.parse(') && !content.contains('tryParse')) {
        issues.add('Using double.parse without error handling');
      }
      
      if (issues.isNotEmpty) {
        print('    ⚠️ ${file.path}: ${issues.join(', ')}');
        _results.addIssue('error_handling', file.path, issues);
      }
    }
  }
  
  Future<void> _scanForVulnerabilities() async {
    print('  🔍 Scanning for security vulnerabilities...');
    
    final sourceFiles = await _getSourceFiles();
    
    for (final file in sourceFiles) {
      final content = await file.readAsString();
      final vulnerabilities = <String>[];
      
      // Check for common vulnerabilities
      if (content.contains('eval(') || content.contains('Function(')) {
        vulnerabilities.add('Code injection risk');
      }
      
      if (content.contains('process.env') && !content.contains('sanitize')) {
        vulnerabilities.add('Environment variable exposure');
      }
      
      if (content.contains('innerHTML') || content.contains('outerHTML')) {
        vulnerabilities.add('XSS vulnerability');
      }
      
      if (content.contains('sqlite') && content.contains('rawQuery')) {
        vulnerabilities.add('SQL injection risk');
      }
      
      if (vulnerabilities.isNotEmpty) {
        print('    🚨 ${file.path}: ${vulnerabilities.join(', ')}');
        _results.addIssue('security', file.path, vulnerabilities);
      }
    }
  }
  
  Future<void> _validateInputSanitization() async {
    print('  🔍 Validating input sanitization...');
    
    final sourceFiles = await _getSourceFiles();
    
    for (final file in sourceFiles) {
      final content = await file.readAsString();
      final issues = <String>[];
      
      // Check for input validation
      if (content.contains('stdin.readLineSync') && !content.contains('trim')) {
        issues.add('Input not sanitized');
      }
      
      if (content.contains('HttpRequest') && !content.contains('validate')) {
        issues.add('HTTP request not validated');
      }
      
      if (issues.isNotEmpty) {
        print('    ⚠️ ${file.path}: ${issues.join(', ')}');
        _results.addIssue('input_validation', file.path, issues);
      }
    }
  }
  
  Future<void> _checkDataExposure() async {
    print('  🔍 Checking for data exposure...');
    
    final sourceFiles = await _getSourceFiles();
    
    for (final file in sourceFiles) {
      final content = await file.readAsString();
      final issues = <String>[];
      
      // Check for sensitive data exposure
      if (content.contains('password') && content.contains('print')) {
        issues.add('Password may be exposed in logs');
      }
      
      if (content.contains('api_key') && content.contains('debugPrint')) {
        issues.add('API key may be exposed in debug logs');
      }
      
      if (content.contains('token') && content.contains('console.log')) {
        issues.add('Token may be exposed in console');
      }
      
      if (issues.isNotEmpty) {
        print('    ⚠️ ${file.path}: ${issues.join(', ')}');
        _results.addIssue('data_exposure', file.path, issues);
      }
    }
  }
  
  Future<List<File>> _getSourceFiles() async {
    final libDir = Directory('$_projectRoot/lib');
    final files = <File>[];
    
    await for (final entity in libDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
    
    return files;
  }
  
  Future<void> _saveTestResult(String testFile, String category, ProcessResult result) async {
    final timestamp = DateTime.now().toIso8601String();
    final fileName = '${testFile.split('/').last}_${timestamp}.json';
    final resultFile = File('$_testResultsDir/$category/$fileName');
    
    await resultFile.parent.create(recursive: true);
    
    final testResult = {
      'test_file': testFile,
      'category': category,
      'timestamp': timestamp,
      'exit_code': result.exitCode,
      'duration_ms': DateTime.now().millisecondsSinceEpoch,
      'stdout': result.stdout,
      'stderr': result.stderr,
      'success': result.exitCode == 0,
    };
    
    await resultFile.writeAsString(jsonEncode(testResult));
  }
  
  Future<void> _generateReports() async {
    print('\n📊 Generating Test Reports...');
    
    await _generateSummaryReport();
    await _generatePerformanceReport();
    await _generateSecurityReport();
    await _generateCoverageReport();
    
    print('✅ Reports generated');
  }
  
  Future<void> _generateSummaryReport() async {
    final reportFile = File('$_reportsDir/test_summary.html');
    
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Termisol Test Summary</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #2196F3; color: white; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .success { background: #4CAF50; color: white; }
        .failure { background: #f44336; color: white; }
        .warning { background: #ff9800; color: white; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Termisol Test Pipeline Summary</h1>
        <p>Generated: ${DateTime.now().toIso8601String()}</p>
    </div>
    
    <div class="section">
        <h2>📈 Overall Results</h2>
        <p>Total Tests: ${_results.totalTests}</p>
        <p>Passed: ${_results.passedTests}</p>
        <p>Failed: ${_results.failedTests}</p>
        <p>Success Rate: ${(_results.successRate * 100).toStringAsFixed(1)}%</p>
        <p>Total Duration: ${_results.totalDuration}ms</p>
    </div>
    
    <div class="section">
        <h2>📋 Test Categories</h2>
        <table>
            <tr><th>Category</th><th>Tests</th><th>Passed</th><th>Failed</th><th>Duration</th></tr>
            ${_results.categories.map((cat) => '''
            <tr>
                <td>${cat.name}</td>
                <td>${cat.totalTests}</td>
                <td>${cat.passedTests}</td>
                <td>${cat.failedTests}</td>
                <td>${cat.totalDuration}ms</td>
            </tr>
            ''').join('')}
        </table>
    </div>
    
    <div class="section">
        <h2>🚨 Issues Found</h2>
        ${_results.issues.isEmpty ? '<p>No issues found</p>' : '''
        <table>
            <tr><th>Type</th><th>File</th><th>Issues</th></tr>
            ${_results.issues.map((issue) => '''
            <tr>
                <td>${issue.type}</td>
                <td>${issue.file}</td>
                <td>${issue.issues.join(', ')}</td>
            </tr>
            ''').join('')}
        </table>
        '''}
    </div>
    
    ${_failedTests.isNotEmpty ? '''
    <div class="section failure">
        <h2>❌ Failed Tests</h2>
        <ul>
            ${_failedTests.map((test) => '<li>$test</li>').join('')}
        </ul>
    </div>
    ''' : ''}
</body>
</html>
    ''';
    
    await reportFile.writeAsString(html);
  }
  
  Future<void> _generatePerformanceReport() async {
    final reportFile = File('$_reportsDir/performance_report.html');
    
    // Generate performance-specific report
    final performanceData = _results.getPerformanceData();
    
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Performance Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { width: 80%; margin: 20px auto; }
        .metric { display: inline-block; margin: 10px; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>⚡ Performance Test Results</h1>
    
    <div class="chart-container">
        <canvas id="performanceChart"></canvas>
    </div>
    
    <div class="metrics">
        ${performanceData.map((metric) => '''
        <div class="metric">
            <h3>${metric.name}</h3>
            <p>${metric.value} ${metric.unit}</p>
        </div>
        ''').join('')}
    </div>
    
    <script>
        const ctx = document.getElementById('performanceChart').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: ${jsonEncode(performanceData.map((m) => m.name))},
                datasets: [{
                    label: 'Performance Metrics',
                    data: ${jsonEncode(performanceData.map((m) => m.value))},
                    backgroundColor: 'rgba(33, 150, 243, 0.2)',
                    borderColor: 'rgba(33, 150, 243, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });
    </script>
</body>
</html>
    ''';
    
    await reportFile.writeAsString(html);
  }
  
  Future<void> _generateSecurityReport() async {
    final reportFile = File('$_reportsDir/security_report.html');
    
    final securityIssues = _results.issues.where((i) => i.type == 'security').toList();
    
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Security Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .critical { background: #f44336; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .warning { background: #ff9800; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
        .info { background: #2196F3; color: white; padding: 10px; margin: 5px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>🔒 Security Scan Results</h1>
    
    <h2>Summary</h2>
    <p>Total Security Issues: ${securityIssues.length}</p>
    <p>Critical: ${securityIssues.where((i) => i.issues.any((issue) => issue.contains('injection'))).length}</p>
    <p>Warnings: ${securityIssues.where((i) => i.issues.any((issue) => issue.contains('exposure'))).length}</p>
    
    <h2>Issues Found</h2>
    ${securityIssues.isEmpty ? '<p>No security issues found ✅</p>' : securityIssues.map((issue) => '''
    <div class="critical">
        <h3>${issue.file}</h3>
        <p>${issue.issues.join(', ')}</p>
    </div>
    ''').join('')}
</body>
</html>
    ''';
    
    await reportFile.writeAsString(html);
  }
  
  Future<void> _generateCoverageReport() async {
    // Generate coverage report using dart test coverage
    final result = await Process.run('dart', [
      'test',
      '--coverage=coverage',
      '$_projectRoot/test',
    ]);
    
    if (result.exitCode == 0) {
      print('  ✅ Coverage report generated');
      
      // Generate HTML coverage report
      await Process.run('dart', [
        'run',
        'coverage:format_coverage',
        '--lcov',
        '--in=coverage',
        '--out=coverage.lcov',
        '--report-on=lib',
      ]);
      
      print('  ✅ Coverage report formatted');
    } else {
      print('  ⚠️ Coverage report generation failed');
    }
  }
  
  Future<void> _cleanup() async {
    print('🧹 Cleaning up temporary files...');
    
    // Clean up temporary test files
    final tempDir = Directory('$_projectRoot/temp');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    
    print('✅ Cleanup completed');
  }
  
  void _printSummary(Stopwatch stopwatch) {
    print('\n' + '=' * 60);
    print('📊 TEST PIPELINE SUMMARY');
    print('=' * 60);
    print('⏱️  Total Duration: ${stopwatch.elapsed.inSeconds}s');
    print('📋 Total Tests: ${_results.totalTests}');
    print('✅ Passed: ${_results.passedTests}');
    print('❌ Failed: ${_results.failedTests}');
    print('📈 Success Rate: ${(_results.successRate * 100).toStringAsFixed(1)}%');
    print('🚨 Issues Found: ${_results.issues.length}');
    print('📊 Reports Generated: $_reportsDir');
    print('=' * 60);
  }
}

/// Test results container
class TestResults {
  final List<TestCategory> _categories = [];
  final List<TestIssue> _issues = [];
  
  void addSuccess(String categoryName, String testFile, int duration) {
    final category = _getCategory(categoryName);
    category.addSuccess(testFile, duration);
  }
  
  void addFailure(String categoryName, String testFile, int duration, String error) {
    final category = _getCategory(categoryName);
    category.addFailure(testFile, duration, error);
  }
  
  void addIssue(String type, String file, List<String> issues) {
    _issues.add(TestIssue(type, file, issues));
  }
  
  TestCategory _getCategory(String name) {
    var category = _categories.firstWhere((c) => c.name == name, orElse: () => TestCategory(name));
    if (!_categories.contains(category)) {
      _categories.add(category);
    }
    return category;
  }
  
  int get totalTests => _categories.fold(0, (sum, cat) => sum + cat.totalTests);
  int get passedTests => _categories.fold(0, (sum, cat) => sum + cat.passedTests);
  int get failedTests => _categories.fold(0, (sum, cat) => sum + cat.failedTests);
  double get successRate => totalTests > 0 ? passedTests / totalTests : 0.0;
  int get totalDuration => _categories.fold(0, (sum, cat) => sum + cat.totalDuration);
  
  List<TestCategory> get categories => List.unmodifiable(_categories);
  List<TestIssue> get issues => List.unmodifiable(_issues);
  
  List<PerformanceMetric> getPerformanceData() {
    final metrics = <PerformanceMetric>[];
    
    for (final category in _categories) {
      if (category.name == 'performance') {
        metrics.add(PerformanceMetric('Test Duration', category.totalDuration, 'ms'));
        metrics.add(PerformanceMetric('Tests Run', category.totalTests, 'count'));
      }
    }
    
    return metrics;
  }
}

class TestCategory {
  final String name;
  final List<TestResult> _results = [];
  
  TestCategory(this.name);
  
  void addSuccess(String testFile, int duration) {
    _results.add(TestResult(testFile, true, duration));
  }
  
  void addFailure(String testFile, int duration, String error) {
    _results.add(TestResult(testFile, false, duration, error));
  }
  
  int get totalTests => _results.length;
  int get passedTests => _results.where((r) => r.success).length;
  int get failedTests => _results.where((r) => !r.success).length;
  int get totalDuration => _results.fold(0, (sum, r) => sum + r.duration);
}

class TestResult {
  final String testFile;
  final bool success;
  final int duration;
  final String? error;
  
  TestResult(this.testFile, this.success, this.duration, [this.error]);
}

class TestIssue {
  final String type;
  final String file;
  final List<String> issues;
  
  TestIssue(this.type, this.file, this.issues);
}

class PerformanceMetric {
  final String name;
  final double value;
  final String unit;
  
  PerformanceMetric(this.name, this.value, this.unit);
}

void main(List<String> args) async {
  final pipeline = AutomatedTestPipeline();
  
  if (args.contains('--category')) {
    final index = args.indexOf('--category');
    final category = args[index + 1];
    
    switch (category) {
      case 'unit':
        await pipeline._runUnitTests();
        break;
      case 'integration':
        await pipeline._runIntegrationTests();
        break;
      case 'performance':
        await pipeline._runPerformanceTests();
        break;
      case 'security':
        await pipeline._runSecurityTests();
        break;
      default:
        print('Unknown category: $category');
        exit(1);
    }
  } else {
    await pipeline.runFullTestSuite();
  }
}
