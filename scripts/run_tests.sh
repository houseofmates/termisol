#!/bin/bash

# Automated Test Runner Script for Termisol
# This script runs the complete test suite and generates reports

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project root
PROJECT_ROOT="${TERMISOL_REPO_DIR:-$(pwd)}"
cd "$PROJECT_ROOT"

echo -e "${BLUE}Starting Termisol Test Suite${NC}"
echo "=================================================="

# Create necessary directories
mkdir -p test_results/{unit,integration,performance,memory,security}
mkdir -p reports

# Function to run a test category
run_test_category() {
    local category=$1
    echo -e "\n${YELLOW}Running $category tests...${NC}"

    case $category in
        "unit")
            echo "Running unit tests..."
            dart test test/unit/ --reporter=json > test_results/unit/results.json 2>&1
            dart test test/unit/ --reporter=compact
            ;;
        "integration")
            echo "Running integration tests..."
            dart test test/integration/ --reporter=json > test_results/integration/results.json 2>&1
            dart test test/integration/ --reporter=compact
            ;;
        "performance")
            echo "Running performance tests..."
            dart test test/performance/ --reporter=json > test_results/performance/results.json 2>&1
            dart test test/performance/ --reporter=compact
            ;;
        "memory")
            echo "Running memory leak tests..."
            dart test test/memory/ --reporter=json > test_results/memory/results.json 2>&1
            dart test test/memory/ --reporter=compact
            ;;
        "security")
            echo "Running security tests..."
            dart test test/production/security_permission_tests.dart --reporter=compact
            ;;
        *)
            echo -e "${RED}Unknown test category: $category${NC}"
            exit 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}$category tests completed successfully${NC}"
    else
        echo -e "${RED}$category tests failed${NC}"
        exit 1
    fi
}

# Function to generate coverage report
generate_coverage() {
    echo -e "\n${YELLOW}Generating coverage report...${NC}"

    dart test --coverage=coverage

    if command -v genhtml &> /dev/null; then
        dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib
        genhtml coverage.lcov --output-directory coverage_html
        echo -e "${GREEN}Coverage report generated in coverage_html/${NC}"
    else
        echo -e "${YELLOW}genhtml not found, generating text coverage report${NC}"
        dart run coverage:format_coverage --report-on=lib --in=coverage --out=coverage.txt
        echo -e "${GREEN}Text coverage report generated in coverage.txt${NC}"
    fi
}

# Function to run comprehensive analysis
run_analysis() {
    echo -e "\n${YELLOW}Running comprehensive analysis...${NC}"

    echo "Running static analysis..."
    dart analyze > test_results/static_analysis.txt 2>&1

    echo "Checking dependencies..."
    dart pub deps --style=tree > test_results/dependencies.txt 2>&1

    echo -e "${GREEN}Analysis completed${NC}"
}

# Main execution
main() {
    local start_time=$(date +%s)

    if [ $# -eq 0 ]; then
        run_test_category "unit"
        run_test_category "integration"
        run_test_category "performance"
        run_test_category "memory"
        run_test_category "security"
        generate_coverage
        run_analysis
    else
        run_test_category "$1"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo -e "\n${GREEN}Test suite completed in ${duration} seconds${NC}"
}

# Check if dart is available
if ! command -v dart &> /dev/null; then
    echo -e "${RED}Dart is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found. Please run from project root.${NC}"
    exit 1
fi

# Install dependencies if needed
if [ ! -d ".dart_tool" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    dart pub get
fi

main "$@"
