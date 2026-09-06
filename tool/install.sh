#!/usr/bin/env bash
# Build and install on a HyperOS/MIUI device.
#
# Xiaomi blocks host-side `adb install` with INSTALL_FAILED_USER_RESTRICTED even
# when "Install via USB" and "USB debugging (Security settings)" are both on.
# Pushing to /data/local/tmp and running pm install ON the device side-steps it.
# (/sdcard does not work -- SELinux denies system_server access to the fuse mount.)
set -euo pipefail
cd "$(dirname "$0")/.."
source tool/env.sh

MODE="${1:-debug}"
shift || true
# Remaining args go straight to the build, e.g.
#   ./tool/install.sh debug --dart-define=DUET_BACKEND=true
cd app
# Per-ABI, and this phone is arm64-only: a universal debug APK ships four
# ABIs (~180 MB); the arm64 slice is a third of that and installs faster.
# Stays DEBUG deliberately -- release builds get versionCode 2001+, and a
# later debug downgrade is an uninstall that wipes the Supabase session
# (docs/14 gotcha 3). `./tool/install.sh release` still works for real
# distribution builds when you actually want one.
flutter build apk --"$MODE" --split-per-abi "$@"
APK="build/app/outputs/flutter-apk/app-arm64-v8a-$MODE.apk"

adb push "$APK" /data/local/tmp/duet.apk
adb shell pm install -r -t /data/local/tmp/duet.apk
adb shell am start -n com.duet.alarm/.MainActivity
echo "installed and launched ($MODE, arm64)"
