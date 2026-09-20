@echo off
chcp 65001 > nul 2>&1
setlocal enabledelayedexpansion

REM ============================================
REM  Log tee: restart self via PowerShell so all
REM  output goes to both console and build_full.log
REM ============================================
if "%~1" NEQ "--log" (
    if not exist "%~dp0build" mkdir "%~dp0build" 2>nul
    powershell -NoProfile -Command ^
        "$OutputEncoding = [Console]::OutputEncoding = [Console]::InputEncoding = [Text.Encoding]::UTF8; " ^
        "$utf8NoBom = [Text.UTF8Encoding]::new($false); " ^
        "$sw = [System.IO.StreamWriter]::new('%~dp0build\build_full.log', $false, $utf8NoBom); $sw.AutoFlush = $true; " ^
        "try { cmd /c '%~f0 --log %*' 2>&1 | ForEach-Object { Write-Host $_; $sw.WriteLine($_) } } finally { $sw.Close() }"
    exit /b
) else (
    shift
)

title Cedinia Build

REM ============================================
REM  Cedinia 一键构建脚本
REM  用法: 双击运行            (完整 Desktop Release 构建)
REM        build android        (构建 Android APK/AAB)
REM        build android-debug  (构建 Android Debug APK)
REM        build clean          (清理构建产物)
REM        build check          (仅检查构建环境)
REM ============================================

REM ---- 全局状态变量 ----
set "BUILD_FAILED=0"
set "STEP_NAME="

REM ---- 环境配置（按实际路径修改） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_NDK_HOME=%ANDROID_HOME%\ndk\27.2.12479018"

REM ---- Rust 便携版路径（绿色免安装，可随 U 盘迁移） ----
REM     下载 rust-{version}-x86_64-pc-windows-msvc.tar.xz
REM     解压后运行 install.ps1（或用 7-Zip 解压所有子包到同一目录）
REM     将最终目录路径填到下方即可
set "RUST_PORTABLE=D:\Tools\DevTools\rust"
set "CARGO_HOME=%RUST_PORTABLE%\cargo_home"

REM ---- 代理检测（Clash 默认端口 7890） ----
set "PROXY_HOST="
set "PROXY_PORT="
set "PROXY_AVAILABLE=0"
netstat -ano 2>nul | findstr /r "127\.0\.0\.1:7890.*LISTENING" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PROXY_HOST=127.0.0.1"
    set "PROXY_PORT=7890"
    set "PROXY_AVAILABLE=1"
)
if "%PROXY_AVAILABLE%"=="1" (
    set "HTTP_PROXY=http://%PROXY_HOST%:%PROXY_PORT%"
    set "HTTPS_PROXY=http://%PROXY_HOST%:%PROXY_PORT%"
)

REM 不合并方案：各组件的 bin 目录分别加入 PATH
set "PATH=%JAVA_HOME%\bin;%RUST_PORTABLE%\rustc\bin;%RUST_PORTABLE%\cargo\bin;%RUST_PORTABLE%\rustfmt-preview\bin;%RUST_PORTABLE%\rust-analyzer-preview\bin;%RUST_PORTABLE%\clippy-preview\bin;%RUST_PORTABLE%\llvm-tools-preview\bin;%CARGO_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM ---- 切换到项目根目录 ----
cd /d "%~dp0"
if %ERRORLEVEL% neq 0 (
    echo [错误] 无法切换到项目目录: %~dp0
    set BUILD_FAILED=1
    goto :end
)

REM ---- 确保根路径 build 目录存在 ----
if not exist "build" mkdir "build" 2>nul

REM ---- 路由到具体任务 ----
if /i "%~1"=="android"       goto :android_build
if /i "%~1"=="android-debug" goto :android_debug_build
if /i "%~1"=="clean"         goto :clean
if /i "%~1"=="check"         goto :check_only
goto :desktop_build

REM ============================================
REM  统一错误处理入口：捕获错误后跳转此处
REM ============================================
:on_error
echo.
echo ============================================
echo  [错误] !STEP_NAME! 执行失败！
echo ============================================
set BUILD_FAILED=1
goto :end

