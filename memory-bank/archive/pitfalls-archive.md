# archive / pitfalls-archive.md（**默认不读**）

> 由 `pitfalls.md` 归档的原文（按时间倒序追加）。归档时逐字搬，不改编号、不删「正确做法 / 反例」。

## PIT-026 `.bat` + `chcp 65001`：头部**中文注释**会被错解析 ⇒ 行错位、注释片段当命令执行
【归档 2026-09-23，超限移出（仍是钉子条目），原文】
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



## PIT-021 【已复现 2026-09-23】日志在 `build\logs\`，而流程第 2 步 `gradle clean` 会删 `build\`
【归档 2026-09-23，超限移出（仍是钉子条目），原文】
- 已复现证据: `build\logs\build_20260922_231449.log:22-31` 报 `Unable to delete directory ... build\logs\build_<ts>.log`；
  同一轮 `clean` 把历史日志全删（`dir /b build\logs` 只剩被占用的那 1 个）⇒ 排查时几乎没有历史日志（钉这一条）。
- 现象（预期）: 被重定向占用的日志文件删不掉 ⇒ `gradle clean` 可能报删除失败；脚本**不检查**该步退出码
  （`build.bat:115-117`）⇒ 静默通过，表现为“日志缺一段”。
- 正确做法: 先看 `[2/5] 清理旧产物` 前后是否完整；彻底避免就把日志移出 `build\`。
- 反例: 看到日志缺一段就怀疑“日志链路又坏了”（先跑 `ISSUE-001` 判据）。
- 自检: `findstr /c:"Unable to delete" build\logs\*.log`　备注: 复现后升级为 `ISSUE-nnn` 并回填证据。


## PIT-019 临时产物散落在仓库根 ⇒ `git status` 噪声
【归档 2026-09-23，原文】
- 正确做法: 中间文件一律 `tmp\`（`mkdir tmp 2>nul`）；收尾 `rmdir /s /q tmp`（或 `clean.bat` / `build.bat clean`）。
- 反例: 把 `> out.txt`、临时 ps1 写在仓库根"用完删"（常忘删；重名还覆盖上次证据）。
- 自检: `git status --porcelain` 除真实改动外**不应有 `??`**。

## PIT-017 检索手段实测：`search_codebase` 常超时、`findstr` 搜中文不可靠
【归档 2026-09-23，原文】
- 现象: `search_codebase` 多次 30s 超时；`findstr` 搜中文**假阴性**（确有该词却零命中），对 `\` `"` 也挑。
- 正确做法: 优先 `read_files`；批量过滤用 `powershell -File` + `Select-String -Encoding UTF8`；纯英文短串再用 `findstr`。
- 反例: 零命中就下结论"没有"。　- 自检: 用"已知一定存在"的词做正控。

## PIT-016 同一个输出文件反复写入时，可能只读到旧内容
【归档 2026-09-23，原文】
- 现象: 读到上一轮内容，或 `dir` 显示 0 字节而 `type` 有内容 ⇒ 误判"命令没跑 / 构建卡住"。
- 正确做法: 每轮换文件名或先 `del`；判断"还在跑"看 `dir /tw build\logs`（本项目日志名带时间戳）
  + `tasklist /fi "imagename eq java.exe"`。
- 反例: 一直用 `tmp\out.txt`；靠读长日志尾部判断进度；`read_files` 读到空就断定失败。
- 自检: 内容是否与刚跑的步骤匹配；再看 `dir /tw` 的 size / mtime。

## PIT-012 别用「管道 + PowerShell 逐行追写」给构建做日志
【归档 2026-09-23，原文】
- 触发条件: 想"控制台看得到 + 写进文件"（tee 思路）。
- 现象: 本项目事故（`ISSUE-001` 第 2、3 层）：`2>&1 | powershell -Command "... Out-File -Append ..."`
  受 cmd 解析期展开影响（`PIT-007`）、长 `-Command` 可能被拦（`PIT-001`）；换 `_logpath.tmp` + `Add-Content`
  **依然丢内容**并留下残留文件。
- 正确做法: `call "%~f0" %* 1>> "%_CM_LOGFILE%" 2>&1` + 紧邻 `set _CM_BUILD_RESULT=%ERRORLEVEL%`，
  父进程 `type` 回显（过程见 `archive/issues-solved-archive.md`）。
