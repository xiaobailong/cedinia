# 踩坑记录（pitfalls）

> 上限 12KB（超了照 `WRITING.md` §3 归档）。每条必填：正确做法 / 反例 / 自检（+ 触发条件与现象）。
> **来源**: 通用坑来自同机同工具链的源仓库 ClipboardMerger（2026-09-23 迁入本仓库，编号沿用）；
> 标了「cedinia」的条目是按本仓库脚本（`build.bat` / `clean.bat` / `gh-release.bat`）复核过的证据。
> 标「已归档」的条目：主文件只留一行要点，原文在 `archive/pitfalls-archive.md`。

## PIT-001 长 `powershell -Command`（含正则/管道）被静默拦截 → 退出码 786、无输出
- 触发条件: `powershell -NoProfile -Command "<长串 / 正则 / 管道>"`　现象: 无输出 + 退出码 **786**。
- 正确做法: 逻辑写成 `.ps1`，用 `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本> -参数`；
  只有极短单表达式可留在 `-Command`（如 `build.bat` 里的 `Get-Date -Format yyyyMMdd_HHmmss`）。
- 例: **cedinia** `build.bat:512-515` 已把这个坑写进注释 —— 本机 EDR 会在「同一进程先读文件再写文件」和
  「调用 `Regex.Replace`」两种情况下静默杀掉 powershell（rc=786、零输出），所以 `:write_version` 改成
  「PowerShell 只读原件 → 结果写 stdout → cmd 的 `>` 落盘 → `move` 覆盖」，替换动作用 `[Regex]::Matches` + `Remove/Insert`。
- 反例: `powershell -Command "$t -replace '(\+)\d+', ...; [IO.File]::WriteAllText(...)"`
- 自检: 退出码 786，或"没输出但应该有输出" ⇒ 立刻改 `-File` 或改「只读 + stdout + cmd 重定向」写法。

## PIT-002 `.ps1` = UTF-8 **带 BOM** + CRLF；`.bat` / `.md` = UTF-8 **无 BOM**（+ CRLF）
- 现象: 无 BOM 的 `.ps1` 被 PowerShell 5.1 按 GBK 读 ⇒ 中文乱码甚至语法错；
  `.bat` 带 BOM ⇒ 首行 `@echo off` 变 garbage。
- 正确做法: 写完核对前 3 字节是否 `EF BB BF`，并统计 CRLF 与 bare LF（几行 PowerShell 即可）。
  本仓库约定：`.clinerules` / `memory-bank` / `*.bat` / `README.md` = **noBOM + CRLF**；`.gitignore` / `.clineignore` = LF；
  `tools\*.ps1` = **BOM + CRLF**。
- 反例: 编辑器"另存为 UTF-8"（多数默认无 BOM）就当合格。
- 自检: `.ps1` 要 `enc=BOM` + `bareLF=0`；`.bat` / `.md` 要 `enc=noBOM` + `bareLF=0`。
- 追加坑: **无 BOM 的 ps1 里不要出现中文字面量 / 中文路径** —— 路径会被 GBK 解码成乱码，
  脚本一声不响、`Get-Content` 返回 **0 行**（看着像"文件是空的"）；改用通配符定位文件。

## PIT-003 嵌套数组被展平 ⇒ 按字符全局替换 — 已归档（2026-09-23）
- 要点: 成对替换用两个独立 `[string]` 参数、单对单次调用；自检: 替换后逐行看 `git diff`。详情: `archive/pitfalls-archive.md`

## PIT-004 替换文本包含查找文本时不能 while/反复 Replace — 已归档（2026-09-23）
- 要点: 只做**单次** `$text.Replace($old,$new)`（否则路径段重复 / 死循环）；自检: grep 重复路径段。详情: `archive/pitfalls-archive.md`

