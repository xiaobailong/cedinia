# 临时文件：一律写进仓库根 `tmp\`

- 中间产物（命令输出、临时脚本、状态/轮询文件、探针日志、临时 JSON / CSV）全写 `tmp\`；
  **禁止**写在仓库根、`src\`、`ui\`、`android\`、`memory-bank\`、`.clinerules\`。
- 不存在先 `mkdir tmp`；只用一层；命名即用途；命令用相对路径：`> tmp\out.txt 2>&1`。
- 例外（不要往 `tmp\` 塞）：构建日志留 `build\`（`build_full.log` / `clean_full.log` / `logs\gh-release_*.log`）、
  知识库条目留 `memory-bank\`、过程文档 `docs\HANDOFF-*.md`（自建并把 `docs/` 加进 `.gitignore`）、要长期保留的脚本入库。
- `tmp\` 被 `.gitignore` 忽略（`/tmp/`），可放心当垃圾桶；`.clineignore` **不**屏蔽它，因为命令输出要重定向到里面再用 `read_files` 读（`PIT-008`）。
- **收尾必须清空**：`rmdir /s /q tmp`（或 `clean.bat` / `build.bat clean`，两者都会删 `tmp\`），并在回复里说明。