REM ============================================
REM  环境检查
REM ============================================
:checkenv
echo.
echo ============================================
echo  检查构建环境...
echo ============================================

REM ---- 检查 Rust ----
where rustc >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 Rust（rustc）。
    echo.
    echo        便携版方案（免安装，换电脑直接拷贝）：
    echo          1. 下载 rust-{version}-x86_64-pc-windows-msvc.tar.xz
    echo             地址: https://static.rust-lang.org/dist/
    echo          2. 用 7-Zip 解压 tar.xz，再次解压得到各组件目录
    echo             目录结构: rustc/  cargo/  rust-std-x86_64-pc-windows-msvc/ 等
    echo          3. 将所有组件目录的内容合并到一个目录（如 rust\）
    echo             最终 bin\ 下应包含: rustc.exe  cargo.exe  rustdoc.exe
    echo          4. 修改本脚本 RUST_PORTABLE 变量指向该目录
    echo.
    echo        当前 RUST_PORTABLE 指向: %RUST_PORTABLE%
    set BUILD_FAILED=1
    goto :eof
)
for /f "tokens=2" %%v in ('rustc --version 2^>^&1') do (
    echo        Rust: %%v
)

where cargo >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [错误] 未找到 Cargo。
    set BUILD_FAILED=1
    goto :eof
)
for /f "tokens=2" %%v in ('cargo --version 2^>^&1') do (
    echo        Cargo: %%v
)

REM ---- 检查 Rust 工具链版本是否符合项目要求 ----
set "REQUIRED_RUST=1.94.1"
for /f "tokens=2" %%v in ('rustc --version 2^>^&1') do set "RUST_VER=%%v"
echo        [Rust 最低要求] %REQUIRED_RUST%，当前: !RUST_VER!

REM ---- 检查 Android 目标平台 ----
if /i "%~1"=="android" (
    echo.
    echo        [Android] 检查 Android 构建环境...

    where java >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo [错误] 未找到 Java。Android 构建需要 JDK 17+。
        echo        下载地址: https://jdk.java.net/17/
        set BUILD_FAILED=1
        goto :eof
    )
    for /f "tokens=3" %%v in ('java -version 2^>^&1 ^| findstr /i "version"') do (
        echo        Java: %%v
    )

    if not exist "%ANDROID_HOME%" (
        echo [错误] Android SDK 未找到: %ANDROID_HOME%
        echo        下载 Android Studio: https://developer.android.com/studio
        set BUILD_FAILED=1
        goto :eof
    )
    echo        Android SDK: %ANDROID_HOME%

    if not exist "%ANDROID_NDK_HOME%" (
        echo [警告] Android NDK 未找到: %ANDROID_NDK_HOME%
        echo        请通过 sdkmanager 安装 NDK 27.2
    ) else (
        echo        Android NDK: %ANDROID_NDK_HOME%
    )

    REM ---- 检查 Android Rust targets ----
    rustup target list --installed 2>nul | findstr "aarch64-linux-android" >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo [警告] 未安装 aarch64-linux-android 目标，尝试安装...
        rustup target add aarch64-linux-android
        if %ERRORLEVEL% neq 0 (
            echo [错误] 无法安装 Android Rust target
            set BUILD_FAILED=1
            goto :eof
        )
    )
    echo        [Rust Target] aarch64-linux-android 已就绪

    REM ---- 检查 cargo-apk ----
    where cargo-apk >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo [警告] 未找到 cargo-apk，尝试安装...
        cargo install cargo-apk
        if %ERRORLEVEL% neq 0 (
            echo [错误] 无法安装 cargo-apk
            set BUILD_FAILED=1
            goto :eof
        )
    )
    echo        cargo-apk 已就绪
)

REM ---- 代理信息 ----
if "%PROXY_AVAILABLE%"=="1" (
    echo        [代理] Clash 代理已启用: %PROXY_HOST%:%PROXY_PORT%
) else (
    echo        [代理] 未检测到代理，将直连下载
)

goto :eof

REM ============================================
REM  仅环境检查，然后退出
REM ============================================
:check_only
call :checkenv desktop
goto :end

