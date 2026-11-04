# Project collaboration rules

- 本仓库（曾用工作区名 `synth1_9_18`，现合并为唯一的 `gaoyun` 工作区）是双板工程的
  唯一权威仓库；历史快照与并行副本已于 2026-11-04 合并清理，不要再新建并行工作区。
- Before a major architectural change, audio data-path refactor, interface change,
  or broad RTL rewrite, commit the current working state and push it to `origin`.
- Small fixes may be grouped into the next meaningful checkpoint.
- Do not commit Gowin implementation output, simulator work libraries, waveform
  files, user-local IDE state, or temporary analysis files.
- Do not run Gowin synthesis or place-and-route solely for automated verification;
  use RTL syntax/elaboration checks unless the project owner explicitly requests it.
- 远程连板与部署注意事项：先读 `docs/REMOTE_ACCESS_IPV6_MIGRATION.md`（IPv6 直连，
  ZeroTier 已弃用）；部署只用 `tools/deploy_verified.py`，SSH 超时禁止自动重试。
- 目录导览与版本管理约定见根目录 `README.md`。
