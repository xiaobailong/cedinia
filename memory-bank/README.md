# memory-bank 索引（**只读需要的那 1 个文件**，别全读）

- 文件代号：`I` = `issues-solved.md`（已定位问题）　`P` = `pitfalls.md`（踩坑）　`D` = `decisions.md`（取舍）
- `archive/` **默认不读**（条目给指针才读那节）；**写**条目看 `WRITING.md`；规矩见 `.clinerules/memory-bank.md`
- 上限：本索引 3KB，`I`/`P`/`D` 各 20KB（迁移时按本仓库条目长度重设，见 `ADR-012`；超了先归档）
- **本知识库迁移自同机同工具链的源仓库 ClipboardMerger**（2026-09-23）：通用坑条目沿用原编号，内容按 cedinia 现状改写，条目里标了「来源」；新条目从最大号 +1 开始

## 症状 → 条目

| 症状 / 报错 | 条目 | 文件 |
| --- | --- | --- |
| 构建日志空 / 缺内容 / 路径为空 | `ISSUE-001`（判据已按 cedinia 的 `--log` tee 改写） | I |
| 构建失败也消耗一个 patch 版本号（跳号） | `ISSUE-002` | I |
| 改 `build.bat` / `gh-release.bat` 的发布 / 日志 / 版本流程 | `ADR-009` / `ADR-010` / `ADR-011`、`ISSUE-004`（未迁移见 `ADR-012`） | D |
| 校验不 push / 推送瞬断失败 / `gh` / Release 出问题 / 同名资产 422 | `ADR-009` / `ADR-011`、`ISSUE-005`、`PIT-027` | D + I + P |
| 只补发 / 重发 GitHub Release、`gh-release.bat` 用法 | `ADR-011` | D |
| 临时文件放哪、怎么清；仓库根堆临时产物 | `ADR-002` | D |
| 知识库为什么按需读、`.clineignore` / 会话压缩怎么用 | `ADR-001` / `ADR-007`（均归档） | D |
| 知识库 / 规则 / 发布脚本从哪来、编号为什么不重排 | `ADR-012` | D |
| 版本号写在哪、APK 叫什么、tag 怎么来 | `ADR-005` | D |
| 自测该跑什么命令、别碰发布 | `ADR-004` | D |
| `powershell -Command` 无输出、退出码 786 | `PIT-001` | P |
| `.ps1` 乱码 / 语法错；`.bat` 首行 `@echo off` 失效 | `PIT-002` | P |
| 批量替换把文件改坏（字符被换 / 路径重复） | `PIT-003`、`PIT-004`、`PIT-014` | P |
| 批处理只跑一半；`echo` 里 `>` / 括号 / 变量展开出错 | `PIT-005`、`PIT-006`、`PIT-007` | P |
| 终端抓不到输出 / 命令互相打断 / 轮询被掐断 | `PIT-008`、`PIT-009`、`PIT-018` | P |
| 日志中文乱码 / PowerShell 查询挂死 / 搜不到东西 | `PIT-010`、`PIT-011`、`PIT-017` | P |
| 管道 + PowerShell 写日志丢内容；`call` 递归退出码不对 | `PIT-012`、`PIT-013` | P |
| 产物放 `build\` 被清 / 日志看不到最新 / 窗口没关又起一轮 / 日志缺一段 | `PIT-015`、`PIT-016`、`PIT-020`、`PIT-021` | P |
| `'C:\Program' is not recognized`；一行 `if/else` 后接 `& 命令` 不执行 | `PIT-023`、`PIT-024` | P |
| `bat` 调 `bat` 不带 `call`；中文注释被错解析；抽段测试误跑主流程 | `PIT-025`、`PIT-026`、`ISSUE-006` | P + I |
| 大文件读到一半就没了（读工具"中间截断"） | `PIT-028` | P |
| 关掉「Enable logging」后仍建 `Download/cedinia` / 仍有日志输出 | `ISSUE-007` | I |
