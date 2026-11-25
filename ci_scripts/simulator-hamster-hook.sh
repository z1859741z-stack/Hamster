#!/usr/bin/env bash
# Hamster simulator comparison shots — extra hook for ci_scripts/simulator-screenshots.sh.
# Runs after the default main-app + system-keyboard captures.
# Best-effort: every step is guarded, failures are logged, nothing here is fatal.
# Always exits 0 and writes hook-result.txt; the screenshots + logs are the deliverables.
set -u

UDID="${SIMULATOR_UDID:?missing SIMULATOR_UDID}"
OUT="${SCREENSHOT_OUTPUT_DIR:?missing SCREENSHOT_OUTPUT_DIR}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:?missing APP_BUNDLE_ID}"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd -P)"
EXT_BUNDLE_ID="dev.fuxiao.app.Hamster.HamsterKeyboard"
PLAIN_HOST_BUNDLE_ID="dev.hamster.simulatorscreenshot.plainkeyboardhost"
PLAIN_HOST_SRC="$HOOK_DIR/KeyboardScreenshotHostPlain.swift"
LOG="$OUT/hook.log"

log() { printf '[hook %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

shot() {
  local name="$1"
  rm -f "$OUT/$name"
  if xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name" >>"$LOG" 2>&1 && [ -s "$OUT/$name" ]; then
    log "shot OK: $name"
  else
    log "shot FAILED: $name"
  fi
}

wait_marker() {
  local container="$1" file="$2" timeout="${3:-60}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$container/$file" ]; then
      log "marker present: $file -> $(cat "$container/$file" 2>/dev/null | tr '\n' ' ')"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  log "marker TIMEOUT after ${timeout}s: $file (container $container)"
  return 1
}

launch_plain_host() {
  xcrun simctl launch --terminate-running-process "$UDID" "$PLAIN_HOST_BUNDLE_ID" >>"$LOG" 2>&1 || log "plain host launch FAILED"
}

# ---------------------------------------------------------------- 1. state
log "=== hamster hook start; sim $UDID; app $APP_BUNDLE_ID ==="
xcrun simctl list devices 2>/dev/null | grep -i "$UDID" | tee -a "$LOG" || true

# ------------------------------------------------- 2. enable Hamster keyboard
log "--- keyboard prefs before ---"
xcrun simctl spawn "$UDID" defaults read com.apple.keyboard >>"$LOG" 2>&1 || log "(com.apple.keyboard domain not present yet)"
log "--- enabling Hamster as the ONLY keyboard ---"
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard AppleKeyboards -array "$EXT_BUNDLE_ID" >>"$LOG" 2>&1 || log "defaults write AppleKeyboards FAILED"
xcrun simctl spawn "$UDID" defaults read com.apple.keyboard AppleKeyboards >>"$LOG" 2>&1 || log "read-back of AppleKeyboards FAILED"

# ------------------------------------------- 3. deployment check (pre-reboot)
GROUP_DIR=""
RIME_BUILD_DIR=""
find_group_dir() {
  local out
  out="$(xcrun simctl get_app_container "$UDID" "$APP_BUNDLE_ID" groups 2>/dev/null | head -n 1)"
  if [ -d "$out" ]; then
    GROUP_DIR="$out"
  else
    GROUP_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup"
  fi
  # Locate the actual Rime build dir anywhere under the group tree.
  RIME_BUILD_DIR="$(find "$GROUP_DIR" -type d -name build -path '*Rime*' 2>/dev/null | head -n 1)"
  [ -n "$RIME_BUILD_DIR" ] && GROUP_DIR="$(dirname "$(dirname "$RIME_BUILD_DIR")")"
  [ -d "$GROUP_DIR" ]
}
count_build_bins() {
  [ -n "$RIME_BUILD_DIR" ] && [ -d "$RIME_BUILD_DIR" ] && find "$RIME_BUILD_DIR" -name '*.bin' 2>/dev/null | wc -l | tr -d ' ' || echo 0
}
if find_group_dir; then
  log "group dir: $GROUP_DIR"
else
  log "group dir NOT FOUND yet (get_app_container output above)"
fi
log "build .bin count before reboot: $(count_build_bins)"

# ------------------------------------------------------- 4. reboot the sim
# Prefs (keyboard list + hardware-keyboard off) are picked up cleanly after a reboot.
log "--- rebooting simulator ---"
xcrun simctl shutdown "$UDID" >>"$LOG" 2>&1 || log "shutdown returned non-zero (may already be down)"
xcrun simctl boot "$UDID" >>"$LOG" 2>&1 || log "boot returned non-zero (may already be booted)"
xcrun simctl bootstatus "$UDID" -b >>"$LOG" 2>&1 || log "bootstatus FAILED"

