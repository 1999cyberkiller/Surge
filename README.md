# Surge

- `Rule/`：自定义规则集
- `Profiles/`：从 iCloud Drive 自动同步过来的 Surge 配置（已脱敏）

## Mac 自动同步 iCloud 配置

`scripts/surge-sync.sh` 把 `iCloud Drive/Surge` 里的 `.conf` / `.dconf` / `.sgmodule` / `.list` / `.txt` / `.js` 复制到 `Profiles/`，有变化就自动 commit 并 push。

```bash
git clone git@github.com:1999cyberkiller/surge.git ~/Surge
cd ~/Surge

# 先试运行，看会提交哪些变化
SURGE_DRY_RUN=1 ./scripts/surge-sync.sh

# 安装 launchd 任务：iCloud 目录变化时自动同步，另外每小时兜底跑一次
./scripts/install-launchd.sh

# 查看日志 / 手动触发 / 卸载
tail -f ~/Library/Logs/surge-sync.log
launchctl kickstart -k gui/$(id -u)/com.github.surge-sync
./scripts/install-launchd.sh uninstall
```

### 脱敏

默认会把以下内容替换为 `<redacted>` 后再提交（iCloud 里的原文件不会被改动）：

- `[Proxy]` 里每个节点的服务器、端口、密码等（只保留节点名和协议类型）
- `policy-path` 订阅链接，以及 `password` / `psk` / `token` / `uuid` / `username` / `private-key` / `preshared-key` 参数
- `[General]` 的 `http-api`、`external-controller-access`
- `[MITM]` 的 `ca-passphrase`、`ca-p12`

如果仓库是私有的、想原样备份，可设 `SURGE_REDACT=0`（安装前 export，或直接改 plist）。

### 可选环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SURGE_SRC` | `~/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents` | Surge 配置目录 |
| `SURGE_DEST` | `Profiles` | 仓库内的目标目录 |
| `SURGE_REDACT` | `1` | 是否脱敏 |
| `SURGE_PUSH` | `1` | 是否自动 push |
| `SURGE_DRY_RUN` | `0` | 只显示差异，不提交 |

### 常见问题

- **日志里出现 `Operation not permitted`**：在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里添加 `/bin/bash`。
- **push 失败 / 要求输入密码**：后台任务无法交互，请确保 SSH key 已加入钥匙串（`ssh-add --apple-use-keychain`），或 HTTPS 方式使用 `osxkeychain` 凭据助手。