- 反例: 管道 tee、"临时文件带路径"传参。
- 自检: 日志首行 + 末尾"日志已保存"都在，中间步骤完整。

## PIT-003 PowerShell 嵌套数组会被展平 ⇒ `@(@('a','b'))` 里 `$pair[0]` 取出的是**字符**
【归档 2026-09-23，原文】
- 现象: 内层数组展平成字符串序列 ⇒ 变成**按单字符全局替换**（源仓库真实事故：把所有 `-` 换成 `F`，文件全废）。
- 正确做法: 每个替换用两个独立 `[string]` 参数，一次调用只做一对替换。
- 反例: `@(@('a','b'), @('c','d'))` 传进 `-Pairs`；`foreach ($p in $pairs) { $p[0] }`
- 自检: 替换完**逐行看 `git diff`**；出现"某字符被大面积替换"立刻 `git checkout -- <路径>`（`PIT-014`）。

## PIT-004 替换文本包含查找文本时，绝不能 `while`/反复 `Replace`
【归档 2026-09-23，原文】
- 触发条件: 例如把 `gradle.bat` 替换成 `D:\...\gradle-8.5\bin\gradle.bat`（新串含旧串）。
- 现象: 路径段重复（`bin\...\bin\...`）或死循环。
- 正确做法: **单次** `$text.Replace($old, $new)`；先 `Contains` 判空。
- 反例: `while ($text.Contains($old)) { $text = $text.Replace($old, $new) }`
- 自检: grep 目标文件是否出现 `bin\...\bin\` / `scripts\scripts\` 这类重复路径段。

## PIT-005 `echo` 里带半角括号且写在 `if (...)` 块内 → `)` 提前闭合批处理
【归档 2026-09-23，原文】
- 现象: `: was unexpected at this time.`，批处理"只跑一半就退出"。
- 正确做法: `^(` `^)` 转义（`&` 写成 `^&`）—— 本项目实例：`echo [错误] GitHub CLI ^(gh^) 未安装！`、
  `echo  构建 ^& 发布成功！`
- 反例: `( ... echo 检查未完全成功 (exit=%X%) ... )`
- 自检: 批处理是否中途退出、有无 `unexpected at this time`。

## PIT-006 `echo` 里的 `>` 要转义；`%ERRORLEVEL%>> file` 相邻会吞内容
【归档 2026-09-23，原文】
- 现象: 提示里的 `>` 被当成重定向；`echo RC=%ERRORLEVEL%>> f.txt` 只留下一行空行。
- 正确做法: 转义 `^>`；退出码先存变量再写（本项目：`set BUILD_EXIT=%ERRORLEVEL%` /
  `set _CM_BUILD_RESULT=%ERRORLEVEL%`），或把 `>>` 挪到行首。
- 反例: `echo RC=%ERRORLEVEL%>> f.txt`
- 自检: 文件里该出现的行是否真的出现。

## PIT-014 批量改动改坏了怎么救：`git checkout -- <路径>` 从 index 还原
【归档 2026-09-23，原文】
- 正确做法: `git checkout -- build.bat version.properties`（从 **index** 还原工作区）；
  `git ls-files -s <路径>` 拿索引 blob 哈希对照确认。
- 反例: 逐个文件手工撤销；`git checkout HEAD -- .`（会连别处未提交的工作一起丢）。
- 自检: 还原后 `git diff --numstat <路径>` 应为空。

## PIT-015 诊断产物 / 交接文档不要放 `build\`
【归档 2026-09-23，原文】
- 现象: `clean.bat`（`rmdir /s /q build`）、`build.bat clean`、`build.bat` 第 2 步的 `gradle clean`
  都会清 `build\` ⇒ 文档/脚本一起消失。
- 正确做法: 要留存的进 `memory-bank\` 或 `docs\HANDOFF-*.md`（自建并把 `docs/` 加进 `.gitignore`）；
  纯临时放 `tmp\`。构建日志留 `build\logs\` 是对的（`build.bat` 自己写、clean 负责清）。
- 反例: 把交接文档写在 `build\` 下。
- 自检: 跑完 `build.bat clean` / `clean.bat` 后文件还在不在。
