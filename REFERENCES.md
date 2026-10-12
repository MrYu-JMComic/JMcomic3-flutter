# 项目引用与第三方声明

本文件保留当前实现的来源说明。删除历史计划文档不代表删除原作者的贡献与版权。

## ComicSparks/jasmine

- 项目：[ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)。
- 固定参考提交：[`e514be163ec39a6f9e0d2799580d132324e23470`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- 参考范围：Flutter 漫画浏览器结构、阅读模式组织、连续阅读的索引列表、
  `PhotoViewGallery` 图库缩放和可见页驱动的阅读进度交互。
- 对应实现：`lib/screens/comic_reader_screen.dart`、`lib/screens/reader/` 与
  `third_party/zoomable_positioned_list/`。
- 本项目补充了反向主轴手势、实际滚动边界、跳页竞态、进度串行保存、资源释放和回归测试。
- 固定参考提交的根目录没有可随代码保留的 `LICENSE` 文件，原 README 的禁止商用与
  内容资产转发约定继续在本项目 README 中标明。本项目不将整个仓库声明为 MIT。

## hect0x7/JMComic-Crawler-Python

- 项目：[hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)。
- 参考范围：`jm_config.py`、`jm_client_impl.py` 中的移动端 API 协议、版本与时间戳、
  请求签名、请求头、登录表单及域名候选/回退处理。
- 对应实现：独立 [Rust 后端](https://github.com/MrYu-JMComic/jmcomic3-rust-backend)
  中的 API 请求与响应适配；Flutter 通过 MethodChannel / C ABI 调用该后端。
- 本应用不包含 Python 解释器，也不将该项目列为运行时依赖。这里标注协议参考来源。
- 上游 [MIT 许可证](https://github.com/hect0x7/JMComic-Crawler-Python/blob/master/LICENSE)
  的版权声明为 `Copyright (c) 2023 hect0x7`；其许可证保留在上游仓库。

## zoomable_positioned_list 1.1.0

- 来源：[pub.dev 1.1.0](https://pub.dev/packages/zoomable_positioned_list/versions/1.1.0)。
- 发布归档 SHA-256：`f17148ca7be6775131737b11ab738d059b845b7e3988d0095eb5b6e41c9023e4`。
- 本地副本：`third_party/zoomable_positioned_list/`，用于连续阅读的缩放和索引定位。
- 保留 [MIT LICENSE](third_party/zoomable_positioned_list/LICENSE) 和原始
  [Fuchsia / Google BSD 声明](third_party/zoomable_positioned_list/LICENSE.fuchsia)。
- 补丁及验证说明：[PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md)。

## 其他依赖与资源

Flutter / Dart 包版本由 `pubspec.yaml` 与提交的 `pubspec.lock` 记录，使用各依赖自己的
许可证。Flutter 的许可证登记机制保留包内声明；发布时同时保留所分发第三方组件的声明。
Rust 后端的固定版本见 `ci/backend.commit.txt`，后端仓库分别维护源码与依赖声明。
漫画、图片和第三方服务内容的权利属于相应权利人。