REM ============================================
REM  配置 Gradle 使用代理（动态写入 gradle.properties）
REM ============================================
:config_gradle_proxy
set "GRADLE_PROPS=android\gradle.properties"

REM 移除旧的代理配置（如果有）
if exist "%GRADLE_PROPS%" (
    powershell -NoProfile -Command ^
        "$lines = Get-Content '%GRADLE_PROPS%' -Encoding UTF8 | Where-Object { $_ -notmatch '^systemProp\.(http|https)\.proxy' }; " ^
        "[IO.File]::WriteAllLines((Resolve-Path '%GRADLE_PROPS%').Path, $lines, (New-Object Text.UTF8Encoding($false)))" 2>nul
)

if "%PROXY_AVAILABLE%"=="1" (
    echo.
    echo [代理] 配置 Gradle 代理: %PROXY_HOST%:%PROXY_PORT%
    echo systemProp.http.proxyHost=%PROXY_HOST%>> "%GRADLE_PROPS%"
    echo systemProp.http.proxyPort=%PROXY_PORT%>> "%GRADLE_PROPS%"
    echo systemProp.https.proxyHost=%PROXY_HOST%>> "%GRADLE_PROPS%"
    echo systemProp.https.proxyPort=%PROXY_PORT%>> "%GRADLE_PROPS%"
)
goto :eof

REM ============================================
REM  清理构建产物
REM ============================================
:clean
echo.
echo ============================================
echo  清理构建产物（保留 target/release/ 和构建缓存）
echo ============================================
if exist "target\debug" rmdir /s /q "target\debug" 2>nul
if exist "target\release\examples" rmdir /s /q "target\release\examples" 2>nul
if exist "target\release\incremental" rmdir /s /q "target\release\incremental" 2>nul
if exist "cedinia-*.apk" del /q "cedinia-*.apk" 2>nul
if exist "*.aab" del /q "*.aab" 2>nul
rmdir /s /q "build\build_full.log" 2>nul
echo       清理完成（target/release/ 已保留）。
goto :end

REM ============================================
REM  Desktop Release 构建
REM ============================================
:desktop_build
echo.
echo ============================================
echo  Cedinia Desktop Release 构建 - %date% %time%
echo ============================================

call :checkenv desktop
if "%BUILD_FAILED%"=="1" goto :end

echo.
echo [1/2] cargo fetch（检查/下载依赖）...
echo       仅下载不编译，已缓存的依赖会直接跳过。

set "STEP_NAME=cargo fetch"
cargo fetch
if %ERRORLEVEL% neq 0 (
    set BUILD_FAILED=1
    goto :on_error
)

echo.
echo [2/2] cargo build --release...
echo       首次编译 Slint UI 可能需要 5-15 分钟...
echo.

set "STEP_NAME=cargo build --release"
cargo build --release
if %ERRORLEVEL% neq 0 (
    set BUILD_FAILED=1
    goto :on_error
)

echo.
echo ============================================
echo  Desktop 构建成功！
echo ============================================
if exist "target\release\cedinia.exe" (
    for %%f in ("target\release\cedinia.exe") do echo  产物: target\release\cedinia.exe  (%%~zf bytes)
) else (
    echo  产物: target\release\cedinia (或无扩展名可执行文件)
)
echo.
echo  运行方式: cargo run --release
goto :end

REM ============================================
REM  Android Debug 构建
REM ============================================
:android_debug_build
set "BUILD_MODE=debug"
set "CARGO_FLAGS="
set "GRADLE_TASK=bundleDebug"
goto :do_android_build

REM ============================================
REM  Android Release 构建
REM ============================================
:android_build
set "BUILD_MODE=release"
set "CARGO_FLAGS=--release"
set "GRADLE_TASK=bundleRelease"
goto :do_android_build

:do_android_build
echo.
echo ============================================
echo  Cedinia Android !BUILD_MODE! 构建 - %date% %time%
echo ============================================

call :checkenv android
if "%BUILD_FAILED%"=="1" goto :end

REM ---- 步骤1: cargo fetch ----
echo.
echo [1/4] cargo fetch（检查/下载依赖）...

set "STEP_NAME=cargo fetch"
cargo fetch
if %ERRORLEVEL% neq 0 (
    set BUILD_FAILED=1
    goto :on_error
)

