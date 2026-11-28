#!/bin/bash
# 豆包风格对照截图（仅模拟器、仅 CI 用；不改 Xcode 工程、不改签名设置）。
# 1) 用 Debug 配置为 iOS 模拟器编译 Hamster（命令行关签名，之后用 ad-hoc 签名 + 原 entitlements 文件，只为能在模拟器里跑）
# 2) 编一个独立的非安全输入框宿主（ci_scripts/DoubaoKeyboardHost.swift）
# 3) 在模拟器里把 Hamster 键盘设为键盘列表第一项，重启模拟器，拉起宿主，截浅色/深色两张
# 截图只是给人看的对照，不是 UI 测试断言。任何一步失败都尽量继续，最后把日志和已有截图都留在 .ci/shots。
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/.ci/shots"
mkdir -p "$out"
log() { echo "[doubao-shots] $*"; }

keyboard_bundle_id="dev.fuxiao.app.Hamster.HamsterKeyboard"
app_bundle_id="dev.fuxiao.app.Hamster"
host_bundle_id="dev.hamster.doubao.keyboardhost"

# ---- 选设备：优先 iPhone 16 Pro Max，其次任意 Pro Max，再次任意 iPhone ----
xcrun simctl list devices available --json > "$out/devices.json"
udid="$(python3 - "$out/devices.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["devices"]
cands = []
for runtime, devs in d.items():
    if "iOS" not in runtime:
        continue
    for dev in devs:
        if dev.get("isAvailable"):
            cands.append((runtime, dev["name"], dev["udid"]))
def pick(pred):
    m = [c for c in cands if pred(c[1])]
    m.sort(key=lambda c: c[0], reverse=True)
    return m[0] if m else None
c = pick(lambda n: n == "iPhone 16 Pro Max") or pick(lambda n: "Pro Max" in n) or pick(lambda n: n.startswith("iPhone"))
print(c[2] if c else "")
sys.stderr.write("picked: %s\n" % (c,))
PY
)"
[ -n "$udid" ] || { log "no simulator found"; exit 0; }
log "simulator udid $udid"

# ---- 编译模拟器版 App ----
dd="$root/.ci/SimDerivedData"
log "building Hamster for simulator..."
xcodebuild build \
  -project "$root/Hamster.xcodeproj" -scheme Hamster -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$dd" -clonedSourcePackagesDirPath "$root/.ci/SourcePackages" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > "$out/xcodebuild-sim.log" 2>&1
status=$?
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$out/xcodebuild-sim.log" | tail -n 40
if [ $status -ne 0 ]; then log "simulator build failed ($status)"; exit 0; fi
app="$dd/Build/Products/Debug-iphonesimulator/Hamster.app"
[ -d "$app" ] || { log "Hamster.app not found"; exit 0; }

# ad-hoc 签名（模拟器在 Apple 芯片上要求有签名）：先内层 framework/dylib，再扩展，最后主 App。
find "$app" \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' f; do
  codesign --force --sign - --timestamp=none "$f" >> "$out/codesign.log" 2>&1
done
for ext in "$app"/PlugIns/*.appex; do
  [ -d "$ext" ] || continue
  name="$(basename "$ext" .appex)"
  ent="$root/$name/$name.entitlements"
  if [ -f "$ent" ]; then
    codesign --force --sign - --timestamp=none --entitlements "$ent" "$ext" >> "$out/codesign.log" 2>&1
  else
    codesign --force --sign - --timestamp=none "$ext" >> "$out/codesign.log" 2>&1
  fi
done
codesign --force --sign - --timestamp=none --entitlements "$root/Hamster/HamsterDebug.entitlements" "$app" >> "$out/codesign.log" 2>&1 \
  || codesign --force --sign - --timestamp=none "$app" >> "$out/codesign.log" 2>&1

# ---- 宿主 ----
work="$(mktemp -d)"
host_app="$work/DoubaoKeyboardHost.app"
mkdir -p "$host_app"
cat > "$host_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>Doubao Host</string>
  <key>CFBundleExecutable</key><string>DoubaoKeyboardHost</string>
  <key>CFBundleIdentifier</key><string>dev.hamster.doubao.keyboardhost</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>DoubaoKeyboardHost</string>
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
        <key>UISceneDelegateClassName</key><string>DoubaoKeyboardHost.SceneDelegate</string>
      </dict></array>
    </dict>
  </dict>
</dict></plist>
PLIST

# ---- 启动模拟器、装 App ----
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false || true
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b || true
arch="$(xcrun simctl spawn "$udid" uname -m | tr -d '\r\n')"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -swift-version 5 -parse-as-library \
  -module-name DoubaoKeyboardHost -sdk "$sdk" -target "$arch-apple-ios15.0-simulator" \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  "$root/ci_scripts/DoubaoKeyboardHost.swift" -o "$host_app/DoubaoKeyboardHost" > "$out/host-build.log" 2>&1 \
  || { log "host build failed"; cat "$out/host-build.log"; exit 0; }
codesign --force --sign - --timestamp=none "$host_app"

xcrun simctl install "$udid" "$app" || { log "install Hamster failed"; exit 0; }
xcrun simctl install "$udid" "$host_app" || { log "install host failed"; exit 0; }

# 主 App 先跑一次，让它把配置和输入方案部署进共享目录（失败也不要紧，键盘外观不依赖 RIME 部署）。
xcrun simctl launch "$udid" "$app_bundle_id" || true
sleep 20
xcrun simctl io "$udid" screenshot --type=png "$out/00-main-app.png" || true
xcrun simctl terminate "$udid" "$app_bundle_id" || true

# ---- 启用 Hamster 键盘并设为第一项 ----
xcrun simctl spawn "$udid" defaults write -g AppleKeyboards -array "$keyboard_bundle_id" "zh_Hans-Pinyin@sw=Pinyin10-Simplified;hw=Automatic" "en_US@sw=QWERTY;hw=Automatic" || true
xcrun simctl spawn "$udid" defaults write -g AppleKeyboardsExpanded -int 1 || true
xcrun simctl spawn "$udid" defaults write com.apple.Preferences KeyboardsCurrentAndNext -array "$keyboard_bundle_id" || true
xcrun simctl spawn "$udid" defaults read -g AppleKeyboards > "$out/apple-keyboards.txt" 2>&1 || true
xcrun simctl shutdown "$udid" || true
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b || true
sleep 5

shot() {
  local name="$1" appearance="$2" returnKey="$3"
  xcrun simctl ui "$udid" appearance "$appearance" || true
  sleep 2
  xcrun simctl launch --terminate-running-process "$udid" "$host_bundle_id" -returnKeyType "$returnKey" || true
  sleep 14
  xcrun simctl io "$udid" screenshot --type=png "$out/$name" || true
}

shot "01-light-search.png" light search
shot "02-dark-default.png" dark default
shot "03-light-send.png" light send
xcrun simctl ui "$udid" appearance light || true

# 键盘扩展的日志（排查键盘没出来时用）
xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate 'process CONTAINS "HamsterKeyboard" OR subsystem CONTAINS "Hamster"' > "$out/keyboard-log.txt" 2>&1 || true
ls -la "$out"
exit 0
