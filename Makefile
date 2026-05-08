# Termisol Makefile
# Replaces the invalid pubspec.yaml scripts section

.PHONY: test test-ci test-unit test-integration test-performance test-production analyze format ci clean help

# Default target
help:
	@echo "Termisol Build & Test Commands:"
	@echo "  test          - Run all tests with coverage"
	@echo "  test-ci       - Run tests with coverage and random ordering"
	@echo "  test-unit     - Run unit tests only"
	@echo "  test-integration - Run integration tests only"
	@echo "  test-performance - Run performance tests only"
	@echo "  test-production - Run production tests only"
	@echo "  analyze       - Run static analysis"
	@echo "  format        - Format Dart code"
	@echo "  ci            - Run analyze + test-ci (CI pipeline)"
	@echo "  clean         - Clean build artifacts"
	@echo "  deps          - Get dependencies"
	@echo "  deps-upgrade  - Upgrade dependencies"

# Test commands
test:
	flutter test --coverage

test-ci:
	flutter test --coverage --test-randomize-ordering-seed random

test-unit:
	flutter test test/unit/

test-integration:
	flutter test test/integration/

test-performance:
	flutter test test/performance/

test-production:
	flutter test test/production/

# Code quality commands
analyze:
	flutter analyze

format:
	dart format .

# CI pipeline
ci: analyze test-ci

# Dependency management
deps:
	flutter pub get

deps-upgrade:
	flutter pub upgrade

# Cleanup
clean:
	flutter clean
	rm -f coverage/lcov.info

# Build commands
build-debug:
	flutter build debug

build-release:
	flutter build release

build-apk:
	flutter build apk --release

build-linux:
	flutter build linux --release

# Development helpers
watch:
	flutter run --debug

run:
	flutter run --release
