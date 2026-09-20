<div align="center"><img src="https://github.com/user-attachments/assets/ed6dfeea-a984-49e8-a621-8d6ae521c760" alt="cedinia_logo" width="600" /></div>

Cedinia 是一款全新的 Android 触控友好型 GUI 前端，基于 Slint 构建，为 Czkawka Core 提供图形界面。

支持与 Krokiet 相同的扫描工具（重复文件、相似图片和视频、空文件和空文件夹、大文件、无效扩展名、重复音乐等）。唯一缺失的功能是基于帧的相似视频检测、损坏视频文件检测以及视频优化，这些功能都需要 FFmpeg。

名称来源于 972 年的 Cedynia 战役，这场胜利对早期波兰国家具有重要意义。

<div align="center"><img src="https://github.com/user-attachments/assets/d1e486a2-1d11-4df8-9fff-0e0af2d003da" alt="cedinia_logo" width="1000" /></div>

## 安装

最简单的安装方式（至少目前如此）是从发布页面下载最新的 release APK：https://github.com/qarmin/czkawka/releases

或者，你也可以在此处下载最新的 nightly 构建版本：https://github.com/qarmin/czkawka/releases/download/Nightly/cedinia.apk

目前尚未通过 F-Droid、Google Play 商店或其他应用商店分发，但我对此领域的建议和贡献持开放态度。

暂不计划支持其他操作系统（如 iOS），不过手动移植应该是可行的。

## 编译 / 环境搭建

构建过程相对复杂，文档也较为有限。你可以参考 Android GitHub workflow 获取更多详细信息，但目前仍缺少完整且最新的说明。

## 已知问题和缺失功能

- 由于 Slint 的 bug，键盘支持目前存在多个问题
- 仅支持竖屏模式和特定的宽高比，可能在某些设备（尤其是平板电脑）上出现问题

## AI 使用说明

由于本项目涉及我不太熟悉的 Android 部分，我在开发过程中使用了 AI 辅助，主要用于通过 `jni-rs` 实现本应用与 Android 之间的桥接代码。相关代码已经过仔细测试。

## 许可证

代码基于 MIT 许可证授权，但由于 Slint 的许可限制，整个项目以 GPL-3.0 协议分发。

所有图标和图片均采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 许可证授权。