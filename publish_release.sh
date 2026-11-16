#!/usr/bin/env bash
set -e

APK_PATH="$1"
VERSION_NAME="${2:-1.0.0}"
VERSION_CODE="${3:-1}"

if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
    echo "Usage: $0 <path-to-apk> [versionName] [versionCode]"
    exit 1
fi

RELEASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APK_NAME="$(basename "$APK_PATH")"
SHA256="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"

GITHUB_APK_URL="https://github.com/shanghai-noodle/androidTV-photo-slideshow-releases/releases/latest/download/${APK_NAME}"
GITEE_APK_URL="https://gitee.com/shanghai-noodle/androidTV-photo-slideshow-releases/releases/download/v1.0.0/${APK_NAME}"

# 1. Upload to GitHub Releases (fast, synchronous)
GH_BIN="$(command -v gh || echo /opt/homebrew/bin/gh)"
if [ -x "$GH_BIN" ]; then
    echo "☁️  [GitHub] Uploading ${APK_NAME} to shanghai-noodle/androidTV-photo-slideshow-releases (v1.0.0)..."
    "$GH_BIN" release upload v1.0.0 "$APK_PATH" --clobber -R shanghai-noodle/androidTV-photo-slideshow-releases && \
        echo "✅ [GitHub] Published: ${GITHUB_APK_URL}" || \
        echo "⚠️  [GitHub] Skipped GitHub Release upload."
fi

# 2. Update lightweight JSON version manifest in androidTV-photo-slideshow-releases
MANIFEST_FILE=""
if [[ "$APK_NAME" == *"baidu"* ]]; then
    MANIFEST_FILE="${RELEASE_DIR}/baidu-version.json"
elif [[ "$APK_NAME" == *"google"* ]]; then
    MANIFEST_FILE="${RELEASE_DIR}/google-version.json"
fi

if [ -n "$MANIFEST_FILE" ]; then
    cat > "$MANIFEST_FILE" <<EOF
{
  "versionCode": ${VERSION_CODE},
  "versionName": "${VERSION_NAME}",
  "sha256": "${SHA256}",
  "apkUrl": "${GITHUB_APK_URL}",
  "giteeApkUrl": "${GITEE_APK_URL}"
}
EOF
    (
        cd "$RELEASE_DIR"
        git add "$(basename "$MANIFEST_FILE")" README.md publish_release.sh 2>/dev/null || true
        if ! git diff --cached --quiet; then
            git commit -m "chore(release): update ${APK_NAME} to v${VERSION_NAME} (build ${VERSION_CODE})" >/dev/null 2>&1 || true
            git push origin main >/dev/null 2>&1 || true
            git push gitee main >/dev/null 2>&1 || true
        fi
    )
fi

# 3. Upload to Gitee Releases in background (since US->China upload is ~25 KB/s)
GITEE_TOKEN_FILE="${HOME}/.gitee_token"
if [ -s "$GITEE_TOKEN_FILE" ]; then
    APK_COPY="/tmp/gitee_staging_${APK_NAME}"
    cp -f "$APK_PATH" "$APK_COPY"
    LOG_FILE="/tmp/gitee_publish_${APK_NAME}.log"
    echo "☁️  [Gitee] Syncing ${APK_NAME} to Gitee Release in background (log: ${LOG_FILE})..."
    nohup bash -c '
        TOKEN="$(tr -d "[:space:]" < "'"$GITEE_TOKEN_FILE"'")"
        REL_JSON="$(curl -sS "https://gitee.com/api/v5/repos/shanghai-noodle/androidTV-photo-slideshow-releases/releases/tags/v1.0.0?access_token=${TOKEN}")"
        REL_ID="$(printf "%s" "$REL_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get(\"id\", \"\"))" 2>/dev/null || true)"
        if [ -n "$REL_ID" ]; then
            ATTACH_LIST="$(curl -sS "https://gitee.com/api/v5/repos/shanghai-noodle/androidTV-photo-slideshow-releases/releases/${REL_ID}/attach_files?access_token=${TOKEN}")"
            OLD_IDS="$(printf "%s" "$ATTACH_LIST" | python3 -c "import sys, json
for item in json.load(sys.stdin):
    if item.get(\"name\") == \"'"$APK_NAME"'\":
        print(item.get(\"id\"))
" 2>/dev/null || true)"
            for old_id in $OLD_IDS; do
                curl -sS -X DELETE "https://gitee.com/api/v5/repos/shanghai-noodle/androidTV-photo-slideshow-releases/releases/${REL_ID}/attach_files/${old_id}?access_token=${TOKEN}" >/dev/null || true
            done
            UPLOAD_HTTP="$(curl --http1.1 -H "Expect:" -sS -o /tmp/gitee_upload_'"$APK_NAME"'.json -w "%{http_code}" -X POST \
                "https://gitee.com/api/v5/repos/shanghai-noodle/androidTV-photo-slideshow-releases/releases/${REL_ID}/attach_files" \
                -F "access_token=${TOKEN}" \
                -F "file=@'"$APK_COPY"'")"
            echo "[$(date)] Gitee upload HTTP ${UPLOAD_HTTP} -> '"$GITEE_APK_URL"'"
        fi
        rm -f "'"$APK_COPY"'"
    ' > "$LOG_FILE" 2>&1 &
else
    echo "ℹ️  [Gitee] ~/.gitee_token not found; skipping Gitee Release upload."
fi
