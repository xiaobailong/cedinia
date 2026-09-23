# 技术决策（decisions / ADR）

> 上限 12KB（超了照 `WRITING.md` §3 归档；已废弃的移入 `archive/decisions-archive.md`）。
> 每条：背景 / 决策 / 理由 / 备选与为何不选 / 影响。编号只增不改。模板见 `WRITING.md` §1。
> **来源**: 2026-09-23 从同机同工具链的源仓库 ClipboardMerger 迁入，编号沿用、内容按 cedinia 现状改写；
> 没有对应载体的源条目未迁移，清单见 `ADR-012`。本仓库当前最大号 `ADR-012`。

## ADR-001 知识库制度：`memory-bank` 按需读取 + 体积阈值 + 归档（控 token） — 已归档（2026-09-23）
- 要点: 只读索引 → 只读命中的那 1 个文件 → 主文件超限先归档；规则常驻 `.clinerules`、写条目看 `WRITING.md`；收尾清 `tmp\`；
  自检 bytes / 编码 / 交叉引用无悬空。详情: `archive/decisions-archive.md`

## ADR-002 Cline 临时产物一律写进仓库根 `tmp\`
- 日期: 2026-09-23 | 状态: 已采纳
- 决策: 中间文件写 `tmp\`（单层，不建子目录）；`.gitignore` 忽略 `/tmp/`（本次迁移已加）；
  `clean.bat` 与 `build.bat clean` 都整目录删除 `tmp\`（迁移时同步补上的，见影响栏）。
- 理由: `git status` 只剩真实改动；清理一条命令；不会误删业务文件。
- 备选与为何不选: 系统 `%TEMP%`（跨会话找不回证据）；`build\`（会被 clean 清掉、易被当构建产物）；每任务建子目录（过度设计）。
- 影响 / 约束: 例外四类（`build\` 下的日志、`memory-bank\`、`docs\HANDOFF-*.md`、长期脚本）；
  `.clineignore` **不**屏蔽 `tmp\`（命令输出要重定向进去再 `read_files` 读，`PIT-008`）；收尾回复要说明 `tmp\` 是否已清空。

## ADR-003 构建日志用「`call` 递归 + 文件重定向」，放弃「管道 + PowerShell 追写」 — 已废弃（2026-09-23，被 `ADR-010` 取代）
- 要点: 当年为避开「管道 + PowerShell 逐行追写」丢内容（`PIT-012`）改用重定向 + 结束后 `type` 回显；代价是控制台要等构建跑完才刷
  （`ADR-010` 已换成 tee）。递归判别变量的思路在 cedinia 变成"私有参数 `--log`"（`build.bat:9`）。
  详情: `archive/decisions-archive.md`

## ADR-004 自测不触碰发布：校验用 `cargo check` / `gh-release.bat check`
- 日期: 2026-09-23 | 状态: 已采纳（迁移自 ClipboardMerger，载体换成 cedinia 的命令）
- 背景: `build.bat` 默认流程含 patch 自增 → `git commit` → `push` → 打 tag → `gh release create`（不可逆），
  失败还会吃掉一个版本号（`ISSUE-002`）。
- 决策: 校验改动优先 `cargo check`（桌面目标；Android 目标加 `--target aarch64-linux-android`，环境变量见 `build.bat:57-74`）、
  `cargo clippy`，格式只看 `cargo fmt --check`；只验发布脚本用 `gh-release.bat check`（只读预检：不动版本、不提交、不推送）；
  `build check` 也是只读的（`build.bat:703-705` → `:checkenv`，不递增版本）。发布只在用户明确要求时跑 `build.bat`，并先 `git status` 确认干净。
- 理由: 编译校验结论一样干净（编译不看发布逻辑），且不动 `Cargo.toml`、不碰远端。
- 备选与为何不选: 跑 `build.bat ... no-bump no-release`（仍然全量编译 + 覆盖 `build_full.log`，慢且打扰 `target\`）；
  跑完再手动回退（远端 tag / Release 已经动过）。
- 影响 / 约束: 校验产物版本号 = 当前 `Cargo.toml` 的 version；Android 目标校验需要 NDK 与 rust-std（`build.bat` 会自动补齐）。

## ADR-005 版本号单一真源 `Cargo.toml`，APK 命名带版本号
- 日期: 2026-09-23 | 状态: 已采纳（迁移自 ClipboardMerger；真源从 `version.properties` 换成 `Cargo.toml`）
- 决策: `Cargo.toml` 的 `[package] version` 是唯一真源；`build.bat` 的 `:bump_version`（`build.bat:444-505`）patch 自增，
  `:write_version`（`build.bat:511-577`）同步写回 `Cargo.toml` 与 `android\app\build.gradle.kts` 的 `versionName` / `versionCode`；
  APK 固定命名 `cedinia-<versionName>.apk`，`:publish_apk`（`build.bat:614-647`）复制到仓库根并清掉历史版本；tag 固定 `v<versionName>`。
- 理由: 版本号只在一个文件里维护；应用内显示的是编译进二进制的 `CARGO_PKG_VERSION`，构建后自动同步；文件名带版本号便于真机区分安装包。
- 备选与为何不选: 版本号写死在 gradle（每次改都产生代码 diff 噪声）；用 git tag / commit 数当版本（与应用内标题栏不好对齐）。
- 影响 / 约束: 别手工改 `Cargo.toml` 的 version 行 —— `build.bat:528-530` 要求全文件**只有 1 行**顶格的 `version = `，多一行直接抛错；
  构建失败也会消耗一个 patch 号（`ISSUE-002`）；改 APK 命名要同步 `gh-release.bat` 的 `:find_apk` 与 `build.bat:618-623`；
  `gh-release.bat` 只读版本号，不递增、不提交。

## ADR-006 发布走 `gh` CLI；`build.bat` 各子命令的差异保留
- 日期: 2026-09-23 | 状态: 已采纳
- 决策: 发布统一用 GitHub CLI（`build.bat:91-95` 定位 `gh`，PATH 上没有就退回 `%ProgramFiles%\GitHub CLI\gh.exe`）；
  `build.bat` 的入口差异照旧保留：无参 / `android` = Release 构建 + 发布，另有 `android-debug` / `android-aab` / `desktop` / `clean` / `check` / `publish`
  与 `no-bump` / `no-release` 两个开关；不要"顺手统一"成一条路径。
- 理由: 不同入口对应不同心态（随手发版 / 只校验 / 只补发 / 只出 Debug 包），差异是刻意固化的。
- 备选与为何不选: Gradle 发布插件（新增依赖与认证配置）；只留一条路径（牺牲易用或严谨）。
- 影响 / 约束: 改发布流程前确认工作区干净 + `gh auth status` 正常；`gh` 缺失时 `build.bat` 只是跳过发布（`build.bat:758-762`），
  而 `gh-release.bat` 直接报错退出（它存在的意义就是发布）；失败分支的 `timeout 60` 会让窗口挂住，重跑前按 `PIT-020` 确认真空。

## ADR-007 Token 策略：仓库侧（`.clineignore` + 精简 `.clinerules` + 检索式知识库）+ 客户端侧（Auto-Compact / `/smol` / `/newtask`） — 已归档（2026-09-23）
- 要点: 仓库侧 = `.clineignore` 挡构建产物（**故意保留 `build\` 下的日志**）+ `.clinerules` 只留硬约束 + 知识库检索式读取 + 主文件限体积；
  客户端侧 = 开 Auto-Compact、收尾 `/smol`、换任务 `/newtask`。详情: `archive/decisions-archive.md`

## ADR-009 gh 发布逻辑集中成子过程 + 幂等 + 推送重试
- 日期: 2026-09-23 | 状态: 已采纳
- 背景: 源仓库把同一段 `gh release` 逻辑复制到多处，`if ... else (...)` 里还带裸括号 ⇒ 整个分支块解析失败、Release 从来没发出去
  （源 `ISSUE-004`，本仓库只迁移了机制 `PIT-005`）。
- 决策: ①仓库全名单一来源 `GH_REPO`（cedinia：未设时从 `git remote get-url origin` 推导，兜底 `xiaobailong/cedinia`）；
  ②`gh-release.bat` 集中成 `:check_gh`（路径存在 + `--version` + `auth status`）/ `:gh_release`（`release view` 判存在 →
  `create` 或 `edit` + `upload --clobber`，最后打印 Release URL）/ `:git_push <ref> [force]`（3 次重试 + 失败指引）；
  ③调用处一律 `call :xxx` + `if errorlevel 1` **硬失败**（不再"警告后继续"，避免"没发出去却报成功"）；
  ④标签：本地 `git tag -f -a`，远端先普通推送，失败自动回落 `-f` 并打警告。
- 理由: 同一版本重跑不会卡在 `already exists` / tag 冲突；日志里直接给出 Release URL（可验证）；一处改动一处生效。
- 备选与为何不选: 把 `build.bat:745-844` 的 `:publish_github_release` 一起改成幂等 + 重试（要动正在稳定工作的主发布链路，本轮不动 ⇒ 代价是两处发布逻辑有漂移风险）；
  用 `gh api` + JSON 判断 Release 是否存在（多一层解析）；保留"已存在只警告"（用户拿不到新 APK 却看到成功）。
- 影响 / 约束: `build.bat` 的 `git push origin HEAD` / `git push origin <tag>` **2026-09-23 第二轮已改为 `:git_push`（3 次重试）**，见 `ADR-013`；
  改 gh 行为要同步两处（`build.bat` 的 `:publish_github_release` 与 `gh-release.bat` 的 `:gh_release`）—— 两侧现已是同一策略（3 次重试 + REST 删同名资产）；
  `--clobber` 会先删同名资产再上传，上传失败原资产会丢（可接受；但 gh 的资产列表可能过期，所以先用 REST 按 id 删同名资产，`PIT-027`）。

## ADR-010 构建日志：逐行先落盘、再回显（tee）
- 日期: 2026-09-23 | 状态: 已采纳（迁移源仓库的 tee 包装器；cedinia 现有两种实现并存）
- 背景: "重定向 + 结束后 `type`"（`ADR-003`）让控制台**全程空白**，构建几十秒看不到进度 / 报错；需求 = 每条日志先写文件、再同步展示。
- 决策: ①`build.bat:9-19` / `clean.bat:9-19` 用**内联 PowerShell tee**：私有参数 `--log` + `%*` 透传，
  PowerShell 里 `StreamWriter(AutoFlush=true)` + `Write-Host` 逐行双写，日志 `build\build_full.log` / `build\clean_full.log`（UTF-8 无 BOM）；
  ②`gh-release.bat` 用**独立包装器** `tools\tee-log.ps1`（迁移来的，UTF-8 **带 BOM** + CRLF）：子进程 stdout 一行一读一写，
  被包装脚本的路径 / 参数经环境变量 `_CED_SELF` / `_CED_ARGS` 传入，子进程命令固定 `cmd /d /s /c ""<bat>" <args> 2>&1"`
  （只留一个输出流，顺序不乱），日志 `build\logs\gh-release_<ts>.log`，退出码经 PowerShell `exit` 原样回传；
  缺 `tools\tee-log.ps1` 时降级回「重定向 + 结束 `type`」（`:log_legacy`）。
- 理由: 逐行 `AutoFlush` ⇒ 文件先、控制台后，顺序稳定；不再用"管道喂 `-Command`"那套（`PIT-012` 的失败模式）。
- 备选与为何不选: 回头用「管道 + PowerShell 追写」（`PIT-012` 已证丢内容）；`Get-Content -Wait` 跟随日志（要并行 tail 进程，结束时机与退出码难把握）；
  把 `build.bat` 整体改写成 PowerShell（改动面太大）；本轮顺手把 `build.bat` / `clean.bat` 换成 `tools\tee-log.ps1`（不动正在工作的主构建脚本，见 `ADR-011` 的备选）。
- 影响 / 约束: 文件名差异 —— `build\build_full.log` 每轮**覆盖**（`PIT-016`），`build\logs\gh-release_*.log` 带时间戳；
  `clean.bat` 会整目录删 `build\`（`PIT-021`）；改日志链路要同步更新 `ISSUE-001` 的判据；
  `tools\` 随仓库入库、别删；控制台内容 ≈ 日志文件内容（tee 之外只剩脚本自己的两行提示）。
  验证方式：只读模式（`gh-release.bat check`）或 `tmp\` 里的假子脚本；**禁跑 `build.bat`**（见 `ADR-004`）。

## ADR-011 新增独立发布脚本 `gh-release.bat`：以「最后一个提交」为发布对象，只做 gh
- 日期: 2026-09-23 | 状态: 已采纳（迁移源仓库的同名脚本，按 cedinia 的版本真源 / 产物名 / 仓库改写）
- 背景: `build.bat` 把 版本自增 → 编译 → commit/push → tag → `gh release` 串成一条**不可逆**的链；
  gh / 网络 / 登录一出问题（`ISSUE-005` 那类瞬断），想"只补发 Release"就得重跑整条链（还会再吃一个 patch 号，`ISSUE-002`）。
  `build publish` 能"不编译"，但它仍会 `git commit` + `push` + 打 tag。需求 = 单独一个脚本，以**最后一个提交**补发 Release，且不碰版本号与工作区。
- 决策: 新增仓库根 `gh-release.bat`（与 `build.bat` 同级，可双击）：**不递增版本、不提交、不编译**。
  ①标签名取自 `Cargo.toml` 的 `package.version`（真源，`ADR-005`）；②标签强制指向 HEAD（`git tag -f -a`），已存在但指他处时先警告 + 要求输入 `y` 确认；
  ③未推送则先 push 分支 → push tag（失败回落 `-f`，统一走 `:git_push` 的 3 次重试）→ `:gh_release` 幂等建 / 更新 Release + 上传 APK；
  ④远端标签已指向 HEAD 就用 `gh api repos/<repo>/commits/<tag> --jq .sha` 判定后**跳过**打标签 / 推标签（走 HTTPS，不吃卡死的 SSH）；
  ⑤Release 说明写成文件后用 `--notes-file` 传入（`build\gh_release_notes.md`），避开命令行里的裸括号 / `>` 被 cmd 解析（`PIT-005` / `PIT-006`）；
  ⑥APK 定位顺序 = 根目录 `cedinia-<版本>.apk` → 根目录任意 `*.apk` → `target\release\apk\*.apk` → `target\debug\apk\*.apk`
  （跳过 `*-unaligned.apk`）；体积 < 1MB 直接判失败（与 `build.bat:634-638` 同策略）；
  ⑦`gh-release.bat check` = 只读预检（只打印将执行的命令；用 `release view` 判定走 `create` 还是 `edit` + `upload`，判定失败时只打印 `create` 分支，
  见脚本里的 `:plan_create` / `:plan_done`）；⑧`GH_EXE` / `GH_REPO` / `GH_PROXY` 支持环境变量覆盖，
  `CEDINIA_NO_PAUSE=1` 跳过收尾倒计时（脚本化调用用）；⑨开头自我重启一次解决 `chcp 65001` + 中文注释错解析（`PIT-026`）。
- 理由: 发布失败可单独、幂等重试；脚本不碰版本号与工作区 ⇒ 重跑不污染 git 历史；`check` 让"发布前看一眼"零成本。
- 备选与为何不选: 让 `build.bat` 改成 `call gh-release.bat`（要动主发布链路，风险大，本轮不动 —— 代价是两处 `:gh_release` 有漂移风险）；
  给 `build.bat` 加子命令（仍要改频繁变动的 `build.bat`）；继续靠 `build publish`（它仍会 commit + push）。
- 影响 / 约束: 脚本只对 HEAD 生效（要发旧提交得先切过去）；改 `:gh_release` 行为要两处一起改（`ADR-009` 影响栏）；
  `:gh_release` 外层 3 次重试 + 内部 `:gh_release_once`（`gh-release.bat:399-438`，2026-09-23 因 `Patch …: EOF` 补）；
  代理探测接受任何非 `000` 应答；2026-09-23 实测：**草稿对 `gh release view <tag>` 可见**（`isDraft:true`，`REL_DRAFT` 分支真的跑到了 `edit --draft=false`），
  所以上次运行残留的草稿会被正常更新 / 发布、不必先清理；但脚本被外部打断（`PIT-029`）留下「已发布但资产为空」的 Release 时它自己补不了，用 `gh release upload <tag> <apk> --clobber`；
  提交标题等动态文本拼进 notes 之前必须消毒（`PIT-025`）；抽段测试必须从**标签行**切（`ISSUE-006`）；`build.bat` 自身行为未改动。

## ADR-012 知识库 / 规则 / 发布脚本从 ClipboardMerger 迁入：沿用原编号、按 cedinia 现状改写
- 日期: 2026-09-23 | 状态: 已采纳
- 背景: 源仓库 ClipboardMerger 与本仓库同机同工具链（cmd / PowerShell 5.1 / gh / git over SSH / 本机 EDR），已积累一套
  `.clinerules` + `memory-bank` + `gh-release.bat`（含 `tools\tee-log.ps1`）的工作方式；cedinia 只有 `build.bat` / `clean.bat`，
  没有 `.clineignore` / `.clinerules` / 知识库，发布只能整链重跑。
- 决策: ①迁入 `.clineignore`（按 `target\` / `android\` / `build\` 结构重写，故意保留 `build\` 下的日志）；
  ②迁入 `.clinerules`（rules / memory-bank / tmp-files，路径、命令、禁令全部换成 cedinia 的：`build.bat` 子命令、`Cargo.toml` 版本真源、`cargo check` 自测）；
  ③迁入知识库（`README.md` / `WRITING.md` / `pitfalls.md` / `issues-solved.md` / `decisions.md` / `archive\`），
  **条目编号沿用原号**（否则条目之间几十处交叉引用全断），内容按 cedinia 的脚本行号复核并标「来源」；
  ④迁入 `gh-release.bat` + `tools\tee-log.ps1`（环境变量前缀从 `_CM_` 改为 `_CED_`）；
  ⑤配套小改：`.gitignore` 加 `/tmp/`，`clean.bat` / `build.bat clean` 顺带清 `tmp\`（让 `ADR-002` 的"收尾清空"成立）。
- 理由: 通用坑（cmd / PowerShell / 终端类）是机器级知识，照抄成本远低于重踩；项目专属条目在 cedinia 没有载体，迁进来只会是噪声。
- 备选与为何不选: 重编号成 cedinia 自己的序列（要改所有交叉引用，且"同名不同事"更易误读）；
  只保留未来新增的条目（把已付过费的机器级结论丢掉）；用 submodule / 软链共享源仓库知识库（跨仓库耦合，改一处影响两处）。
- 影响 / 约束: 同号条目的内容现在是 cedinia 版 —— 引用前先看条目里的「来源」标记；新增条目取**当前最大号 +1**（以 `.clinerules/memory-bank.md` 记的"现有最大"为准，别照抄本条这份迁移时的快照）；
  源仓库那份知识库仍是它的真源，两边不再自动同步（结论更新要各自落）。
- 体积上限按本仓库重设（索引 3KB、`I` / `P` / `D` 各 20KB）：迁移后的条目带 cedinia 的「具体形态 + 判据」，比源条目长，
  先按新值运行；真超限仍照 `WRITING.md` §3 归档（先搬到 `archive/`，主文件留一行摘要）。
- **未迁移的源条目**（cedinia 无对应载体）: `ISSUE-003`（Kotlin `Logger` 日志开关持久化）、`ISSUE-004`（源 `build.bat` 的括号块解析事故，
  机制已由 `PIT-005` 覆盖）、`PIT-022`（`build.gradle.kts` 里 `java.text.X` 全限定名被 Gradle 的 `java` 扩展遮蔽）、
  `ADR-008`（应用内 “更多” 菜单 + BuildConfig 构建信息注入）。

## ADR-013 `build.bat` 的发布链与 `gh-release.bat` 对齐（推翻 `ADR-009` 的"本轮不动 build.bat"）
- 日期: 2026-09-23 | 状态: 已采纳（用户明确要求）
- 背景: `ADR-009` 当初刻意不动主发布链 ⇒ 两套发布逻辑漂移；`ISSUE-005` 的复发（`Connection reset` + `Patch …: EOF`）证明 `build.bat` 那条路
  一旦踩到就是"整条构建做完、发布失败"，且它**没有代理**（全局探测只认 7890，本机在 7897）⇒ gh 裸连、`auth status` 超时被误判"未登录"。
- 决策: 把 `gh-release.bat` 的三件套搬进 `build.bat`（`:git_push` / `:pub_gh_*` / `:pub_gh_del_asset`，`:745-935`）：
  ①`:git_push <ref> [force]`（3 次重试 / 间隔 3 秒 / 落败打印成因 + 手工命令），`git push origin HEAD` 与 `<tag>` 都改走它；
  ②gh 步骤 = 外层 3 次重试 + `:pub_gh_once`（create；或 edit(草稿转正) + REST 按 id 删同名资产 + `upload --clobber`，`PIT-027`）；
  ③发布步骤内**再探一次代理**（7897 → 7890，非 `000` 即认）—— 只设本步骤的 `http_proxy` / `https_proxy`，**不动全局**与 `android\gradle.properties`
  （全局设了会把 cargo / gradle 也拉进代理）；
  ④顺带推导 `GH_REPO`（`gh repo view --json nameWithOwner --jq .nameWithOwner`），只给 REST 删资产用，推导失败就跳过该步；
  ⑤`:pub_check_auth`：`auth status`（联网自检）重试 3 次，仍失败只警告并**继续**发布（不再"静默跳过"，那会表现为"构建成功但没发版"）；
  ⑥`:pub_tag`：远端 tag 已指向 HEAD 就**跳过推送**（走 HTTPS API，避开时通时断的 SSH）；**不做**"指向别处就强推"的交互确认（要能无人值守跑），比较不出来时按老逻辑推。
- 理由: 漂移是 `ISSUE-005` 结构性复发的原因；对齐后瞬断可自愈，不再依赖"手动补发"。
- 备选与为何不选: 只给两处 `git push` 加重试（gh 步骤仍单次尝试，`EOF` 照样中断发布）；让 `build.bat` 直接 `call gh-release.bat`
  （参数 / 日志 / 倒计时链路都要改）；`auth status` 失败改成"继续尝试发布"最初被跳过（保留原"静默跳过"语义）——
  **2026-09-23 第三轮已采纳**（决策 ⑤），"构建成功但没发版"这个缺口已消除。
- 影响 / 约束: **改发布逻辑必须同时改两处**（`build.bat` 的 `:pub_tag` / `:pub_gh_*` 与 `gh-release.bat` 的 `:gh_release*`）；`build.bat` 不能自测
  （跑一次就 patch + commit + push + 发 Release）⇒ 靠抽段测试 + 静态扫描（见 `ISSUE-006` ④-⑧）。本轮 11 个用例全绿: `:git_push` 2、
  gh create 2、gh update 1（含删同名资产）、`:pub_check_auth` 3、`:pub_tag` 3。
- 相关: `ADR-009` / `ISSUE-005` / `ISSUE-006` / `PIT-027` / `PIT-029`
