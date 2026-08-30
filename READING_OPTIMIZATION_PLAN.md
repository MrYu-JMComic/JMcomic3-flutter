# 阅读功能优化方案（持续维护）

> 文档性质：基于当前代码的设计、风险和实施跟踪文档。每次审查或实现后，先更新本文档，再修改代码。
>
> 最后更新：2026-08-30（二次逻辑/后果审查）
>
> 当前状态：方案审查完成；M1 已提交一个可回滚子集，正在进行提交后的静态复核。Flutter/Dart/Rust 运行时验证仍待工具链准备，所有后续任务继续按阶段门禁执行。

## 1. 目标与边界

### 目标

1. 降低长章节阅读的解码内存、首图延迟和掉帧。
2. 让在线阅读、离线阅读、单页、纵向和双页模式共享一致的数据与进度语义。
3. 避免预取浪费流量，保证切章、重试、后台恢复和离线场景可控。
4. 建立可回滚、可测量、可观测的发布流程。

### 非目标

- 第一阶段不重写整个 `ComicReaderScreen`。
- 不在解扰前对 JM 原始图片做缩放、裁剪或压缩。
- 不把普通“清理缓存”扩展成删除用户已下载内容。
- 不在没有基线的情况下承诺固定的性能百分比。

## 2. 当前阅读链路

```text
在线：ComicInfo/入口 → ComicReaderScreen → methods.chapter
离线：DownloadAlbumScreen → ComicReaderScreen → methods.dlImageByChapterId
                                  ↓
              _ComicReader 根据配置选择四种 reader state
```

关键文件：

- [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart)
- [D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart)
- [D:/Cat/jmcomic3/lib/basic/methods.dart](D:/Cat/jmcomic3/lib/basic/methods.dart)
- [D:/Cat/jmcomic3/lib/basic/entities.dart](D:/Cat/jmcomic3/lib/basic/entities.dart)
- [D:/Cat/jmcomic3/lib/screens/download_album_screen.dart](D:/Cat/jmcomic3/lib/screens/download_album_screen.dart)
- [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs)

### 已有可复用基础

- WebToon/List 已使用 builder，未必要整体换成另一套列表组件。
- 当前页 UI 更新有约 80ms 节流。
- 阅读记录已有约 220ms debounce，并在 dispose 时尝试 flush。
- 图片尺寸 Future 有 in-flight 合并测试，见 [D:/Cat/jmcomic3/test/download_album_test.dart](D:/Cat/jmcomic3/test/download_album_test.dart:535)。
- 测试目录目前只有 `download_album_test.dart` 和一个 16 行的 `widget_test.dart`，没有四种 reader state 的专门回归/性能测试；因此“已有测试基础”不能等同于阅读链路已被覆盖。
- Rust 已有原子写、坏缓存清理、按章节目录和 validated-path LRU。
- 下载状态使用分片持久化，章节加载器通过回调注入，在线/离线入口可以共享。

### 阅读模式现状矩阵

| 模式 | 主要组件 | 当前图片入口 | 当前尺寸来源 | 主要优化边界 |
|---|---|---|---|---|
| Gallery | `PhotoViewGallery.builder` | `PageImageProvider` | codec 默认尺寸 | 先验证 target codec 和邻页调度；不改解扰顺序 |
| 自由缩放/横向 | `PhotoViewGallery.builder` | `PageImageProvider` + `PhotoView` | codec 默认尺寸、运行时缩放 | target 只做初始采样，不能把放大手势误当作缓存尺寸 |
| WebToon/纵向 | `ScrollablePositionedList.builder` | `JMPageImage` | `renderSizeFor` + `ResizeImage`（路径图片） | 先修真实高度/陈旧回调，再统一 descriptor 尺寸 |
| 双页 | `PhotoViewGallery`（整章 options） | `PageImageProvider` | codec 默认尺寸 | 先做配对/封面/RTL 测试，再窗口化；target key 需限档 |
| 离线 | `DownloadAlbumScreen` 注入 `loadChapter` | 仍调用 `jm_page_image` | metadata 名称，路径由后端解析 | 必须先有 offline owner/localPath；`dl_status` 不能替代文件校验 |

## 3. 已确认的问题与影响

