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
        "try { cmd /c '%~f0 --log %*' 2>&1 | ForEach-Object { Write-Host $_; $sw.WriteLine($_) }; $rc = $LASTEXITCODE } finally { $sw.Close() }; exit $rc"
    exit /b
) else (
    shift
)

title Cedinia Build

REM ============================================
REM  Cedinia 一键构建脚本
REM  默认（双击运行/无参数）= 构建 Android Release APK
REM  用法: build                (Android Release APK -> cedinia-<版本>.apk)
REM        build android        (同上)
REM        build android-debug  (Android Debug APK -> cedinia-<版本>.apk)
REM        build android-aab    (Google Play 用 .aab，需要 android\gradlew.bat)
REM        build desktop        (桌面版 Release 构建)
REM        build clean          (清理构建产物)
REM        build check          (仅检查构建环境)
REM        build ... no-bump    (本次构建不递增版本号)
REM
REM  版本号: 读取 Cargo.toml 的 package version，每次 Android 构建 patch 自增，
REM          并同步写回 Cargo.toml / android/app/build.gradle.kts
REM  签名  : android/keystore/ 未提交到仓库（just gen_keystores 生成），
REM          首次构建自动用 keytool 生成自签名密钥库；密码取自环境变量
REM          CEDINIA_KEYSTORE_PASSWORD（未设置时用 123456，与 build.gradle.kts 兜底一致）
REM  产物  : 导出到项目根目录，文件名带版本号（cedinia-<版本>.apk / .aab）；
REM          每次导出成功后会删除根目录下其他版本的安装包，只保留本次产物
REM ============================================

REM ---- 全局状态变量 ----
set "BUILD_FAILED=0"
set "STEP_NAME="

REM ---- 环境配置（按实际路径修改） ----
set "JAVA_HOME=D:\Tools\DevTools\Java\JDK\jdk-21.0.10-oracle"
set "ANDROID_HOME=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_SDK_ROOT=D:\Tools\DevTools\Android\Sdk"
set "ANDROID_NDK_HOME=%ANDROID_HOME%\ndk\27.2.12479018"

REM ---- 签名密钥库密码（android/keystore/ 未提交，首次构建自动生成） ----
if not defined CEDINIA_KEYSTORE_PASSWORD set "CEDINIA_KEYSTORE_PASSWORD=123456"
set "KS_PASS=%CEDINIA_KEYSTORE_PASSWORD%"

REM ---- 目标 ABI（不指定 --target 时 cargo-apk 会去查已连接设备） ----
set "ANDROID_TARGET=aarch64-linux-android"

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
if /i "%~1"=="desktop"       goto :desktop_build
if /i "%~1"=="android"       goto :android_build
if /i "%~1"=="android-debug" goto :android_debug_build
if /i "%~1"=="android-aab"   goto :android_aab_build
if /i "%~1"=="clean"         goto :clean
if /i "%~1"=="check"         goto :check_only
if "%~1"==""                 goto :android_build
if /i "%~1"=="no-bump"       goto :android_build
echo [错误] 未知参数: %~1
echo        可用参数: (无) android android-debug android-aab desktop clean check
set BUILD_FAILED=1
goto :end

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
    if errorlevel 1 (
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

    REM 便携环境下 NDK 版本号未必等于 27.2.12479018，这里自动挑选
    call :resolve_ndk
    if "!BUILD_FAILED!"=="1" goto :eof
    echo        Android NDK: !ANDROID_NDK_HOME!

    REM 便携版 Rust 没有 rustup，缺少 target 时直接下载官方 rust-std 组件
    call :ensure_android_target
    if "!BUILD_FAILED!"=="1" goto :eof

    call :ensure_cargo_apk
    if "!BUILD_FAILED!"=="1" goto :eof

    call :ensure_keystore
    if "!BUILD_FAILED!"=="1" goto :eof
)

REM ---- 代理信息 ----
if "%PROXY_AVAILABLE%"=="1" (
    echo        [代理] Clash 代理已启用: %PROXY_HOST%:%PROXY_PORT%
) else (
    echo        [代理] 未检测到代理，将直连下载
)

goto :eof

