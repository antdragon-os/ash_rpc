#!/bin/bash

# Test Hex publishing setup
# This script validates the package configuration before publishing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info "Testing AshRpc Hex publishing setup..."

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    print_error "mix.exs not found. Please run this script from the ash_rpc package directory."
    exit 1
fi

# Check Elixir version
print_info "Checking Elixir version..."
ELIXIR_VERSION=$(elixir -v | grep "Elixir" | cut -d' ' -f2)
print_success "Elixir version: $ELIXIR_VERSION"

# Check Mix version
print_info "Checking Mix version..."
MIX_VERSION=$(mix --version | grep "Mix" | cut -d' ' -f3)
print_success "Mix version: $MIX_VERSION"

# Check current version
print_info "Checking current package version..."
CURRENT_VERSION=$(mix run -e "IO.puts Mix.Project.config()[:version]" | tail -1)
print_success "Package version: $CURRENT_VERSION"

# Check Hex user authentication
print_info "Checking Hex authentication..."
if mix hex.user whoami > /dev/null 2>&1; then
    HEX_USER=$(mix hex.user whoami)
    print_success "Authenticated as: $HEX_USER"
else
    print_warning "Not authenticated with Hex. Run 'mix hex.user auth' to authenticate."
fi

# Check dependencies
print_info "Checking dependencies..."
mix deps.get > /dev/null 2>&1
print_success "Dependencies installed"

# Check compilation
print_info "Checking compilation..."
mix compile --warnings-as-errors > /dev/null 2>&1
print_success "Compilation successful"

# Check tests
print_info "Running tests..."
mix test > /dev/null 2>&1
print_success "All tests passed"

# Check formatting
print_info "Checking code formatting..."
if mix format --check-formatted > /dev/null 2>&1; then
    print_success "Code is properly formatted"
else
    print_warning "Code formatting issues found. Run 'mix format' to fix."
fi

# Check Credo
print_info "Running Credo..."
if mix credo --strict > /dev/null 2>&1; then
    print_success "Credo checks passed"
else
    print_warning "Credo issues found. Review and fix code quality issues."
fi

# Check documentation
print_info "Checking documentation generation..."
mix docs > /dev/null 2>&1
print_success "Documentation generated successfully"

# Check package configuration
print_info "Validating package configuration..."
PACKAGE_NAME=$(mix run -e "IO.puts Mix.Project.config()[:app]" | tail -1)
print_success "Package name: $PACKAGE_NAME"

# Check Hex publish dry run
print_info "Running Hex publish dry-run..."
if mix hex.publish --dry-run > /dev/null 2>&1; then
    print_success "Hex publish validation passed"
else
    print_error "Hex publish validation failed. Check the output above for details."
    exit 1
fi

# Check required files
print_info "Checking required files..."
REQUIRED_FILES=("README.md" "CHANGELOG.md" "LICENSE" "mix.exs")
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "✓ $file exists"
    else
        print_error "✗ $file missing"
        exit 1
    fi
done

# Check guides directory
if [ -d "guides" ]; then
    GUIDE_COUNT=$(find guides -name "*.md" | wc -l)
    print_success "✓ Guides directory exists with $GUIDE_COUNT guide files"
else
    print_warning "⚠️  Guides directory not found"
fi

print_success "All checks passed! Ready to publish AshRpc to Hex."
print_info "Next steps:"
echo "  1. Update version in mix.exs if needed"
echo "  2. Update CHANGELOG.md"
echo "  3. Run './bin/publish_local.sh' for local testing"
echo "  4. Run './bin/release.sh' for full release"
echo "  5. Or push a git tag to trigger automated release"

exit 0
