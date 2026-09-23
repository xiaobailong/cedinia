# archive / issues-solved-archive.md（**默认不读**）

> 由 `issues-solved.md` 归档的原文。新增归档按时间倒序插在最前面。

## ISSUE-001 【归档于 2026-09-23】`build.bat` 构建日志写不进去 —— 三次连环修复的完整过程

- 状态: 已修复　首次记录: 2026-09-23
- 症状 / 现场: 双击/命令行跑 `build.bat`，控制台有输出，但 `build\logs\build_<yyyyMMdd_HHmmss>.log`
  只有首行、只有空行、或整段缺失；中途还出现过 `build\logs\_logpath.tmp` 这种临时文件残留。

### 第 1 层：括号块内 `%VAR%` 解析期展开为空（`d21ff87`）
原始写法（错）：
```bat
if not defined _CM_LOG_ACTIVE (
    set "_CM_LOG_ACTIVE=1"
    if not exist "build\logs" mkdir "build\logs"
    for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "_CM_LOG_TS=%%i"
    set "_CM_LOGFILE=build\logs\build_%_CM_LOG_TS%.log"
    echo [%_CM_LOG_TS%] ClipboardMerger Build Start > "%_CM_LOGFILE%"
    "%~f0" %* 2>&1 | powershell -NoProfile -Command "$input | ForEach-Object { $_ | Out-File -FilePath '%_CM_LOGFILE%' -Append -Encoding utf8; Write-Output $_ }"
    ...
)
```
整个块在解析期一次性展开 ⇒ 块内 `set` 之后再用的 `%_CM_LOG_TS%` / `%_CM_LOGFILE%` 仍是**空**：
首行变 `[] ClipboardMerger Build Start`、重定向目标变成空路径。
修法：改成 `if not defined _CM_LOG_ACTIVE goto :init_log` / `goto :skip_log`，用**标签块**替代括号块（见 `PIT-007`）。

### 第 2 层：管道 + `powershell -Command` 里的路径同样被预展开（`f9bc43c`）
`-Command "... -FilePath '%_CM_LOGFILE%' ..."` 里的 `%_CM_LOGFILE%` 由 cmd 在解析期展开（此时为空），
且本机对长 `-Command` 有拦截风险（`PIT-001`）。当时的绕法是把路径写进临时文件再读：
```bat
echo %_CM_LOGFILE%> "build\logs\_logpath.tmp"
"%~f0" %* 2>&1 | powershell -NoProfile -Command "$log = (Get-Content build\logs\_logpath.tmp -Raw).Trim(); ... Add-Content -Path $log -Value $_ -Encoding UTF8"
del "build\logs\_logpath.tmp" 2>nul
```
问题：这仍是"管道 + PowerShell 逐行追写"，还多一个残留文件（Windows 上还容易被别的进程锁住）。

### 第 3 层：管道 tee 本身丢内容 ⇒ 整条思路作废（`bccd4ca`）
最终改成**父进程重定向 + `call` 递归**，不再经过 PowerShell：
```bat
echo 正在构建，日志文件: %_CM_LOGFILE%
call "%~f0" %* 1>> "%_CM_LOGFILE%" 2>&1
set _CM_BUILD_RESULT=%ERRORLEVEL%
echo ============================================ >> "%_CM_LOGFILE%"
echo 日志已保存: %_CM_LOGFILE%
echo ----------------------------------------
type "%_CM_LOGFILE%"
echo ----------------------------------------
timeout /t 10 > nul
exit /b %_CM_BUILD_RESULT%
```
要点：①`call` 回来的**下一行**立刻取 `%ERRORLEVEL%`（否则被后续 `echo`/`type` 覆盖，见 `PIT-013`）；
②`_CM_LOG_ACTIVE` 环境变量是父子进程判别的关键，别改名；
③日志名带时间戳，天然每轮一换，避开"读到旧内容"（`PIT-016`）。

### 附带结论
- 首行 `[<ts>] ClipboardMerger Build Start` 用 PowerShell 写（UTF-8 **BOM**，便于编辑器识别中文），
  其余内容由 cmd 以 `chcp 65001` 追加（见 `PIT-002` 的编码约定）。
- 当时还考虑过"整体重写为 PowerShell 构建脚本"，因改动面太大放弃（`ADR-003` 的备选）。
