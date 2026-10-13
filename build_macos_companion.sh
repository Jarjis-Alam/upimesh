#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$PROJECT_ROOT/macos/build/UPIMeshCompanion.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "=== Building UPI Offline Mesh — macOS Peer Test Companion ==="

# 1. Clean and prepare app bundle directory
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

# 2. Compile companion binary using macOS Swift toolchain
echo "--> Compiling Swift sources for macOS..."
swiftc -framework SwiftUI \
       -framework AppKit \
       -framework MultipeerConnectivity \
       -framework Security \
       -framework CryptoKit \
       "$PROJECT_ROOT/ios/UPIMesh/UPIMesh/PaymentInstruction.swift" \
       "$PROJECT_ROOT/ios/UPIMesh/UPIMesh/OfflinePaymentPacket.swift" \
       "$PROJECT_ROOT/ios/UPIMesh/UPIMesh/PeerTransferMessage.swift" \
       "$PROJECT_ROOT/macos/UPIMeshCompanion/MacDeviceIdentityManager.swift" \
       "$PROJECT_ROOT/macos/UPIMeshCompanion/MacReceivedPacketStore.swift" \
       "$PROJECT_ROOT/macos/UPIMeshCompanion/MacPeerTransportService.swift" \
       "$PROJECT_ROOT/macos/UPIMeshCompanion/MacCompanionView.swift" \
       "$PROJECT_ROOT/macos/UPIMeshCompanion/UPIMeshCompanionApp.swift" \
       -o "$MACOS_DIR/UPIMeshCompanion"

# 3. Copy Info.plist and PkgInfo
echo "--> Bundling Info.plist..."
cp "$PROJECT_ROOT/macos/UPIMeshCompanion/Info.plist" "$CONTENTS_DIR/Info.plist"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 4. Code sign app bundle
echo "--> Code signing app bundle..."
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)
if [ -n "$SIGN_ID" ]; then
    echo "Using signing identity: $SIGN_ID"
    codesign --force --sign "$SIGN_ID" --entitlements "$PROJECT_ROOT/macos/UPIMeshCompanion/UPIMeshCompanion.entitlements" "$APP_DIR"
else
    echo "Using ad-hoc signing (Sign to Run Locally)"
    codesign --force --sign - --entitlements "$PROJECT_ROOT/macos/UPIMeshCompanion/UPIMeshCompanion.entitlements" "$APP_DIR"
fi

# 5. Verify code signature
codesign -v "$APP_DIR"

echo "=== Build Succeeded! ==="
echo "App Bundle created at: $APP_DIR"
echo "Launch with: open $APP_DIR"
