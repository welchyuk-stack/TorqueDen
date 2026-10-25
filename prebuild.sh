#!/bin/bash
set -e

echo "→ Cleaning Flutter..."
flutter clean

echo "→ Getting packages..."
flutter pub get

echo "→ Patching Package.swift to iOS 15.0..."
sed -i '' 's/.iOS("13.0")/.iOS("15.0")/' \
  ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift

echo "✓ Done — now do Product → Clean Build Folder (⇧⌘K) in Xcode, then Archive."