| ID | 问题 | 证据 | 主要后果 | 初始优先级 |
|---|---|---|---|---|
| R-01 | Gallery、自由缩放、双页直接使用 `PageImageProvider`，没有像 `buildFile` 那样明确使用目标尺寸 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1360)、[D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:862) | 原图位图解码，低端设备 OOM/掉帧 | P0 |
| R-02 | 双页初始化整章创建 `ips/options`，使用非 builder 的 `PhotoViewGallery` | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:2142) | 长章节初始化慢、内存峰值高；封面/RTL 配对难维护 | P1（高风险） |
| R-03 | 预取固定范围，未统一去重、优先级、取消和错误处理 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1434) | 快速翻页时重复请求和无效流量 | P1 |
| R-04 | 页面路径和尺寸可能分开走桥接调用；章节级缓存不足 | [D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:624) | 首图延迟和 FFI/JSON 往返增加 | P1 |
| R-05 | 离线章节只把 `DlImage` 映射成名称，丢掉宽高 | [D:/Cat/jmcomic3/lib/screens/download_album_screen.dart](D:/Cat/jmcomic3/lib/screens/download_album_screen.dart:324) | 纵向布局、跳转和目标解码缺少可靠元数据 | P0/P1 |
| R-06 | 纵向阅读用总滚动比例推算页码；远跳也用线性比例 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1851) | 可变高度图片进度不准、恢复位置抖动 | P1（高风险） |
| R-07 | 全屏初始化与自定义 AppBar 高度存在逻辑/布局风险 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:367)、[D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:913) | 系统栏闪烁、内容遮挡或无效空白 | P0 |
| R-08 | `clean_all_cache` 删除的目录与下载页图共享；下载 worker 当前只是调用 `jm_page_image` 并记录 completed，并没有另存一份 offline 文件 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3176)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3997) | 下载状态显示完成但图片被清理，离线阅读失败；简单改目录会直接破坏导出和恢复 | P1（迁移风险高） |
| R-09 | Rust 首次缓存校验可能整文件读取；解扰需完整 RGBA 转换和重新编码 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8524)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8615) | 后端冷启动 CPU/I/O/内存峰值高 | P1 |
| R-10 | 页面相对路径通常只有一个 CDN URL；重试未按错误类型细分 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8237)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8788) | 单 host 故障时失败或产生无效重试 | P1 |
| R-11 | 阅读记录、全局事件和音量监听跨 state 共享 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:166)、[D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:279) | 快速切页/切章、配置变化和销毁时存在竞态 | P1 |
| R-12 | `sort` 使用 `int.parse`；release 日志和阅读器测试不足 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:309)、[D:/Cat/jmcomic3/.github/workflows/Build.yml](D:/Cat/jmcomic3/.github/workflows/Build.yml:3) | 脏数据崩溃，回归难以发现 | P0/P2 |
| R-13 | 工具链版本漂移，不只是“测试不一致” | [D:/Cat/jmcomic3/.fvmrc](D:/Cat/jmcomic3/.fvmrc:2)、[D:/Cat/jmcomic3/.github/workflows/Build.yml](D:/Cat/jmcomic3/.github/workflows/Build.yml:28)、[D:/Cat/jmcomic3/pubspec.yaml](D:/Cat/jmcomic3/pubspec.yaml:8) | CI 使用的 Flutter/Dart 可能不满足当前 SDK 约束，导致门禁本身无法解析 | P0 |
| R-14 | `ignore_view_log` 在 Dart 侧传入并参与缓存 key，但 Rust `album` 参数结构目前只反序列化 `id` | [D:/Cat/jmcomic3/lib/basic/methods.dart](D:/Cat/jmcomic3/lib/basic/methods.dart:499)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:4324) | 设置可能只改变 Dart 缓存分桶，未改变后端行为；读者初始化还会多发一次 album 请求 | P0/P1 |
| R-15 | `ComicReaderScreen.initState` 在 `super.initState()` 前调用 `_load()`，而 `_load()` 内部调用 `setState` | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:58) | debug 生命周期检查可能直接报错，初始化行为依赖 Flutter 版本 | P0 |
| R-16 | path/size Future 被 force-refresh 淘汰后，旧 Future 的 `catchError` 仍按同一个 key 无条件 remove | [D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:191)、[D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:283) | 重试时旧请求失败可能误删新请求的缓存项，导致重复请求、错误闪烁或“新请求永远不复用” | P0/P1 |
| R-17 | 离线 reader 目前只拿到名称和状态，图片路径仍通过 `jm_page_image` 解析；`dl_status=1` 不等于本机文件存在 | [D:/Cat/jmcomic3/lib/screens/download_album_screen.dart](D:/Cat/jmcomic3/lib/screens/download_album_screen.dart:326)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:6859) | 无网或清理后会把“完成”页面当作在线请求，产生错误或长时间等待 | P0/P1 |
| R-18 | WebDAV 当前同步下载元数据而非实际图片文件 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:7934) | 另一设备恢复出 `completed` 壳记录，但本地没有可读图片 | P1 |
| R-19 | view-log 只有服务端接收时生成的 `last_view_time`，没有客户端事件序号/时间戳 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:218) | 队列重放、跨设备同步或网络乱序时，较旧页面可能覆盖较新页面 | P1 |
| R-20 | `_ComicReader.didUpdateWidget` 只重建章节缓存，没有重置当前页、滚动控制器、子 state 或预取 generation | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:387) | 父层复用同一 State 切章时可能沿用旧索引/offset；旧页异步结果还可能写入新章节，甚至越界 | P0/P1 |
| R-21 | 阅读模式/方向设置通过异步 `reload` 切换，未定义 flush、取消旧任务和恢复位置的事务边界 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:387) 附近及各 reader state | 切换模式期间丢进度、跳回错误页、旧预取结果污染新模式；bottom sheet 返回时 State 可能已销毁 | P1 |
| R-22 | 音量监听释放依据 dispose 时的“当前配置”，不是 init 时是否实际订阅 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:378) | 运行中关闭/打开设置会导致全局计数不对称、重复监听或订阅泄漏 | P0/P1 |
| R-23 | 全屏退出固定写回 `edgeToEdge + overlays`，且 init 的系统副作用发生在 `super.initState` 前 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:366) | 覆盖进入阅读前的沉浸式/桌面系统 UI 状态；初始化异常时可能留下全局副作用 | P0/P1 |
| R-24 | `JMPageImage` 的尺寸回调和旧 `_future` 没有 generation/identity 校验 | [D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:615) | cell 快速复用或重试乱序时，旧页面尺寸写入新页面，纵向布局/进度错误；旧失败可能影响新请求 | P0/P1 |
| R-25 | `PageImageProvider` 当前 key 只有 id/name/scale；加入目标尺寸后若直接使用窗口/DPR 原值会产生大量 key | [D:/Cat/jmcomic3/lib/screens/components/images.dart](D:/Cat/jmcomic3/lib/screens/components/images.dart:89) | 旋转、分屏、DPR 变化造成缓存膨胀和旧尺寸命中；目标解码收益被 cache churn 抵消 | P1 |
| R-26 | 下载任务去重/状态更新主要按 `chapter_id + image_name`，没有完整 offline owner 维度 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3885) | 同名页跨任务/专辑可能互相覆盖；删除或重试一个任务会影响另一个任务 | P1 |
| R-27 | `dl_image_by_chapter_id` 优先返回 store 元数据，不验证路径、长度和可读性 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3630) | 文件被清理/截断后仍显示 completed；离线 reader 反复走网络路径，错误延迟暴露 | P0/P1 |
| R-28 | 图片文件名进入路径/缓存 key 的规范化边界尚未统一 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:6859)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8603) | `../`、分隔符、Windows 保留字、大小写碰撞或超长 Unicode 可能导致路径逃逸、覆盖或不可读 | P0/P1 |
| R-29 | reader 预取、下载 worker 和解扰共用的 CPU/IO 预算尚未形成统一调度 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1431)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3961) | 后台下载可挤占当前页，取消只丢弃结果但仍消耗网络/线程；首图 P95 反而变差 | P1 |
| R-30 | 诊断/重试日志若直接记录请求 URL，可能包含 cookie、签名参数或用户标识 | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8562) | 日志泄漏凭据，且高频预取造成日志/磁盘增长；难以满足隐私和配额要求 | P1 |
| R-31 | `maybe_unscramble_jm_page_image` 在行重排失败时回退原始 bytes，而上层仍可能把它写入 `decoded_v1` | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8615) | 原始 scrambled 图片可能被误标为 canonical；目标尺寸解码虽不破坏解扰，却会把错误源稳定缓存，问题难以通过重试自愈 | P0/P1 |
| R-32 | `resolve_jm_page_image_urls` 接受 image name 中的任意绝对 URL/`//host`，reader 请求会附带全局 cookie 和 referer | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8237)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8804) | 恶意/脏元数据可诱导向非 CDN 主机发送凭据；fallback 扩展后泄漏面更大 | P0/P1 |
| R-33 | `clean_all_cache` 递归删除整棵目录，与正在 fetch/读取/下载的文件没有统一锁或 generation | [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:3176)、[D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs:8524) | Windows 文件锁、半文件、ENOENT 和“刚下载即被删”竞态；清理后状态与文件不一致 | P0/P1 |
| R-34 | `readerKeyboardHolder` 在每次 build 创建新的 `FocusNode`，没有对应 dispose | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:190) | 重建/切换设置后焦点节点泄漏、焦点状态异常，键盘响应不可预测 | P1 |
| R-35 | Gallery/双页的 `addPostFrameCallback`、`precacheImage` 结果没有统一的 mounted/chapter generation 和错误收敛 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1444)、[D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:2302) | 快速 pop/切章后仍访问旧 context、未处理异常或把旧图写入新 session；后台任务持续占资源 | P1 |
| R-36 | `startIndex` 未按章节 image count 统一 clamp；空章节也可能创建 `PageController`/列表 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:376)、[D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1309) | 旧阅读记录、脏数据或空响应导致越界、初始页断言、无法退出章节 | P0/P1 |
| R-37 | `chapter.images` 未统一过滤空名/重复名并保留服务端索引映射 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:1260)、[D:/Cat/jmcomic3/lib/screens/download_album_screen.dart](D:/Cat/jmcomic3/lib/screens/download_album_screen.dart:333) | 空名路径请求失败；重复名共享 provider/cache，错误重载一个页可能影响另一个页，页码与服务端顺序脱节 | P1 |
| R-38 | `reload`/`onChangeEp` 在异步导航回调中没有统一的 `mounted`、串行化和重复触发保护 | [D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart](D:/Cat/jmcomic3/lib/screens/comic_reader_screen.dart:120) | 快速切章/返回时对已卸载 context 调 Navigator，抛导航生命周期异常或叠加多个 replacement | P0/P1 |
| R-39 | `DownloadCreate.initialChapterId` 在章节列表为空时回退为 `album.id`，下载页仍允许进入 reader | [D:/Cat/jmcomic3/lib/basic/entities.dart](D:/Cat/jmcomic3/lib/basic/entities.dart:1231)、[D:/Cat/jmcomic3/lib/screens/download_album_screen.dart](D:/Cat/jmcomic3/lib/screens/download_album_screen.dart:268) | album id 被当作 chapter id 请求，空下载任务进入黑屏/错误重试；“兼容旧数据”反而掩盖数据损坏 | P0/P1 |

## 4. 关键不变量（任何实现都不能破坏）

