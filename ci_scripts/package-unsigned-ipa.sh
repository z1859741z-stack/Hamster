#!/usr/bin/env bash
# Package an already-built, genuinely unsigned iPhoneOS app. Never signs,
# removes signatures, or modifies the input app.
set -euo pipefail
usage() {
  cat <<'USAGE'
Usage: package-unsigned-ipa.sh --app PATH/Hamster.app --output PATH/Hamster.ipa
                               [--license PATH] [--notices DIRECTORY]

Requires an iPhoneOS arm64 build with HamsterKeyboard.appex only. Signed/ad-hoc-signed code, provisioning profiles,
simulator binaries and broken/escaping symlinks are rejected. The project's
LICENSE.txt is copied into the app. Optional third-party notices are copied
without modification; by default Frameworks/CI-licenses is used if present.
An unsigned IPA cannot be installed without subsequent proper signing.
USAGE
}
die() { echo "package-unsigned-ipa: $*" >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
app= output= license="$root/LICENSE.txt" notices=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app|--output|--license|--notices)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in
        --app) [ -z "$app" ] || die 'duplicate --app'; app=$2 ;;
        --output) [ -z "$output" ] || die 'duplicate --output'; output=$2 ;;
        --license) license=$2 ;;
        --notices) notices=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$app" ] && [ -n "$output" ] || die '--app and --output are required'
