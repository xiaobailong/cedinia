@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion

REM ============================================
REM  Log tee: restart self via PowerShell so all
REM  output goes to both console and clean_full.log
REM ============================================
if "%~1" NEQ "--log" (
    if not exist "%~dp0build" mkdir "%~dp0build" 2>nul
    powershell -NoProfile -Command ^
        "$OutputEncoding = [Console]::OutputEncoding = [Console]::InputEncoding = [Text.Encoding]::UTF8; " ^
        "$utf8NoBom = [Text.UTF8Encoding]::new($false); " ^
        "$sw = [System.IO.StreamWriter]::new('%~dp0build\clean_full.log', $false, $utf8NoBom); $sw.AutoFlush = $true; " ^
        "try { cmd /c '%~f0 --log %*' 2>&1 | ForEach-Object { Write-Host $_; $sw.WriteLine($_) } } finally { $sw.Close() }"
    exit /b
) else (
    shift
)

title Cedinia Clean

REM ============================================
REM  Cedinia 构建产物清理脚本
REM  用法: 双击运行            (标准清理)
REM        clean all            (深度清理，含 Gradle 缓存)
REM        clean rust           (仅清理 Rust 编译产物)
REM        clean android        (仅清理 Android 构建产物)
REM        clean logs           (仅清理日志文件)
REM ============================================

REM ---- 全局状态变量 ----
set "CLEAN_FAILED=0"
set "TOTAL_FREED=0"

REM ---- 切换到项目根目录 ----
cd /d "%~dp0"
if %ERRORLEVEL% neq 0 (
    echo [错误] 无法切换到项目目录: %~dp0
    pause
    exit /b 1
)

REM ---- 路由到具体任务 ----
if /i "%~1"=="all"     goto :deep_clean
if /i "%~1"=="rust"    goto :clean_rust
if /i "%~1"=="android" goto :clean_android
if /i "%~1"=="logs"    goto :clean_logs
goto :standard_clean

REM ============================================
REM  标准清理（保留 Gradle 缓存，加快后续构建）
REM ============================================
:standard_clean
echo.
echo ============================================
echo  Cedinia 标准清理 - %date% %time%
echo ============================================

call :clean_rust
call :clean_android_build
call :clean_output_files
call :clean_logs
call :clean_temp

goto :summary

REM ============================================
REM  深度清理（含 Gradle 缓存、Cargo 注册表缓存）
REM ============================================
:deep_clean
echo.
echo ============================================
echo  Cedinia 深度清理 - %date% %time%
echo ============================================

call :clean_rust
call :clean_android_all
call :clean_output_files
call :clean_logs
call :clean_temp
call :clean_gradle_cache
call :clean_cargo_cache

echo.
echo [提示] 深度清理后，下次构建将重新下载所有依赖，耗时较长。
goto :summary

REM ============================================
REM  清理 Rust 编译产物（保留 target/release/）
REM ============================================
:clean_rust
echo.
echo [Rust] 清理编译产物（保留 target/release/）...

set "DEBUG_DIR=target\debug"
set "TARGET_DIR=target"

if exist "%DEBUG_DIR%" (
    call :get_dir_size "%DEBUG_DIR%"
    echo        target/debug/ 大小: !DIR_SIZE!
    rmdir /s /q "%DEBUG_DIR%" 2>nul
    if not exist "%DEBUG_DIR%" (
        echo        target/debug/ 已删除，释放约 !DIR_SIZE!
        call :add_freed "!DIR_BYTES!"
    ) else (
        echo        [警告] target/debug/ 部分文件无法删除，可能被占用
        set CLEAN_FAILED=1
    )
) else (
    echo        target/debug/ 不存在，跳过
)

REM 清理 release 下的临时目录，但保留编译产物和增量指纹
if exist "%TARGET_DIR%\release\examples" (
    rmdir /s /q "%TARGET_DIR%\release\examples" 2>nul
)
if exist "%TARGET_DIR%\release\incremental" (
    rmdir /s /q "%TARGET_DIR%\release\incremental" 2>nul
)
echo        target/release/ 编译产物已保留（含增量编译缓存）
goto :eof