1. **解扰顺序不变**：原始图片必须先由 Rust 完整解扰，再写入 canonical `decoded` 文件；Flutter 的目标尺寸只作用于已解扰文件的最终 codec 解码。
2. **canonical 文件不可被缩略图覆盖**：目标尺寸变体不能覆盖 `decoded_v1`；如落盘，必须使用独立版本和独立 key。
3. **离线文件不受普通缓存清理影响**：只有明确的“删除下载”操作才能删除 offline assets。
4. **当前页优先于预取**：任何预取失败不得冒泡为当前页失败。
5. **旧接口可回退**：批量 API、进度新格式和新缓存目录都必须保留旧路径/旧协议的兼容读取。
6. **最新本地进度优先**：远端同步失败不能覆盖本地较新的进度；写回必须按事件序号/客户端时间戳幂等、单调，不能要求 page index 单调递增（用户可以回退阅读）。
7. **任何新能力可独立关闭**：目标解码、调度器、批量接口、双页窗口化、缓存迁移分别具备开关或回退路径。
8. **解扰失败不可伪装成功**：行重排/重新编码失败时不得把原始 scrambled bytes 写入 `decoded_v1`；必须返回可分类错误或进入未验证临时态。
9. **请求目标必须受信任**：图片 metadata 中的 URL 只能命中允许的 CDN/代理 host；向非允许 host 请求时不得附带全局 cookie 或 referer。
10. **清理与写入互斥**：缓存清理、下载落盘、读取/校验必须通过同一 owner 锁或原子版本协议协调，不能让清理穿过正在提交的文件。

## 5. 对原计划逐项逻辑与后果审查

| 任务 | 逻辑判断 | 可能后果 | 修订决定 |
|---|---|---|---|
| 先做目标尺寸解码 | 方向正确，但不能假设外层 `ResizeImage` 对自定义 provider 一定真正下采样；当前 provider 同时实现新旧 load API，并直接调用 `decode(buffer)` | 可能看似改完但仍按原图生成位图；若把尺寸加入缓存 key，会增加多尺寸缓存数量 | 单独做 M2；先用 `ImageInfo.image.width/height` 和 profile 验证，必要时显式在 provider codec 传 target；只保留 1–2 个档位，放大时原图兜底 |
| 把 target decode 放在 P0 止血 | 只降低 Flutter 位图内存，不能消除 Rust 解扰的完整 RGBA 峰值，也不能减少 `readAsBytes` 的压缩字节峰值 | 对 OOM 的改善被夸大，用户可能仍在极端大图上崩溃 | 从“P0 必做”降为独立、可验证的小步；指标拆分 Flutter 峰值和 Rust 峰值 |
| 一次性引入 ReaderSession | 抽象方向正确，但四种 state 有不同 controller、手势和生命周期 | 大重构同时改变进度、手势、全屏，回归难定位 | 先定义 `PageDescriptor/Repository` 纯数据层，再以 facade 逐模式接入；保留旧回调和 feature flag |
| 立即做可取消预取 | 队列任务可取消，但已发出的 MethodChannel/Rust HTTP 不一定能中断 | “取消”可能只是不写回结果，流量仍已消耗；并发还会与下载/解扰抢资源 | 明确两级语义：队列取消 + generation 丢弃；后端 request_id 取消另行实现；共享 network/CPU semaphore |
| 双页立即改 builder | 能降整章 widget 数量，但配对、封面偏移、RTL、旋转和 `PhotoView` 相邻预建都复杂 | 可能出现左右页错位、首张封面消失、恢复到错误页 | 与 scheduler 分离发布；先补配对测试，再做页对窗口化 |
| 直接用实际高度重做纵向进度 | 目标正确，但懒构建列表远端页面的高度在布局前未知 | 远跳需估算后校正，图片尺寸异步变化会导致跳动 | 定义“最主要可见页”规则；保存 page+offset；估算→滚动→二次校正；兼容旧百分比 |
| 用批量接口替代所有单页接口 | 能减少桥接往返，但整章响应会放大 JSON、内存和失败面 | 一页失败可能拖累整批；旧版本协议不兼容 | 批次限长、逐项结果、部分成功、版本化；旧单页接口并行 fallback |
| Rust 侧生成多个尺寸文件 | 能降低重复解码，但磁盘会按尺寸倍增，且容易误把变体当解扰源 | 存储膨胀、缓存污染、解扰失败 | 默认只保留 canonical 解扰文件；尺寸变体仅在有基准后作为短期 LRU |
| 直接降低 PNG 压缩等级 | 可能降低 CPU，但会增大文件体积/流量 | 网络和磁盘成本上升，格式/缓存版本不一致 | 先 benchmark；编码算法或解扰版本变更必须 bump cache schema |
| 缓存校验改 sidecar/头部 | 可减少整文件 I/O，但 sidecar 与图片不是同事务就不可信 | 崩溃后出现“元数据有效、图片损坏” | 使用临时文件+原子 rename，或保守保留一次完整校验 |
| 增加 CDN fallback/熔断 | 对 host 故障有效 | URL 规范化错误、错误页写缓存、瞬时故障误熔断、敏感 URL 泄漏 | 逐 host 校验 MIME/内容；Retry-After 有上限；不记录完整 URL；独立开关 |
| 用写回队列替换 220ms debounce | 能降写盘，但队列本身引入崩溃丢失和并发顺序问题 | pause/route pop 时未 flush 会丢最新进度；部分失败可能整批丢失 | 先保留 debounce，新增单写者队列和强制 flush；失败保留、幂等、容量上限；稳定后再切换 |
| 立即做磁盘配额清理 | 可防止缓存无限增长 | 可能删掉正在读取/下载的文件，Windows rename/lock 失败 | 只作用 reader_cache；按 manifest、实际大小和最后访问淘汰；清理与下载共用锁 |
| 简单把 `image_cache` 改名为 `reader_cache` | 目录名变化本身不能产生离线副本；当前下载 worker 的 `resolve_download_image_path` 直接复用 `jm_page_image` 返回的路径 | 下载完成状态仍指向临时 reader 文件，迁移后可能全部变成“完成但不存在” | M6 必须先实现 offline owner/copy 或专用下载路径，再做清理语义；导出链路同步验证 |
| 把 `dl_status=1` 当作离线可读 | 状态来自元数据，不代表文件仍在本机；WebDAV 也不传图片 | 离线场景会反复等待网络，或把损坏/缺失文件显示成完成 | 新增 `localPath/availability`，启动和打开章节时校验存在性；缺失时明确显示重新下载 |
| 让 WebDAV 同步后直接标记本地下载完成 | 当前同步的是下载 metadata，不是图片 bytes | 用户以为可离线阅读，实际首次打开才失败 | 将“远端完成”和“本地可读”拆成两个状态；同步后只进入待补齐状态 |
| 以“页码单调递增”解决 view-log 乱序 | 用户可以主动退回上一页/上一章，页码本身不能单调 | 合法的回退阅读不会被记录，或被错误丢弃 | 单调约束应放在事件序号/客户端时间戳，不是 page index；合并规则按 session sequence 决定 |
| 先做视觉/动效增强 | 用户可感知，但不解决首要性能问题 | 增加手势冲突、遮挡和无障碍回归 | 放在基础稳定性之后；控件满足 safe-area、Semantics、44/48dp 和 reduced-motion |
| 先补 CI 和指标 | 逻辑正确，是所有后续任务的验证基础 | 如果 Flutter/NDK/backend 版本未固定，指标和测试结果不可比较 | 先冻结工具链和 backend SHA，再加 analyze/test/contract smoke |
| 只把 Flutter 版本写成同一个数字 | 还要核对 Dart SDK 约束、插件兼容性、生成代码和 NDK | CI 可能在 `pub get` 阶段就失败，或本地与发布产物行为不同 | M0 先做“可解析、可构建、可测试”的工具链矩阵，不能只改 workflow 字符串 |
| 给现有 Build/Release workflow 直接加 PR 触发 | 这两个 workflow 会签名、下载外部 backend、构建 APK，并依赖 secrets | 每个 PR 变成昂贵且可能因密钥/私有仓库失败的发布构建，开发反馈变慢 | 新建无签名、无发布副作用的 `CI` workflow 做 analyze/test；Build/Release 继续手动或受保护分支触发 |
| 一开始接入远程 feature flag | 当前代码没有明显的阅读能力 flag 框架；远程配置本身可能失败、延迟或被缓存 | 新能力的默认值和回滚行为不确定，调试时出现组合爆炸 | 首期使用本地/编译期能力开关，按单一能力隔离；远程开关待观测链路稳定后再加 |
| 直接删除 reader 初始化中的 `album()` 请求 | 可能会改变“详情页不记录、阅读页记录”的产品语义；而且当前 Rust 是否消费 `ignore_view_log` 尚未对齐 | 可能导致详情页/阅读历史重复记录或完全不记录 | 先写协议测试并明确语义；修复参数传递后，再决定是否删除额外请求 |
| 用固定性能目标验收 | 目标有方向性 | 没有设备/网络基线时容易误判，预取命中率也受网络影响 | 先采基线；同时看白屏率、取消后流量、错误率、帧耗时和峰值内存 |

