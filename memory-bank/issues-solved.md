# 已排查问题（issues-solved）

> 上限 12KB（超了照 `WRITING.md` §3 归档）。每条必填：症状 / 复发判据 / 根因 / 证据 / 修法 / 反例。
> 编号只增不改，新条目取当前最大号 +1（本仓库当前最大 `ISSUE-007`）。
> **来源**: 本文件 2026-09-23 从同机同工具链的源仓库 ClipboardMerger 迁入，编号沿用、结论按 cedinia 的脚本行号复核；
> 源仓库中纯属其自身应用（Kotlin 日志开关、`version.properties`、Gradle `BUILD_TIME`）的 `ISSUE-003` / `ISSUE-004` 未迁移，见 `ADR-012`。

## ISSUE-001 构建日志写不进去（只有首行 / 空行 / 整段缺失）
- 状态: 已规避（2026-09-23 迁入；cedinia 的日志链路按同一结论设计并复核）
- 症状 / 现场（源仓库实录）: 控制台有输出，日志文件只有首行 / 只有空行 / 整段缺失，中途还留下 `build\logs\_logpath.tmp` 残留。
- 复发判据（cedinia，5 秒）:
  ```bat
  findstr /n "--log" build.bat
  findstr /n "logpath" build.bat
  ```
  期望：第一条命中 `build.bat:9`（`if "%~1" NEQ "--log"`）与 `build.bat:11-15`（内联 PowerShell tee + `cmd /c '%~f0 --log %*'`）；
  第二条 **0 命中**。构建**进行中** `type build\build_full.log` 能看到已产出的行（逐行落盘）。
  出现 `2>&1 | powershell -Command "... Out-File -Append ..."`、`_logpath.tmp`、或在 `( )` 块里先 `set` 再用 `%VAR%` 拼日志路径 ⇒ 复发。
- 根因（源仓库三层，逐层修掉）: ①括号块内 `%VAR%` 解析期展开为空；②管道 + `powershell -Command` 里的路径同样被预展开；
  ③管道 + `Out-File` / `Add-Content` 逐行追写**依然丢内容**。
- 修法（cedinia 现状）: `build.bat:9-19` = 「私有参数 `--log` + `%*` 透传 + 内联 PowerShell tee」，不经管道喂 `-Command`、也没有块内展开；
  `gh-release.bat` = `tools\tee-log.ps1`（`-File` + 子进程 stdout 直读，见 `ADR-010`），并保留缺脚本时的降级分支。
- 反例 / 易误判: 认定"日志是空文件 ⇒ 构建没跑"（先看 `PIT-016`）；把 `> "%LOG%"` 写在括号块里；用管道给 PowerShell 做 tee。
- 相关: `PIT-007` / `PIT-012` / `PIT-013` / `ADR-003`（已废弃）/ `ADR-010`；
  **三次失败方案的完整过程分析见 `archive/issues-solved-archive.md`**
- 首次记录: 2026-09-23（源仓库） ／ 最近复核: 2026-09-23（迁入 cedinia，判据已按本仓库 `build.bat` 行号改写）

## ISSUE-002 构建失败也会消耗一个 patch 版本号（版本号跳号）
- 状态: 未修复（已知行为，影响仅跳号，可接受）
- 症状 / 现场: 编译失败的下一轮构建成功发布后，版本号比上一版 **+2**；失败也留下 `Cargo.toml` 与 `android\app\build.gradle.kts` 的改动。
- 复发判据: 构建失败后 `git --no-pager diff -- Cargo.toml android/app/build.gradle.kts` 仍显示版本号已 +1。
- 根因: 递增排在编译之前且失败不回滚 —— `build.bat:974`（`:do_android_build`）、`build.bat:1034`（`:do_android_aab_build`）都先 `call :bump_version`；
  `:bump_version` 在 `BUMPED=1` 时立刻 `call :write_version`（`build.bat:501-504`）写回 `Cargo.toml`
  与 `android\app\build.gradle.kts`（`build.bat:548-577`）。随后 `cargo fetch` / `cargo apk build` 失败即留下已递增的文件。
- 修法: 未修。要连续号就把写回挪到打包成功之后（发布流程要读 `versionName` / `versionCode`，位置要一起调）；
  只想不跳号：失败后 `git checkout -- Cargo.toml android/app/build.gradle.kts` 回退，或本次构建加 `no-bump`。