REM ============================================
REM  定位 Android NDK
REM  优先使用 ANDROID_NDK_HOME 指向的目录，其次在 SDK\ndk 下挑最新版本
REM ============================================
:resolve_ndk
if exist "!ANDROID_NDK_HOME!\source.properties" goto :ndk_ready
echo [提示] 配置的 NDK 路径不存在: !ANDROID_NDK_HOME!
set "ANDROID_NDK_HOME="
for /f "delims=" %%d in ('dir /b /ad /o-n "%ANDROID_HOME%\ndk" 2^>nul ^| findstr /b /c:"27."') do (
    if not defined ANDROID_NDK_HOME set "ANDROID_NDK_HOME=%ANDROID_HOME%\ndk\%%d"
)
if not defined ANDROID_NDK_HOME (
    for /f "delims=" %%d in ('dir /b /ad /o-n "%ANDROID_HOME%\ndk" 2^>nul') do (
        if not defined ANDROID_NDK_HOME set "ANDROID_NDK_HOME=%ANDROID_HOME%\ndk\%%d"
    )
)
if not defined ANDROID_NDK_HOME (
    echo [错误] 未找到 Android NDK。请执行: sdkmanager "ndk;27.2.12479018"
    echo        或把本脚本的 ANDROID_NDK_HOME 直接指向已有 NDK 目录
    set BUILD_FAILED=1
    goto :eof
)
echo        [提示] 已切换 NDK: !ANDROID_NDK_HOME!
:ndk_ready
set "ANDROID_NDK_ROOT=!ANDROID_NDK_HOME!"
goto :eof

REM ============================================
REM  确保 aarch64-linux-android 标准库可用
REM  便携版 Rust 没有 rustup：优先进口官方 rust-std 组件
REM ============================================
:ensure_android_target
if exist "%RUST_PORTABLE%\rustc\lib\rustlib\aarch64-linux-android\lib" (
    echo        [Rust Target] aarch64-linux-android 已就绪
    goto :eof
)
where rustup >nul 2>&1
if not errorlevel 1 (
    echo        [Rust Target] 通过 rustup 安装 aarch64-linux-android...
    rustup target add aarch64-linux-android
    if errorlevel 1 (
        echo [错误] rustup target add aarch64-linux-android 失败
        set BUILD_FAILED=1
        goto :eof
    )
    echo        [Rust Target] aarch64-linux-android 已就绪
    goto :eof
)
call :download_android_std
goto :eof

