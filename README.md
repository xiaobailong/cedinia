<div align="center"><img src="https://github.com/user-attachments/assets/ed6dfeea-a984-49e8-a621-8d6ae521c760" alt="cedinia_logo" width="600" /></div>

Cedinia 是一款 Android 触控友好型 GUI 前端，基于 [Slint](https://slint.dev) 构建，为 [Czkawka Core](https://github.com/qarmin/czkawka) 提供图形界面。当前版本：**12.0.4**。

名称来源于 972 年的 Cedynia 战役，这场胜利对早期波兰国家具有重要意义。

<div align="center"><img src="https://github.com/user-attachments/assets/d1e486a2-1d11-4df8-9fff-0e0af2d003da" alt="cedinia_screenshot" width="1000" /></div>

## 功能

### 扫描工具

| 工具 | 说明 |
|------|------|
| 🔍 **重复文件** | 按哈希 (Blake3/CRC32/XXH3)、名称或大小查找内容相同的文件 |
| 📁 **空文件夹** | 查找无内容的目录 |
| 🖼 **相似图像** | 查找视觉上相似的照片，支持多种哈希算法和相似度阈值 |
| 📄 **空文件** | 查找零大小的文件 |
| 🗑 **临时文件** | 查找临时文件和缓存文件（可自定义扩展名） |
| 📦 **最大文件** | 查找磁盘上最大或最小的文件 |
| ⚠ **损坏的文件** | 检测损坏的音频、PDF、压缩包、图片、字体和标记语言文件 |
| 🏷 **无效扩展名** | 查找扩展名与内容不匹配的文件 |
| 🎵 **重复音乐** | 按标签或音频内容查找重复的音乐文件 |
| ✏ **不规范名称** | 查找名称含问题字符的文件（大写扩展名、表情符号、首尾空格等） |
| 📷 **EXIF 数据** | 查找并清除图像中的 EXIF 元数据 |
| 🎬 **相似视频** | 按音频相似度查找相似的视频文件 |

> 注：基于帧的相似视频检测、损坏视频文件检测以及视频优化需要 FFmpeg，目前不支持。

### 图片对比

相似图像工具内置全屏图片对比模式，支持以下视图：

- **Normal** — 并排对比左右两张图片
- **Split** — 滑块分割视图，拖动查看差异
- **Overlay** — 叠加视图，带透明度滑块
- **Diff** — 自动计算像素级差异图

支持在对比界面直接勾选/取消勾选图片、切换上一组/下一组、交换左右图片位置。

### 相似图像图库

以网格卡片形式浏览相似图像分组，一目了然地查看所有分组内的图片缩略图。

### 选择工具

在结果列表中提供丰富的批量选择功能：

- 全选 / 取消全选
- 选择除一个外的所有项
- 选择每组中最大/最小的文件
- 选择每组中最高/最低分辨率的图像
- 反转选择

### 国际化

支持 **27 种语言**：阿拉伯语、保加利亚语、捷克语、德语、希腊语、英语、西班牙语、波斯语、法语、印地语、印尼语、意大利语、日语、韩语、荷兰语、挪威语、波兰语、葡萄牙语、巴西葡萄牙语、罗马尼亚语、俄语、瑞典语、土耳其语、乌克兰语、越南语、简体中文、繁体中文。

### 设置

- **常规** — 缓存开关、隐藏文件过滤、文件大小限制、语言切换、暗色主题、扩展名过滤
- **工具** — 各扫描工具的详细参数配置（哈希算法、相似度阈值、音乐标签等）
- **诊断** — 缩略图缓存管理、应用缓存清理、日志导出、文件访问测试

## 安装

从发布页面下载最新的 release APK：https://github.com/qarmin/czkawka/releases

或下载最新的 nightly 构建版本：https://github.com/qarmin/czkawka/releases/download/Nightly/cedinia.apk

目前尚未通过 F-Droid、Google Play 商店或其他应用商店分发，欢迎提出建议和贡献。

暂不计划支持其他操作系统（如 iOS），不过手动移植应该是可行的。

## 编译 / 环境搭建

项目提供了 `build.bat` 一键构建脚本（Windows），支持以下命令：

| 命令 | 说明 |
|------|------|
| `build` / `build android` | 构建 Android Release APK |
| `build android-debug` | 构建 Android Debug APK |
| `build android-aab` | 构建 Google Play AAB 包 |
| `build desktop` | 构建桌面版 |
| `build clean` | 清理构建产物 |
| `build check` | 检查构建环境 |

构建前需配置以下环境变量：

- `JAVA_HOME` — JDK 21+
- `ANDROID_HOME` / `ANDROID_SDK_ROOT` — Android SDK 路径
- `ANDROID_NDK_HOME` — Android NDK 路径 (27.x)
- `CEDINIA_KEYSTORE_PASSWORD` — 签名密钥库密码（可选，默认使用 123456）

首次构建会自动生成签名密钥库。也可参考 GitHub Actions workflow 获取更多详细信息。

## 已知问题

- 由于 Slint 的 bug，键盘支持目前存在多个问题
- 仅支持竖屏模式和特定的宽高比，可能在某些设备（尤其是平板电脑）上出现问题

## AI 使用说明

由于本项目涉及 Android 部分，开发过程中使用了 AI 辅助，主要用于通过 `jni-rs` / `jni-high` 实现本应用与 Android 之间的桥接代码。相关代码已经过仔细测试。

## 许可证

代码基于 MIT 许可证授权，但由于 Slint 的许可限制，整个项目以 GPL-3.0 协议分发。

所有图标和图片均采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 许可证授权。