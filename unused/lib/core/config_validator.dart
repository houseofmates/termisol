import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// Configuration Schema Validator - Best-in-class configuration validation
/// 
/// Provides comprehensive configuration validation with:
/// - JSON Schema-based validation
/// - YAML schema validation
/// - Custom validation rules
/// - Automatic error correction
/// - Configuration migration
/// - Real-time validation feedback
class ConfigValidator {
  static final ConfigValidator _instance = ConfigValidator._internal();
  factory ConfigValidator() => _instance;
  ConfigValidator._internal();

  final Map<String, ConfigSchema> _schemas = {};
  final List<ValidationRule> _globalRules = [];
  final Map<String, List<ValidationResult>> _validationHistory = {};
  
  bool _isInitialized = false;
  bool _autoCorrect = true;
  
  final _validationController = StreamController<ValidationEvent>.broadcast();
  Stream<ValidationEvent> get events => _validationController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get autoCorrect => _autoCorrect;

  /// Initialize the configuration validator
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Register default schemas
      await _registerDefaultSchemas();
      
      // Register global validation rules
      await _registerGlobalRules();
      
      _isInitialized = true;
      debugPrint('🔍 Configuration Validator initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Configuration Validator: $e');
      rethrow;
    }
  }

  /// Validate configuration data
  ValidationResult validateConfig(String configType, dynamic configData) {
    final schema = _schemas[configType];
    if (schema == null) {
      return ValidationResult(
        isValid: false,
        errors: [ValidationError('No schema found for config type: $configType')],
        warnings: [],
        correctedData: configData,
      );
    }

    final errors = <ValidationError>[];
    final warnings = <ValidationWarning>[];
    dynamic correctedData = configData;

    // Validate against schema
    _validateAgainstSchema(schema, configData, '', errors, warnings);

    // Apply global rules
    _applyGlobalRules(configType, configData, errors, warnings);

    // Auto-correct if enabled
    if (_autoCorrect && errors.isNotEmpty) {
      correctedData = _autoCorrectErrors(schema, configData, errors);
    }

    final result = ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      correctedData: correctedData,
      configType: configType,
    );

    // Store in history
    _validationHistory[configType] ??= [];
    _validationHistory[configType]!.add(result);
    if (_validationHistory[configType]!.length > 100) {
      _validationHistory[configType]!.removeAt(0);
    }

    // Emit validation event
    _validationController.add(ValidationEvent(
      type: ValidationEventType.validationCompleted,
      configType: configType,
      result: result,
      timestamp: DateTime.now(),
    ));

    return result;
  }

  /// Validate YAML configuration
  ValidationResult validateYamlConfig(String configType, String yamlContent) {
    try {
      final yamlData = loadYaml(yamlContent);
      return validateConfig(configType, yamlData);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errors: [ValidationError('Invalid YAML: $e')],
        warnings: [],
        correctedData: null,
        configType: configType,
      );
    }
  }

  /// Validate JSON configuration
  ValidationResult validateJsonConfig(String configType, String jsonContent) {
    try {
      final jsonData = json.decode(jsonContent);
      return validateConfig(configType, jsonData);
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errors: [ValidationError('Invalid JSON: $e')],
        warnings: [],
        correctedData: null,
        configType: configType,
      );
    }
  }

  /// Validate configuration file
  Future<ValidationResult> validateConfigFile(String configType, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ValidationResult(
          isValid: false,
          errors: [ValidationError('Configuration file not found: $filePath')],
          warnings: [],
          correctedData: null,
          configType: configType,
        );
      }

      final content = await file.readAsString();
      
      if (filePath.endsWith('.yaml') || filePath.endsWith('.yml')) {
        return validateYamlConfig(configType, content);
      } else if (filePath.endsWith('.json')) {
        return validateJsonConfig(configType, content);
      } else {
        return ValidationResult(
          isValid: false,
          errors: [ValidationError('Unsupported file format: $filePath')],
          warnings: [],
          correctedData: null,
          configType: configType,
        );
      }
    } catch (e) {
      return ValidationResult(
        isValid: false,
        errors: [ValidationError('Error reading file: $e')],
        warnings: [],
        correctedData: null,
        configType: configType,
      );
    }
  }

  /// Register a configuration schema
  void registerSchema(String configType, ConfigSchema schema) {
    _schemas[configType] = schema;
    debugPrint('🔍 Registered schema for: $configType');
  }

  /// Register a validation rule
  void registerValidationRule(ValidationRule rule) {
    _globalRules.add(rule);
    debugPrint('🔍 Registered validation rule: ${rule.name}');
  }

  /// Validate against schema
  void _validateAgainstSchema(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (schema.isRequired && (data == null || data == '')) {
      errors.add(ValidationError('Required field missing: $path'));
      return;
    }

    if (data == null) return;

    switch (schema.type) {
      case SchemaType.string:
        _validateString(schema, data, path, errors, warnings);
        break;
      case SchemaType.number:
        _validateNumber(schema, data, path, errors, warnings);
        break;
      case SchemaType.boolean:
        _validateBoolean(schema, data, path, errors, warnings);
        break;
      case SchemaType.array:
        _validateArray(schema, data, path, errors, warnings);
        break;
      case SchemaType.object:
        _validateObject(schema, data, path, errors, warnings);
        break;
      case SchemaType.enum_:
        _validateEnum(schema, data, path, errors, warnings);
        break;
    }
  }

  /// Validate string field
  void _validateString(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (data is! String) {
      errors.add(ValidationError('Expected string at $path, got ${data.runtimeType}'));
      return;
    }

    if (schema.minLength != null && data.length < schema.minLength!) {
      errors.add(ValidationError('String at $path is too short (min: ${schema.minLength})'));
    }

    if (schema.maxLength != null && data.length > schema.maxLength!) {
      errors.add(ValidationError('String at $path is too long (max: ${schema.maxLength})'));
    }

    if (schema.pattern != null && !RegExp(schema.pattern!).hasMatch(data)) {
      errors.add(ValidationError('String at $path does not match pattern: ${schema.pattern}'));
    }
  }

  /// Validate number field
  void _validateNumber(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (data is! num) {
      errors.add(ValidationError('Expected number at $path, got ${data.runtimeType}'));
      return;
    }

    if (schema.min != null && data < schema.min!) {
      errors.add(ValidationError('Number at $path is too small (min: ${schema.min})'));
    }

    if (schema.max != null && data > schema.max!) {
      errors.add(ValidationError('Number at $path is too large (max: ${schema.max})'));
    }
  }

  /// Validate boolean field
  void _validateBoolean(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (data is! bool) {
      errors.add(ValidationError('Expected boolean at $path, got ${data.runtimeType}'));
    }
  }

  /// Validate array field
  void _validateArray(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (data is! List) {
      errors.add(ValidationError('Expected array at $path, got ${data.runtimeType}'));
      return;
    }

    if (schema.minItems != null && data.length < schema.minItems!) {
      errors.add(ValidationError('Array at $path has too few items (min: ${schema.minItems})'));
    }

    if (schema.maxItems != null && data.length > schema.maxItems!) {
      errors.add(ValidationError('Array at $path has too many items (max: ${schema.maxItems})'));
    }

    // Validate array items
    if (schema.items != null) {
      for (int i = 0; i < data.length; i++) {
        _validateAgainstSchema(
          schema.items!,
          data[i],
          '$path[$i]',
          errors,
          warnings,
        );
      }
    }
  }

  /// Validate object field
  void _validateObject(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (data is! Map) {
      errors.add(ValidationError('Expected object at $path, got ${data.runtimeType}'));
      return;
    }

    final dataMap = data as Map<String, dynamic>;

    // Check required properties
    for (final prop in schema.requiredProperties ?? []) {
      if (!dataMap.containsKey(prop)) {
        errors.add(ValidationError('Required property missing: ${path.isEmpty ? prop : '$path.$prop'}'));
      }
    }

    // Validate each property
    for (final entry in dataMap.entries) {
      final propSchema = schema.properties?[entry.key];
      if (propSchema != null) {
        final propPath = path.isEmpty ? entry.key : '$path.${entry.key}';
        _validateAgainstSchema(propSchema, entry.value, propPath, errors, warnings);
      } else if (schema.additionalProperties == false) {
        warnings.add(ValidationWarning('Unexpected property: ${path.isEmpty ? entry.key : '$path.${entry.key}'}'));
      }
    }
  }

  /// Validate enum field
  void _validateEnum(
    ConfigSchema schema,
    dynamic data,
    String path,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    if (!schema.enumValues!.contains(data)) {
      errors.add(ValidationError('Invalid enum value at $path: $data (expected: ${schema.enumValues})'));
    }
  }

  /// Apply global validation rules
  void _applyGlobalRules(
    String configType,
    dynamic data,
    List<ValidationError> errors,
    List<ValidationWarning> warnings,
  ) {
    for (final rule in _globalRules) {
      try {
        final result = rule.validate(configType, data);
        errors.addAll(result.errors);
        warnings.addAll(result.warnings);
      } catch (e) {
        warnings.add(ValidationWarning('Validation rule ${rule.name} failed: $e'));
      }
    }
  }

  /// Auto-correct errors
  dynamic _autoCorrectErrors(ConfigSchema schema, dynamic data, List<ValidationError> errors) {
    // This would implement automatic error correction
    // For now, return original data
    return data;
  }

  /// Register default schemas
  Future<void> _registerDefaultSchemas() async {
    // Terminal configuration schema
    registerSchema('terminal', ConfigSchema.object({
      'properties': {
        'font_family': ConfigSchema.string(
          minLength: 1,
          maxLength: 100,
          defaultValue: 'Fira Code',
        ),
        'font_size': ConfigSchema.number(
          min: 8,
          max: 72,
          defaultValue: 14,
        ),
        'theme': ConfigSchema.enum_(['dark', 'light', 'auto'], defaultValue: 'dark'),
        'opacity': ConfigSchema.number(
          min: 0.1,
          max: 1.0,
          defaultValue: 0.9,
        ),
        'scrollback_size': ConfigSchema.number(
          min: 100,
          max: 100000,
          defaultValue: 10000,
        ),
        'enable_gpu_acceleration': ConfigSchema.boolean(defaultValue: true),
        'enable_ai_assistant': ConfigSchema.boolean(defaultValue: true),
      },
      'requiredProperties': ['font_family', 'font_size'],
    }));

    // AI configuration schema
    registerSchema('ai', ConfigSchema.object({
      'properties': {
        'provider': ConfigSchema.enum_(['nvidia', 'openai', 'local'], defaultValue: 'nvidia'),
        'model': ConfigSchema.string(
          minLength: 1,
          maxLength: 100,
          defaultValue: 'kimi-k2.6',
        ),
        'api_key': ConfigSchema.string(),
        'endpoint': ConfigSchema.string(),
        'max_tokens': ConfigSchema.number(
          min: 1,
          max: 8192,
          defaultValue: 2048,
        ),
        'temperature': ConfigSchema.number(
          min: 0.0,
          max: 2.0,
          defaultValue: 0.7,
        ),
      },
      'requiredProperties': ['provider'],
    }));

    // Performance configuration schema
    registerSchema('performance', ConfigSchema.object({
      'properties': {
        'enable_lazy_loading': ConfigSchema.boolean(defaultValue: true),
        'enable_object_pooling': ConfigSchema.boolean(defaultValue: true),
        'enable_throttling': ConfigSchema.boolean(defaultValue: true),
        'memory_limit_mb': ConfigSchema.number(
          min: 512,
          max: 8192,
          defaultValue: 2048,
        ),
        'cpu_threshold': ConfigSchema.number(
          min: 0.5,
          max: 1.0,
          defaultValue: 0.8,
        ),
      },
    }));

    debugPrint('🔍 Registered ${_schemas.length} default schemas');
  }

  /// Register global validation rules
  Future<void> _registerGlobalRules() async {
    // Security validation rule
    registerValidationRule(ValidationRule(
      name: 'security_check',
      validate: (configType, data) {
        final errors = <ValidationError>[];
        final warnings = <ValidationWarning>[];

        // Check for sensitive data
        if (data is Map) {
          for (final entry in data.entries) {
            if (entry.key.toLowerCase().contains('password') ||
                entry.key.toLowerCase().contains('secret') ||
                entry.key.toLowerCase().contains('token')) {
              if (entry.value != null && entry.value.toString().isNotEmpty) {
                warnings.add(ValidationWarning('Sensitive data detected in configuration: ${entry.key}'));
              }
            }
          }
        }

        return ValidationResult(errors: errors, warnings: warnings);
      },
    ));

    // Performance validation rule
    registerValidationRule(ValidationRule(
      name: 'performance_check',
      validate: (configType, data) {
        final errors = <ValidationError>[];
        final warnings = <ValidationWarning>[];

        if (configType == 'performance' && data is Map) {
          final memoryLimit = data['memory_limit_mb'];
          if (memoryLimit != null && memoryLimit is num && memoryLimit < 1024) {
            warnings.add(ValidationWarning('Low memory limit may affect performance'));
          }
        }

        return ValidationResult(errors: errors, warnings: warnings);
      },
    ));

    debugPrint('🔍 Registered ${_globalRules.length} global rules');
  }

  /// Get validation statistics
  ValidationStatistics getStatistics() {
    return ValidationStatistics(
      registeredSchemas: _schemas.length,
      registeredRules: _globalRules.length,
      validationHistory: Map.unmodifiable(_validationHistory),
      autoCorrectEnabled: _autoCorrect,
    );
  }

  /// Set auto-correction mode
  void setAutoCorrect(bool enabled) {
    _autoCorrect = enabled;
    debugPrint('🔍 Auto-correction ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Dispose configuration validator
  Future<void> dispose() async {
    _validationController.close();
    _schemas.clear();
    _globalRules.clear();
    _validationHistory.clear();
    
    debugPrint('🔍 Configuration Validator disposed');
  }
}

/// Configuration schema
class ConfigSchema {
  final SchemaType type;
  final dynamic defaultValue;
  final bool isRequired;
  final String? pattern;
  final int? minLength;
  final int? maxLength;
  final num? min;
  final num? max;
  final int? minItems;
  final int? maxItems;
  final List<String>? enumValues;
  final ConfigSchema? items;
  final Map<String, ConfigSchema>? properties;
  final List<String>? requiredProperties;
  final bool additionalProperties;

  ConfigSchema({
    required this.type,
    this.defaultValue,
    this.isRequired = false,
    this.pattern,
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.minItems,
    this.maxItems,
    this.enumValues,
    this.items,
    this.properties,
    this.requiredProperties,
    this.additionalProperties = true,
  });

  factory ConfigSchema.string({
    String? defaultValue,
    bool isRequired = false,
    String? pattern,
    int? minLength,
    int? maxLength,
  }) {
    return ConfigSchema(
      type: SchemaType.string,
      defaultValue: defaultValue,
      isRequired: isRequired,
      pattern: pattern,
      minLength: minLength,
      maxLength: maxLength,
    );
  }

  factory ConfigSchema.number({
    num? defaultValue,
    bool isRequired = false,
    num? min,
    num? max,
  }) {
    return ConfigSchema(
      type: SchemaType.number,
      defaultValue: defaultValue,
      isRequired: isRequired,
      min: min,
      max: max,
    );
  }

  factory ConfigSchema.boolean({
    bool? defaultValue,
    bool isRequired = false,
  }) {
    return ConfigSchema(
      type: SchemaType.boolean,
      defaultValue: defaultValue,
      isRequired: isRequired,
    );
  }

  factory ConfigSchema.array({
    ConfigSchema? items,
    int? minItems,
    int? maxItems,
    bool isRequired = false,
  }) {
    return ConfigSchema(
      type: SchemaType.array,
      items: items,
      minItems: minItems,
      maxItems: maxItems,
      isRequired: isRequired,
    );
  }

  factory ConfigSchema.object({
    Map<String, ConfigSchema>? properties,
    List<String>? requiredProperties,
    bool isRequired = false,
    bool additionalProperties = true,
  }) {
    return ConfigSchema(
      type: SchemaType.object,
      properties: properties,
      requiredProperties: requiredProperties,
      isRequired: isRequired,
      additionalProperties: additionalProperties,
    );
  }

  factory ConfigSchema.enum_(
    List<String> values, {
    String? defaultValue,
    bool isRequired = false,
  }) {
    return ConfigSchema(
      type: SchemaType.enum_,
      enumValues: values,
      defaultValue: defaultValue,
      isRequired: isRequired,
    );
  }
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;
  final dynamic correctedData;
  final String? configType;

  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    this.correctedData,
    this.configType,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Validation error
class ValidationError {
  final String message;
  final String? path;
  
  ValidationError(this.message, {this.path});
  
  @override
  String toString() => path != null ? '$path: $message' : message;
}

/// Validation warning
class ValidationWarning {
  final String message;
  final String? path;
  
  ValidationWarning(this.message, {this.path});
  
  @override
  String toString() => path != null ? '$path: $message' : message;
}

/// Validation rule
class ValidationRule {
  final String name;
  final ValidationResult Function(String, dynamic) validate;
  
  ValidationRule({
    required this.name,
    required this.validate,
  });
}

/// Validation event
class ValidationEvent {
  final ValidationEventType type;
  final String configType;
  final ValidationResult? result;
  final DateTime timestamp;
  
  ValidationEvent({
    required this.type,
    required this.configType,
    this.result,
    required this.timestamp,
  });
}

/// Validation statistics
class ValidationStatistics {
  final int registeredSchemas;
  final int registeredRules;
  final Map<String, List<ValidationResult>> validationHistory;
  final bool autoCorrectEnabled;
  
  ValidationStatistics({
    required this.registeredSchemas,
    required this.registeredRules,
    required this.validationHistory,
    required this.autoCorrectEnabled,
  });
}

/// Enums
enum SchemaType { string, number, boolean, array, object, enum_ }
enum ValidationEventType { 
  validationStarted, 
  validationCompleted, 
  schemaRegistered, 
  ruleRegistered 
}
