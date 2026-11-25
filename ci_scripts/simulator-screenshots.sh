#!/usr/bin/env bash
# Real Simulator screenshots only. No repository project or CI modifications are made.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ci_scripts/simulator-screenshots.sh --udid UDID --app PATH.app --output DIR
       [--require-device NAME] [--require-device-type IDENTIFIER]
       [--require-ios VERSION] [--main-wait SECONDS]
       [--keyboard-timeout SECONDS] [--extra-hook EXECUTABLE]

Runs only on macOS with a selected full Xcode, an installed iOS Simulator runtime,
python3, and a simulator-built .app. It boots (but never erases) the given device,
installs/launches the app, and takes actual simctl screenshots:
  01-main-app-launch-unverified.png  launch capture, requires visual/UI-test review
  02-system-keyboard-secure.png      system keyboard in a secure helper field

The helper waits for keyboardDidShow, but this is not an XCTest or pixel assertion.
Existing named outputs are never overwritten. An optional executable extra hook
runs after both captures. It receives no positional arguments; these environment
variables are exported: SIMULATOR_UDID, APP_PATH, APP_BUNDLE_ID,
SCREENSHOT_OUTPUT_DIR, MAIN_APP_SCREENSHOT, SYSTEM_KEYBOARD_SCREENSHOT.
The hook must do its own UI setup, assertions and real captures; nonzero fails the
script. No custom keyboard installation, enabling or input test is implemented.

Example:
  ci_scripts/simulator-screenshots.sh --udid "$UDID" --app "$APP" \
    --output /tmp/hamster-shots --require-device 'iPhone 16 Pro Max' \
    --require-device-type 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max' \
    --require-ios 26.2
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }
need_value() { [ "$#" -ge 2 ] && [ -n "$2" ] || die "Missing value for $1"; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

udid='' app='' output='' required_device='' required_device_type='' required_ios='' hook=''
main_wait=8 keyboard_timeout=30
while [ "$#" -gt 0 ]; do
  case "$1" in
    --udid) need_value "$@"; udid=$2; shift 2;;
    --app) need_value "$@"; app=$2; shift 2;;
    --output) need_value "$@"; output=$2; shift 2;;
    --require-device) need_value "$@"; required_device=$2; shift 2;;
    --require-device-type) need_value "$@"; required_device_type=$2; shift 2;;
    --require-ios) need_value "$@"; required_ios=$2; shift 2;;
    --main-wait) need_value "$@"; main_wait=$2; shift 2;;
    --keyboard-timeout) need_value "$@"; keyboard_timeout=$2; shift 2;;
    --extra-hook) need_value "$@"; hook=$2; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done
[ -n "$udid" ] && [ -n "$app" ] && [ -n "$output" ] || { usage >&2; die 'Supply --udid, --app and --output'; }
is_uint "$main_wait" && [ "$main_wait" -le 120 ] || die '--main-wait must be an integer from 0 to 120'
is_uint "$keyboard_timeout" && [ "$keyboard_timeout" -ge 1 ] && [ "$keyboard_timeout" -le 180 ] || die '--keyboard-timeout must be an integer from 1 to 180'
[ "$(uname -s)" = Darwin ] || die 'macOS with Xcode and an iOS simulator is required'
for tool in xcrun python3 codesign; do command -v "$tool" >/dev/null 2>&1 || die "Missing required command: $tool"; done
[ -d "$app" ] && [ -f "$app/Info.plist" ] || die "Not an app bundle with Info.plist: $app"
app="$(cd "$app" && pwd -P)"
if [ -n "$hook" ]; then
  [ -f "$hook" ] && [ -x "$hook" ] || die "Extra hook must be an executable file: $hook"
  hook="$(cd "$(dirname "$hook")" && pwd -P)/$(basename "$hook")"
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ -f "$script_dir/KeyboardScreenshotHost.swift" ] || die 'Missing KeyboardScreenshotHost.swift beside the script'

work="$(mktemp -d "${TMPDIR:-/tmp}/hamster-screenshots.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Simulator build and bundle checks: refuse a device-only archive as input.
python3 - "$app/Info.plist" > "$work/app-info" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    p = plistlib.load(f)
bundle = p.get('CFBundleIdentifier', '')
exe = p.get('CFBundleExecutable', '')
if p.get('CFBundlePackageType') != 'APPL' or 'iPhoneSimulator' not in p.get('CFBundleSupportedPlatforms', []):
    sys.exit('ERROR: provide a simulator-built application, not an iphoneos archive or extension')
