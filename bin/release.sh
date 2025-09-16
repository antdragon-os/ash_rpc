#!/bin/bash

# AshRpc Release Script
# This script helps with releasing AshRpc to Hex from your local machine

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
    print_error "You are not authenticated with Hex. Please run 'mix hex.user auth' first."
    exit 1
fi

# Get current version
CURRENT_VERSION=$(mix run -e "IO.puts Mix.Project.config()[:version]" | tail -1)
print_info "Current version: $CURRENT_VERSION"

# Ask for version bump type
echo "Select version bump type:"
echo "1) Patch (bug fixes) - $CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print $1"."$2"."($3+1)}')"
echo "2) Minor (new features) - $CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print $1"."($2+1)".0"}')"
echo "3) Major (breaking changes) - $CURRENT_VERSION -> $(echo $CURRENT_VERSION | awk -F. '{print ($1+1)".0.0"}')"
echo "4) Custom version"
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        # Patch version
        IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
        NEW_VERSION="${VERSION_PARTS[0]}.${VERSION_PARTS[1]}.$((VERSION_PARTS[2] + 1))"
        ;;
    2)
        # Minor version
        IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
        NEW_VERSION="${VERSION_PARTS[0]}.$((VERSION_PARTS[1] + 1)).0"
        ;;
    3)
        # Major version
        IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
        NEW_VERSION="$((VERSION_PARTS[0] + 1)).0.0"
        ;;
    4)
        # Custom version
        read -p "Enter custom version: " NEW_VERSION
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

print_info "New version will be: $NEW_VERSION"

# Confirm
read -p "Continue with release? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_info "Release cancelled"
    exit 0
fi

# Run pre-release checks
print_info "Running pre-release checks..."
mix release.check

# Update version in mix.exs
print_info "Updating version in mix.exs..."
sed -i.bak "s/@version \".*\"/@version \"$NEW_VERSION\"/" mix.exs

# Generate docs
print_info "Generating documentation..."
mix docs

# Show what will be published
print_info "Dry run of Hex publish..."
mix hex.publish --dry-run

# Confirm final release
read -p "Ready to publish to Hex? (y/N): " final_confirm
if [[ ! $final_confirm =~ ^[Yy]$ ]]; then
    print_warning "Release cancelled. Restoring original mix.exs..."
    mv mix.exs.bak mix.exs
    exit 0
fi

# Publish to Hex
print_info "Publishing to Hex..."
mix hex.publish --yes

# Create git tag
print_info "Creating git tag..."
git add mix.exs
git commit -m "Release v$NEW_VERSION"
git tag "v$NEW_VERSION"
git push origin main
git push origin "v$NEW_VERSION"

# Clean up backup
rm mix.exs.bak

print_success "Successfully released ash_rpc v$NEW_VERSION!"
print_info "Don't forget to:"
echo "  - Update the CHANGELOG.md"
echo "  - Create a GitHub release if using GitHub"
echo "  - Notify your team about the new release"

# Optional: Open browser to create GitHub release
if command -v open &> /dev/null; then
    read -p "Open GitHub releases page? (y/N): " open_gh
    if [[ $open_gh =~ ^[Yy]$ ]]; then
        open "https://github.com/antdragon-os/ash_rpc/releases/new?tag=v$NEW_VERSION&title=Release%20v$NEW_VERSION"
    fi
fi
