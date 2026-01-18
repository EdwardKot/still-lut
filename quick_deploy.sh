#!/bin/bash
# One-click deployment script for Still-LUT
# This script automates all installation and build steps

set -e  # Exit on any error

echo "🎬 Still-LUT - One-Click Deployment Script"
echo "============================================"
echo ""

# 1. Check for Homebrew
echo "📦 Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found."
    echo "Please install Homebrew first:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
echo "   ✅ Homebrew found: $(brew --version)"
echo ""

# 2. Check for Swift
echo "🔍 Checking for Swift..."
if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found."
    echo "Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi
SWIFT_VERSION=$(swift --version)
echo "   ✅ Swift found: $SWIFT_VERSION"
echo ""

# 3. Install LibRaw (if not installed)
echo "📚 Checking for LibRaw..."
if ! brew list libraw &> /dev/null; then
    echo "   LibRaw not found. Installing..."
    brew install libraw
    echo "   ✅ LibRaw installed"
else
    echo "   ✅ LibRaw already installed"
fi
echo ""

# 4. Check macOS version
echo "💻 Checking macOS version..."
MACOS_VERSION=$(sw_vers -productVersion)
echo "   macOS version: $MACOS_VERSION"

# Convert version to number for comparison (e.g., 14.0 -> 14)
MAJOR_VERSION=$(echo $MACOS_VERSION | cut -d. -f1)
if [ "$MAJOR_VERSION" -lt 14 ]; then
    echo "   ⚠️ Warning: macOS 14.0+ is required (you have $MACOS_VERSION)"
    echo "   The app may not work correctly on this version."
fi
echo ""

# 5. Build the app
echo "🔨 Building Still-LUT app..."
./package_native_app.sh
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "🎉 Still-LUT is ready to use!"
    echo ""
    echo "App location: dist/RawToLog.app"
    echo ""
    echo "To run:"
    echo "  open dist/RawToLog.app"
    echo ""
    echo "Or double-click 'RawToLog.app' in Finder"
else
    echo ""
    echo "❌ Build failed with exit code $BUILD_STATUS"
    exit $BUILD_STATUS
fi
