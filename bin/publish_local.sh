#!/bin/bash

# AshRpc Local Publish Script
# This script helps with testing Hex publishing locally

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

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    print_error "mix.exs not found. Please run this script from the ash_rpc package directory."
    exit 1
fi

# Check if Hex is authenticated
if ! mix hex.user whoami > /dev/null 2>&1; then
    print_error "You are not authenticated with Hex."
    print_info "Please authenticate with: mix hex.user auth"
    exit 1
fi

print_info "Hex user: $(mix hex.user whoami)"

# Run checks
print_info "Running pre-publish checks..."
mix release.check

# Generate docs
print_info "Generating documentation..."
mix docs

# Dry run
print_info "Running dry-run publish..."
mix hex.publish --dry-run

# Ask for confirmation
read -p "Publish to Hex? (y/N): " confirm
if [[ $confirm =~ ^[Yy]$ ]]; then
    print_info "Publishing to Hex..."
    mix hex.publish --yes
    print_success "Successfully published to Hex!"
else
    print_info "Publish cancelled"
fi
