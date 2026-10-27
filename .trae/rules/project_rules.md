# cedinia 项目规则

## 概述
Android（及辅助桌面端）GUI 应用，基于 Rust + Slint 构建，功能镜像自 krokiet，针对移动端约束做了适配：触控优化布局、JNI 文件选择器、运行时权限、系统 insets。`SimilarVideos` 保留但仅使用音频指纹匹配（`rusty-chromaprint`），不做帧哈希。

## 技术栈
- **语言**: Rust
- **UI 框架**: Slint 1.15
- **核心引擎**: czkawka_core
- **Android**: android-activity 0.6, JNI 0.22
- **构建**: Cargo + Gradle (Android), android-build 0.1.2
- **翻译**: i18n-embed + Fluent
- **桌面端**: rfd, trash, notify-rust

## 目录结构
```
cedinia/
├── src/
│   ├── lib.rs                     # Android 入口
│   ├── app.rs                     # 桌面入口 + 共享 run_app_inner()
│   ├── bin/cedinia.rs             # 桌面二进制包装
│   ├── common.rs                  # 列索引枚举
│   ├── model.rs                   # FileEntry 切换/计数逻辑
│   ├── compare.rs                 # 图片对比叠加层
│   ├── file_actions.rs            # 删除路径
│   ├── scan_runner.rs             # 工作线程 + ScanRequest/ScanResult
│   ├── scanners.rs                # 工具特定扫描构建
│   ├── notifications.rs           # 桌面通知
│   ├── set_initial_gui_infos.rs   # 初始 GUI 状态
│   ├── thumbnail_loader.rs        # 异步图片缩略图加载
│   ├── translations.rs            # 翻译填充
│   ├── volumes.rs                 # 存储卷检测
│   ├── localizer_cedinia.rs       # flc! 宏, LANGUAGE_LIST
│   ├── file_picker_android.rs     # JNI + 嵌入式 DEX 文件选择器
│   ├── logging.rs                 # 日志开关控制
│   ├── callbacks/                 # Slint 回调绑定
│   └── settings/                  # CediniaSettings 结构体
├── ui/                            # Slint UI 文件
├── android/                       # Android 工程
├── i18n/                          # Fluent 翻译文件
├── java/                          # Android Java 辅助类
├── icons/                         # SVG/PNG 图标
├── memory-bank/                   # 知识库
├── build/                         # 构建日志
└── tmp/                           # 临时文件（gitignored）
```

## 关键约定

### 构建命令
- **完整构建**: `build.bat`（无参 = Android Release）
  - `build.bat android` — Android Release
  - `build.bat android-debug` — Android Debug
  - `build.bat android-aab` — Android AAB
  - `build.bat desktop` — 桌面端
  - `build.bat clean` — 清理
  - `build.bat check` — 只读环境预检
  - `build.bat publish` — 单独补发 Release
- **清理**: `clean.bat`
- **只补发 Release**: `gh-release.bat`（不编译、不提交、只对 HEAD 打标签并上传 APK）
- **版本号**: `Cargo.toml` 的 `package.version` 是唯一真源

### 自测（禁止跑 build.bat）
- **禁止为了自测跑 `build.bat`**（会 patch +1、commit、push、发 Release）
- 校验改动优先 `cargo check` / `cargo clippy`
- Android 目标加 `--target aarch64-linux-android`
- 只验发布脚本用 `gh-release.bat check`（只读预检）

### 代码规范
- Rust/Slint 代码按仓库现有风格写
- 中文注释、日志、文案保持中文
- 不做与任务无关的重排或全文件格式化
- Slint 列表用 `ListView`（不用 ScrollView + for 循环）

### 交流约定（强制）
- 所有思考、分析、回答必须使用中文
- 代码注释可使用中文或英文

### 终端管理（强制）
- **不要假设终端类型！** 实际可能是 PowerShell 也可能是 cmd，每次执行命令前**必须先探测**。
  - 探测命令：`$PSVersionTable`
    - 输出含版本信息 → **PowerShell**
    - 报 `is not recognized` → **cmd**
  - **PowerShell 语法**：分隔用 `;`、重定向 `2>$null`、注释 `#`、变量 `$env:VAR`、末尾 `; exit`
  - **cmd 语法**：分隔用 `&`/`&&`、重定向 `2>nul`、注释 `rem`、变量 `%VAR%`、末尾 `& exit`
  - 禁止用 `cmd /c` 包裹命令
- **终端内容标识（必须）**：每个新终端首条命令必须是标识头：
  ```
  PowerShell: echo "=== task-N-用途 ==="
  cmd:        echo === task-N-用途 ===
  ```
- **终端自关闭（强制）**：每条命令末尾加自关闭语句
- **禁止主动杀进程**：`taskkill /f /im cmd.exe` 会误伤用户自己的 cmd

### Git 操作约定（强制）
- **禁用分页器**：所有 `git` 命令必须加 `--no-pager` 参数
- **推送只推当前分支**：禁止 `git push --all` / `--mirror`

### 临时文件管理（强制）
- 所有中间产物全写 `tmp\`
- `tmp\` 被 `.gitignore` 忽略（`/tmp/`）
- **收尾必须清空**：`rmdir /s /q tmp`（或 `clean.bat` / `build.bat clean`）

### 知识库管理
- 知识库位于 `memory-bank/`，索引文件 `memory-bank/README.md`
- 开工读索引 → 只读命中条目；收工照 `memory-bank/WRITING.md` 回填
- 禁止 `read all` 知识库、禁止扫全仓库

### 命令等待
- 在终端执行命令后必须等待命令执行完成，不要命令一发出就立刻查看输出并断定执行失败

## 常用操作
- **编译检查**: `cargo check --target aarch64-linux-android`
- **Clippy**: `cargo clippy --target aarch64-linux-android`
- **完整构建发布**: `build.bat`（含 patch 自增 + git 提交/推送/打 tag/Release）
- **清理构建缓存**: `build.bat clean` 或 `clean.bat`
- **只读发布预检**: `gh-release.bat check`

## 项目记忆
- Git 仓库位于 `D:\WorkSpace\test\cedinia`，所有代码变更通过 git 管理
- 版本号由 `Cargo.toml` 的 `package.version` 管理，`build.bat` 自动递增 patch
- APK 命名格式: `cedinia-<versionName>.apk`