## 6. 修订后的实施路线

估时为单人粗估，实际以基线和测试结果为准。

### 当前任务状态

| 任务 | 状态 | 下一动作 | 进入条件/阻塞 |
|---|---|---|---|
| 二次逻辑/边界审查 | 已完成（本轮） | 将新增风险和发布门禁纳入本文档 | 只读审查；未修改业务代码 |
| M0 基线与工具链冻结 | 部分完成（分支/PR） | 准备目标 Flutter/Rust 工具链，采集三类设备基线 | 分支 `MrYu/reader-optimization-m1`、Draft PR #2 和基线 tag 已建立；2026-08-30 检查仍未找到 `flutter`、`dart`、`cargo`、`fvm`、`rustup` |
| M1 低风险稳定性修复 | 已实现子集（待运行时验证） | 安装/锁定工具链后补 widget 回归；再决定是否继续 M1 全屏状态恢复 | 已提交生命周期/缓存竞态子集及异步错误/索引防护补强；本环境无法运行 Flutter 测试，target-size/离线 owner 未混入 |
| M2 目标尺寸解码 | 待验证 | 用 known scrambled fixture 检查 codec 实际输出尺寸 | 必须证明 target 不会在 provider 内被忽略 |
| M3 PageDescriptor/Repository | 待开始 | 先增加兼容转换，不改变现有 UI | 需要确认在线 chapter 响应的旧/新格式 |
| M4 ReaderSession/generation 与预取调度器 | 待开始 | 先定义 chapter identity、取消/丢弃语义，再只在在线 Gallery 实验 | 需要 M2、M3 的页面 key/尺寸语义；不得与双页重构同批发布 |
| M5 Rust 批量与网络协议 | 待开始 | 先定义版本化 contract 和部分成功结构 | 需要 wire/mock contract test |
| M6 离线缓存隔离 | 待开始 | 盘点旧目录 owner，设计 manifest 和迁移演练 | 不能在未确认下载文件归属前清理旧目录 |
| M7 双页窗口化 | 待开始 | 先固定封面、奇偶和 RTL/LTR 配对规则 | 需要独立 widget/golden 回归 |
| M7 垂直精确进度 | 待开始 | 定义可见页规则和远跳二次校正算法 | 需要 PageDescriptor 尺寸或可靠 fallback |
| M7 阅读记录队列 | 待开始 | 在现有 debounce 外加单写者队列和 lifecycle flush | 需要明确本地存储的崩溃恢复能力 |
| P2 测试/CI/观测 | 待开始 | 先固定版本，再添加 PR 门禁和结构化指标 | CI 当前不自动触发且版本漂移 |

### 本轮继续执行记录（2026-08-30）

- 在 `715c469` 上创建并推送可恢复检查点标签 `reader-optimization-m1-checkpoint-715c469`；不改写已有提交历史。
- 对 M1 两个代码提交完成第二轮只读复核：确认空章节在父层被拦截、索引被统一 clamp、Future identity/generation 防护和监听事实记录已覆盖主要路径。
- 发现并列入下一独立修复提交的低风险项：`JMPageImage` 旧请求在 generation 失效后仍可能发起尺寸查询；FutureBuilder 类型应显式化；reader 复用章节时应补齐加载器/章节身份与阅读记录语义；初始化专辑请求需收敛异常。
- 当前未运行 Flutter/Dart/Cargo；上述问题不能以“编译通过”表述，修复后仍须在工具链可用时执行 analyzer、widget test 和 Rust contract test。

### M0：基线与工具链冻结（0.5–1 天）

- 记录低端 Android、常规 Android、iOS/桌面各一组：首图、切章、长章节峰值内存、白屏、错误、帧耗时。
- 记录 Rust 解扰耗时和峰值内存，与 Flutter codec 解码耗时分开。
- 先验证 `.fvmrc`、CI Flutter 对应的 Dart SDK 是否满足 [D:/Cat/jmcomic3/pubspec.yaml](D:/Cat/jmcomic3/pubspec.yaml:8)，再统一 NDK 并固定 Rust backend commit/tag；不能只替换 workflow 中的版本字符串。
- 只加诊断，不改变默认阅读行为。

### M1：低风险稳定性修复（2–3 天）

- 修全屏系统栏和真实 AppBar/SafeArea 布局。
- 修正高度时必须同时审查各 reader 的 `padding`、底部 130px 补偿和 `Column` 空间，不能只把 `_appBarHeight()` 从 0 改成 56，否则会双重留白或改变恢复 offset。
- `sort` 使用 `tryParse` 和稳定 fallback。
- 修复 listener、FocusNode、Timer、异步回调的生命周期保护。
- 为键盘 FocusNode 建立明确 owner 并在 dispose 释放；导航/刷新使用 `mounted` 和单飞 token。
- 将 `ComicReaderScreen.initState` 中依赖 `setState` 的初始 `_load()` 改为 `super.initState()` 后直接赋值，避免 debug 生命周期断言。
- 重试时精准 evict provider，不清空全局 image cache。
- 修复 in-flight Future 淘汰竞态：`catchError` 只有在 map 中仍指向同一个 Future 时才可 remove。
- 对齐 `ignore_view_log` 的 Dart/Rust 协议和产品语义；在协议未验证前不删除 reader 初始化请求。
- FutureBuilder 进入 reader 前处理空章节；对 `initRank` 做统一 clamp，并对空名/重复图片保留稳定索引或显示明确占位。
- 为章节加载失败、重试和切章补最小 widget 回归。

### M2：已解扰文件的目标尺寸解码（3–5 天）

- 保持 Rust 的“下载→解扰→canonical 文件”顺序不变。
- 在 Gallery/WebToon 先做验证，再接自由缩放和双页。
- 验证 provider 实际输出像素尺寸；缓存 key 必须区分尺寸和算法版本。
- 先在选定 Flutter 版本上确认 `loadBuffer`/`loadImage` 的 decoder 签名和废弃行为；不能用一套 provider API 假定兼容 `.fvmrc` 与旧 CI 版本。
- 目标尺寸切换时保留请求 generation，旧尺寸 Future 不能清掉新尺寸 Future。
- 只保留固定尺寸档位；放大时按需原图兜底。
- 以 known scrambled fixture 检查方向、比例和内容一致性。
- 将“无须解扰”和“解扰失败”区分为不同结果；失败不得回退成可写入 `decoded_v1` 的原始 bytes。

### M3：统一页面数据模型（约 1 周）