## PIT-005 `echo` 里半角括号写在 `if (...)` 块内 → `)` 提前闭合批处理
- 现象: `: was unexpected at this time.`，批处理"只跑一半就退出"（本项目源仓库事故见 `ISSUE-004`）。
- 正确做法: `^(` `^)` 转义（`&` 写成 `^&`）—— 本仓库实例：`build.bat:213` 的 `echo 删除 %%~nxi  ^(%%~zi bytes^)`、
  `build.bat:933` 的 `echo 产物: target\release\cedinia.exe  ^(%%~zf bytes^)`。
- 反例: `( ... echo 检查未完全成功 (exit=%X%) ... )`
- 自检: 批处理是否中途退出、有无 `unexpected at this time`；块内的 `echo` 是否含裸 `(` `)`。

## PIT-006 `echo` 里的 `>` 要转义；`%ERRORLEVEL%>> file` 相邻会吞内容
- 现象: 提示里的 `>` 被当成重定向（凭空多出文件）；`echo RC=%ERRORLEVEL%>> f.txt` 只留下一行空行。
- 正确做法: 转义 `^>`；退出码先存变量再写（本仓库：`build.bat:1085` 的 `set "GRADLE_EXIT=%ERRORLEVEL%"`），
  或把 `>>` 挪到行首（`build.bat:820-825` 写 release notes 就是这个写法）。
- 反例: `echo RC=%ERRORLEVEL%>> f.txt`　自检: 文件里该出现的行是否真的出现。

## PIT-007 `%VAR%` 是解析期展开、`!VAR!` 才是延迟展开（括号块 / 同行 `&` 链必踩）
- 触发条件: 在 `( ... )` 里**先 `set` 再用 `%VAR%`**，或同一行 `&` 链里读刚设的变量 / `ERRORLEVEL`。
- 现象: 取到**空值或旧值**（源仓库事故的直接起因，见 `ISSUE-001`）。
- 正确做法: 先设后用就**跳出括号块**（`goto :label` 分流）或 `setlocal enabledelayedexpansion` + `!VAR!`；
  同行 `&` 链用绝对路径；退出码先 `set "RC=%ERRORLEVEL%"`。
  **cedinia**：`build.bat:3` 开了 `enabledelayedexpansion`，全程用 `!VAR!`；参数的传递坑见 `build.bat:972-973`
  （`call :label` 会清空子例程的 `%*`，必须显式透传，否则 `no-bump` / `no-release` 失效）。
- 反例: 块内 `set` + `%VAR%` 混用；`set "FL=path" & "%FL%\x.exe"`；块内读 `%ERRORLEVEL%`
- 自检: 变量 / 退出码判断是否"永远走同一分支"；日志首行是否为空方括号。

## PIT-008 本环境终端抓不到命令输出 ⇒ 重定向到文件再读；**一次只发一条命令链**
- 现象: 提示 `could not be captured through shell integration`；新命令会**掐掉仍在跑的前一条**；
  回显里只有上一次命令的内容，容易把"上一条的输出"当成"这一条的结果"。