- 反例 / 易误判: 把跳号当成"脚本跑了两次 / Cargo 缓存问题"的证据。
- 相关: `ADR-005`　首次记录: 2026-09-23（源仓库） ／ 最近复核: 2026-09-23（cedinia 代码位置已复核：974 / 1034 / 501-504）

## ISSUE-005 `git push` 瞬断（`Connection reset … port 22`）/ `gh` TLS 超时 导致发布中断，tag/Release 全没做
- 状态: 已规避（源仓库实录；cedinia 侧由 `gh-release.bat` 承载同样的重试 + 代理 + 快路径）
- 症状 / 现场: 提交成功后 `Connection reset by 20.205.243.166 port 22` ⇒ 脚本硬退出，tag 与 Release 都没执行（本地多一个未推送提交）；
  同一轮 `检查 gh CLI` 还报过"未登录或登录状态异常" —— 其实 `gh auth status` 会联网校验，是网络瞬断；事后复测凭据正常。
  `gh` 走 HTTPS 也报 `net/http: TLS handshake timeout`，设 `http_proxy` / `https_proxy=http://127.0.0.1:7897` 后恢复可用。
- 复发判据: 日志出现 `Connection reset by … port 22` / `fatal: Could not read from remote repository` / `TLS handshake timeout`；
  修复后应是 `推送 <ref> ...`（必要时跟 `[重试 n/3]`），并且远端标签已指向 HEAD 时**直接跳过**打标签 / 推标签。
- 根因: 本机到 github.com:22 时通时断；脚本原来一次失败就硬退出，没有重试，也没有可操作的提示。
- 修法（cedinia 现状）: `gh-release.bat` 提供 `:git_push <ref> [force]`（最多 3 次、间隔 3 秒、全败打印成因与手工命令 +
  「改走 HTTPS」指引）、用 `gh api repos/<repo>/commits/<tag> --jq .sha` 判断"远端标签已在 HEAD"从而跳过 tag 推送（走 HTTPS，绕开卡死的 SSH）、
  `GH_PROXY` 注入代理（未设时探测 `127.0.0.1:7897` / `7890`）。
  **`build.bat:806-817` 的 `git push origin HEAD` / `git push origin <tag>` 仍是单次尝试**（无重试、不查远端标签）⇒ 这条路径仍会踩坑，见 `ADR-009` 的影响栏。
- 反例 / 易误判: 把 `gh 未登录` 当真（其实是联网自检失败）；把推送失败当脚本 bug（链路问题要换 HTTPS / 代理）。
- 相关: `ADR-009` / `ADR-011`；首次记录: 2026-09-23（源仓库） ／ 最近复核: 2026-09-23（cedinia 现状行号已复核）

## ISSUE-006 抽段测试把「主流程」当成子过程跑了 ⇒ 误建并推送真实 tag
- 状态: 已修复（源仓库实录；cedinia 沿用同一抽取纪律）
- 症状 / 现场: 假 `gh` 用例跑到 `check_gh` 时，输出里冒出**真实主流程**（`[2/6] 读取版本信息` … `Updated tag 'v1.53' (was 94f9621)` …
  `推送 v1.53 ...`）⇒ 本地多出 tag，**远端也被推上 `refs/tags/v1.53`**（据 tag 对象消息 `Release v1.53` 与正常发布的 `Cedinia <tag>` 区分是谁建的）。
- 复发判据: ①抽取脚本自身断言 `firstline=:check_gh`，出现 `ERR: carve leaked main flow` 即复发；
  ②测试输出里**不该**出现 `[2/6]` / `Updated tag` / `推送 `；③`git tag --list` 在测试前后应完全一致。
- 根因: `$text.IndexOf(':check_gh')` 命中的是**主流程里的 `call :check_gh`**（早于 `:check_gh` 标签行）；
  切出来的正文 = 主流程 + 尾部子过程，派发器 `goto :check_gh` 落到这个「伪标签」后顺序执行主流程（只有 `gh` 是假的，所以没建 Release）。
