#!/bin/bash
# 把 iCloud Drive 里的 Surge 配置同步到本仓库的 Profiles/ 目录，并自动提交推送。
# 兼容 macOS 自带的 bash 3.2 和 BSD awk。
#
# 可用环境变量覆盖：
#   SURGE_SRC     Surge 配置目录（默认 iCloud Drive 的 Surge 目录）
#   SURGE_DEST    仓库内的目标子目录（默认 Profiles）
#   SURGE_REDACT  1=脱敏后再提交（默认），0=原样提交
#   SURGE_PUSH    1=提交后推送（默认），0=只本地提交
#   SURGE_DRY_RUN 1=只生成文件、显示差异，不提交不推送

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SURGE_SRC:-$HOME/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents}"
DEST_NAME="${SURGE_DEST:-Profiles}"
DEST="$REPO_DIR/$DEST_NAME"
REDACT="${SURGE_REDACT:-1}"
PUSH="${SURGE_PUSH:-1}"
DRY_RUN="${SURGE_DRY_RUN:-0}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# 去掉代理密码、订阅链接、MITM 证书等敏感信息
redact() {
  awk '
    function lower(s) { return tolower(s) }
    /^[ \t]*\[.*\][ \t]*$/ {
      section = lower($0); gsub(/[ \t\[\]]/, "", section); print; next
    }
    /^[ \t]*[#;\/]/ || /^[ \t]*$/ { print; next }
    {
      line = $0
      eq = index(line, "=")
      key = (eq > 0) ? substr(line, 1, eq - 1) : ""
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      lkey = lower(key)

      if (section == "proxy" && eq > 0) {
        # 保留节点名和协议类型，隐藏服务器、端口、密码等
        rest = substr(line, eq + 1)
        n = split(rest, parts, ",")
        type = parts[1]; gsub(/^[ \t]+|[ \t]+$/, "", type)
        if (n > 1 && type != "direct" && type != "reject" && type != "reject-tinygif") {
          print key " = " type ", <redacted>"; next
        }
      }
      if (section == "mitm" && (lkey == "ca-passphrase" || lkey == "ca-p12")) {
        print key " = <redacted>"; next
      }
      if (section == "general" && (lkey == "http-api" || lkey == "external-controller-access")) {
        print key " = <redacted>"; next
      }
      # 订阅链接、带凭据的参数（含 WireGuard 密钥）
      gsub(/policy-path[ \t]*=[ \t]*[^,< \t][^,]*/, "policy-path=<redacted>", line)
      while (match(line, /(password|passwd|psk|token|uuid|username|private-key|preshared-key)[ \t]*=[ \t]*[^,< \t][^,]*/)) {
        seg = substr(line, RSTART, RLENGTH)
        k = substr(seg, 1, index(seg, "=") - 1); gsub(/[ \t]+$/, "", k)
        line = substr(line, 1, RSTART - 1) k "=<redacted>" substr(line, RSTART + RLENGTH)
      }
      print line
    }
  '
}

if [ ! -d "$SRC" ]; then
  log "找不到 Surge 配置目录：$SRC"
  exit 1
fi

# 让 iCloud 把只存在云端的文件下载到本地（brctl 只在 macOS 上有）
if command -v brctl >/dev/null 2>&1; then
  find "$SRC" -maxdepth 2 -name '.*.icloud' | while IFS= read -r f; do
    brctl download "$f" >/dev/null 2>&1 || true
  done
  sleep 2
fi

cd "$REPO_DIR"

if [ "$DRY_RUN" != "1" ]; then
  # 先拉取远端更新（例如在 GitHub 网页上改过的规则），避免推送冲突
  git pull --rebase --autostash --quiet || { log "git pull 失败"; exit 1; }
fi

# 在临时目录里重新生成一份，再整体替换 Profiles/，这样 iCloud 里删除的文件也会同步删除
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

count=0
while IFS= read -r f; do
  rel="${f#"$SRC"/}"
  mkdir -p "$TMP/$(dirname "$rel")"
  case "$f" in
    *.conf|*.dconf)
      if [ "$REDACT" = "1" ]; then redact < "$f" > "$TMP/$rel"; else cp "$f" "$TMP/$rel"; fi ;;
    *)
      cp "$f" "$TMP/$rel" ;;
  esac
  count=$((count + 1))
done < <(find "$SRC" -maxdepth 2 -type f \
  \( -name '*.conf' -o -name '*.dconf' -o -name '*.sgmodule' -o -name '*.list' -o -name '*.txt' -o -name '*.js' \) \
  ! -name '.*' | sort)

if [ "$count" -eq 0 ]; then
  log "源目录里没有找到配置文件，跳过（可能 iCloud 尚未下载完成）"
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$TMP"/. "$DEST"/

git add -A -- "$DEST_NAME"
if git diff --cached --quiet -- "$DEST_NAME"; then
  log "没有变化（$count 个文件）"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  git diff --cached --stat -- "$DEST_NAME"
  git reset --quiet -- "$DEST_NAME"
  log "DRY RUN：以上为将要提交的变化，未提交"
  exit 0
fi

git commit --quiet -m "Sync Surge profiles from iCloud ($(date '+%Y-%m-%d %H:%M'))" -- "$DEST_NAME"
log "已提交：$(git log -1 --pretty=%s)"

if [ "$PUSH" = "1" ]; then
  git push --quiet && log "已推送到 $(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo origin)"
fi