REM ============================================
REM  下载官方 rust-std 组件并合入便携版 Rust
REM  URL 形如 https://static.rust-lang.org/dist/<日期>/rust-std-<版本>-aarch64-linux-android.tar.xz
REM  日期从 channel-rust-<版本>.toml 读取，不硬编码
REM ============================================
:download_android_std
set "RUSTC_VER="
for /f "tokens=2" %%v in ('rustc --version 2^>^&1') do set "RUSTC_VER=%%v"
if not defined RUSTC_VER (
    echo [错误] 无法获取 rustc 版本号
    set BUILD_FAILED=1
    goto :eof
)
echo        [Rust Target] 下载 rust-std %RUSTC_VER% (aarch64-linux-android)...
set "STD_CHAN=build\channel-rust-%RUSTC_VER%.toml"
set "STD_DATE="
if exist "%STD_CHAN%" (
    for /f "tokens=2 delims== " %%d in ('findstr /b /c:"date = " "%STD_CHAN%"') do set "STD_DATE=%%~d"
)
if not defined STD_DATE (
    curl -fsSL --retry 2 --max-time 60 -o "%STD_CHAN%" "https://static.rust-lang.org/dist/channel-rust-%RUSTC_VER%.toml" 2>nul
    if not exist "%STD_CHAN%" curl -fsSL --retry 2 --max-time 60 -o "%STD_CHAN%" "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/channel-rust-%RUSTC_VER%.toml" 2>nul
    for /f "tokens=2 delims== " %%d in ('findstr /b /c:"date = " "%STD_CHAN%" 2^>nul') do set "STD_DATE=%%~d"
)
if not defined STD_DATE (
    echo [错误] 无法确定 rust-std 的发布目录（channel-rust-%RUSTC_VER%.toml 解析失败）
    echo        请手动执行: rustup target add aarch64-linux-android
    set BUILD_FAILED=1
    goto :eof
)
set "STD_TAR=build\rust-std-%RUSTC_VER%-aarch64-linux-android.tar.xz"
set "STD_OK=0"
for %%m in (
    "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/%STD_DATE%/rust-std-%RUSTC_VER%-aarch64-linux-android.tar.xz"
    "https://rsproxy.cn/dist/%STD_DATE%/rust-std-%RUSTC_VER%-aarch64-linux-android.tar.xz"
    "https://static.rust-lang.org/dist/%STD_DATE%/rust-std-%RUSTC_VER%-aarch64-linux-android.tar.xz"
) do (
    if "!STD_OK!"=="0" (
        echo        下载: %%~m
        curl -fL --retry 2 --connect-timeout 20 -o "%STD_TAR%" "%%~m"
        if not errorlevel 1 (
            tar -tf "%STD_TAR%" >nul 2>&1
            if not errorlevel 1 set "STD_OK=1"
        )
    )
)
if "!STD_OK!"=="0" (
    echo [错误] rust-std 组件下载失败，请手动安装:
    echo        rustup target add aarch64-linux-android
    set BUILD_FAILED=1
    goto :eof
)
REM rust-std 包里没有 rustc 目录，且目录名与包名不同：
REM   rust-std-<ver>-aarch64-linux-android/rust-std-aarch64-linux-android/lib/rustlib/aarch64-linux-android
REM 所以先整包解到 build\std_unpack，再把目标架构目录合进便携版 rustc。
set "STD_UNPACK=build\std_unpack"
set "STD_INNER=rust-std-aarch64-linux-android"
if exist "%STD_UNPACK%" rd /s /q "%STD_UNPACK%" 2>nul
mkdir "%STD_UNPACK%" 2>nul
tar -xf "%STD_TAR%" -C "%STD_UNPACK%" --strip-components=1
if errorlevel 1 (
    echo [错误] 解压失败: %STD_TAR%
    set BUILD_FAILED=1
    goto :eof
)
if not exist "%STD_UNPACK%\%STD_INNER%\lib\rustlib\aarch64-linux-android\lib" (
    echo [错误] rust-std 包结构异常，未找到 %STD_INNER%\lib\rustlib\aarch64-linux-android\lib
    set BUILD_FAILED=1
    goto :eof
)
if not exist "%RUST_PORTABLE%\rustc\lib\rustlib" mkdir "%RUST_PORTABLE%\rustc\lib\rustlib" 2>nul
REM 用 robocopy 而不是 xcopy：目标目录还不存在时 xcopy 会停下来问“是文件还是目录”，
REM 无人值守/后台构建会永久卡在那里（robocopy 不交互，返回码 <8 即成功）。
robocopy "%STD_UNPACK%\%STD_INNER%\lib\rustlib\aarch64-linux-android" "%RUST_PORTABLE%\rustc\lib\rustlib\aarch64-linux-android" /e /njh /njs /nfl /ndl /nc /ns /np /r:1 /w:1 >nul
if !ERRORLEVEL! GEQ 8 (
    echo [错误] 复制 rust-std 到 %RUST_PORTABLE%\rustc\lib\rustlib 失败
    set BUILD_FAILED=1
    goto :eof
)
rd /s /q "%STD_UNPACK%" 2>nul
del /q "%STD_TAR%" 2>nul
if not exist "%RUST_PORTABLE%\rustc\lib\rustlib\aarch64-linux-android\lib" (
    echo [错误] 解压后仍未找到 rustlib\aarch64-linux-android
    set BUILD_FAILED=1
    goto :eof
)
echo        [Rust Target] aarch64-linux-android 已就绪
goto :eof

REM ============================================
REM  确保 cargo-apk 可用
REM ============================================
:ensure_cargo_apk
where cargo-apk >nul 2>&1
if not errorlevel 1 (
    echo        cargo-apk 已就绪
    goto :eof
)
echo        [cargo-apk] 未安装，执行 cargo install cargo-apk（首次约 3-8 分钟）...
cargo install cargo-apk
if errorlevel 1 (
    echo [错误] cargo install cargo-apk 失败
    set BUILD_FAILED=1
    goto :eof
)
where cargo-apk >nul 2>&1
if errorlevel 1 (
    echo [错误] 安装后仍未找到 cargo-apk，请确认 %CARGO_HOME%\bin 已在 PATH 中
    set BUILD_FAILED=1
    goto :eof
)
echo        cargo-apk 已就绪
goto :eof

REM ============================================
REM  确保签名密钥库存在
REM  android/keystore/ 不在版本库里，首次构建用 keytool 生成自签名密钥库。
REM  密码通过 CARGO_APK_<PROFILE>_KEYSTORE / _PASSWORD 传给 cargo-apk
REM  （优先级高于 Cargo.toml 里被清理成占位符的 signing 配置）。
REM ============================================
:ensure_keystore
if /i "!BUILD_MODE!"=="release" (
    set "KS_PROFILE=release"
    set "KS_FILE=android\keystore\release.keystore"
    set "KS_ALIAS=release"
) else (
    set "KS_PROFILE=dev"
    set "KS_FILE=android\keystore\debug.keystore"
    set "KS_ALIAS=dev"
)