- 新增 `PageDescriptor`，在线旧 `images: List<String>` 可转换，离线保留 `DlImage.width/height`。
- 新增 `ChapterRepository/ImageRepository` facade，但不改变默认渲染。
- 页面尺寸失败时回退到现有 `image_size`，不得让布局等待永不结束。

### M4：ReaderSession/generation 与预取调度器（约 1 周）

- 先定义 chapter identity、模式切换和 generation 生命周期，再只对在线 Gallery 灰度启用。
- 实现优先级、去重、并发上限、generation 丢弃、网络条件判断。
- 预取失败隔离；记录实际取消与无效流量，不把“取消”宣传成已中断网络请求。
- 与下载 worker 共享资源预算，避免解扰 CPU 被后台下载挤占。

### M5：Rust 批量与网络协议（1–2 周）

- 增加版本化的页面元数据/批量路径接口，限制批次大小和响应体。
- 每项返回成功或错误，保留旧单页 API fallback。
- 增加 CDN fallback、错误分类重试、退避抖动、MIME 校验和 host 熔断。
- 绝对 URL/`//host` 仅允许受信任 host；非受信任目标不得携带 cookie/referer；fallback 不能扩大凭据发送范围。
- 解扰/编码/缓存校验优化必须先 benchmark，再变更默认值。

### M6：离线缓存隔离（约 1 周起，需迁移演练）

- 盘点旧 `image_cache` 的 owner，建立 manifest 和 schema 版本。
- 先让下载 worker 把已完成文件**复制**到 offline owner，校验并原子落盘后再写 completed；迁移稳定一个版本周期后才评估删除旧副本，不能只改目录常量或直接移动。
- 启动时原子迁移或只读兼容，不因迁移失败删除旧文件。
- 只清理 reader_cache；下载文件由任务管理器显式删除。
- 下载状态在文件原子落盘后再标记 completed；清理与读取/下载使用同一保护机制。
- `clean_all_cache`、fetch、读取校验共享锁或提交 generation；清理不得删除正在提交/读取的文件。
- 离线 reader 通过专用本地路径接口读取并校验文件存在性；WebDAV 恢复的 metadata 只能标记“待补齐”，不能伪装成本地可读。

### M7：高风险阅读模型（各自独立开关）

- 双页窗口化：先做封面/奇偶/RTL/LTR/旋转测试，再替换整章 options。
- 垂直精确进度：定义可见页规则，估算后校正，兼容旧记录。
- 阅读记录写回队列：先双写或灰度，pause、pop、切章、shutdown 必须 flush。
- 新事件携带客户端 sequence/time；合并按事件版本而不是 page index，支持用户回退到旧页。

### 6.1 二次逻辑/后果审查结论（2026-08-30）

本轮审查没有改变“先稳定性、再数据模型、最后高风险模型”的总体方向，但把几个原来只写在实现备注里的隐含前置条件提升为发布门禁：

| 审查项 | 若直接实施的后果 | 必须先满足的条件 |
|---|---|---|
| 同一 `State` 切换 chapter | `_current`、滚动 offset、PhotoView controller 和旧预取结果残留；旧 future 可能越界写新章节 | 以 `chapterIdentity` 触发显式 `reset + cancel/generation++ + restore`，或使用新的 widget key；同 key 切章必须有测试 |
| readerType/方向切换 | bottom sheet 返回后 State 可能已 dispose；模式切换丢失最新阅读位置 | 切换前 flush；保存 `page + offset`；取消旧 generation；切换后按新模式恢复并校正；所有异步回调检查 `mounted` |
| 音量监听 | 依据运行时配置释放会出现计数不对称、重复订阅或泄漏 | 保存 `_didAddVolumeListen`（或等价 token），按订阅事实对称释放；设置变化做订阅/退订测试 |
| 全屏系统栏 | 固定恢复值覆盖进入阅读前的系统 UI；初始化异常遗留全局副作用 | 保存并恢复进入前的 UI mode/overlays；`super.initState()` 先于副作用；route push/pop、旋转和异常路径均验证 |
| `JMPageImage` 异步尺寸 | cell 复用或重试乱序把旧尺寸写入新页，导致纵向布局/进度抖动 | 为 path/size future 使用 generation + `(id, imageName)` 身份校验；尺寸变更后触发可见性和进度重算 |
| target-size provider key | 每个窗口/DPR 生成新 key，内存和磁盘缓存倍增；旧尺寸可能继续命中 | 只允许有限尺寸档位，key 包含算法/解码版本；放大时原图兜底；旋转/DPR 测试 |
| offline owner 与下载状态 | 同名页互相覆盖；metadata 显示 completed 但文件不存在 | owner 至少含 album/task/schema；文件原子落盘并校验后才写 completed；读取接口返回 availability |
| 文件名和路径 | 恶意或不兼容名称导致目录逃逸、覆盖、Windows 不可读 | 统一 canonicalize/sanitize；拒绝 `..`、分隔符、保留字、空名和超长组件；跨平台路径测试 |
| 预取与下载并发 | “取消”只是不写回结果，流量/CPU 仍消耗；当前页 P95 变差 | 共享 semaphore/预算；区分队列取消与请求中止；记录取消后实际字节和线程数 |
| 日志与指标 | URL 中的 cookie/签名泄漏；高频预取撑爆日志 | 只记录 host、错误类别和脱敏 key；采样、环形缓冲和本地容量上限；默认关闭详细 payload |
| 绝对图片 URL | 脏 metadata 可能把 cookie 带到任意主机 | 仅允许配置的 CDN/代理 host；非允许 host 直接拒绝或剥离凭据 |
| 清理与 fetch 并发 | 递归删除穿过写入临界区，产生半文件/ENOENT | 共享锁或 generation；清理只处理已提交且未被 pin/读取的文件 |
| 空章节/非法初始页 | 空 `PhotoViewGallery`、越界 `PageController` 或黑屏 | FutureBuilder 层先显示空章节状态；统一 clamp `startIndex`，并记录纠正原因 |
| 图片列表异常 | 空名/重复名造成路径失败、cache 冲突或服务端索引错位 | DTO 归一化时保留原索引；空名占位失败，重复项使用稳定 identity |
| 异步导航/焦点 | pop 后仍 `Navigator` 或重复 `FocusNode` 回调 | 导航 token + `mounted` + 单飞锁；FocusNode 由可拥有的 State 创建和释放 |

这些条件是逻辑不变量，不是可选的“后续清理”。任一条件未满足时，只能保留旧路径，不能把新开关默认打开。

优先级解释：P0 表示数据完整性、安全、生命周期崩溃或无法回退的问题，未修复不得扩大灰度；P1 表示明显性能/一致性/可维护性风险，可在开关关闭时继续推进其他独立阶段；P2 表示体验增强或观测完善。表中“P0/P1”表示需要先用 fixture/压力测试确认影响范围，而不是可以忽略。

本轮建议先作为“发布阻断候选”跟踪的条目：R-08（普通清理可能删除下载资产）、R-15（`setState` 生命周期）、R-28（路径边界）、R-31（解扰失败伪装成功）、R-32（凭据可能发送到非受信 host）、R-33（清理/写入竞态）、R-36（空章/非法初始页）和 R-39（空下载任务误用 album id）。在复现或契约测试确认后，将其固定为 P0；在此之前不能以“暂时概率低”作为默认放量理由。

### 6.2 硬依赖图与可发布增量

```text
工具链/后端 SHA 冻结
          ↓
      M0 基线与契约测试
          ↓
 M1 生命周期/布局/缓存竞态修复
          ↓
 M2 target-size（只作用于 decoded canonical）
          ↓
 M3 PageDescriptor + Repository facade
          ↓
 M4 Session/generation + 预取调度器
          ↓
 M5 批量协议/CDN fallback（旧单页 API 并行）
          ↓
 M6 offline owner/manifest/迁移（先复制校验，再切读路径）
          ↓
 M7 双页窗口化、精确进度、view-log 队列（彼此独立）
```

