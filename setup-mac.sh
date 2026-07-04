#!/usr/bin/env bash
#
# setup-mac.sh — Set up this Mac for iOS development of the TorqueDen Flutter app.
#
# Focused on iOS only: Xcode + Command Line Tools, Homebrew, Flutter (Dart),
# CocoaPods, and the iOS Simulator. No Android / web tooling.
#
# Safe to re-run: every step checks whether the tool is already installed
# and skips it if so. Some steps (Xcode license, Homebrew) will prompt for
# your password — that's expected.
#
# Usage:
#   cd "/Users/lukewelch/Claude/Car App"
#   chmod +x setup-mac.sh
#   ./setup-mac.sh
#
set -uo pipefail

# ---- pretty output -----------------------------------------------------------
bold=$(tput bold 2>/dev/null || true); reset=$(tput sgr0 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true); yellow=$(tput setaf 3 2>/dev/null || true)
red=$(tput setaf 1 2>/dev/null || true)
step() { echo; echo "${bold}==> $*${reset}"; }
ok()   { echo "${green}  ✓ $*${reset}"; }
warn() { echo "${yellow}  ! $*${reset}"; }
err()  { echo "${red}  ✗ $*${reset}"; }
have() { command -v "$1" >/dev/null 2>&1; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 0. sanity ---------------------------------------------------------------
step "Checking machine"
echo "  Architecture: $(uname -m)"
echo "  macOS:        $(sw_vers -productVersion 2>/dev/null)"
echo "  Project:      $PROJECT_DIR"

# ---- 1. Xcode Command Line Tools + license -----------------------------------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode / CLT path: $(xcode-select -p)"
else
  warn "Installing Command Line Tools (a GUI dialog will pop up)…"
  xcode-select --install || true
  warn "Finish the CLT install dialog, then re-run this script."
  exit 1
fi

if [ ! -d /Applications/Xcode.app ]; then
  err "Xcode.app not found in /Applications — install Xcode from the App Store first."
  exit 1
fi

# Point the toolchain at the full Xcode (not just CLT) — required for iOS builds.
if [ "$(xcode-select -p)" != "/Applications/Xcode.app/Contents/Developer" ]; then
  warn "Pointing xcode-select at Xcode.app…"
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
fi

step "Xcode first-launch components + license"
sudo xcodebuild -runFirstLaunch 2>/dev/null || true
sudo xcodebuild -license accept 2>/dev/null && ok "Xcode license accepted" || warn "Could not auto-accept license (may already be accepted)"

step "iOS Simulator runtime"
xcodebuild -downloadPlatform iOS 2>/dev/null && ok "iOS platform present/downloaded" || warn "Could not verify iOS platform — check Xcode ▸ Settings ▸ Components"

# ---- 2. Homebrew -------------------------------------------------------------
step "Homebrew"
if have brew; then
  ok "Homebrew already installed: $(brew --version | head -1)"
else
  warn "Installing Homebrew (will prompt for your password)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make brew available in THIS shell (Apple Silicon installs to /opt/homebrew)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Persist brew in future zsh sessions
if have brew; then
  BREW_LINE="eval \"\$($(brew --prefix)/bin/brew shellenv)\""
  if ! grep -qsF "$BREW_LINE" "$HOME/.zprofile" 2>/dev/null; then
    echo "$BREW_LINE" >> "$HOME/.zprofile"
    ok "Added Homebrew to ~/.zprofile"
  fi
else
  err "Homebrew still not on PATH — open a new terminal and re-run."
  exit 1
fi

# ---- 3. Flutter (bundles Dart) + CocoaPods -----------------------------------
step "Flutter SDK"
if have flutter; then
  ok "Flutter already installed: $(flutter --version 2>/dev/null | head -1)"
else
  warn "Installing Flutter via Homebrew…"
  brew install --cask flutter
fi

step "CocoaPods (required for iOS plugin builds)"
if have pod; then
  ok "CocoaPods already installed: $(pod --version)"
else
  warn "Installing CocoaPods…"
  brew install cocoapods
fi

# ---- 4. Restore project dependencies -----------------------------------------
step "Restoring project dependencies (flutter pub get)"
if have flutter; then
  ( cd "$PROJECT_DIR" && flutter pub get ) && ok "Dependencies restored"
fi

step "Installing iOS CocoaPods for the project"
if [ -d "$PROJECT_DIR/ios" ] && have pod; then
  ( cd "$PROJECT_DIR/ios" && pod install ) && ok "Pods installed" || warn "pod install had issues — often fixed by 'flutter clean' then re-running"
fi

# ---- 5. Doctor ---------------------------------------------------------------
step "flutter doctor"
if have flutter; then
  flutter doctor
fi

echo
echo "${bold}${green}Done.${reset}"
echo "Next steps (iOS):"
echo "  1. Open a NEW terminal (so brew + flutter are on PATH)."
echo "  2. Review any ✗ / ! items from 'flutter doctor' above."
echo "  3. Boot a simulator and run:"
echo "       cd \"$PROJECT_DIR\""
echo "       open -a Simulator"
echo "       flutter devices          # confirm the simulator is listed"
echo "       flutter run              # runs on the booted simulator"
echo
echo "Note: running on a physical iPhone additionally needs a free Apple ID"
echo "signing team set in Xcode (open ios/Runner.xcworkspace ▸ Signing & Capabilities)."