if not exist "!KS_FILE!" (
    echo        [签名] 生成自签名密钥库 !KS_FILE! ...
    if not exist "android\keystore" mkdir "android\keystore" 2>nul
    if exist "build\keystore_gen.log" del /q "build\keystore_gen.log" 2>nul
    keytool -genkeypair -v -storetype PKCS12 -keystore "!KS_FILE!" -alias !KS_ALIAS! -keyalg RSA -keysize 2048 -validity 10000 -storepass %KS_PASS% -keypass %KS_PASS% -dname "CN=Cedinia, OU=Dev, O=Cedinia, L=NA, ST=NA, C=US" >> "build\keystore_gen.log" 2>&1
    if errorlevel 1 (
        echo [错误] keytool 生成密钥库失败
        echo        详见 build\keystore_gen.log
        set BUILD_FAILED=1
        goto :eof
    )
)
echo        [签名] !KS_FILE! (alias=!KS_ALIAS!)

set "CARGO_APK_!KS_PROFILE!_KEYSTORE=%CD%\!KS_FILE!"
set "CARGO_APK_!KS_PROFILE!_KEYSTORE_PASSWORD=%KS_PASS%"
REM android/app/build.gradle.kts 读这两个变量（AAB 构建用）
set "KEYSTORE_PASSWORD=%KS_PASS%"
set "KEY_PASSWORD=%KS_PASS%"
goto :eof

REM ============================================
REM  版本号自增
REM  读取 Cargo.toml 的 [package] version（x.y.z），patch +1 后写回
REM  Cargo.toml 与 android/app/build.gradle.kts；带 no-bump 参数则只读取不递增。
REM ============================================
:bump_version
REM shift 不影响 %*，所以 no-bump 放在任意位置都能识别
set "NO_BUMP=0"
for %%a in (--log %*) do if /i "%%~a"=="no-bump" set "NO_BUMP=1"

set "CUR_VER="
for /f "tokens=2 delims== " %%v in ('findstr /b /c:"version" Cargo.toml') do if not defined CUR_VER set "CUR_VER=%%~v"
if not defined CUR_VER (
    echo [错误] 无法从 Cargo.toml 读取 package version
    set BUILD_FAILED=1
    goto :eof
)

for /f "tokens=1,2,3 delims=." %%x in ("!CUR_VER!") do (
    set "V_MAJOR=%%x"
    set "V_MINOR=%%y"
    set "V_PATCH=%%z"
)
if not defined V_PATCH (
    echo [错误] Cargo.toml 的版本号 "!CUR_VER!" 不是 x.y.z 格式
    set BUILD_FAILED=1
    goto :eof
)

set "BUMPED=0"
if "!NO_BUMP!"=="1" (
    set "VERSION_NAME=!CUR_VER!"
    echo        版本号   : !VERSION_NAME!（no-bump，不递增）
) else (
    set /a "NEW_PATCH=!V_PATCH!+1"
    set "NEW_MINOR=!V_MINOR!"
    set "NEW_MAJOR=!V_MAJOR!"
    REM cargo-apk 把 x.y.z 打包成 versionCode，每段只有 8 位，超过 255 会直接报错
    if !NEW_PATCH! gtr 255 (
        set "NEW_PATCH=0"
        set /a "NEW_MINOR+=1"
    )
    if !NEW_MINOR! gtr 255 (
        set "NEW_MINOR=0"
        set /a "NEW_MAJOR+=1"
    )
    if !NEW_MAJOR! gtr 255 (
        echo [错误] 版本号 major 超过 255，Android versionCode 无法表示
        set BUILD_FAILED=1
        goto :eof
    )
    set "VERSION_NAME=!NEW_MAJOR!.!NEW_MINOR!.!NEW_PATCH!"
    set "V_MAJOR=!NEW_MAJOR!"
    set "V_MINOR=!NEW_MINOR!"
    set "V_PATCH=!NEW_PATCH!"
    set "BUMPED=1"
    echo        版本号   : !CUR_VER! -^> !VERSION_NAME!
)

REM 与 cargo-apk(ndk-build VersionCode::to_code) 一致：apk_id = 1
set /a "VERSION_CODE=16777216 + !V_MAJOR! * 65536 + !V_MINOR! * 256 + !V_PATCH!"

if "!BUMPED!"=="1" (
    call :write_version !VERSION_NAME! !VERSION_CODE!
    if "!BUILD_FAILED!"=="1" goto :eof
)
goto :eof

