#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist")"
ARCHIVE_NAME="ClamshellGuardian-${VERSION}-arm64-beta.zip"

"${SCRIPT_DIR}/build.sh" "${DIST_DIR}"

if [[ -e "${DIST_DIR}/${ARCHIVE_NAME}" ]]; then
  /bin/rm -f "${DIST_DIR}/${ARCHIVE_NAME}"
fi
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  "${DIST_DIR}/合盖守护.app" \
  "${DIST_DIR}/${ARCHIVE_NAME}"

(
  cd "${DIST_DIR}"
  /usr/bin/shasum -a 256 "${ARCHIVE_NAME}" > SHA256SUMS.txt
)

print "发布包：${DIST_DIR}/${ARCHIVE_NAME}"
print "校验值：${DIST_DIR}/SHA256SUMS.txt"