# ---------------------------------- 5. deployment: relaunch main app, poll
log "--- relaunching main app so first-run deployment can finish ---"
xcrun simctl launch --terminate-running-process "$UDID" "$APP_BUNDLE_ID" >>"$LOG" 2>&1 || log "main app relaunch FAILED"
if find_group_dir; then
  log "group dir: $GROUP_DIR"
  waited=0
  while [ "$waited" -lt 120 ]; do
    find_group_dir || true
    n="$(count_build_bins)"
    if [ "$n" -gt 0 ]; then
      log "deployment done: $n .bin files in Rime/build after ${waited}s"
      break
    fi
    sleep 10
    waited=$((waited + 10))
  done
  [ "$(count_build_bins)" -eq 0 ] && log "WARNING: no .bin in Rime/build after 120s; keyboard may show without candidates"
  find "$GROUP_DIR" \( -name 'installation.yaml' -o -name 'default.custom.yaml' -o -name 'hamster.plist' \) 2>/dev/null | tee -a "$LOG" || true
else
  log "WARNING: group dir still not found; cannot verify deployment"
fi

# ---------------------------------- 6. turn on the popup-latency debug toggle
HAMSTER_PLIST="$(find "${GROUP_DIR:-/nonexistent}" -name 'hamster.plist' 2>/dev/null | head -n 1)"
if [ -n "$HAMSTER_PLIST" ] && [ -f "$HAMSTER_PLIST" ]; then
  log "hamster.plist: $HAMSTER_PLIST"
  python3 - "$HAMSTER_PLIST" >>"$LOG" 2>&1 <<'PY' || log "showPopupLatency edit FAILED"
import plistlib, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    data = plistlib.load(f)
print('top-level keys:', sorted(data.keys()))
kb = data.get('keyboard')
print('keyboard section present:', isinstance(kb, dict))
if isinstance(kb, dict):
    kb['showPopupLatency'] = True
    with open(p, 'wb') as f:
        plistlib.dump(data, f)
    print('showPopupLatency set to True')
else:
    print('no keyboard dict; toggle NOT set')
PY
else
  log "hamster.plist NOT found under group dir; popup-latency toast unavailable (toggle cannot be switched on)"
fi

# ------------------------------------------- 7. build + install plain host
log "--- building plain keyboard host ---"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(xcrun simctl spawn "$UDID" uname -m | tr -d '\r\n')"
PLAIN_WORK="$(mktemp -d "${TMPDIR:-/tmp}/hamster-plain-host.XXXXXX")"
PLAIN_APP="$PLAIN_WORK/PlainKeyboardHost.app"
mkdir -p "$PLAIN_APP"
cat > "$PLAIN_APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Plain Keyboard Host</string>
  <key>CFBundleExecutable</key><string>PlainKeyboardHost</string>
  <key>CFBundleIdentifier</key><string>dev.hamster.simulatorscreenshot.plainkeyboardhost</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>PlainKeyboardHost</string>
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
        <key>UISceneDelegateClassName</key><string>PlainKeyboardHost.SceneDelegate</string>
      </dict></array>
    </dict>
  </dict>
</dict></plist>
PLIST
# Swift module name must match the file's @main class namespace (no module prefix used).
xcrun --sdk iphonesimulator swiftc -swift-version 5 -parse-as-library \
  -module-name PlainKeyboardHost -sdk "$SDK" -target "$ARCH-apple-ios15.0-simulator" \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  "$PLAIN_HOST_SRC" -o "$PLAIN_APP/PlainKeyboardHost" >>"$LOG" 2>&1 || log "plain host COMPILE FAILED"
codesign --force --sign - --timestamp=none "$PLAIN_APP" >>"$LOG" 2>&1 || log "plain host codesign FAILED"
xcrun simctl install "$UDID" "$PLAIN_APP" >>"$LOG" 2>&1 || log "plain host INSTALL FAILED"
PLAIN_DATA="$(xcrun simctl get_app_container "$UDID" "$PLAIN_HOST_BUNDLE_ID" data 2>/dev/null)"
log "plain host data container: $PLAIN_DATA"

# ------------------------------------------------ 8. light: Hamster keyboard
log "--- launching plain host (light) ---"
launch_plain_host
sleep 1
wait_marker "$PLAIN_DATA" "Documents/hamster-plain-keyboard-ready" 60 || true
sleep 1
shot "03-hamster-light.png"