每个箭头前的阶段必须可以单独发布：

- M0/M1：默认行为不变，只增加诊断和低风险修复。
- M2：目标尺寸默认限于实验组，失败回退无尺寸 provider；不改 canonical 文件。
- M3：只增加兼容转换和 facade，旧 UI 仍可读旧响应。
- M4：仅在线 Gallery 灰度；预取失败不会改变当前页结果。
- M5：客户端先探测协议版本，批量失败逐项回退单页。
- M6：迁移使用复制→校验→原子提交→标记；旧目录至少保留一个版本周期，失败只回退旧读路径。
- M7：双页、垂直进度、记录队列各自独立开关，不允许同一版本同时强制开启。

### 6.3 各阶段完成定义（Definition of Done）

| 阶段 | 只有同时满足以下条件才算完成 |
|---|---|
| M0 | 工具链/依赖/后端 SHA 可重现；三档设备和三类网络有基线；诊断不改变默认行为；基线数据已脱敏并可复跑 |
| M1 | 生命周期、排序、全屏和精准淘汰回归测试通过；无全局 image cache 清空；旧协议行为保持一致 |
| M2 | known scrambled fixture 内容、方向、比例一致；provider 实际输出达到 target 档位；失败可回退；Flutter 与 Rust 峰值指标分开记录 |
| M3 | 在线/离线旧响应均可转换为 `PageDescriptor`；尺寸缺失有超时/回退；旧 UI 与旧 API 仍可用 |
| M4 | chapter generation 能隔离切章/切模式结果；队列去重、优先级、并发上限和取消语义有测试；当前页失败不被预取吞掉 |
| M5 | 新旧客户端/后端契约测试通过；批量逐项错误、限批、超时和单页 fallback 可用；fallback/熔断日志已脱敏 |
| M6 | 复制迁移可幂等、可中断恢复；文件校验后才标记完成；普通清理无法删除 offline；metadata-only 明确可见 |
| M7 | 双页配对、精确进度、记录队列分别通过专项测试和灰度观察；任一能力可单独关闭并恢复旧数据 |

## 7. 数据和 API 草案

```text
PageDescriptor {
  index,
  name,
  sourceWidth,
  sourceHeight,
  localPath?,
  availability,       // metadata-only / downloading / local / missing / failed
  pairIndex?
}
```

建议新增而不是立即破坏旧协议：

```text
chapter_page_meta(chapterId) -> PageDescriptor[]
jm_page_image_batch(chapterId, indexes) ->
  [{ index, path, width, height, cacheHit, error }]
```

批量接口必须支持部分成功、批次上限、超时、generation/请求标识和旧接口回退；不能默认一次返回整章所有图片 bytes。

### 7.1 解扰与目标尺寸解码边界契约

“统一目标尺寸解码”指统一 Flutter 侧对**已经解扰的 canonical 文件**请求 codec 目标尺寸，不是把原始 JM 图片先缩放再交给解扰算法。允许的顺序只有：

```text
压缩原图/网络 bytes
  → Rust `maybe_unscramble_jm_page_image`
  → 完整解码、行重排、重新编码（`decoded_v1` canonical）
  → Flutter provider 读取 canonical
  → codec(targetWidth, targetHeight)
  → ImageInfo/位图
```

因此目标尺寸不会改变解扰所需的行数、排列或密钥输入；它只改变最终位图的采样尺寸。以下顺序必须视为错误并阻止合入：

```text
原始 scrambled bytes → target-size decode/resize → unscramble
```

实现前必须确认 `PageImageProvider.loadBuffer/loadImage` 的 `decode` 回调确实接收并使用 target 尺寸。仅在外层包 `ResizeImage` 不足以证明这一点，因为当前 provider 直接执行 `decode(buffer)`。如果运行时 API 不支持自定义 provider 的目标参数，优先改为显式 codec 入口或使用已验证的 `FileImage + ResizeImage` 组合；不得凭假设宣称已降采样。

目标尺寸计算建议先采用“视口像素上限 + 少量量化档位”，而不是把每次布局得到的浮点宽高直接作为 key：

```text
requested = ceil(logicalViewportExtent × devicePixelRatio × overscanFactor)
target = nearestAllowedTier(requested)
target = min(target, sourceDimension)  // source 已知时禁止无意义放大
```

`overscanFactor`、档位数量和上限必须由 M0 基线决定；尺寸未知时可暂用保守档位，尺寸回读后再一次重建，不应为每个 cell 生成无限变体。

M2 的最小安全矩阵：

| 场景 | 预期结果 | 不得发生 |
|---|---|---|
| 已解扰 canonical + 小于源尺寸 target | 内容/方向一致，位图接近 target | 重新解扰、覆盖 canonical、比例改变 |
| target 大于源尺寸或缺失 | 原图 codec 兜底 | 生成无限尺寸 key 或强制放大 |
| canonical 损坏/不存在 | 重新获取并重新解扰，再重试一次 | 把缩略图/半文件当解扰源 |
| 需要解扰但行重排/编码失败 | 返回可分类错误并不落盘 canonical | 用原始 bytes 伪装成功并永久缓存 |
| 旧 `decoded_v1` 与新算法版本混用 | 按版本 key 隔离并回退 | 静默显示错位图片 |
| provider target 请求失败 | 回退无 target provider，记录分类错误 | 当前页被预取错误替换或整章失败 |

验收要同时比较“内容正确性”和“资源峰值”：target-size 只能降低 Flutter codec/位图峰值，不能宣称消除 Rust 解扰阶段的完整 RGBA 峰值，除非另有独立的流式解扰方案和基准证据。

### 7.2 尚未决策的产品/协议问题

这些问题可以先用旧行为继续运行，但在对应阶段开启开关前必须记录最终选择；否则实现会把产品决策悄悄固化在缓存或协议里。

| 问题 | 可选方向 | 未决时的安全默认 |
|---|---|---|
| target 尺寸策略 | 视口/DPR 动态、固定 1–2 档、仅原图 | 固定少量档位；不生成任意窗口尺寸 key |
| offline owner 粒度 | album、download task、内容去重 blob | task/album 维度优先，宁可重复文件也不共享删除权 |
| 缺失离线文件 | 自动联网补齐、明确提示重新下载、只读失败 | 无网时立即显示“本地文件缺失”，不无限重试网络 |
| 多设备进度冲突 | 最后事件、设备优先级、用户选择 | 保留本地未同步事件；按 sequence/time 合并，不按 page index 单调 |
| CDN allowlist | 固定官方 host、用户代理 host、签名代理 | 只允许配置的官方 host；非允许 host 不发送凭据 |
| Flutter 基线 | `.fvmrc` 版本、CI 版本或另一个升级版本 | 在 M0 形成兼容矩阵前不改 provider API |
| 清理语义 | 普通缓存清理、删除下载、两者分开 | 默认只清临时 reader cache；offline 必须显式操作 |
| 导出与离线共享 | 共享 canonical、导出专用副本、按需复制 | 在 owner 明确前不改变现有导出路径 |

### 7.3 内存峰值拆解（避免误判目标解码收益）

单页处理的峰值至少可能同时包含以下部分：

```text
网络/文件压缩 bytes
 + Rust `DynamicImage`/RGBA（解扰阶段，约 4 × sourceWidth × sourceHeight）
 + 重新编码缓冲
 + Dart `readAsBytes`/ImmutableBuffer
 + Flutter 最终位图（约 4 × targetWidth × targetHeight）
```

target-size codec 只能直接降低最后一项（以及其相关 Flutter cache）；它不会自动减少 Rust 解扰的 source RGBA，也不会消除 Dart 侧压缩 bytes 的读取峰值。若要优化 Rust 峰值，必须另立“流式解扰/分块编码”课题，并证明行重排算法允许这样做；不能把两类收益混写成一个“内存下降百分比”。

