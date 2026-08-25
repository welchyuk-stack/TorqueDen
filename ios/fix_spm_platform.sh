#!/bin/sh
# Patches the Flutter-generated SwiftPM Package.swift to require iOS 15.0
# instead of 13.0, which is needed by firebase_core and firebase_messaging.
# Run after `flutter pub get` or `flutter clean && flutter pub get`.
PACKAGE_SWIFT="$(dirname "$0")/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ -f "$PACKAGE_SWIFT" ]; then
  sed -i '' 's/\.iOS("13\.0")/.iOS("15.0")/g' "$PACKAGE_SWIFT"
  echo "Patched $PACKAGE_SWIFT to iOS 15.0"
fi