# ------------------------------------------------ 9. memory while keyboard is up
log "--- keyboard extension process memory ---"
{
  echo "ps matches for HamsterKeyboard:"
  ps aux | grep -i hamsterkeyboard | grep -v grep || echo "(none)"
  KPID="$(pgrep -f HamsterKeyboard | head -n 1)"
  if [ -n "$KPID" ]; then
    echo "HamsterKeyboard pid: $KPID"
    for i in 1 2 3; do
      echo "--- sample $i ---"
      if command -v footprint >/dev/null 2>&1; then
        footprint -p "$KPID" 2>&1 | tail -n 5
      else
        echo "(footprint tool not available)"
      fi
      ps -o pid,rss,vsz,command -p "$KPID" 2>&1
      sleep 5
    done
  else
    echo "HamsterKeyboard process NOT running (keyboard did not load or already dismissed)"
  fi
} | tee -a "$LOG" > "$OUT/memory.txt"
log "memory samples saved to memory.txt"

# --------------------------- 10. on-screen taps (Simulator window clicks)
# Device points (440x956 iPhone 16 Pro Max). Keyboard top ~658pt; rows 56pt.
# 123 key (34,894); letters: n(332,838) i(330,726) h(264,782) a(24,782) o(374,726).
sim_click() {
  local dx="$1" dy="$2"
  osascript - "$dx" "$dy" >>"$LOG" 2>&1 <<'APPLESCRIPT' || log "osascript click FAILED for device point ($dx,$dy)"
on run argv
  set dx to item 1 of argv as number
  set dy to item 2 of argv as number
  tell application "Simulator" to activate
  delay 0.5
  tell application "System Events"
    tell process "Simulator"
      set wb to bounds of front window
    end tell
  end tell
  set winW to (item 3 of wb) - (item 1 of wb)
  -- Window chrome estimate: title bar 28pt, side bezels 8pt each (scaled).
  set scaleFactor to winW / 456.0
  set sx to (item 1 of wb) + (8 * scaleFactor) + (dx * scaleFactor)
  set sy to (item 2 of wb) + (28 * scaleFactor) + (dy * scaleFactor)
  tell application "System Events" to click at {sx as integer, sy as integer}
end run
APPLESCRIPT
}
log "--- opening Simulator window for on-screen taps ---"
open -a Simulator >>"$LOG" 2>&1 || log "open -a Simulator FAILED"
sleep 3
log "--- tapping 123 key ---"
sim_click 34 894
sleep 1
shot "04-hamster-numberlayer.png"
log "--- tapping ABC key (back to letters) ---"
sim_click 34 894
sleep 1
log "--- typing nihao by tapping keys ---"
sim_click 332 838
sleep 0.3
sim_click 330 726
sleep 0.3
sim_click 264 782
sleep 0.3
sim_click 24 782
sleep 0.3
sim_click 374 726
sleep 1
shot "05-hamster-nihao-click.png"

# --------------------------- 11. hardware-keyboard keystroke attempt
log "--- keystroke attempt: hardware keyboard on + Cmd+K + type nihao ---"
launch_plain_host
sleep 1
wait_marker "$PLAIN_DATA" "Documents/hamster-plain-keyboard-ready" 60 || true
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool true >>"$LOG" 2>&1 || true
osascript -e 'tell application "Simulator" to quit' >>"$LOG" 2>&1 || true
sleep 2
open -a Simulator >>"$LOG" 2>&1 || log "reopen Simulator FAILED"
sleep 3
osascript >>"$LOG" 2>&1 <<'APPLESCRIPT' || log "keystroke attempt FAILED"
tell application "Simulator" to activate
delay 0.5
tell application "System Events"
  keystroke "k" using command down
  delay 1
  keystroke "nihao"
end tell
APPLESCRIPT
sleep 1
shot "05b-hamster-nihao-keys.png"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false >>"$LOG" 2>&1 || true

# ------------------------------------------------ 12. dark appearance
log "--- switching to dark appearance ---"
xcrun simctl ui "$UDID" appearance dark >>"$LOG" 2>&1 || log "appearance dark FAILED"
sleep 2
launch_plain_host
sleep 1
wait_marker "$PLAIN_DATA" "Documents/hamster-plain-keyboard-ready" 60 || true
sleep 1
shot "06-hamster-dark.png"
xcrun simctl ui "$UDID" appearance light >>"$LOG" 2>&1 || true

# ------------------------------------------------ 13. summary
{
  echo "=== hamster hook result ==="
  echo "simulator: $UDID"
  echo "files in $OUT:"
  ls -la "$OUT"
  echo "--- marker (plain host) ---"
  [ -n "${PLAIN_DATA:-}" ] && cat "$PLAIN_DATA/Documents/hamster-plain-keyboard-ready" 2>/dev/null || echo "(no marker)"
  echo "--- memory.txt ---"
  cat "$OUT/memory.txt" 2>/dev/null || echo "(no memory.txt)"
} | tee -a "$LOG" > "$OUT/hook-result.txt"
log "=== hamster hook done (exit 0 by design) ==="
exit 0