REM ============================================
REM  清理 Android 构建产物（保留 Gradle 缓存）
REM ============================================
:clean_android_build
echo.
echo [Android] 清理构建产物...

set "ANDROID_BUILD=android\app\build"
if exist "%ANDROID_BUILD%" (
    call :get_dir_size "%ANDROID_BUILD%"
    echo        android\app\build\ 大小: !DIR_SIZE!
    rmdir /s /q "%ANDROID_BUILD%" 2>nul
    if not exist "%ANDROID_BUILD%" (
        echo        android\app\build\ 已删除
        call :add_freed "!DIR_BYTES!"
    )
) else (
    echo        android\app\build\ 不存在，跳过
)

set "ANDROID_BUILD_ROOT=android\build"
if exist "%ANDROID_BUILD_ROOT%" (
    call :get_dir_size "%ANDROID_BUILD_ROOT%"
    rmdir /s /q "%ANDROID_BUILD_ROOT%" 2>nul
    echo        android\build\ 已删除
    call :add_freed "!DIR_BYTES!"
)
goto :eof

REM ============================================
REM  清理 Android 所有产物（含 Gradle 缓存）
REM ============================================
:clean_android_all
echo.
echo [Android] 清理所有产物（含 Gradle 缓存）...

call :clean_android_build

set "GRADLE_DIR=android\.gradle"
if exist "%GRADLE_DIR%" (
    call :get_dir_size "%GRADLE_DIR%"
    rmdir /s /q "%GRADLE_DIR%" 2>nul
    echo        android\.gradle\ 已删除
    call :add_freed "!DIR_BYTES!"
)

REM .kotlin 目录
set "KOTLIN_DIR=android\.kotlin"
if exist "%KOTLIN_DIR%" (
    rmdir /s /q "%KOTLIN_DIR%" 2>nul
    echo        android\.kotlin\ 已删除
)

REM local.properties (自动生成的)
if exist "android\local.properties" (
    del /q "android\local.properties" 2>nul
    echo        android\local.properties 已删除
)
goto :eof

REM ============================================
REM  清理输出文件 (APK/AAB)
REM ============================================
:clean_output_files
echo.
echo [产物] 清理输出文件...

set "FOUND_OUTPUT=0"
for %%f in (cedinia-*.apk cedinia-*.aab *.apk *.aab) do (
    if exist "%%f" (
        for %%i in ("%%f") do echo        删除 %%~nxi  (%%~zi bytes)
        del /q "%%f" 2>nul
        set "FOUND_OUTPUT=1"
    )
)
if "!FOUND_OUTPUT!"=="0" (
    echo        未找到 APK/AAB 输出文件
)
goto :eof

REM ============================================
REM  清理日志文件
REM ============================================
:clean_logs
echo.
echo [日志] 清理日志文件...

set "LOG_DIR=build"
if exist "%LOG_DIR%" (
    call :get_dir_size "%LOG_DIR%"
    rmdir /s /q "%LOG_DIR%" 2>nul
    echo        build\ (日志目录) 已删除
    call :add_freed "!DIR_BYTES!"
) else (
    echo        build\ 不存在，跳过
)
goto :eof

REM ============================================
REM  清理临时文件
REM ============================================
:clean_temp
echo.
echo [临时] 清理临时文件...

REM .cargo 配置备份
if exist ".cargo\config.toml.bak" (
    del /q ".cargo\config.toml.bak" 2>nul
    echo        .cargo\config.toml.bak 已删除
)

REM cargo apk 可能残留的 unaligned APK
for /r "target" %%f in (*.apk.unaligned) do (
    del /q "%%f" 2>nul
    echo        %%f 已删除
) 2>nul

REM Rust analyzer 缓存
if exist "%USERPROFILE%\.rustup\toolchains" (
    echo        [跳过] Rust 工具链（非构建产物）
)
goto :eof

REM ============================================
REM  清理全局 Gradle 缓存
REM ============================================
:clean_gradle_cache
echo.
echo [Gradle] 清理全局 Gradle 缓存...

