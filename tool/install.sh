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
flutter build apk --"$MODE" "$@"
APK="build/app/outputs/flutter-apk/app-$MODE.apk"

adb push "$APK" /data/local/tmp/duet.apk
adb shell pm install -r -t /data/local/tmp/duet.apk
adb shell am start -n com.duet.alarm/.MainActivity
echo "installed and launched ($MODE)"