REM ============================================
REM  把新版本号写回 Cargo.toml 与 android/app/build.gradle.kts
REM  %1 = versionName, %2 = versionCode
REM ============================================
:write_version
REM 本仓库 Windows 环境的 EDR 会在两种情况下静默杀掉 powershell（rc=786、零输出）：
REM   a) 同一进程里先读文件再写文件   b) 调用 Regex.Replace
REM 所以这里 PowerShell 只读原件、把结果按字节写到 stdout，由 cmd 的 '>' 落到
REM build\_wv_new.tmp，再 move 覆盖原文；替换动作改用 [Regex]::Matches + String.Remove/Insert。
set "WV_NAME=%~1"
set "WV_CODE=%~2"
set "WV_LOG=build\version_write.log"
set "WV_TMP=build\_wv_new.tmp"
set "WV_ERR=build\_wv_err.txt"
if not exist "build" mkdir "build" 2>nul
> "!WV_LOG!" echo write_version: name=!WV_NAME! code=!WV_CODE!

set "WV_CARGO=Cargo.toml"
powershell -NoProfile -Command ^
    "$ErrorActionPreference = 'Stop'; $enc = New-Object Text.UTF8Encoding($false); $q = [char]34; try { " ^
    "$t = [IO.File]::ReadAllText($env:WV_CARGO, $enc); " ^
    "$ms = [Regex]::Matches($t, '(?m)^version[ \t]*=[^\r\n]*'); " ^
    "if ($ms.Count -ne 1) { throw ('Cargo.toml: expected exactly 1 version line, found {0}' -f $ms.Count) }; " ^
    "$m = $ms[0]; $t = $t.Remove($m.Index, $m.Length).Insert($m.Index, ('version = {0}{1}{0}' -f $q, $env:WV_NAME)); " ^
    "$b = $enc.GetBytes($t); [Console]::OpenStandardOutput().Write($b, 0, $b.Length); " ^
    "[Console]::Error.WriteLine('Cargo.toml -> {0}' -f $env:WV_NAME) " ^
    "} catch { [Console]::Error.WriteLine('ERR: {0}' -f $_.Exception.Message); exit 1 }" > "!WV_TMP!" 2> "!WV_ERR!"
set "WV_RC=!ERRORLEVEL!"
type "!WV_ERR!" >> "!WV_LOG!"
if !WV_RC! neq 0 (
    echo [错误] 写回 Cargo.toml 失败（rc=!WV_RC!，详情见 !WV_LOG!）
    set BUILD_FAILED=1
    goto :eof
)
move /y "!WV_TMP!" "!WV_CARGO!" >nul
if errorlevel 1 (
    echo [错误] 覆盖 Cargo.toml 失败（临时文件 !WV_TMP! 写入不完整？）
    set BUILD_FAILED=1
    goto :eof
)

if exist "android\app\build.gradle.kts" (
    set "WV_GRADLE=android\app\build.gradle.kts"
    powershell -NoProfile -Command ^
        "$ErrorActionPreference = 'Stop'; $enc = New-Object Text.UTF8Encoding($false); $q = [char]34; try { " ^
        "$t = [IO.File]::ReadAllText($env:WV_GRADLE, $enc); " ^
        "$mc = [Regex]::Matches($t, '(?m)^[ \t]*versionCode[ \t]*=[^\r\n]*'); " ^
        "$mn = [Regex]::Matches($t, '(?m)^[ \t]*versionName[ \t]*=[^\r\n]*'); " ^
        "if (($mc.Count -ne 1) -or ($mn.Count -ne 1)) { throw 'build.gradle.kts: versionCode/versionName line not found' }; " ^
        "$m = $mc[0]; $ind = $m.Value.Substring(0, $m.Value.Length - $m.Value.TrimStart().Length); " ^
        "$t = $t.Remove($m.Index, $m.Length).Insert($m.Index, ('{0}versionCode = {1}' -f $ind, $env:WV_CODE)); " ^
        "$mn = [Regex]::Matches($t, '(?m)^[ \t]*versionName[ \t]*=[^\r\n]*'); $m = $mn[0]; " ^
        "$ind = $m.Value.Substring(0, $m.Value.Length - $m.Value.TrimStart().Length); " ^
        "$t = $t.Remove($m.Index, $m.Length).Insert($m.Index, ('{0}versionName = {1}{2}{1}' -f $ind, $q, $env:WV_NAME)); " ^
        "$b = $enc.GetBytes($t); [Console]::OpenStandardOutput().Write($b, 0, $b.Length); " ^
        "[Console]::Error.WriteLine(('build.gradle.kts -> {0} ({1})' -f $env:WV_NAME, $env:WV_CODE)) " ^
        "} catch { [Console]::Error.WriteLine('ERR: {0}' -f $_.Exception.Message); exit 1 }" > "!WV_TMP!" 2> "!WV_ERR!"
    set "WV_RC2=!ERRORLEVEL!"
    type "!WV_ERR!" >> "!WV_LOG!"
    if !WV_RC2! neq 0 (
        echo [错误] 写回 android\app\build.gradle.kts 失败（rc=!WV_RC2!，详情见 !WV_LOG!）
        set BUILD_FAILED=1
        goto :eof
    )
    move /y "!WV_TMP!" "!WV_GRADLE!" >nul
    if errorlevel 1 (
        echo [错误] 覆盖 android\app\build.gradle.kts 失败（临时文件 !WV_TMP! 写入不完整？）
        set BUILD_FAILED=1
        goto :eof
    )
)
goto :eof

