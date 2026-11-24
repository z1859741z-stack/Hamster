#!/usr/bin/env bash
# Fetch a pinned, community-built librime static XCFramework plus its notices.
# Hashes identify the publisher's release bytes; they do not prove ABI or safety.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
base='https://github.com/ghostflyby/librime-xcframework/releases/download/1.17.0-pack.10.0.0'
local_dir=''
if [ "$#" -eq 2 ] && [ "$1" = '--source-dir' ]; then
  local_dir="$2"
elif [ "$#" -ne 0 ]; then
  echo 'Usage: prepare-rime-framework.sh [--source-dir DIR]' >&2; exit 2
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/hamster-rime.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
fetch() {
  local name="$1" sha="$2"
  if [ -n "$local_dir" ]; then
    cp "$local_dir/$name" "$work/$name"
  else
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 30 "$base/$name" -o "$work/$name"
  fi
  python3 - "$work/$name" "$sha" <<'PY'
import hashlib, sys
p, expected = sys.argv[1:]
h = hashlib.sha256()
with open(p, 'rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
if h.hexdigest() != expected:
    sys.exit('SHA-256 mismatch: ' + p)
print('Verified', p.rsplit('/', 1)[-1], h.hexdigest())
PY
}
fetch librime-static.xcframework.zip 9e9923112ee9cee9bb53c25b41e51a2d7ea2ab3d91f34c7c99682224a23718ac
fetch LICENSE.txt 2d022e82aab5aab07ac9dab2cd8d8f14c39a2d9d26478247ae1a1b5b8ff58609
fetch THIRD_PARTY_NOTICES.md 273f004fc58ece11b1935949db017c0c7fa41234b31f6149b901ddeef89f13b6
fetch third-party-notices.zip 74c7e7a0ac34671903d4aca4cc0fec0187daf3dc747d01bf782bb0be703b08f1

python3 - "$work" <<'PY'
import os, pathlib, plistlib, shutil, stat, sys, zipfile
work = pathlib.Path(sys.argv[1])

def unpack(name, destination, expected_root):
    destination.mkdir()
    seen = set()
    total = 0
    with zipfile.ZipFile(work / name) as z:
        for item in z.infolist():
            path = pathlib.PurePosixPath(item.filename)
            if (not path.parts or path.is_absolute() or '..' in path.parts or
                '\\' in item.filename or path.parts[0] != expected_root):
                sys.exit('Unsafe archive member: ' + item.filename)
            kind = (item.external_attr >> 16) & 0o170000
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                sys.exit('Unsupported archive member: ' + item.filename)
            if path in seen:
                sys.exit('Duplicate archive member: ' + item.filename)
            seen.add(path)
            total += item.file_size
            if total > 150 * 1024 * 1024:
                sys.exit('Archive expands beyond size limit')
            target = destination.joinpath(*path.parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with z.open(item) as src, open(target, 'xb') as dst:
                    shutil.copyfileobj(src, dst)

unpack('librime-static.xcframework.zip', work / 'framework', 'librime-static.xcframework')
unpack('third-party-notices.zip', work / 'notices', 'third-party-notices')
xc = work / 'framework' / 'librime-static.xcframework'
with (xc / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
libs = info.get('AvailableLibraries', [])
for platform, variant, arch in [('ios', None, 'arm64'), ('ios', 'simulator', 'arm64'), ('ios', 'simulator', 'x86_64'), ('macos', None, 'arm64')]:
    matches = [x for x in libs if x.get('SupportedPlatform') == platform and x.get('SupportedPlatformVariant') == variant and arch in x.get('SupportedArchitectures', [])]
    if len(matches) != 1:
        sys.exit('Missing or ambiguous XCFramework slice: ' + str((platform, variant, arch)))
    entry = matches[0]
    identifier = pathlib.PurePosixPath(entry.get('LibraryIdentifier', ''))
    library = pathlib.PurePosixPath(entry.get('LibraryPath', ''))
    if not identifier.parts or not library.parts or identifier.is_absolute() or library.is_absolute() or '..' in identifier.parts or '..' in library.parts:
        sys.exit('Invalid XCFramework path')
    binary = xc.joinpath(*identifier.parts, *library.parts)
    if not binary.is_file() or binary.stat().st_size == 0:
        sys.exit('Missing XCFramework binary: ' + str(binary))
    print('Found metadata slice:', platform, variant or 'device', arch)
if not any((work / 'notices' / 'third-party-notices').rglob('*.txt')):
    sys.exit('Missing third-party license texts')
PY
# On Mac, also check the actual archive architecture with Apple's lipo.
if [ "$(uname -s)" = Darwin ]; then
  xcrun lipo "$work/framework/librime-static.xcframework/ios-arm64/librime.a" -verify_arch arm64
  xcrun lipo "$work/framework/librime-static.xcframework/ios-arm64_x86_64-simulator/librime.a" -verify_arch arm64 x86_64
fi
mkdir -p "$root/Frameworks"
rm -rf "$root/Frameworks/librime-static.xcframework" "$root/Frameworks/CI-licenses"
cp -R "$work/framework/librime-static.xcframework" "$root/Frameworks/librime-static.xcframework"
mkdir -p "$root/Frameworks/CI-licenses/librime-xcframework"
cp "$work/LICENSE.txt" "$work/THIRD_PARTY_NOTICES.md" "$root/Frameworks/CI-licenses/librime-xcframework/"
cp -R "$work/notices/third-party-notices" "$root/Frameworks/CI-licenses/librime-xcframework/"
echo 'Pinned framework and license notices prepared. Xcode linkage and runtime behavior still require verification.'
