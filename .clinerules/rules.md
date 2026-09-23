# Cedinia — Cline 工作约定

> 只放：编码 / 输出 / 目录结构 / 禁止操作 + 两条流程指针。历史与细节在 `memory-bank/`（索引 `memory-bank/README.md`）。

## 1. 编码
- 文本 UTF-8 **无 BOM**；`.clinerules`、`memory-bank`、`*.bat`、`README.md` 用 **CRLF**；`.gitignore`、`.clineignore` 保持 LF（跟随仓库现状）。
- `.ps1` 必须 UTF-8 **带 BOM**，且不在无 BOM 的 ps1 里写中文 / 中文路径。
- Rust/Slint 代码按仓库现有风格写（`src/*.rs`、`ui/**/*.slint`）；中文注释、日志、文案保持中文；不做与任务无关的重排或全文件格式化。

## 2. 输出
- 不复述需求、不写前置长说明；先给结论 / 代码 / 命令，解释压到最短。
- 未明确要求时不新建文档、不写长报告；收尾只讲：改了什么、怎么验证的、`tmp\` 是否已清空。

## 3. 目录结构
- 代码：Rust `src\`、Slint UI `ui\`、Android 工程 `android\`、翻译 `i18n\`。
- 构建：`build.bat`（无参=Android Release；`android` / `android-debug` / `android-aab` / `desktop` / `clean` / `check` / `publish`，
  另有 `no-bump` / `no-release`）；清理 `clean.bat`；只补发 Release 用根目录 `gh-release.bat`（不编译、不提交、只对 HEAD 打标签并上传 APK）；
  日志 tee 包装器 `tools\tee-log.ps1`（逐行：先写文件 → 再回显控制台）。
- 日志：`build\build_full.log`（build.bat）、`build\clean_full.log`（clean.bat）、`build\logs\gh-release_<ts>.log`（gh-release.bat）。
- 产物：`cedinia-<版本>.apk` 在仓库根 + `target\{release,debug}\apk\`；版本号真源 `Cargo.toml` 的 `package.version`
  （构建时 patch 自增并同步写回 `android\app\build.gradle.kts` 的 `versionName` / `versionCode`）。
- 知识库 `memory-bank\`；临时文件 `tmp\`（gitignored）。

## 4. 禁止操作
- 禁止 `git commit` / `push` / 打 tag / 发 Release（只由 `build.bat` / `gh-release.bat` 做，且需用户明确要求）。
- **禁止为了自测跑 `build.bat`**（会 patch +1、commit、push、发 Release）；校验改动优先 `cargo check` / `cargo clippy`
  （Android 目标再加 `--target aarch64-linux-android`），只验发布脚本用 `gh-release.bat check`（只读预检）。
- 禁止把中间文件写在仓库根或 `src\` / `ui\` / `android\` / `memory-bank\` / `.clinerules\`（一律 `tmp\`）。
- 禁止 `read all` 知识库、禁止扫全仓库：只读当前任务必需的文件（`.clineignore` 已挡构建产物）。
- 禁止删知识库条目 / 改编号；禁止写 token、密钥、私密凭据。

## 5. 两条强制流程
- **知识库**：开工读 `memory-bank/README.md`（索引）→ 只读命中的那 1 个文件；收工照 `memory-bank/WRITING.md` 回填。
  细则见 `.clinerules/memory-bank.md`。
- **临时文件**：中间产物一律 `tmp\`，收尾清空。见 `.clinerules/tmp-files.md`。