[ -d "$app" ] && [ ! -L "$app" ] || die "app directory not found or is a symlink: $app"
[ "$(basename "$app")" = 'Hamster.app' ] || die 'app must be named Hamster.app'
[ -f "$license" ] || die "license not found: $license"
case "$output" in *.ipa) ;; *) die 'output must end in .ipa' ;; esac
[ ! -L "$output" ] || die 'output may not be a symlink'
[ -z "$notices" ] || [ -d "$notices" ] || die "notices directory not found: $notices"
if [ -z "$notices" ] && [ -d "$root/Frameworks/CI-licenses" ]; then notices="$root/Frameworks/CI-licenses"; fi
for cmd in python3 zip unzip; do command -v "$cmd" >/dev/null || die "missing command: $cmd"; done
app="$(cd "$app" && pwd -P)"
mkdir -p "$(dirname "$output")"
outdir="$(cd "$(dirname "$output")" && pwd -P)"
output="$outdir/$(basename "$output")"
case "$output" in "$app"/*) die 'output cannot be inside the source app' ;; esac
work="$(mktemp -d "$outdir/.hamster-ipa.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/Payload"
cp -R "$app" "$work/Payload/Hamster.app"
# Refuse to overwrite files that may be part of the app.
dst="$work/Payload/Hamster.app"
[ ! -e "$dst/LICENSE-Hamster.txt" ] && [ ! -L "$dst/LICENSE-Hamster.txt" ] || die 'LICENSE-Hamster.txt already exists in app'
cp "$license" "$dst/LICENSE-Hamster.txt"
if [ -n "$notices" ]; then
  [ ! -e "$dst/ThirdPartyNotices" ] && [ ! -L "$dst/ThirdPartyNotices" ] || die 'ThirdPartyNotices already exists in app'
  cp -R "$notices" "$dst/ThirdPartyNotices"
fi
python3 - "$dst" <<'PY'
import os, pathlib, plistlib, struct, sys
root=pathlib.Path(sys.argv[1]).resolve()
def fail(msg): sys.exit('package-unsigned-ipa: '+msg)
def read_plist(bundle):
    try:
        with (bundle/'Info.plist').open('rb') as f: return plistlib.load(f)
    except Exception as e: fail('invalid Info.plist in '+str(bundle)+': '+str(e))
def executable(bundle, info):
    name=info.get('CFBundleExecutable')
    if not isinstance(name,str) or not name or '/' in name or name in ('.','..'):
        fail('invalid CFBundleExecutable in '+str(bundle))
    p=bundle/name
    if not p.is_file() or p.is_symlink(): fail('missing executable: '+str(p))
    return p
app=read_plist(root)
if app.get('CFBundlePackageType') != 'APPL': fail('app is not an APPL bundle')
if 'iPhoneOS' not in app.get('CFBundleSupportedPlatforms', []): fail('app is not built for iPhoneOS')
app_id=app.get('CFBundleIdentifier')
if not isinstance(app_id,str) or not app_id: fail('app bundle identifier missing')
required=[executable(root,app)]
for name in ('HamsterKeyboard',):
    bundle=root/'PlugIns'/(name+'.appex')
    if not bundle.is_dir() or bundle.is_symlink(): fail('missing keyboard extension: '+str(bundle))
    info=read_plist(bundle)
    if info.get('CFBundlePackageType') != 'XPC!': fail('not an app extension: '+str(bundle))
    if info.get('NSExtension',{}).get('NSExtensionPointIdentifier') != 'com.apple.keyboard-service': fail('not a keyboard extension: '+str(bundle))
    if not isinstance(info.get('CFBundleIdentifier'),str) or not info['CFBundleIdentifier'].startswith(app_id+'.'):
        fail('extension bundle identifier is not nested under app identifier: '+str(bundle))
    required.append(executable(bundle,info))
# Mach-O parsing: reject LC_CODE_SIGNATURE even for ad-hoc signatures; also
# reject non-iOS/simulator slices. Recognize thin and fat 32/64 bit, either endian.
thin={b'\xce\xfa\xed\xfe':('<',False),b'\xcf\xfa\xed\xfe':('<',True),
      b'\xfe\xed\xfa\xce':('>',False),b'\xfe\xed\xfa\xcf':('>',True)}
fat={b'\xca\xfe\xba\xbe':('>',False),b'\xbe\xba\xfe\xca':('<',False),
     b'\xca\xfe\xba\xbf':('>',True),b'\xbf\xba\xfe\xca':('<',True)}
def parse(data, path):
    if len(data)<4: return False
    slices=[]
    if data[:4] in thin: slices=[(0,len(data))]
    elif data[:4] in fat:
        endian,wide=fat[data[:4]]
        if len(data)<8: fail('truncated fat binary: '+str(path))
        count=struct.unpack_from(endian+'I',data,4)[0]; stride=32 if wide else 20
        if count<1 or count>64 or 8+count*stride>len(data): fail('invalid fat binary: '+str(path))
        for i in range(count):
            pos=8+i*stride
            off,size=struct.unpack_from(endian+('QQ' if wide else 'II'),data,pos+8)
            if size<28 or off+size>len(data): fail('invalid fat slice: '+str(path))
            slices.append((off,size))
    else: return False
    for off,size in slices:
        magic=data[off:off+4]
        if magic not in thin: fail('invalid Mach-O slice: '+str(path))
        endian,wide=thin[magic]; header=32 if wide else 28
        if size<header: fail('truncated Mach-O header: '+str(path))
        cpu=struct.unpack_from(endian+'I',data,off+4)[0]
        ncmd,cmdbytes=struct.unpack_from(endian+'II',data,off+16)
        if ncmd>100000 or header+cmdbytes>size: fail('invalid Mach-O commands: '+str(path))
        pos=off+header; end=pos+cmdbytes; platform=None
        for _ in range(ncmd):
            if pos+8>end: fail('truncated load command: '+str(path))
            cmd,length=struct.unpack_from(endian+'II',data,pos)
            if length<8 or pos+length>end: fail('invalid load command: '+str(path))
            if cmd == 0x1d: fail('Mach-O has a code signature (including ad-hoc): '+str(path))
            if cmd == 0x32:
                if length<24: fail('invalid LC_BUILD_VERSION: '+str(path))
                platform=struct.unpack_from(endian+'I',data,pos+8)[0]
                if platform != 2: fail('Mach-O is not an iOS device binary: '+str(path))
            elif cmd == 0x25: platform=2 # legacy LC_VERSION_MIN_IPHONEOS
            elif cmd in (0x24,0x2f,0x30): fail('Mach-O targets a different Apple platform: '+str(path))
            pos+=length
        if pos != end or platform != 2: fail('missing or invalid iOS platform load command: '+str(path))
        if cpu != 0x0100000c: fail('Mach-O slice is not arm64 iOS device: '+str(path))
    return True
found=set()
for base,dirs,files in os.walk(root,followlinks=False):
    for name in dirs+files:
        p=pathlib.Path(base)/name
        if name == '_CodeSignature' or name in ('embedded.mobileprovision','embedded.provisionprofile'):
            fail('signature or provisioning material found: '+str(p))
        if p.is_symlink():
            if os.path.isabs(os.readlink(p)): fail('absolute symlink: '+str(p))
            try: target=p.resolve(strict=True)
            except (FileNotFoundError,RuntimeError): fail('broken/cyclic symlink: '+str(p))
            if target != root and root not in target.parents: fail('symlink escapes app: '+str(p))
    for name in files:
        p=pathlib.Path(base)/name
        if p.is_symlink() or not p.is_file(): continue
        with p.open('rb') as f:
            magic=f.read(4)
            if magic not in thin and magic not in fat: continue
            f.seek(0); data=f.read()
        if parse(data,p): found.add(p)
for p in required:
    if p not in found: fail('bundle executable is not a valid unsigned arm64 iOS Mach-O: '+str(p))
print('Verified unsigned arm64 iOS app and both keyboard extensions.')
PY
(
  cd "$work"
  zip -qry "$work/unsigned.ipa" Payload
)
unzip -tq "$work/unsigned.ipa" >/dev/null || die 'IPA integrity check failed'
mv -f "$work/unsigned.ipa" "$output"
echo "Created unsigned IPA: $output"
