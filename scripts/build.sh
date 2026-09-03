#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-${PROJECT_DIR}/dist}"

if [[ -z "${OUTPUT_DIR}" || "${OUTPUT_DIR}" == "/" ]]; then
  print -u2 "拒绝使用不安全的输出目录"
  exit 2
fi

cd "${PROJECT_DIR}"
export MACOSX_DEPLOYMENT_TARGET=14.0

print "[1/5] 编译并运行安全策略测试"
swift run ClamshellGuardianPolicyTests

print "[2/5] 编译 Release 应用与 Helper"
swift build -c release --arch arm64
RELEASE_BIN="$(swift build -c release --arch arm64 --show-bin-path)"

mkdir -p "${OUTPUT_DIR}"
APP_PATH="${OUTPUT_DIR}/合盖守护.app"
if [[ -e "${APP_PATH}" ]]; then
  /bin/rm -rf "${APP_PATH}"
fi
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"
install -m 0755 "${RELEASE_BIN}/ClamshellGuardianApp" "${APP_PATH}/Contents/MacOS/ClamshellGuardian"
install -m 0755 "${RELEASE_BIN}/ClamshellGuardianHelper" "${APP_PATH}/Contents/Resources/ClamshellGuardianHelper"
install -m 0644 "${PROJECT_DIR}/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

print "[3/5] 生成原生应用图标"
ICON_WORK="$(mktemp -d /tmp/clamshellguardian-icon.XXXXXX)"
trap '/bin/rm -rf "${ICON_WORK}"' EXIT
swift "${PROJECT_DIR}/scripts/IconGenerator.swift" "${ICON_WORK}/base.png"
mkdir -p "${ICON_WORK}/AppIcon.iconset"
for specification in \
  "16 icon_16x16.png" "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  pixels="${specification%% *}"
  filename="${specification#* }"
  sips -z "${pixels}" "${pixels}" "${ICON_WORK}/base.png" \
    --out "${ICON_WORK}/AppIcon.iconset/${filename}" >/dev/null
done
iconutil -c icns "${ICON_WORK}/AppIcon.iconset" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"

print "[4/5] Ad-hoc 签名"
codesign --force --sign - --timestamp=none "${APP_PATH}/Contents/Resources/ClamshellGuardianHelper"
codesign --force --deep --sign - --timestamp=none "${APP_PATH}"

print "[5/5] 验证包结构与签名"
plutil -lint "${APP_PATH}/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
file "${APP_PATH}/Contents/MacOS/ClamshellGuardian" "${APP_PATH}/Contents/Resources/ClamshellGuardianHelper"
if ! file "${APP_PATH}/Contents/MacOS/ClamshellGuardian" | /usr/bin/grep -q "arm64"; then
  print -u2 "应用主程序不是 arm64，停止发布"
  exit 1
fi
print "完成：${APP_PATH}"
