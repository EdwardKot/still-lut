#!/bin/bash

# Native Swift/Metal App Packaging Script
# No Python dependency - pure Swift build

# Configuration
APP_NAME="RawToLog"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
SWIFT_EXECUTABLE="RawToLogConverter"
ASSETS_DIR="Sources/RawToLogConverter/Assets.xcassets"

echo "📦 Starting Native App Packaging..."

# 1. Check Prerequisites
if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found."
    exit 1
fi

# 2. Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 3. Build Swift App (Release)
echo "🚀 Building Swift App (Release)..."
swift build -c release
if [ $? -ne 0 ]; then
    echo "❌ Swift build failed."
    exit 1
fi

# 4. Create App Bundle Structure
echo "📂 Assembling App Bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 5. Copy Swift Binary
echo "📋 Copying binary..."
cp "${BUILD_DIR}/${SWIFT_EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 6. Generate App Icon (.icns)
echo "🎨 Generating App Icon..."
ICONSET_DIR="${ASSETS_DIR}/AppIcon.appiconset"
ICNS_FILE="${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

if [ -d "$ICONSET_DIR" ]; then
    # Create a temporary .iconset directory with proper naming for iconutil
    TEMP_ICONSET="/tmp/AppIcon.iconset"
    rm -rf "$TEMP_ICONSET"
    mkdir -p "$TEMP_ICONSET"
    
    # Copy icons with iconutil-compatible naming
    cp "${ICONSET_DIR}/icon_16x16.png" "${TEMP_ICONSET}/icon_16x16.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_16x16@2x.png" "${TEMP_ICONSET}/icon_16x16@2x.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_32x32.png" "${TEMP_ICONSET}/icon_32x32.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_32x32@2x.png" "${TEMP_ICONSET}/icon_32x32@2x.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_128x128.png" "${TEMP_ICONSET}/icon_128x128.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_128x128@2x.png" "${TEMP_ICONSET}/icon_128x128@2x.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_256x256.png" "${TEMP_ICONSET}/icon_256x256.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_256x256@2x.png" "${TEMP_ICONSET}/icon_256x256@2x.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_512x512.png" "${TEMP_ICONSET}/icon_512x512.png" 2>/dev/null
    cp "${ICONSET_DIR}/icon_512x512@2x.png" "${TEMP_ICONSET}/icon_512x512@2x.png" 2>/dev/null
    
    # Generate .icns file
    iconutil -c icns "$TEMP_ICONSET" -o "$ICNS_FILE"
    if [ $? -eq 0 ]; then
        echo "   ✅ App Icon created"
    else
        echo "   ⚠️ Icon generation failed, continuing without icon"
    fi
    rm -rf "$TEMP_ICONSET"
else
    echo "   ⚠️ No icon assets found at $ICONSET_DIR"
fi

# 7. Create Info.plist
echo "📝 Generating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.edward.RawToLog</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>RAW+LUT</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 8. Sign App Bundle (Ad-hoc)
echo "🔏 Signing App Bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Packaging Complete!"
echo "应用已生成在: ${APP_BUNDLE}"
echo ""
echo "🎉 原生 Swift/Metal 版本 - 无 Python 依赖"
echo "   - 更快的启动速度"
echo "   - 更小的应用体积"
echo "   - 更稳定的运行"
echo "   - 自定义应用图标"