- 正确做法: `cmd > tmp\out.txt 2>&1` 后用 `read_files` 读；多条独立命令串进同一行（`&` / `&&`）并用 `echo ===` 分段；
  长任务用独立窗口（`PIT-009`）。`tmp\` 故意不被 `.clineignore` 屏蔽，就是为了这条链路。
- 反例: 一条消息里发多条独立命令；依赖终端回显下结论。
- 自检: 关键结果是否落在文件里、能否二次读取复核。

## PIT-009 长构建要放独立窗口，前台跑会被下一条命令掐断
- 触发条件: `build.bat` / `cargo apk build` 这类分钟级任务。
- 现象: 跑到一半被杀，`build\build_full.log` 停在中间。
- 正确做法: `start "Cedinia Build" cmd /c "build.bat"`，之后**只用 `read_files` 轮询**日志；
  等一会儿用 `ping -n N 127.0.0.1 > nul`（非交互环境 `timeout` 不可靠）。
- 反例: 前台起构建后又发命令；构建中反复发命令。
- 自检: 日志是否连续；`tasklist /fi "imagename eq cargo.exe"` / `rustc.exe` 里编译进程是否还在。

## PIT-010 `Get-Content` 默认按 GBK(936) 解码 ⇒ 中文被啃成 `?` 或乱码
- 正确做法: `Get-Content -LiteralPath <f> -Raw -Encoding UTF8`；控制台先 `[Console]::OutputEncoding = [Text.Encoding]::UTF8`。
- 反例: `Get-Content build\build_full.log -Tail 20`（本仓库日志是 UTF-8）
- 自检: 读回来的中文是否正常（拿已知中文行验证）。

## PIT-011 本机 WMI / `jps` / `jcmd` / `Get-Counter` 会**挂死**（无输出、永不返回）
- 正确做法: 内存用 `GlobalMemoryStatusEx`（P/Invoke）或 `Get-Process` + 路径过滤；杀进程 `Stop-Process`；
  "构建是否在跑"用 `tasklist /fi "imagename eq cargo.exe"`。
- 反例: `Get-CimInstance Win32_OperatingSystem`、`jps -l`、`Get-Counter`
- 自检: 命令是否 1~2 秒内返回（否则立刻停手）。备注: 属"**已规避**"类，不要试图真正修好。

## PIT-012 别用「管道 + PowerShell 逐行追写」给构建做日志 — 已归档（2026-09-23）
- 要点: 用 `call "%~f0" %* 1>> "<log>" 2>&1` + 紧邻 `set "RC=%ERRORLEVEL%"`；
  自检: 日志首行与末尾"日志已保存"都在。详情: `archive/pitfalls-archive.md`
- 补充: 该"重定向 + 结束后 `type`"方案已废弃（控制台全程空白）→ 改用逐行 tee（`ADR-010`）。

## PIT-013 `call` 递归调用自身后，必须**立刻** `set "RC=%ERRORLEVEL%"`
- 现象: 中间的 `echo` / `type` / `timeout` / `pause` 会改写 `ERRORLEVEL` ⇒ 外层永远拿到成功码 ⇒ **失败却报成功**。
- 正确做法: `call` 回来的下一行 `set "_CED_REL_RESULT=%ERRORLEVEL%"`，最后 `exit /b %_CED_REL_RESULT%`
  （cedinia `clean.bat:16` 的 `exit /b`、`gh-release.bat` 的 `:log_done` 同型）。
- 反例: `call ... 1>> log 2>&1` 之后隔几行再 `exit /b %ERRORLEVEL%`
- 自检: 故意让脚本失败，看外层退出码是否非 0。

## PIT-014 批量改动改坏了怎么救：`git checkout -- <路径>` 从 index 还原 — 已归档（2026-09-23）
- 要点: 从 **index** 还原工作区（别用 `git checkout HEAD -- .`）；自检: `git diff --numstat <路径>` 为空。详情: `archive/pitfalls-archive.md`

## PIT-015 诊断产物 / 交接文档不要放 `build\` — 已归档（2026-09-23）
- 要点: 要留存的进 `memory-bank\` 或 `docs\HANDOFF-*.md`（`docs/` 需自行 gitignore），纯临时进 `tmp\`。
  **cedinia**：`clean.bat:254-267` 会 `rmdir /s /q build`。详情: `archive/pitfalls-archive.md`

## PIT-016 同一输出文件反复写入可能只读到旧内容
- 现象: 读到上一轮内容，或 `dir` 显示 0 字节而 `type` 有内容 ⇒ 误判"命令没跑 / 构建卡住"。
- **cedinia 具体形态**: `build.bat:14` 的 tee 用 `StreamWriter($Log, $false, ...)` **覆盖**同一个
  `build\build_full.log`（`clean_full.log` 同理）⇒ 日志文件名每轮不变，读到的可能是"上一轮的内容"。
  `gh-release.bat` 反过来用带时间戳的 `build\logs\gh-release_<ts>.log`，天然每轮一换。
- 正确做法: 判断"还在跑"看 `dir /tw build` + `tasklist /fi "imagename eq cargo.exe"`；
  要对比两轮结果就先把当前日志复制进 `tmp\`。
- 反例: 靠读长日志尾部判断进度；`read_files` 读到空就断定失败。
- 自检: 内容是否与刚跑的步骤匹配；再看 `dir /tw` 的 size / mtime。

## PIT-017 检索手段实测：`search_codebase` 常超时、`findstr` 搜中文不可靠 — 已归档（2026-09-23）
- 要点: 优先 `read_files`；批量过滤用 `powershell -File` + `Select-String -Encoding UTF8`；
  另外 `search_codebase` 实测**不覆盖 `.bat` / `.md`**（本仓库搜 `:publish_only` 零命中，实际 `build.bat:123` 有）。
  自检: 用"已知一定存在"的词做正控。详情: `archive/pitfalls-archive.md`

## PIT-018 长等待会被提前掐断 ⇒ 轮询必须"先写状态文件、再等"
- 现象: 命令 30~60 秒就被回收，`&` 后面的命令**根本没执行**，状态文件没创建 ⇒ 误判"命令没跑"。
- 正确做法: ①按 1 分钟粒度轮询，**先写状态文件再 `ping -n 400`**；②状态文件写 `tmp\`；
  ③长任务放独立窗口（`PIT-009`）；④判断"在跑"用 `dir /tw` + `tasklist`。
- 反例: 发一条 `ping -n 600` 指望等 10 分钟；把 `&` 后面的命令当作一定执行。
- 自检: 状态文件 mtime 是否推进；`cargo.exe` / `rustc.exe` 是否还在。

## PIT-019 临时产物散落在仓库根 ⇒ `git status` 噪声 — 已归档（2026-09-23）
- 要点: 中间文件一律 `tmp\`，收尾 `rmdir /s /q tmp`；自检 `git status --porcelain` 除真实改动外不应有 `??`。详情: `archive/pitfalls-archive.md`
- 复发 2026-09-23（cedinia 迁移任务，同一个错）: 排查脚本时把 `findstr` 结果重定向到**仓库根**的 `build_logs_scan.txt`，
  `git status` 里立刻多出一条 `?? build_logs_scan.txt` ⇒ 当场删除并改成 `> tmp\out.txt`。临时文件优先顺序：先建 `tmp\` 再执行命令。

## PIT-020 上一轮构建窗口还停在 `timeout 60` 时启动第二轮 ⇒ 并发构建
- 现象: 两个构建抢 `target\` 与根目录 APK，版本号连跳，日志分散难辨认（`build.bat:1136` 收尾有 `timeout /t 60`）。
- 正确做法: 重跑前 `tasklist /fi "imagename eq cargo.exe"` + `dir /tw build` 确认真空。
- 反例: 失败后马上原地重跑，再对上一轮的日志/退出码下结论。
- 自检: 新构建 10 秒内出现**新的日志时间**（`build\logs\gh-release_*.log` 直接看文件名）；同时只有一个编译进程。

## PIT-021 日志 / 临时产物放在会被 clean 清掉的地方
- 现象: 日志写到 `build\`，而 `clean.bat:254-267`（`:clean_logs`）直接 `rmdir /s /q build` ⇒ 历史日志整批消失；
  `build.bat:889`（`:clean`）只删 `build_full.log` / `build_exit.log`，**删不到** `build\logs\` ⇒ 两个清理入口的覆盖面不一致。
  占用中的日志删不掉时，`clean.bat:262-264` 只提示"下次清理时删除"。
- 正确做法: 排查前先确认日志还在（`dir /b build\logs`）；要留证据就复制进 `tmp\`（`tmp\` 不在 `build\` 下）；
  先跑 `ISSUE-001` 的判据确认 tee 链路没坏，再怀疑"日志缺一段"。
- 反例: 看到日志缺一段就怀疑"日志链路又坏了"。
- 自检: `findstr /c:"Unable to delete" build\*.log`；跑一次 `clean.bat` 后 `build\logs\` 是否已消失。

## PIT-023 `cmd /c ""C:\Program Files\...\x.exe" ..."` 吞引号 ⇒ `'C:\Program' is not recognized`
- 触发条件: 批处理里写 `for /f ... in ('cmd /c ""%EXE%" --version | findstr ..."')`；
  现象: 日志出现 `'C:\Program' is not recognized`。
- **cedinia 具体形态**: gh 装在 `C:\Program Files\GitHub CLI\gh.exe`（路径带空格），
  `build.bat:91-95` 与 `gh-release.bat` 都用「`where gh` → 退回 `%ProgramFiles%\GitHub CLI\gh.exe`」定位。
- 正确做法: 直接 `"%GH_EXE%" --version`；要取输出用 usebackq：``for /f "usebackq delims=" %%i in (`"%GH_EXE%" api ...`) do ...``
  （`gh-release.bat` 的 `:tag_check_try` / `:drop_same_asset` 就是这个写法）。
- 反例: `for /f %%i in ('cmd /c ""%GH_EXE%" --version"') do ...`　自检: 日志里不出现 `is not recognized`。

## PIT-024 同一行 `if ... ( ) else ( )` 之后接 `& 命令` ⇒ 后面的命令根本不执行
- 触发条件: 把 `cmd > out 2>&1 & if errorlevel 1 (echo A) else (echo B) & 下一条 > out2` 挤在一行。
- 现象: `out` 写对了，`out2` **文件都不存在**（不是内容错，是压根没跑）。
- 正确做法: `if/else` 单独占行（或用 `goto` 分流）；一行里只留无分支的 `&` 链。
- 自检: 链上每个产物文件是否都生成；缺一个就拆行（别据此以为"命令失败了"）。

## PIT-025 批处理里调另一个 `.bat` 必须 `call`；抽段测试的起点要用「标签行」
- 触发条件: ①`.bat` 里直接写 `other.bat`（不带 `call`）；②用"从某标签切到文件尾"的方式抽子过程去测。
- 现象: ①子批的 `exit /b` 会**顶替父批上下文** ⇒ 父批后续行一行都不执行（静默"跑一半"）；
  ②`IndexOf(':check_gh')` 命中主流程里的 `call :check_gh`，抽出来的是**主流程本体** ⇒ 测试把真实脚本整套跑了一遍，
  当时误建并推送了真实 tag（源仓库事故见 `ISSUE-006`）。
- 正确做法: ①`call "x.bat"`；②抽取用 `(?m)^:check_gh\s*$` 定位，并断言「首行 = 该标签」「正文不含主流程标志」；
  ③测试环境把假 `git` / 假 `gh` 放 PATH 最前，假 git 的 `tag` / `push` 一律失败兜底。
- 反例: 以为「`exit /b 1` 会正常返回父批」；以为「抽段测试只是文本切片，不会执行真流程」。
- 自检: 测试输出里出现主流程标志（`[2/6]` / `Updated tag` / `推送 `）⇒ 主流程被跑，立刻停手查抽取起点。

## PIT-026 `.bat` + `chcp 65001`：头部**中文注释**会被错解析 ⇒ 行错位、注释片段当命令执行
- 触发条件: UTF-8（无 BOM）`.bat` 且前段有中文 / 全角注释；在**新控制台**（起始代码页 936：双击、`start "" /min cmd /c`）运行。
- 现象: 输出顶部冒出 `'EM' is not recognized` / `'…长头部注释块。' is not recognized` 这类垃圾报错；脚本大体还能跑，
  但**被带偏的下一行可能整行失效**。
- 正确做法: ①**根治 = 脚本开头自我重启一次**：`chcp 65001 > nul` 之后写
  `if defined _CED_GH_RELAUNCH goto :gh_relaunched` → `set "_CED_GH_RELAUNCH=1"` →
  `cmd /d /s /c ""%~f0" %*"` → `set "_CED_GH_RC=%ERRORLEVEL%"` → `exit /b %_CED_GH_RC%`
  —— 新 cmd 的起始代码页已是 65001，整个文件从第 0 字节起按 UTF-8 解析（`gh-release.bat` 用这招）；
  `build.bat` / `clean.bat` 靠"父进程先用 PowerShell 把控制台设成 UTF-8 再起子 cmd"（`build.bat:11-15`），效果等价；
  ②兜底（不自我重启时）: 重启块之前的 `REM` 注释保持 ASCII；注释里不要出现 `> < & | ^ %`
  （`REM a > b` 会创建文件、`REM a & b` 会执行 `b`，`PIT-006` 同族）；
  ③把 `chcp 65001` 挪到第 1 行**没用**。
- 反例: 以为"有 `chcp 65001` 就没事"；把垃圾报错当成"脚本逻辑坏了 / 命令失败"。
- 自检: 用**新控制台**跑只读模式 `start "" /min cmd /c "gh-release.bat check > tmp\x.out 2>&1"`，
  输出顶部不应出现任何 `is not recognized`；注释行扫描 `rem_bad=0`（临时 ps1：非 ASCII 或 `> < & | ^ %` 计数）。

## PIT-027 `gh release upload --clobber` 会漏删同名资产 ⇒ HTTP 422 `ReleaseAsset.name already exists`
- 触发条件: Release 里已经有同名 APK（尤其是上一次上传中途 TLS 超时 / 中断过），再次 `release upload --clobber`。
- 现象: `HTTP 422: Validation Failed (.../assets?label=&name=xxx.apk)` + `ReleaseAsset.name already exists`；
  此时 `gh release view --json assets` 可能返回**空列表**（`--clobber` 正是靠它找旧资产）—— 但 `gh api .../releases/<id>/assets` 能查到那条已 uploaded 的资产。
- 正确做法: 别信 gh 的资产列表，走 REST：`gh api "repos/<repo>/releases/tags/<tag>" --jq .id` 取 release id →
  `gh api "repos/<repo>/releases/<id>/assets?per_page=100" --jq ".[].id"` 列资产 id →
  逐个 `gh api "repos/<repo>/releases/assets/<id>" --jq .name` 比对文件名，命中即
  `gh api -X DELETE "repos/<repo>/releases/assets/<id>"`，最后再 `release upload --clobber`。
  cedinia 已落到 `gh-release.bat`（`:drop_same_asset`）。
- 反例: 以为"`--clobber` 一定覆盖成功"；把 422 当成"权限 / 标签不存在"。
- 自检: 同一版本**连跑两次** `gh-release.bat`，第二次不应再出现 422。

## PIT-028 Cline 的读取有上限，超了会**中间截断**（首尾保留）⇒ 大文件必须分段读
- 触发条件: `read_files` 读 >2000 行 / ~47k 字符的文件（本仓库 `build.bat` 1137 行、`gh-release.bat` ~420 行）；
  终端命令输出 >~48k 字符（`PIT-008` 同一族）。　首次记录: 2026-09-23（cedinia 迁移任务）
- 现象: 结果里出现 `...[truncated N chars]...` —— **中间那段代码看不到**。本仓库实例：
  `read_files build.bat`（420-800 行）中间丢了 8048 字符，一次读 `gh-release.bat` 丢了 10077 字符；
  若没注意到标记，会得出"文件里没有这段逻辑"的错误结论（`PIT-017` 的翻版）。
- 正确做法: ①按行区间分段读（`start_line` / `end_line`），每段 200~400 行；②看到 `truncated` 就补读被吞的区间；
  ③终端输出先 `> tmp\out.txt` 落地再读，生成侧能用 `findstr` / `Select-String` 过滤就先过滤。
- 反例: 一次读完整个 `build.bat` 就宣称"已通读全仓库脚本"。
- 自检: 读到的区间是否与文件总行数拼得上（`find /c /v "" <file>` 拿总行数）。