- 修法: ①起点改 `(?m)^:check_gh\s*$`；②加断言「首行 = `:check_gh`」「正文不含 `[2/6]`」「标签唯一」；
  ③测试用假 `git` 放 PATH 最前且 `tag` 一律 `exit /b 1`（兜底）；④抽取副本只做「行首 `"..."` → `call "..."`」的最小改写（`PIT-025`）。
- 反例 / 易误判: 以为「测试只调子过程、不会碰远端」；把非强制推送的 `already exists` 拒绝当成「远端本来就有这个 tag」；只看用例退出码。
- 相关: `PIT-025`、`ADR-009`、`ADR-011`；
  cedinia 的子过程集合（抽段测试要按**标签行**切）：`:check_gh` / `:git_push` / `:gh_release` / `:drop_same_asset` / `:find_apk`
- 首次记录: 2026-09-23（源仓库） ／ 最近复核: 2026-09-23（迁入 cedinia 时复核子过程集合）

## ISSUE-007 「Enable logging」关掉后仍创建 `Download/cedinia` 并写入启动日志（全局开关不生效）
- 状态: 已修复（编译校验：`cargo check --release --target aarch64-linux-android` 与桌面目标 `cargo check --release` 均通过、无 warning/error；真机行为未复测）
- 症状: 设置里关掉「Enable logging」后，`/storage/emulated/0/Download/cedinia/` 还是被建出来、当天 `cedinia_<date>.log` 里仍有几行；重启（设置里已存 `false`）后照样。
- 复发判据（5 秒）: 关掉开关 → 杀进程重开 App →
  `adb shell ls /sdcard/Download/cedinia 2>&1` 期望 `No such file or directory`；
  再断言开关本身：关闭后当天日志**最后一行的后续不应有新行**（末行应停在 `settings: saving on user request (logging_enabled=false)`）。
- 根因（3 处，都是「logger 安装早于开关生效」）:
  ① `app.rs::setup_logger_cache()`（`lib.rs::android_main` 在 `load_settings()` **之前**调用）无条件 `open_android_log_file()`，
  而 `logging::android::download_log_dir()` 内部 `create_dir_all` ⇒ 目录必然创建；`lib.rs` / `prune_stale_logs` 的 `log::info!` 也全在 `load_settings()` 之前落盘；
  ② `setup_android_logger()` 硬编码 `log::set_max_level(log::LevelFilter::Debug)` ⇒ 把启动时刚置上的 `Off` 又打开；
  ③ 权限轮询 `retarget_log_file()`、`collect_log_files()`、`prune_stale_logs()` 都走会建目录的 `download_log_dir()`。
  桌面侧同类问题：`setup_logger()` 在 `load_settings()` 之前 `FileRotate::new` 就建了 `cedinia.log`。
- 修法: 让开关接管「日志文件 / logger 的生命周期」——
  ① 新增 `settings::load_logging_enabled_flag()`（只读持久化开关），`setup_logger_cache()` 在装 logger **之前** `logging::set_logging_enabled(...)`；
  ② 新增 `logging::apply_log_level()`，装完 logger 后重 apply（装 logger 会重置 facade 的 max level）；用 `LOG_LEVEL` 常量替代原来捕获 `log::max_level()`，避免恢复成 facade 默认的 `Trace`；
  ③ `logging::android::download_log_dir()` 不再建目录，新增仅由「打开日志文件」调用的 `create_download_log_dir()`；
  ④ 新增 `logging::set_log_file_hooks(open, close)` + `open_log_file()` / `close_log_file()`：off 关句柄、on 再打开，Android 权限授予也复用 `open_log_file()`；
  ⑤ 桌面改为 `install_desktop_logger()`（`OnceLock` 幂等）在开关 on 时安装，之后打开时由 hook 延迟安装。
- 反例 / 易误判: 以为「设置已存 `false` 就必然安静」——off 之前的所有 `log::*!` 仍会落盘（这正是用户看到的那几行）；
  把目录说成「旧会话遗留」也不行，`prune_old_logs` 只删 7 天以上的 `cedinia*.log`，目录本身从来不清。
- 相关: `AGENTS.md` 的 Logging 段落（已同步改写）
- 首次记录: 2026-09-23 ／ 最近复核: 2026-09-23（Android 目标 1m25s、桌面目标 4m25s 的 `cargo check --release` 均 `Finished`，无 warning）