## 8. 验收指标（先基线，后定目标）

指标必须先固定口径：冷启动需区分进程冷启动、磁盘已有缓存和网络类型；首图定义为“首个完整可见页面”；内存同时记录 Flutter 位图、Rust 解扰峰值和进程 RSS；预取命中率的分母要排除用户直接跳转造成的不可预测请求；白屏需定义最小持续时长。否则同一个改动可能因为测试条件变化而被误判为改进。

| 指标 | 建议观察方式 | 初始方向 |
|---|---|---|
| 首图延迟 | 在线冷启动、本地冷启动分别统计 P50/P95 | 逐阶段下降，不先承诺绝对值 |
| 内存 | 分开记录 Rust 解扰峰值、Flutter 位图峰值、进程 RSS | 长章节峰值较基线下降；低端设备无 OOM |
| 白屏/图片失败 | 按模式、网络类型、CDN host 分桶 | 白屏率和失败率持续下降 |
| 预取 | 命中率、取消后流量、重复请求率 | 命中率提升且无效流量受控 |
| 流畅度 | 首帧、翻页、切章的 P95 帧耗时/卡顿率 | 重点场景接近 60fps |
| 进度 | 恢复后的页索引和 offset 误差 | 单页不超过一页，双页不超过一个页对 |
| 数据可靠性 | view-log 丢失、离线文件丢失、迁移失败数 | 不丢最新本地进度、不误删下载 |
| 桥接效率 | 每章节 metadata/image 方法调用数 | 从逐页调用降到批量调用 |

## 9. 测试清单

### Flutter

- 四种 reader mode 的加载、初始页、切章、重试。
- 同一 widget key 替换 chapter、快速切章/切模式/切方向时的 reset、flush、generation 隔离。
- 空章节、负数/超范围 `initRank`、重复/空图片名和下载任务无章节时的明确错误/占位行为。
- 目标尺寸解码实际像素尺寸和原图回退。
- 解扰 fixture 显示方向、比例和内容不变。
- 双页封面、奇数页、RTL/LTR、横竖屏旋转。
- 纵向可变高度、远距离跳转和恢复校正。
- 快速翻页预取去重、generation、错误隔离。
- 延迟乱序的 path/size future、cell 复用后的 identity 校验，以及旋转/DPR/分屏下有限尺寸档位。
- pause/pop/dispose 后 view-log、event、volume、FocusNode 清理；运行中开关音量监听后订阅数仍对称。
- 快速 pop/重复点按切章不会触发已卸载 context 的 Navigator，也不会重复触发键盘翻页。
- Semantics、触控区域、safe-area、动态字体和 reduced motion。

### Rust

- 解扰前后 canonical 文件版本和校验。
- 解扰成功、解扰失败、错误 MIME 和已知未加扰图片分别验证缓存状态；失败样本不能生成可复用 canonical 文件。
- 损坏缓存、空响应、错误 MIME、部分成功批量响应。
- 429/5xx/网络错误与 403/404 的重试差异。
- CDN fallback、熔断恢复和敏感信息脱敏。
- reader/offline 目录隔离、迁移中断恢复、配额清理并发。
- 恶意/超长/保留字图片名的 canonicalize、路径逃逸和大小写碰撞。
- 非 CDN 绝对 URL/协议相对 URL 的拒绝、cookie/referer 不外泄。
- metadata `completed` 但文件缺失/截断时的 availability 修复；同名页跨任务不互相覆盖。
- 下载状态 queued → downloading → completed/failed 的原子转换。
- reader 预取与下载 worker 共享并发预算，取消后线程/字节数不会继续增长。
- `clean_all_cache` 与 fetch/read 并发压力测试：不得出现半文件、误删或未处理的 ENOENT。

### CI

- 新建轻量 `CI` workflow，在 `push`/`pull_request` 自动执行 Flutter analyze/test；不要直接让现有签名/发布 workflow 对所有 PR 运行。
- Rust fmt/clippy/test 和批量/缓存合约测试。
- 校验 `pubspec.lock`、`Cargo.lock`、FRB 生成文件。
- 固定 Flutter、NDK 和 backend SHA，避免发布产物漂移。

## 10. 回滚和保护策略

- 目标尺寸、预取调度、批量 API、双页窗口化、进度模型、缓存迁移分别设置开关。
- 新缓存迁移失败时保留旧目录只读回退，不自动删除。
- 新批量接口失败时回退单页接口。
- 目标解码失败时回退无尺寸 provider，不重复覆盖 canonical 文件。
- 解扰算法、编码参数、缓存目录和 API schema 各自 bump 版本，禁止混用旧缓存。
- 任何清理任务都要排除正在读取、正在下载和未完成的临时文件。

### 10.1 能力开关矩阵（首发默认值）

首期只使用本地/编译期开关，避免远程配置不可用时产生组合爆炸。远程开关要等指标链路稳定后再引入。开关名称是建议值，落地时保持“一项能力一个开关”，不要用一个总开关捆绑多个高风险改动。

| 开关 | 首发默认 | 灰度范围 | 关闭后的回退 |
|---|---:|---|---|
| `reader_page_descriptor_v1` | OFF | 内部测试 | 旧 `images`/`DlImage` 转换和旧 UI |
| `reader_target_decode_v1` | OFF | Gallery 在线用户 | 无尺寸 `PageImageProvider`；canonical 文件不变 |
| `reader_prefetch_scheduler_v1` | OFF | 在线 Gallery | 现有固定邻页 `precacheImage` |
| `reader_batch_api_v1` | OFF | 可回滚的小比例 | 旧单页 `jm_page_image`/`image_size` |
| `reader_offline_owner_v1` | OFF | 有备份的内部设备 | 旧目录只读兼容；不删除旧文件 |
| `reader_two_page_window_v1` | OFF | 双页实验组 | 现有整章 options |
| `reader_precise_progress_v1` | OFF | 纵向实验组 | 旧百分比恢复 |
| `reader_viewlog_queue_v1` | OFF | 内部/小比例 | 现有 debounce 写回 |

开关配置必须记录版本、来源和生效时间；启动日志只记录开关摘要，不记录账号、cookie、签名 URL。任何开关关闭都应在下一个请求/帧边界生效，不能留下后台 timer、订阅或请求。

### 10.2 缓存目录、owner 和迁移协议（提案）

目录名和 schema 尚未定稿，下面的分层是为了明确 owner，而不是要求现在立即改常量：

```text
storage/
├─ reader_cache/v1/pages/<chapter-key>/<canonical-key>.<ext>
├─ offline_assets/v1/<album-or-task-key>/<chapter-key>/<page-key>.<ext>
└─ manifests/
   ├─ reader-v1.json
   └─ offline-v1.json
```

约束：

1. `reader_cache` 只由在线/临时阅读 owner 管理；普通清理只能淘汰这一层。
2. `offline_assets` 由下载任务 owner 管理；删除下载任务时才允许删除对应资产。
3. `<page-key>` 由 canonicalized 的 `(album/task, chapter, image identity, algorithm version)` 生成，不能直接拼接未经验证的文件名。
4. 写入顺序固定为：写唯一临时文件 → fsync/校验（平台允许时）→ 原子 rename → 更新 manifest → 最后写 `completed`。任何中断只留下可清理的孤儿临时文件。
5. 迁移采用“复制+校验+幂等重试”，不先移动、不先删除；新读路径成功率达到门槛并经过一个版本周期后才允许清理旧副本。
6. 读取必须重新检查存在性、非空和格式；metadata `completed` 只能表示远端/任务状态，不能单独表示本地可读。

迁移演练至少覆盖：进程在 rename 前崩溃、manifest 更新前崩溃、目标磁盘空间不足、同名页冲突、Windows 文件锁、大小写不敏感文件系统，以及 WebDAV 只恢复 metadata 的情况。