set "GRADLE_CACHE=%USERPROFILE%\.gradle\caches"
if exist "%GRADLE_CACHE%" (
    call :get_dir_size "%GRADLE_CACHE%"

    REM 清理构建缓存但保留 jdk 包装器
    for /d %%d in ("%GRADLE_CACHE%\build-cache-*") do (
        rmdir /s /q "%%d" 2>nul
    )
    rmdir /s /q "%GRADLE_CACHE%\transforms-*" 2>nul
    rmdir /s /q "%GRADLE_CACHE%\journal-*" 2>nul

    echo        Gradle 缓存已清理，释放约 !DIR_SIZE!
    call :add_freed "!DIR_BYTES!"
) else (
    echo        Gradle 缓存不存在，跳过
)
goto :eof

REM ============================================
REM  清理 Cargo 注册表缓存（谨慎使用）
REM ============================================
:clean_cargo_cache
echo.
echo [Cargo] 清理 Cargo 缓存...

set "CARGO_REGISTRY=%USERPROFILE%\.cargo\registry\cache"
if exist "%CARGO_REGISTRY%" (
    call :get_dir_size "%CARGO_REGISTRY%"
    rmdir /s /q "%CARGO_REGISTRY%" 2>nul
    echo        Cargo registry cache 已清理，释放约 !DIR_SIZE!
    call :add_freed "!DIR_BYTES!"
)

set "CARGO_GIT=%USERPROFILE%\.cargo\git\db"
if exist "%CARGO_GIT%" (
    call :get_dir_size "%CARGO_GIT%"
    rmdir /s /q "%CARGO_GIT%" 2>nul
    echo        Cargo git cache 已清理
    call :add_freed "!DIR_BYTES!"
)
goto :eof

REM ============================================
REM  获取目录大小（设置 DIR_SIZE 和 DIR_BYTES）
REM ============================================
:get_dir_size
set "DIR_SIZE="
set "DIR_BYTES=0"
for /f "tokens=3" %%b in ('dir /s /-c "%~1" 2^>nul ^| findstr /i "File(s)"') do (
    set "DIR_BYTES=%%b"
)
REM 转换为可读格式
set "DIR_SIZE=!DIR_BYTES! bytes"
if !DIR_BYTES! geq 1073741824 (
    set /a "GB=!DIR_BYTES!/1073741824"
    set "DIR_SIZE=!GB! GB"
) else if !DIR_BYTES! geq 1048576 (
    set /a "MB=!DIR_BYTES!/1048576"
    set "DIR_SIZE=!MB! MB"
) else if !DIR_BYTES! geq 1024 (
    set /a "KB=!DIR_BYTES!/1024"
    set "DIR_SIZE=!KB! KB"
)
goto :eof

REM ============================================
REM  累加释放空间
REM ============================================
:add_freed
set /a "TOTAL_FREED=%TOTAL_FREED% + %~1" 2>nul
goto :eof

REM ============================================
REM  清理汇总
REM ============================================
:summary
echo.
echo ============================================
echo  清理完成 - %date% %time%
echo ============================================
if %TOTAL_FREED% geq 1073741824 (
    set /a "GB=%TOTAL_FREED%/1073741824"
    echo  本次释放约 !GB! GB 磁盘空间
) else if %TOTAL_FREED% geq 1048576 (
    set /a "MB=%TOTAL_FREED%/1048576"
    echo  本次释放约 !MB! MB 磁盘空间
) else if %TOTAL_FREED% geq 1024 (
    set /a "KB=%TOTAL_FREED%/1024"
    echo  本次释放约 !KB! KB 磁盘空间
) else (
    echo  无需清理或暂无可清理产物
)

if "!CLEAN_FAILED!"=="1" (
    echo.
    echo  [警告] 部分文件清理失败，可能被其他程序占用。
    echo        请关闭 IDE / 模拟器后重试。
)
echo.
echo 窗口将在 30 秒后自动关闭，或按任意键立即关闭...
timeout /t 30 > nul
exit /b %CLEAN_FAILED%