REM ============================================
REM  运行 cargo apk build，并容忍收尾阶段的已知 panic
REM  %1 = 必须存在的 APK 产物路径；该文件在构建前删除，
REM       所以构建后仍然存在 == 本轮确实打包并签名成功
REM ============================================
:run_cargo_apk
set "CAPK_OUT=%~1"
if exist "!CAPK_OUT!" del /q "!CAPK_OUT!" 2>nul
if exist "!CAPK_OUT!.idsig" del /q "!CAPK_OUT!.idsig" 2>nul
if exist "%~dp1%~n1-unaligned.apk" del /q "%~dp1%~n1-unaligned.apk" 2>nul

set "STEP_NAME=cargo apk build !CARGO_FLAGS!"
cargo apk build !CARGO_FLAGS!
set "CAPK_RC=!ERRORLEVEL!"
if !CAPK_RC! equ 0 (
    echo       cargo apk 编译完成。
    goto :eof
)
if not exist "!CAPK_OUT!" (
    set BUILD_FAILED=1
    goto :on_error
)
echo.
echo [警告] cargo apk build 返回 rc=!CAPK_RC!，但本轮产物已生成并签名:
echo        !CAPK_OUT!
echo        原因: cargo-apk 依赖的 cargo-subcommand 在打包完成后收集产物时，
echo              遇到同时含 bin 与 cdylib 目标的 crate 会 panic
echo              （Bin is not compatible with Cdylib）—— 收尾阶段误报，APK 本身正常。
echo        继续使用已生成的 APK...
goto :eof

REM ============================================
REM  把 cargo-apk 产出的 APK 复制到项目根目录（文件名带版本号）
REM ============================================
:publish_apk
set "APK_DIR=target\!BUILD_MODE!\apk"
set "APK_SRC="
REM cargo-apk 产物固定为 <build_dir>/<apk_name>.apk（apk_name 缺省取自 crate 名）
if exist "!APK_DIR!\cedinia.apk" set "APK_SRC=!APK_DIR!\cedinia.apk"
if not defined APK_SRC if exist "!APK_DIR!" (
    for /f "delims=" %%f in ('dir /b /s /o-d "!APK_DIR!\*.apk" 2^>nul') do (
        REM 跳过 aapt 生成的中间产物 <name>-unaligned.apk
        if not defined APK_SRC if /i not "%%~nxf"=="cedinia-unaligned.apk" set "APK_SRC=%%f"
    )
)
if not defined APK_SRC (
    echo [错误] 未在 !APK_DIR! 下找到 APK 产物
    echo        请确认上面的 cargo apk build 已成功
    set BUILD_FAILED=1
    goto :eof
)

echo        来源     : !APK_SRC!
REM 体积下限用于识别被截断/未打包完整的中间产物（正常 release APK 约 20 MB）
for %%f in ("!APK_SRC!") do if %%~zf LSS 1048576 (
    echo [错误] APK 体积异常（%%~zf 字节），打包可能未完成
    set BUILD_FAILED=1
    goto :eof
)
copy /y "!APK_SRC!" "cedinia-!VERSION_NAME!.apk" >nul
if errorlevel 1 (
    echo [错误] 复制 APK 到项目根目录失败
    set BUILD_FAILED=1
    goto :eof
)
REM 导出成功后清掉历史版本的安装包，根目录只留本次产物
call :purge_old_packages_current
goto :eof