if not isinstance(bundle, str) or not bundle or '\n' in bundle or not isinstance(exe, str) or not exe or '/' in exe or '\n' in exe:
    sys.exit('ERROR: invalid bundle identifier or executable in app Info.plist')
print(bundle)
print(exe)
PY
bundle_id="$(sed -n '1p' "$work/app-info")"
app_executable="$(sed -n '2p' "$work/app-info")"
[ -f "$app/$app_executable" ] || die "App executable is missing: $app/$app_executable"
host_bundle_id='dev.hamster.simulatorscreenshot.keyboardhost'
[ "$bundle_id" != "$host_bundle_id" ] || die 'App bundle ID collides with the standalone keyboard host'

xcrun simctl list devices --json > "$work/devices.json"
python3 - "$work/devices.json" "$udid" "$required_device" "$required_device_type" "$required_ios" <<'PY'
import json, sys
path, udid, expected_name, expected_type, expected_ios = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
matches = [(runtime, d) for runtime, devices in data['devices'].items() for d in devices if d.get('udid', '').upper() == udid.upper()]
if len(matches) != 1:
    sys.exit('ERROR: UDID not found uniquely in this Xcode device set')
runtime, device = matches[0]
if not device.get('isAvailable', False):
    sys.exit('ERROR: simulator is unavailable: ' + str(device.get('availabilityError', runtime)))
if not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
    sys.exit('ERROR: selected device is not an iOS simulator: ' + runtime)
if expected_name and device.get('name') != expected_name:
    sys.exit('ERROR: simulator name mismatch: ' + device.get('name', ''))
if expected_type and device.get('deviceTypeIdentifier') != expected_type:
    sys.exit('ERROR: simulator device type mismatch or unavailable: ' + str(device.get('deviceTypeIdentifier')))
if expected_ios and runtime != 'com.apple.CoreSimulator.SimRuntime.iOS-' + expected_ios.replace('.', '-'):
    sys.exit('ERROR: simulator runtime mismatch: ' + runtime)
print('Simulator: {} | {} | {} | {} | {}'.format(device.get('name'), device.get('deviceTypeIdentifier'), runtime, device.get('udid'), device.get('state')))
PY

mkdir -p "$output"
output="$(cd "$output" && pwd -P)"
main_shot="$output/01-main-app-launch-unverified.png"
system_shot="$output/02-system-keyboard-secure.png"
[ ! -e "$main_shot" ] && [ ! -e "$system_shot" ] || die "Refusing to overwrite existing screenshots in $output; choose a fresh output directory"

# A booted device returns an error from boot; bootstatus also verifies availability.
# First boots on CI machines are flaky (SpringBoard can stall); retry the boot once.
boot_attempt=0
while :; do
  boot_attempt=$((boot_attempt + 1))
  if ! xcrun simctl boot "$udid" > "$work/boot.log" 2>&1; then
    log 'Boot command did not start a device (it may already be booted); checking boot status.'
  fi
  if xcrun simctl bootstatus "$udid" -b; then
    break
  fi
  log "bootstatus failed on attempt $boot_attempt"
  if [ "$boot_attempt" -ge 2 ]; then
    cat "$work/boot.log" >&2
    die 'Simulator did not reach the booted state'
  fi
  log 'Retrying simulator boot once...'
  xcrun simctl shutdown "$udid" >>"$work/boot.log" 2>&1 || true
  sleep 5
done
arch="$(xcrun simctl spawn "$udid" uname -m | tr -d '\r\n')"
case "$arch" in arm64|x86_64) ;; *) die "Unsupported simulator architecture: $arch";; esac
app_archs="$(xcrun lipo -archs "$app/$app_executable")"
case " $app_archs " in *" $arch "*) ;; *) die "App lacks simulator architecture $arch (has: $app_archs)";; esac
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
[ -d "$sdk" ] || die 'iPhone Simulator SDK not found in selected Xcode'

# Build a tiny, separate, temporary UIKit app; do not touch the Xcode project.
host_app="$work/KeyboardScreenshotHost.app"
mkdir -p "$host_app"
cat > "$host_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Keyboard Screenshot Host</string>
  <key>CFBundleExecutable</key><string>KeyboardScreenshotHost</string>
  <key>CFBundleIdentifier</key><string>dev.hamster.simulatorscreenshot.keyboardhost</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>KeyboardScreenshotHost</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key><dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key><dict>
      <key>UIWindowSceneSessionRoleApplication</key><array><dict>
        <key>UISceneConfigurationName</key><string>Default Configuration</string>
        <key>UISceneDelegateClassName</key><string>KeyboardScreenshotHost.SceneDelegate</string>
      </dict></array>
    </dict>
  </dict>