### 10.3 阅读进度事件 schema（兼容草案）

旧字段继续保留，新字段先双写一个版本周期：

```json
{
  "version": 2,
  "comic_id": 123,
  "chapter_id": 456,
  "page_index": 17,
  "offset": 2480.5,
  "reader_mode": "vertical",
  "direction": "ltr",
  "session_id": "opaque-random-id",
  "client_sequence": 1042,
  "client_time_ms": 1770000000000
}
```

- `client_sequence` 在同一设备/会话内严格递增；批量重放按 sequence 去重。
- 跨设备没有共同 sequence 时，以客户端时间戳和服务端接收时间做有界合并；时钟异常必须降级为“较新已知事件”，不能覆盖本地未同步事件。
- `page_index` 可以减少，不能把“页码单调”当作冲突解决规则。
- `offset` 只在页面尺寸已知时使用；未知时保存 page index，并在布局完成后一次校正。
- 解析失败、旧版本字段缺失或模式未知时回退旧记录，不阻塞打开章节。

### 10.4 发布门禁、观察窗和回滚 runbook

**发布前**：锁定 Flutter/Dart、NDK、Rust backend SHA、lockfile 和生成文件；跑静态检查、单元/widget/契约测试；用固定 fixture 验证解扰前后内容和尺寸；核对迁移 dry-run 报告；确认开关默认值均可关闭。

**灰度顺序**：内部/狗粮设备 → 5% → 25% → 100%。每档至少覆盖在线、离线、单页、纵向、双页、RTL/LTR 和低端 Android。每档观察完整的冷启动、切章和后台恢复周期，不以一次成功请求作为放量依据。

**立即停止并回滚**（任一满足即执行）：

- 发现离线文件被普通清理误删、迁移后无法恢复，或 view-log 出现可复现的最新进度丢失；
- 解扰 fixture 内容/方向不一致，或错误 MIME/HTML 被写入 canonical/offline 文件；
- 新能力引起 OOM、白屏、图片失败或首图 P95 超过 M0 基线的暂定门槛（门槛在 M0 记录后固化）；
- 批量协议出现跨版本解析错误，且旧单页 fallback 不可用；
- 日志/指标出现 cookie、签名 URL、账号标识等敏感数据。

**回滚顺序**：先关闭对应能力开关并停止新任务 → 保留并标记现场（manifest、错误类别、版本）→ 回退客户端读路径/旧 API → 验证当前页和离线页可读 → 再处理孤儿文件。禁止用清空全局缓存或删除 offline 目录作为“快速修复”。数据迁移失败时只回退读取，不做破坏性清理。

### 10.5 兼容矩阵与验证环境

| 组件 | 当前发现 | 发布前动作 |
|---|---|---|
| Flutter | `.fvmrc` 为 3.41.2，Build/Release workflow 为 3.7.3 | 先确认插件/API/Dart 约束可解析；选定一个版本并锁 action/cache |
| Dart SDK | `pubspec.yaml` 仅约束 `>=3.0.0 <4.0.0` | 记录实际 `dart --version`，在 CI 和本地使用同一版本 |
| Android NDK | Build 为 25.2.9519653，Release 为 27.2.12479018 | 固定一个兼容矩阵；Rust JNI 两架构均做 smoke |
| Rust backend | 主仓库 checkout 未固定 SHA；Rust 工作树有用户未提交改动 | 发布构建固定 commit/tag；先保存/审查未提交 diff，不覆盖它 |
| 协议/生成文件 | Flutter/Rust 通过 MethodChannel/生成绑定交互 | 批量 API 和字段变更先做旧客户端→新 backend、新客户端→旧 backend 契约测试 |
| 文件系统 | Windows/Linux/Android 行为和大小写规则不同 | 至少在 Windows 与 Linux 跑路径、原子 rename、并发清理测试 |

### 10.6 指标与隐私约束

指标按设备档位、网络类型、章节长度、reader mode 和能力开关分桶；同时记录样本数和版本，避免小样本误判。预取命中率分母只包含用户实际翻到的页面，并单独报告重复请求、取消后的实际字节、当前页等待和后台任务数。内存指标记录 Flutter 位图、Rust 解扰峰值和进程 RSS，至少包含 30 分钟长章节测试。

原始图片 URL、query、cookie、Authorization、WebDAV 路径和账号信息一律不进入日志/指标。错误只保留 host、状态类别、脱敏 cache key 和 request id；本地诊断使用有上限的环形缓冲，上传前再采样和脱敏。

## 11. 当前工作区保护事项

本轮证据基于以下基线提交（Rust 工作树另有未提交差异）：

- 主仓库 HEAD：`9f79d738e36bcdf919ad13d94460c697e65b56aa`
- Rust 仓库 HEAD：`6759c5a8142797cc8378ba96e456075293876133`

Rust 仓库已有用户未提交修改，至少包括：

- [D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs](D:/Cat/jmcomic3-rust-backend/rust/src/api/invoke.rs)
- [D:/Cat/jmcomic3-rust-backend/rust/README.md](D:/Cat/jmcomic3-rust-backend/rust/README.md)

后续实现只能增量修改，不能使用 reset/checkout 覆盖这些改动。

当前环境未找到 `flutter`、`dart`、`cargo` 命令；在对应工具链准备好之前，本文档中的验证项均标记为“待执行”，不得把未运行的测试写成已通过。

## 12. 变更记录

### 2026-08-30

- 创建本文档，记录阅读链路和初版优化方案。
- 完成前端、Rust 后端、质量/交付三路只读审查。
- 将“目标尺寸解码”明确为“解扰后的 Flutter codec 下采样”，禁止解扰前缩放。
- 将原 P0 中的高风险项拆出：缓存迁移、ReaderSession、预取、双页窗口化、精确进度、批量 API 分阶段实施。
- 将固定性能数字改为“先采集基线，再设相对门槛”。
- 二次审查补充 R-20～R-30：切章/模式切换 generation、音量监听对称释放、全屏状态恢复、异步尺寸陈旧回调、尺寸 key 限档、offline owner/路径规范化、并发预算和日志脱敏。
- 继续深审补充 R-31～R-33：解扰失败不得伪装成 canonical、绝对 URL 的凭据外泄、`clean_all_cache` 与 fetch/read 并发竞态。
- 边界审查补充 R-34～R-39：FocusNode/预取回调生命周期、空章节与非法初始页、异常图片列表、异步导航，以及空下载任务误用 album id。
- 增加硬依赖图、各阶段完成定义、能力开关矩阵、缓存迁移/进度 schema 草案、灰度回滚 runbook、兼容矩阵和隐私约束。
- 记录主仓库与 Rust 基线 SHA；确认 Rust 工作树仍有用户未提交修改，未运行 Flutter/Dart/Cargo 验证。
- 按可回溯要求创建分支 `MrYu/reader-optimization-m1`、基线提交 `c7b8498`、本地基线 tag，并推送 Draft PR #2；M1 仅启动生命周期/缓存竞态子集。
- M1 子集已拆分并推送：`cfaf5f4`（Future/cache generation）和 `6474b38`（reader 生命周期、边界、导航、FocusNode/音量监听）；后续补强正在独立提交中；已执行 `git diff --check`/`git show --check`，未执行 Flutter/Dart 运行时测试。

## 13. 后续更新规则

每次继续工作时，按以下顺序更新本文档：

1. 在“任务状态”或“变更记录”中写明本轮做了什么。
2. 记录新增证据、假设和未验证项。
3. 若任务的优先级、依赖、后果或回滚方式改变，先修改对应审查表。
4. 实现后补充实际测试命令、设备、结果和失败样本；未运行的项目保持“待执行”。
5. 完成一个阶段后再开启下一个阶段，避免同时发布多个高风险开关。