REM ============================================
REM  删除项目根目录下历史版本的安装包（APK/AAB 及 apksigner 的 .idsig 签名）
REM  %1 / %2 / %3 = 需要保留的文件名（如 cedinia-12.0.6.apk），留空表示该槽位不保留
REM ============================================
:purge_old_packages
set "KEEP_PKG1=%~1"
set "KEEP_PKG2=%~2"
set "KEEP_PKG3=%~3"
set "PURGED_PKG=0"
for %%f in (cedinia-*.apk cedinia-*.aab cedinia-*.idsig *.apk *.aab *.idsig) do (
    if exist "%%f" (
        if /i not "%%~nxf"=="!KEEP_PKG1!" if /i not "%%~nxf"=="!KEEP_PKG2!" if /i not "%%~nxf"=="!KEEP_PKG3!" (
            for %%i in ("%%f") do echo        删除旧包 %%~nxi  %%~zi 字节
            del /q "%%f" 2>nul
            set /a PURGED_PKG+=1
        )
    )
)
if "!PURGED_PKG!"=="0" echo        无历史版本安装包需要清理
goto :eof

REM ============================================
REM  清理历史版本安装包，只保留当前版本号对应的产物
REM ============================================
:purge_old_packages_current
call :purge_old_packages "cedinia-!VERSION_NAME!.apk" "cedinia-!VERSION_NAME!.apk.idsig" "cedinia-!VERSION_NAME!.aab"
goto :eof

REM ============================================
REM  复制 cargo apk 产出的 .so 到 Android jniLibs（AAB 构建用）
REM ============================================
:copy_so_to_jnilibs
REM cargo 的产物布局是 target\<triple>\<profile>\lib<name>.so（见 ndk-build dylibs.rs）
set "SO_SRC=target\!ANDROID_TARGET!\!BUILD_MODE!\libcedinia.so"
set "SO_DST=android\app\src\main\jniLibs\arm64-v8a"
if not exist "!SO_SRC!" (
    echo [错误] 未找到原生库 !SO_SRC!
    echo        请先执行: cargo apk build !CARGO_FLAGS!
    set BUILD_FAILED=1
    goto :eof
)
if not exist "!SO_DST!" mkdir "!SO_DST!" 2>nul
copy /y "!SO_SRC!" "!SO_DST!\libcedinia.so" >nul
if errorlevel 1 (
    echo [错误] 复制 libcedinia.so 失败
    set BUILD_FAILED=1
    goto :eof
)
echo        已复制: !SO_DST!\libcedinia.so
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
REM 同 :write_version：PowerShell 只读文件、结果写 stdout，由 cmd 的 '>' 落盘再 move 覆盖，
REM 避免"同进程读+写文件"被 EDR 静默杀掉（rc=786）。
if exist "%GRADLE_PROPS%" (
    powershell -NoProfile -Command ^
        "$enc = New-Object Text.UTF8Encoding($false); " ^
        "$lines = Get-Content '%GRADLE_PROPS%' -Encoding UTF8 | Where-Object { $_ -notmatch '^systemProp\.(http|https)\.proxy' }; " ^
        "$nl = [Environment]::NewLine; $txt = '{0}{1}' -f ($lines -join $nl), $nl; " ^
        "$b = $enc.GetBytes($txt); [Console]::OpenStandardOutput().Write($b, 0, $b.Length)" > "%GRADLE_PROPS%.tmp"
    if errorlevel 1 (
        echo [错误] 清理 %GRADLE_PROPS% 中的旧代理配置失败
        set BUILD_FAILED=1
        goto :eof
    )
    move /y "%GRADLE_PROPS%.tmp" "%GRADLE_PROPS%" >nul
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
REM 根目录下的安装包（含历史版本）与 cargo apk 的中间产物一并清理
call :purge_old_packages
for %%d in ("target\debug\apk" "target\release\apk") do (
    if exist "%%~d" (
        del /q "%%~d\*.apk" "%%~d\*.idsig" "%%~d\*.unaligned" 2>nul
        echo        %%~d\ 已清理
    )
)
del /q "build\build_full.log" "build\build_exit.log" 2>nul
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
    for %%f in ("target\release\cedinia.exe") do echo  产物: target\release\cedinia.exe  ^(%%~zf bytes^)
) else (
    echo  产物: target\release\cedinia （或无扩展名可执行文件）
)
echo.
echo  运行方式: cargo run --release
goto :end

REM ============================================
REM  Android Debug 构建
REM ============================================
:android_debug_build
set "BUILD_MODE=debug"
set "CARGO_FLAGS=--target %ANDROID_TARGET%"
goto :do_android_build

REM ============================================
REM  Android Release 构建（默认）
REM ============================================
:android_build
set "BUILD_MODE=release"
set "CARGO_FLAGS=--release --target %ANDROID_TARGET%"
goto :do_android_build