REM ---- 步骤2: cargo apk 编译 ----
echo.
echo [2/4] cargo apk build !CARGO_FLAGS!...
echo       编译 Rust 原生库和 Java DEX（首次约 10-20 分钟）...
echo.

set "STEP_NAME=cargo apk build !CARGO_FLAGS!"
cargo apk build !CARGO_FLAGS!
if %ERRORLEVEL% neq 0 (
    set BUILD_FAILED=1
    goto :on_error
)
echo       cargo apk 编译完成。

REM ---- 步骤3: 复制 .so 到 Android jniLibs ----
echo.
echo [3/4] 复制原生库到 Android jniLibs...

REM cargo apk 将产物放在 target/debug/apk 或 target/release/apk
set "APK_BUILD_DIR=target\!BUILD_MODE!\apk"

REM 查找生成的 .so 文件并复制到 jniLibs
set "JNILIBS_DIR=android\app\src\main\jniLibs\arm64-v8a"
if not exist "!JNILIBS_DIR!" mkdir "!JNILIBS_DIR!" 2>nul

REM 尝试从 cargo apk 输出目录查找 .so
set "SO_FOUND=0"
for /r "!APK_BUILD_DIR!" %%f in (libcedinia.so) do (
    echo       从 %%f 复制...
    copy /y "%%f" "!JNILIBS_DIR!\libcedinia.so" > nul 2>&1
    set "SO_FOUND=1"
    goto :so_done
)

REM 如果上面没找到，尝试从 target 目录查找
:so_done
if "!SO_FOUND!"=="0" (
    for /r "target" %%f in (libcedinia.so) do (
        echo       从 %%f 复制...
        copy /y "%%f" "!JNILIBS_DIR!\libcedinia.so" > nul 2>&1
        set "SO_FOUND=1"
        goto :so_done2
    )
)
:so_done2

if "!SO_FOUND!"=="1" (
    echo       原生库已复制到 !JNILIBS_DIR!
) else (
    echo [警告] 未找到 libcedinia.so，尝试继续 Gradle 构建...
)

REM ---- 步骤4: Gradle 打包 AAB ----
echo.
echo [4/4] Gradle !GRADLE_TASK!...
echo       打包 Android App Bundle（首次需要下载 Gradle 依赖）...
echo.

call :config_gradle_proxy

set "STEP_NAME=Gradle !GRADLE_TASK!"
pushd android
call gradlew.bat !GRADLE_TASK!
set "GRADLE_EXIT=%ERRORLEVEL%"
popd

if !GRADLE_EXIT! neq 0 (
    echo [错误] Gradle 构建失败！
    set BUILD_FAILED=1
    goto :end
)

echo.
echo ============================================
echo  Android 构建成功！
echo ============================================

REM 查找产物
if /i "!BUILD_MODE!"=="release" (
    set "AAB_PATH=android\app\build\outputs\bundle\release\app-release.aab"
) else (
    set "AAB_PATH=android\app\build\outputs\bundle\debug\app-debug.aab"
)

if exist "!AAB_PATH!" (
    for %%f in ("!AAB_PATH!") do echo  AAB: %%~nxf  (%%~zf bytes)
    echo.
    echo  产物路径: !AAB_PATH!
) else (
    echo [提示] AAB 文件未在预期路径找到，请检查 android/app/build/outputs/
)

REM 也检查 APK
for /r "target\!BUILD_MODE!\apk" %%f in (*.apk) do (
    echo  APK: %%f  (%%~zf bytes)
)
goto :end

REM ============================================
REM  统一出口
REM ============================================
:end
echo %date% %time% BUILD_FAILED=%BUILD_FAILED% > build\build_exit.log 2>nul
echo.
echo ============================================
if "%BUILD_FAILED%"=="1" (
    echo  构建过程有错误，请查看上方日志。
    echo  完整日志: build\build_full.log
) else (
    echo  构建流程结束。
)
echo ============================================
echo.
echo 窗口将在 60 秒后自动关闭，或按任意键立即关闭...
timeout /t 60 > nul
exit /b %BUILD_FAILED%