</dict></plist>
PLIST
log "Building standalone keyboard host for $arch..."
xcrun --sdk iphonesimulator swiftc -swift-version 5 -parse-as-library \
  -module-name KeyboardScreenshotHost -sdk "$sdk" -target "$arch-apple-ios15.0-simulator" \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  "$script_dir/KeyboardScreenshotHost.swift" -o "$host_app/KeyboardScreenshotHost"
codesign --force --sign - --timestamp=none "$host_app"

launch() {
  local bundle="$1" result pid
  result="$(xcrun simctl launch --terminate-running-process "$udid" "$bundle")" || die "Launch failed: $bundle"
  log "$result" >&2
  pid="${result##* }"
  is_uint "$pid" || die "Unable to determine launch PID: $result"
  printf '%s\n' "$pid"
}
capture() {
  local destination="$1" temporary="$work/capture.png"
  [ ! -e "$destination" ] || die "Refusing to overwrite $destination"
  rm -f "$temporary"
  xcrun simctl io "$udid" screenshot --type=png "$temporary"
  [ -s "$temporary" ] || die 'simctl did not produce a nonempty screenshot'
  # A hard link makes the no-overwrite guarantee atomic even if another process races us.
  # The temporary screenshot is on another filesystem in some setups, so copy to a
  # private file in the output directory before the atomic link.
  local staging
  staging="$(mktemp "$output/.hamster-shot.XXXXXX")"
  if ! cp "$temporary" "$staging" || ! ln "$staging" "$destination"; then
    rm -f "$staging"
    die "Could not publish screenshot without overwriting: $destination"
  fi
  rm -f "$staging"
  log "Captured: $destination"
}

log "Installing and launching main app: $bundle_id"
xcrun simctl install "$udid" "$app"
main_pid="$(launch "$bundle_id")"
sleep "$main_wait"
kill -0 "$main_pid" 2>/dev/null || die 'Main app process exited before capture; inspect simulator logs'
capture "$main_shot"
log 'NOTE: main-app launch capture is unverified; review for loading screens, alerts and correct foreground UI.'

log 'Installing and launching the temporary secure-field keyboard host...'
xcrun simctl install "$udid" "$host_app"
host_data="$(xcrun simctl get_app_container "$udid" "$host_bundle_id" data)"
[ -d "$host_data" ] || die 'Could not locate keyboard host data container'
marker="$host_data/Documents/hamster-system-keyboard-ready"
rm -f "$marker"
host_pid="$(launch "$host_bundle_id")"
waited=0
while [ ! -f "$marker" ] && [ "$waited" -lt "$keyboard_timeout" ]; do
  kill -0 "$host_pid" 2>/dev/null || die 'Keyboard host exited before showing the keyboard'
  sleep 1
  waited=$((waited + 1))
done
[ -f "$marker" ] || die 'No keyboardDidShow readiness signal. Disable Connect Hardware Keyboard / enable the software keyboard in Simulator and retry with a fresh output directory.'
# Let the show animation and compositor settle, then ensure the signal remains valid.
sleep 1
kill -0 "$host_pid" 2>/dev/null && [ -f "$marker" ] || die 'Keyboard host lost readiness before capture'
capture "$system_shot"
if [ ! -f "$marker" ]; then
  rm -f "$system_shot"
  die 'Keyboard host lost readiness during capture; screenshot discarded'
fi
log 'NOTE: keyboardDidShow is a readiness signal, not a pixel/UI assertion; visually review the screenshot.'

if [ -n "$hook" ]; then
  log "Running extra capture hook: $hook"
  export SIMULATOR_UDID="$udid" APP_PATH="$app" APP_BUNDLE_ID="$bundle_id"
  export SCREENSHOT_OUTPUT_DIR="$output" MAIN_APP_SCREENSHOT="$main_shot" SYSTEM_KEYBOARD_SCREENSHOT="$system_shot"
  "$hook" || die 'Extra capture hook failed; existing captures are partial results'
else
  log 'SKIPPED: custom keyboard enabling, selection, behavior and screenshots (no extra hook).'
fi
log 'Finished. No UI test assertions have been run by this script.'