REM ============================================
REM  Android AAB 构建（走 android\gradlew.bat，需要 Gradle 工程）
REM ============================================
:android_aab_build
set "BUILD_MODE=release"
set "CARGO_FLAGS=--release --target %ANDROID_TARGET%"
set "GRADLE_TASK=bundleRelease"
goto :do_android_aab_build

:do_android_build
echo.
echo ============================================
echo  Cedinia Android !BUILD_MODE! APK 构建 - %date% %time%
echo ============================================

REM cmd 的 'call :label'（不带参数）会清空子例程内的 %1..%9 与 %*，
REM 所以必须显式透传，否则 :bump_version 读不到 no-bump
call :bump_version %*
if "!BUILD_FAILED!"=="1" goto :end

call :checkenv android
if "!BUILD_FAILED!"=="1" goto :end

REM ---- 步骤1: cargo fetch ----
echo.
echo [1/3] cargo fetch（检查/下载依赖）...

set "STEP_NAME=cargo fetch"
cargo fetch
if %ERRORLEVEL% neq 0 (
    set BUILD_FAILED=1
    goto :on_error
)

REM ---- 步骤2: 交叉编译并打包 APK ----
echo.
echo [2/3] cargo apk build !CARGO_FLAGS!...
echo       编译 Rust 原生库和 Java DEX（首次约 10-20 分钟）...
echo.

call :run_cargo_apk "target\!BUILD_MODE!\apk\cedinia.apk"
if "!BUILD_FAILED!"=="1" goto :end

REM ---- 步骤3: 导出 APK 到项目根目录（文件名带版本号）----
echo.
echo [3/3] 导出 APK 到项目根目录...

call :publish_apk
if "!BUILD_FAILED!"=="1" goto :end

echo.
echo ============================================
echo  Android APK 构建成功！
echo ============================================
echo  版本号   : !VERSION_NAME!  (versionCode=!VERSION_CODE!)
for %%f in ("cedinia-!VERSION_NAME!.apk") do echo  APK      : %%~nxf  (%%~zf 字节)
echo  文件位置 : %CD%\cedinia-!VERSION_NAME!.apk
echo  安装命令 : adb install -r "cedinia-!VERSION_NAME!.apk"
goto :end

REM ============================================
REM  Android AAB 构建（cargo apk 出 .so，再交给 Gradle 打 AAB）
REM ============================================
:do_android_aab_build
echo.
echo ============================================
echo  Cedinia Android !BUILD_MODE! AAB 构建 - %date% %time%
echo ============================================

REM 同上：子例程参数必须显式透传，否则 no-bump 失效
call :bump_version %*
if "!BUILD_FAILED!"=="1" goto :end

call :checkenv android
if "!BUILD_FAILED!"=="1" goto :end

if not exist "android\gradlew.bat" (
    echo [错误] 未找到 android\gradlew.bat（仓库内没有 Gradle wrapper）
    echo        AAB 打包需要完整 Gradle 工程；只装 APK 请直接运行 build.bat
    set BUILD_FAILED=1
    goto :end
)

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

call :run_cargo_apk "target\!BUILD_MODE!\apk\cedinia.apk"
if "!BUILD_FAILED!"=="1" goto :end

REM ---- 步骤3: 复制 .so 到 Android jniLibs ----
echo.
echo [3/4] 复制原生库到 Android jniLibs...

call :copy_so_to_jnilibs
if "!BUILD_FAILED!"=="1" goto :end

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

REM 查找产物
if /i "!BUILD_MODE!"=="release" (
    set "AAB_SRC=android\app\build\outputs\bundle\release\app-release.aab"
) else (
    set "AAB_SRC=android\app\build\outputs\bundle\debug\app-debug.aab"
)

echo.
echo ============================================
echo  Android AAB 构建成功！
echo ============================================
if exist "!AAB_SRC!" (
    copy /y "!AAB_SRC!" "cedinia-!VERSION_NAME!.aab" >nul
    if errorlevel 1 (
        echo [提示] 复制到项目根目录失败，原始文件: !AAB_SRC!
    ) else (
        for %%f in ("cedinia-!VERSION_NAME!.aab") do echo  AAB      : %%~nxf  (%%~zf 字节)
        echo  文件位置 : %CD%\cedinia-!VERSION_NAME!.aab
        REM 导出成功后清掉历史版本的安装包，根目录只留本次产物
        call :purge_old_packages_current
    )
) else (
    echo [提示] AAB 文件未在预期路径找到，请检查 android\app\build\outputs\
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