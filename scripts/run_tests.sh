#!/bin/bash

# Automated Test Runner Script for Termisol
# This script runs the complete test suite and generates reports

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="/home/house/termisol"
cd "$PROJECT_ROOT"

echo -e "${BLUE}🚀 Starting Termisol Test Suite${NC}"
echo "=================================================="

# Create necessary directories
mkdir -p test_results/{unit,integration,performance,memory,security}
mkdir -p reports

# Function to run a test category
run_test_category() {
    local category=$1
    echo -e "\n${YELLOW}🧪 Running $category tests...${NC}"
    
    case $category in
        "unit")
            echo "Running unit tests..."
            dart test test/unit/ --reporter=json > test_results/unit/results.json 2>&1 || true
            dart test test/unit/ --reporter=compact
            ;;
        "integration")
            echo "Running integration tests..."
            dart test test/integration/ --reporter=json > test_results/integration/results.json 2>&1 || true
            dart test test/integration/ --reporter=compact
            ;;
        "performance")
            echo "Running performance tests..."
            dart test test/performance/ --reporter=json > test_results/performance/results.json 2>&1 || true
            dart test test/performance/ --reporter=compact
            ;;
        "memory")
            echo "Running memory leak tests..."
            dart test test/memory_leak_detector.dart --reporter=json > test_results/memory/results.json 2>&1 || true
            dart test test/memory_leak_detector.dart --reporter=compact
            ;;
        "security")
            echo "Running security tests..."
            dart run scripts/test_runner.dart --category security
            ;;
        *)
            echo -e "${RED}Unknown test category: $category${NC}"
            exit 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $category tests completed successfully${NC}"
    else
        echo -e "${RED}❌ $category tests failed${NC}"
    fi
}

# Function to generate coverage report
generate_coverage() {
    echo -e "\n${YELLOW}📊 Generating coverage report...${NC}"
    
    # Run tests with coverage
    dart test --coverage=coverage
    
    # Format coverage report
    if command -v genhtml &> /dev/null; then
        dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib
        genhtml coverage.lcov --output-directory coverage_html
        echo -e "${GREEN}✅ Coverage report generated in coverage_html/${NC}"
    else
        echo -e "${YELLOW}⚠️  genhtml not found, generating text coverage report${NC}"
        dart run coverage:format_coverage --report-on=lib --in=coverage --out=coverage.txt
        echo -e "${GREEN}✅ Text coverage report generated in coverage.txt${NC}"
    fi
}

# Function to run comprehensive analysis
run_analysis() {
    echo -e "\n${YELLOW}🔍 Running comprehensive analysis...${NC}"
    
    # Run the Dart test runner
    dart run scripts/test_runner.dart
    
    # Run static analysis
    echo "Running static analysis..."
    dart analyze > test_results/static_analysis.txt 2>&1 || true
    
    # Check for security vulnerabilities
    echo "Running security scan..."
    dart run scripts/security_scan.dart > test_results/security_scan.txt 2>&1 || true
    
    # Run dependency check
    echo "Checking dependencies..."
    dart pub deps --style=tree > test_results/dependencies.txt 2>&1 || true
    
    echo -e "${GREEN}✅ Analysis completed${NC}"
}

# Function to generate final report
generate_final_report() {
    echo -e "\n${YELLOW}📋 Generating final report...${NC}"
    
    # Create summary report
    cat > reports/test_summary.md << EOF
# Termisol Test Suite Summary

**Date:** $(date)
**Project:** Termisol Terminal Emulator

## Test Results

### Unit Tests
$(cat test_results/unit/results.json 2>/dev/null | jq -r '.suite.tests | length // 0' 2>/dev/null || echo "0") tests run

### Integration Tests  
$(cat test_results/integration/results.json 2>/dev/null | jq -r '.suite.tests | length // 0' 2>/dev/null || echo "0") tests run

### Performance Tests
$(cat test_results/performance/results.json 2>/dev/null | jq -r '.suite.tests | length // 0' 2>/dev/null || echo "0") tests run

### Memory Tests
$(cat test_results/memory/results.json 2>/dev/null | jq -r '.suite.tests | length // 0' 2>/dev/null || echo "0") tests run

## Coverage
$(grep -o '[0-9]*%' coverage.txt 2>/dev/null | head -1 || echo "N/A")

## Issues Found
- Security Issues: $(grep -c "vulnerability\|risk" test_results/security_scan.txt 2>/dev/null || echo "0")
- Static Analysis Issues: $(grep -c "error\|warning" test_results/static_analysis.txt 2>/dev/null || echo "0")

## Recommendations
- Review any failed tests and fix issues
- Address security vulnerabilities found
- Improve test coverage where below 80%
- Fix any static analysis warnings

EOF
    
    echo -e "${GREEN}✅ Final report generated in reports/test_summary.md${NC}"
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    if [ $# -eq 0 ]; then
        # Run all tests
        run_test_category "unit"
        run_test_category "integration" 
        run_test_category "performance"
        run_test_category "memory"
        run_test_category "security"
        generate_coverage
        run_analysis
        generate_final_report
    else
        # Run specific category
        run_test_category "$1"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "\n${GREEN}🎉 Test suite completed in ${duration} seconds${NC}"
    echo -e "${BLUE}📊 Reports available in:${NC}"
    echo "  - reports/test_summary.md"
    echo "  - reports/test_summary.html"
    echo "  - reports/performance_report.html"
    echo "  - reports/security_report.html"
    echo "  - coverage_html/ (if genhtml available)"
    
    # Exit with error if any tests failed
    if grep -q "failed\|error" test_results/*/results.json 2>/dev/null; then
        echo -e "\n${RED}❌ Some tests failed. Check the reports for details.${NC}"
        exit 1
    else
        echo -e "\n${GREEN}✅ All tests passed successfully!${NC}"
        exit 0
    fi
}

# Check if dart is available
if ! command -v dart &> /dev/null; then
    echo -e "${RED}❌ Dart is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}❌ Error: pubspec.yaml not found. Please run from project root.${NC}"
    exit 1
fi

# Install dependencies if needed
if [ ! -d ".dart_tool" ]; then
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    dart pub get
fi

# Run main function with all arguments
main "$@"
