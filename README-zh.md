# JMComic3 Flutter

[![版本](https://img.shields.io/github/v/release/MrYu-JMComic/JMcomic3-flutter)](https://github.com/MrYu-JMComic/JMcomic3-flutter/releases/latest)

简体中文 · [English](README.md)

JMComic3 使用 Flutter 构建界面、Rust 提供服务能力。本仓库维护 Flutter 应用、
Android / Windows 平台入口、测试和本地发布工具。当前稳定版为 **v1.7.26+55**。

## 下载与安装

从 [GitHub Releases](https://github.com/MrYu-JMComic/JMcomic3-flutter/releases/latest)
下载本地构建的发布包。

| 文件 | 用途 |
| --- | --- |
| `Jmcomic3-arm64-v8a-*.apk` | 适用于大多数当前 Android 设备 |
| `Jmcomic3-armeabi-v7a-*.apk` | 适用于需要 32 位 ARM 的 Android 设备 |
| `Jmcomic3-android-*.aab` | Android App Bundle，用于分发工具，不能直接安装 |
| `Jmcomic3-windows-x64-*.zip` | 完整解压后运行 `jmcomic3.exe` |
| `SHA256SUMS.txt` / `build-info.json` | 校验下载文件并查看源码、工具链及验证信息 |

Windows 压缩包中的 EXE、DLL 与 `data` 目录需要一起保留。Windows 程序未进行代码
签名，部分系统需要安装 Visual C++ 运行库。

Android v1.7.26+55 沿用已发布 v1.7.25+54 的签名密钥，使用相同架构的 APK 可以覆盖
更新该版本。使用更早签名密钥的安装需要先备份数据，再卸载并重新安装。

本次正式发布和验证的平台为 **Android ARM64 / ARM32 与 Windows x64**；
其他平台不在本版本的发布范围内。

## 主要功能

- 漫画浏览、搜索、分类、详情、彩色标签和章节目录。
- 收藏、阅读历史、每周必看与评论。
- 普通连续、自由缩放连续、单页和双页阅读，支持阅读方向切换与实际可见页进度保存。
- 离线章节阅读、下载管理、导入导出与 WebDAV 同步。
- 响应式导航、主题、语言和网络线路配置。

本次更新内容见 [CHANGELOG.md](CHANGELOG.md)。

## 开发与维护

Flutter 版本由 [.fvmrc](.fvmrc) 固定。Rust 后端位于独立的
[jmcomic3-rust-backend](https://github.com/MrYu-JMComic/jmcomic3-rust-backend)
仓库，发布使用的提交记录在 [ci/backend.commit.txt](ci/backend.commit.txt)。
后端检出目录、工具链、签名密钥和构建产物不提交到本仓库。

- [构建与测试](docs/BUILDING.md)
- [分支、PR 与发布规范](docs/RELEASING.md)
- [Android 阅读器回归](integration_test/README.md)

## 引用与致谢

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)：Flutter 阅读器结构
  和阅读交互参考，固定参考提交为
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)：
  独立 Rust 后端的移动端 API 协议、请求签名与请求头、登录和域名回退参考；
  本应用没有将该 Python 项目作为运行时依赖。
- `zoomable_positioned_list` 1.1.0：连续阅读组件，保留上游版权和许可证，本地补丁
  见 [PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md)。

详细引用范围和第三方声明见 [REFERENCES.md](REFERENCES.md)。相关项目名称及版权
归各自作者所有，本项目独立维护。

## 使用约定

应用访问第三方服务，服务可用性取决于外部站点。请在遵守当地规定和内容权利的前提下
用于个人学习。沿用原项目的禁止商用、禁止转发内容资产约定；第三方组件继续适用
各自许可证。