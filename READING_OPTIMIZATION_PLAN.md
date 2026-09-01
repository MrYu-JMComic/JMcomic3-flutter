# 阅读功能优化方案（持续维护）

> 文档性质：基于当前代码的设计、风险和实施跟踪文档。每次审查或实现后，先更新本文档，再修改代码。
>
> 最后更新：2026-09-01 14:10（M2 最终本地门禁及 PR #3 状态核对）
>
> 当前状态：安全可回滚的 M1/M2/M3/M4/M5/M7 实现子集已通过本地门禁并由 PR #2 合并到 `main`（merge commit `c1cd690`）；当前阶段分支 `MrYu/reader-optimization-m2` 在此基础上增加了默认关闭的 view-log 版本化持久化适配器、恢复/重试回归和双页窗口 widget 回归，并在当前 HEAD `0fc4251`（代码行为自 `85034cf` 后未变，仅追加文档）通过默认/全 flags 132/132 测试。该持久化适配器复用现有属性桥接，能在正常重启后重放 pending 事件，但尚未完成 native 原子文件写入、强杀窗口和跨设备恢复演练，不能替代完整 M6/M7 发布证据。M5 Rust availability 仅在隔离 worktree 提交，未覆盖原 Rust 工作树用户 dirty 文件。M6 offline owner/迁移/并发清理、M0 真机基线、M2 真实 scrambled fixture 及 M7 golden/真实 list reader 仍未完成，所有高风险开关继续默认关闭。平台构建和验证继续使用 `D:\Cat\jm3\build` 隔离输出，未验证项目保持待执行。

## 0. 固定工作上下文（压缩/换代理后先读）

> 本节是工作区、构建和安全约束的持久记录，不是新的产品需求。若用户后来给出明确的新指令，以最新指令为准；否则不要凭记忆改变下面的路径、分支或能力开关。每次继续任务时，先读本节和“变更记录”，完成验证后再追加证据。

### 0.1 路径与版本控制快照

| 字段 | 固定值/当前记录（2026-09-01 13:28） |
|---|---|
| 功能代码工作区 | `D:\Cat\jmcomic3` |
| 本地构建/工具链根 | `D:\Cat\jm3` |
| 所有平台构建输出根 | `D:\Cat\jm3\build` |
| 环境入口脚本 | `D:\Cat\jm3\scripts\enter_build_env.ps1` |
| 环境自检脚本 | `D:\Cat\jm3\scripts\verify_build_env.ps1` |
| 当前功能分支 | `MrYu/reader-optimization-m2` |
| 合并状态 | PR #2 已合并到 `main`；merge commit `c1cd690410b27ef0fa842a7ed781beafb4dcf647`；源分支和 checkpoint 分支均保留 |
| 代码/测试基线 | 代码基线 `85034cf`（本阶段代码提交 `1270602`、测试提交 `8b96fd5`、key 校验提交 `85034cf`）；当前 HEAD `0fc4251` 仅追加文档，默认/全 flags 均为 132/132 |
| 文档收尾提交链 | `dba86f7` → `f4f0565` → `9d9873b` → `1fe2088`；本阶段文档提交将在当前分支追加；代码与测试提交历史不改写；Flutter/Windows 生成文件仍 dirty，均未纳入提交 |
| 远端同步 | `origin/main` 已包含 merge commit `c1cd690` 及文档同步提交 `94a8bcc`；阶段分支 `MrYu/reader-optimization-m2` 与 `origin` 同步至 `0fc4251`，PR #3 为 Draft；本轮没有主动触发 GitHub 构建 |
| 上下文提交同步记录 | `2717aaa`、`6d73c8c`、`346ad0a` 均已推送；当前 HEAD/是否领先以 `git rev-parse --short HEAD` 与 `git status --short --branch` 复核 |
| PR #2 | `MERGED`，原 head `9d9873b`，base `main` 原为 `9f79d73`；merge commit 为 `c1cd690`；GitHub 只作代码评审，不作本地构建验收 |
| 恢复点 | `reader-optimization-m2-start-20260901-133345`（本阶段起点）、`reader-optimization-pre-merge-20260901-132232`（PR #2 合并前 head）、`reader-optimization-post-merge-docs-20260901-132900`（main 文档同步后）、`reader-optimization-final-local-gates-20260831-035800`，以及既有恢复点；源分支未删除，禁止改写已有提交历史 |
| 外部 Rust 工作树 | `D:\Cat\jmcomic3-rust-backend`；存在用户未提交修改，禁止 reset/checkout/覆盖 |
| 构建 checkout | `D:\Cat\jm3` 有独立且可能 dirty 的工作树；不要假定它自动等于功能分支，构建前先核对 commit/diff |
| 未跟踪生成物 | `D:\Cat\jmcomic3\windows\rust.h`；保留并先确认来源，不要擅自删除或提交 |
| 忘记清理的临时目录 | `D:\Cat\jm3\worktrees\build`、`D:\Cat\jm3\worktrees\reader-optimization-m1` 可能只含本轮生成物；清理前必须逐项确认绝对路径，不能递归误删整个 `D:\Cat\jm3` |

### 0.2 构建边界与固定命令

- **禁止走 GitHub 构建**：`.github/workflows/CI.yml` 仅保留手动诊断触发；本轮验收以本地命令和 `D:\Cat\jm3\build` 产物为准。
- 新 PowerShell 窗口不会自动继承项目工具链 PATH；每次构建前执行：

  ```powershell
  Set-Location D:\Cat\jm3
  . .\scripts\enter_build_env.ps1
  . .\scripts\verify_build_env.ps1
  ```

- 环境加载脚本只修改当前 PowerShell 进程，故意不污染系统 PATH；不要在未加载环境时用系统同名工具替代它们。
- Android/Windows 构建脚本位于 `D:\Cat\jm3\scripts`。构建前确认源代码 checkout 与目标分支一致；不要因方便而在 dirty checkout 上执行 reset、clean 或覆盖用户文件。
- 产物必须落在 `D:\Cat\jm3\build` 的隔离子目录，例如：
  - Windows：`D:\Cat\jm3\build\reader-optimization-m1\windows\x64\runner\Release`
  - Android：`D:\Cat\jm3\build\reader-optimization-m1-android\app\outputs\flutter-apk`
- 清理只允许针对已核实的本轮隔离子目录；先列出绝对路径和文件清单，再执行可恢复的移动/删除。不得清空仓库 `build`、offline 下载目录或 Rust 用户工作树。
- 编辑使用增量补丁；禁止 `git reset --hard`、无确认的 `git checkout`、强制覆盖或改写历史。每个阶段先提交独立 checkpoint，再进行下一阶段。

### 0.3 已冻结的工具链矩阵

| 工具 | 版本/路径 | 状态 |
|---|---|---|
| Flutter / Dart | 3.41.2 / 3.11.0，`D:\Cat\jm3\_flutter\flutter` | 已通过 `flutter doctor -v` |
| Rust / cargo / rustfmt | 1.98.0，`D:\Cat\jm3\toolchains\cargo` | 已通过版本检查与后端测试 |
| cargo-ndk / FRB codegen | 4.1.2 / 2.11.1 | 已验证 |
| Android SDK | platforms 32/35/36，Build Tools 28.0.3/30.0.2/35.0.0 | 已验证，licenses 已接受 |
| Android NDK | 25.2.9519653 | 项目显式固定；本地构建成功 |
| JDK | 21.0.6，`C:\Program Files\Java\jdk-21` | 已验证 |
| Windows C++ | VS Build Tools 2022、MSVC 14.44、Windows SDK 10.0.26100.0 | 已验证 |
| CMake / Ninja | 4.4.3 / 1.13.2 | 已验证 |

已知边界：部分 Flutter 插件声明 NDK 27.0.12077973，而当前 Rust/项目矩阵使用 NDK 25.2；25.2 在本机 smoke build 成功，但在决定安装/切换 NDK 27 并重新跑双 ABI 前，不得声称跨机器发布兼容。Android 尚无正式签名 keystore/`key.properties`，当前 APK 不能当作正式发布包。

### 0.4 阶段状态与不可破坏不变量

- M0：工具链和本地构建门禁已验证；真机性能基线仍未采集。
- M1：低风险 reader 生命周期/缓存竞态子集已实现；定向 reader 回归 13/13 通过，analyzer 0 error（既有 info/lint 仍使命令返回 1）。
- M2：目标 codec provider 与固定 bucket 已实现并有 canonical fixture 证据；**保持关闭**，尚未完成真实 scrambled fixture、跨设备峰值和所有 reader 端到端验证。目标尺寸只允许作用于 Rust 已完整解扰后的 canonical 文件。
- M3：PageDescriptor/Repository 兼容层已实现；离线顺序/availability 仍需持续验证。
- M4：generation/session 与 scheduler 最小接入已实现；真实网络中止和资源预算未验证。
- M5：Dart 批量 adapter 与 Rust availability 合约测试已实现；Rust availability 独立提交 `a7a8015`（tag `reader-optimization-m5-availability-20260831`），尚未安全合并到原 Rust dirty 工作树，跨版本 smoke 待执行。
- M6：Flutter availability 最小接线已实现；真实 offline owner、复制/校验/原子提交、迁移和清理锁未实现，开关保持关闭。
- M7：双页配对、可变高度进度模型和内存 view-log 重试队列已有模型实现；本阶段新增默认关闭的版本化属性 journal，可在正常重启后恢复 pending 事件并受 `maxPending`/字节上限约束；强杀窗口、native 原子提交和 golden/真实 list reader 仍待执行。
- 离线文件必须与普通 reader cache 隔离；`dl_status=1` 不等于本机文件可读；普通清理不得删除 offline assets。
- 当前页优先于预取；旧 Future/旧章节结果不得写入新 generation；任何新能力必须可独立关闭和回退。

### 0.5 最近验证证据与未完成项

| 检查 | 结果/产物 |
|---|---|
| `D:\Cat\jm3\scripts\verify_build_env.ps1` | 全部工具/SDK 检查通过；`flutter doctor -v` 为 `No issues found!` |
| Flutter tests | 在固定环境、当前 HEAD `0fc4251` 下重新运行默认 `flutter test --no-pub` 及全部 8 个 reader flags，均为 132/132 通过；最新日志位于 `D:\Cat\jm3\build\reader-optimization-m2-validation\flutter-test-default-final-rerun.log` 和 `flutter-test-all-reader-flags-final-rerun.log` |
| Flutter analyze | 当前 0 error；137 条既有 info/lint，命令按 Flutter 约定以退出码 1 结束；`flutter analyze` 不支持 `--dart-define`，全 flags 代码路径由上述测试编译覆盖 |
| Dart format / diff | 本阶段 6 个目标 Dart 文件 `dart format --set-exit-if-changed` 通过（0 changed）；`git diff --check` 通过 |
| Rust | 隔离 worktree `a7a8015` 上 `cargo fmt --check` 通过，`cargo test --offline` 128/128 通过（含 doc/smoke；仅既有 dead_code/linker warning） |
| Windows Release | 历史 smoke 产物位于 `D:\Cat\jm3\build\reader-optimization-m1\windows\x64\runner\Release\jmcomic3.exe`；本轮代码提交后未重新生成平台包 |
| Android Release | 历史 arm64-v8a/armeabi-v7a smoke APK 已核对 ABI 与 `librust.so`；本轮未重新生成，且 Gradle/JNI staging 仍可能触碰 checkout |
| Android 真机 | 当前未连接（`adb devices` 无设备）；reader 真实回归/性能基线待做 |
| 正式签名 | 未配置 `android/key.properties` 或 keystore；待用户提供发布签名材料 |
| symlink 权限 | 新环境若 `pub get` 失败，先检查 Windows Developer Mode/权限；已有验证使用固定环境和 `--no-pub` |

### 0.6 继续任务的最小流程

1. 读取本节、`### 当前任务状态` 和最新变更记录。
2. 只读确认 `git status --short --branch`、当前 HEAD、Rust 外部工作树 dirty 状态和 `D:\Cat\jm3\build` 目标目录。
3. 若要改代码，先在当前分支创建/确认独立 checkpoint；先补测试，再实现，再跑本地门禁。
4. 若要构建，加载并验证环境，明确隔离输出目录，构建后核对 ABI/manifest/`librust.so`/SHA-256。
5. 将命令、时间、结果、产物、未验证项追加到本文档；没有运行的检查保持“待执行”，不要推断为通过。

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
| M0 基线与工具链冻结 | 部分完成（分支/PR/工具链已验；Android 输出隔离待处理） | 固定已验证的 NDK 25.2，完成外部构建目录 smoke build；之后采集三类设备基线并固定产物命名 | 分支 `MrYu/reader-optimization-m1`、Draft PR #2、基线 tag 和 `D:\Cat\jm3` 工具链已建立；`verify_build_env.ps1`/`flutter doctor -v` 通过；Windows 外部目录构建和 Android arm64 构建均已通过，但 Flutter Android Gradle 模板仍把 APK 输出落到当前仓库 `build`，设备基线仍待采集 |
| M1 低风险稳定性修复 | 已实现低风险子集；专项复用/全屏恢复待补 | 补同一 State 切章/快速 pop 的专项 widget 回归；审查全屏状态恢复 | Flutter 3.41.2 analyzer 无 error（仅既有 lint/deprecation 信息），全量 Flutter test 通过；新能力默认未强制开启 |
| M2 目标尺寸解码 | 已实现默认关闭子集；真实 fixture/端到端待验证 | 重跑图片/cache 回归并用 scrambled fixture 核验实际像素及错误回退 | 必须证明 target 不会被自定义 provider 忽略，且不改变 canonical/解扰流程 |
| M3 PageDescriptor/Repository | 已完成兼容前置层（UI 仍旧数据驱动） | 接入离线入口并确认重复名/availability 语义 | 在线/离线转换测试已通过；默认渲染路径保持旧 API |
| M4 ReaderSession/generation 与预取调度器 | 已完成最小 UI generation 接入；资源预算/真实 scheduler 灰度待补 | 增加真实队列接入、并发/取消/错误专项测试 | 当前页与旧行为保持兼容；取消的网络中止仍待实测 |
| M5 Rust 批量与网络协议 | Dart adapter 已实现；availability 路由在隔离 worktree 提交 | 补新旧契约 smoke、脱敏审查，并决定是否由后端维护者合并 `a7a8015` | 原 Rust 工作树 `rust/README.md`/`invoke.rs` 有用户 dirty 修改，不能直接合并或覆盖 |
| M6 离线缓存隔离 | Flutter availability 与 metadata-only 占位已实现；真实 owner/迁移/清理隔离待补 | 接入 DownloadAlbumScreen/Reader，增加文件复制、校验、原子提交和 manifest 演练 | 不触碰外部 dirty Rust 文件；未完成迁移前保持旧目录只读兼容 |
| M7 双页窗口化 | builder 窗口路径已接入且默认关闭；新增默认/flag 两种 widget 回归（cover/RTL/奇数/单页） | 完成真实设备和 golden 回归后再评估灰度 | legacy static options 仍是默认路径；测试未替代 golden |
| M7 垂直精确进度 | `ReaderExtentIndex` 已实现并有边界测试 | 补真实 list reader/动态尺寸回归 | 未知尺寸仍使用保守 fallback |
| M7 阅读记录队列 | 单写者、失败重试、`maxPending`/`droppedCount` 及默认关闭的版本化属性 journal 已实现 | 进行 native 原子写入/强杀窗口演练、恢复指标和隐私审查后再评估灰度 | 当前适配器复用属性桥接；属性写入本身的原子性由 Rust store 保证范围外，跨设备合并仍未定义 |
| P2 测试/CI/观测 | 本地门禁已执行；远端自动构建暂停 | 继续补 reader 专项回归和结构化指标 | 使用 `D:\Cat\jm3\_flutter\flutter`（Flutter 3.41.2/Dart 3.11.0），输出根为 `D:\Cat\jm3\build`；workflow 仅保留手动触发，不把 GitHub 结果当验收依据 |

### 本轮继续执行记录（2026-08-30）

- 在 `715c469` 上创建并推送可恢复检查点标签 `reader-optimization-m1-checkpoint-715c469`；不改写已有提交历史。
- 对 M1 两个代码提交完成第二轮只读复核：确认空章节在父层被拦截、索引被统一 clamp、Future identity/generation 防护和监听事实记录已覆盖主要路径。
- 发现并列入下一独立修复提交的低风险项：`JMPageImage` 旧请求在 generation 失效后仍可能发起尺寸查询；FutureBuilder 类型应显式化；reader 复用章节时应补齐加载器/章节身份与阅读记录语义；初始化专辑请求需收敛异常。
- 本轮已在本地 Flutter 3.41.2/Dart 3.11.0 上执行 analyzer 和 widget test；Rust contract test、真实平台设备回归和性能基线仍待执行，不能以本地 Flutter 结果替代它们。
- 新增 `.github/workflows/CI.yml`：原设计仅执行无签名副作用的 `flutter pub get`、`flutter analyze` 和 `flutter test`；按本轮本地构建要求已改为仅手动诊断触发，不改变现有 Build/Release 手动发布流程。
- CI 首次运行（GitHub Actions run `33315355755`/`33315357701`，2026-08-30）在 job 启动前因仓库账号 billing issue 被 GitHub 拒绝，`steps` 为空；这不是 analyzer/test 结果。按用户要求后续不依赖托管 runner，workflow 已改为仅手动触发，本地门禁才是本轮验收依据。
- 预取错误隔离补强正在独立提交：邻页 `precacheImage` 失败只记录错误类型，不传播到当前页，也不输出 URL/签名参数；post-frame 入口继续受 `mounted` 保护。
- 使用本地锁定工具链运行 `flutter test --no-pub`：全量 69 个测试通过；reader 新增空章节占位、章节 loader 错误和越界初始索引 3 个回归用例均通过。测试夹具显式初始化 reader 配置，避免绕过 `InitScreen` 时触发未初始化的 `late` 配置。
- 使用同一工具链运行 `flutter analyze --no-pub`：发现 0 个 analyzer error；命令因项目既有 137 条 info/deprecation lint 以退出码 1 结束，这些信息不属于本轮 M1 编译错误。修复了本轮代码引入的 reader key 插值错误和两个不必要的非空断言。
- 按用户指定将本地验证/构建输出根固定为 `D:\Cat\jm3\build`（实际测试通过 `FLUTTER_BUILD_DIR` 指向该目录）；未继续触发 GitHub Actions，`.github/workflows/CI.yml` 改为仅 `workflow_dispatch`。

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

本地构建环境已可用：`D:\Cat\jm3\_flutter\flutter` 提供 Flutter 3.41.2/Dart 3.11.0，`D:\Cat\jm3\toolchains` 提供 Rust/Android/MSVC 工具链；平台构建必须使用 `D:\Cat\jm3\build` 的隔离子目录，不能覆盖用户已有的主构建缓存。Rust 仓库工作树仍有用户未提交修改，未在本轮改动。

## 12. 变更记录

### 2026-08-30

- 增加“固定工作上下文”章节，持久记录源代码工作区与独立构建根、环境加载命令、分支/PR/恢复点、禁止事项、M1/M2 状态、构建产物路径和未验证风险，供上下文压缩或换代理后恢复。
- 2026-08-30 23:26（+08:00）再次执行 `D:\Cat\jm3\scripts\verify_build_env.ps1`：工具链、SDK、MSVC、Rust metadata 和 `flutter doctor -v` 全部通过；本次仅做只读核验，未触发 GitHub 构建、未改动外部 Rust 工作树。
- 将上下文记录提交为 `2717aaa`/`6d73c8c`/`346ad0a`，创建并推送恢复标签 `reader-optimization-m1-checkpoint-context`，并将功能分支同步到 Draft PR #2；未使用 force-push，未触发任何 GitHub workflow。
- 创建本文档，记录阅读链路和初版优化方案。
- 完成前端、Rust 后端、质量/交付三路只读审查。
- 将“目标尺寸解码”明确为“解扰后的 Flutter codec 下采样”，禁止解扰前缩放。
- 将原 P0 中的高风险项拆出：缓存迁移、ReaderSession、预取、双页窗口化、精确进度、批量 API 分阶段实施。
- 将固定性能数字改为“先采集基线，再设相对门槛”。
- 二次审查补充 R-20～R-30：切章/模式切换 generation、音量监听对称释放、全屏状态恢复、异步尺寸陈旧回调、尺寸 key 限档、offline owner/路径规范化、并发预算和日志脱敏。
- 继续深审补充 R-31～R-33：解扰失败不得伪装成 canonical、绝对 URL 的凭据外泄、`clean_all_cache` 与 fetch/read 并发竞态。
- 边界审查补充 R-34～R-39：FocusNode/预取回调生命周期、空章节与非法初始页、异常图片列表、异步导航，以及空下载任务误用 album id。
- 增加硬依赖图、各阶段完成定义、能力开关矩阵、缓存迁移/进度 schema 草案、灰度回滚 runbook、兼容矩阵和隐私约束。
- 记录主仓库与 Rust 基线 SHA；确认 Rust 工作树仍有用户未提交修改（本轮未触碰）。
- 按可回溯要求创建分支 `MrYu/reader-optimization-m1`、基线提交 `c7b8498`、本地基线 tag，并推送 Draft PR #2；M1 仅启动生命周期/缓存竞态子集。
- M1 子集已拆分并推送：`cfaf5f4`（Future/cache generation）和 `6474b38`（reader 生命周期、边界、导航、FocusNode/音量监听）；后续补强保持独立提交，并持续执行 `git diff --check`/`git show --check`。
- 本地验证补充：使用 `D:\Cat\jm3\_flutter\flutter`（Flutter 3.41.2/Dart 3.11.0）执行全量 `flutter test --no-pub`，69 个测试通过；`flutter analyze --no-pub` 发现 0 个 error，退出码 1 仅由项目既有 137 条 info/deprecation lint 触发。
- 新增 reader widget 回归用例（空章节占位、章节加载失败、越界初始索引），并为直挂 reader 的测试夹具显式初始化配置；修复 analyzer 报出的 reader key 插值错误和不必要的非空断言。
- 按用户要求停止依赖 GitHub 构建：`.github/workflows/CI.yml` 改为仅手动诊断触发；本地测试/平台构建输出统一指向 `D:\Cat\jm3\build` 的隔离子目录，避免覆盖已有构建缓存。
- 本轮先完成本地环境证据核验：`D:\Cat\jm3\scripts\verify_build_env.ps1` 全部工具/SDK 检查通过，`flutter doctor -v` 为 `No issues found!`；使用 Flutter 3.41.2 对当前分支执行 `flutter build windows --release --no-pub`，产物写入 `D:\Cat\jm3\build\reader-optimization-m1\windows\x64\runner\Release`。
- Android smoke build 暴露配置阻塞：当前分支 `android/gradle.properties` 写死 `C:\\Program Files\\ojdkbuild\\...`，该目录不存在；在修改前不把“工具链齐全”误报为“Android 构建已通过”。下一步仅移除该开发机专属覆盖，改由已验证的 `JAVA_HOME`（JDK 21）提供 Gradle JDK，再重跑构建。
- 移除 JDK 覆盖后，Android smoke build 又确认 `flutter.ndkVersion` 在 Flutter 3.41.2 下解析为 `28.2.13676358`；`D:\Cat\jm3\toolchains\android-sdk\ndk\28.2.13676358` 仅有 `.installer`、缺少 `source.properties`。本地 Rust JNI/SDK 验证矩阵实际固定为 NDK `25.2.9519653`，因此下一步在 app 配置中显式固定 25.2，并在构建后核对 JNI 文件 hash 未被改写。
- Android 构建在显式 NDK 25.2 后成功生成 arm64 Release APK，但 Flutter 3.41.2 的 Android Gradle 模板仍把 Gradle 输出根硬编码为仓库 `../build`，因此本次 APK/中间文件落在 `D:\Cat\jmcomic3\build`，没有把这一点误记为“已完全外置到 `D:\Cat\jm3\build`”。后续需单独设计可回滚的 Android 输出重定向，再纳入本地构建脚本。
- 对当前工作树执行 `flutter pub get --offline` 时，依赖缓存可解析但插件 symlink 创建被 Windows 权限拒绝（提示启用 Developer Mode/管理员权限），退出码为 1；该命令产生的 `pubspec.lock` 镜像/传递版本改写只属于本轮验证副作用，已计划撤销，不作为功能变更提交。
- 使用外部 target 目录运行 Rust 后端 `cargo test --offline`：120 个单元测试、doc-test 和 smoke binary 均通过；Rust 工作树仍保留用户原有未提交修改，测试未写入源文件。
- Flutter 回归门禁再次通过：`flutter test --no-pub` 69/69；`flutter analyze --no-pub` 0 error，但因既有 137 条 info/deprecation lint 返回 1。Windows Release 产物已核验包含 exe、`flutter_windows.dll`、插件 DLL 和 `data` 目录；Android arm64 APK 已核验 manifest/version/ABI 与 `lib/arm64-v8a/librust.so`。
- Android 构建仍有非阻塞提示：file_picker 等插件声明 NDK 27.0.12077973，而本地已验证 Rust 构建使用 NDK 25.2.9519653；在本机 25.2 下构建成功。发布前应决定是否补装/切换 NDK 27，并重新跑两 ABI smoke，不把该 warning 当作跨机器兼容性证明。

## 13. 后续更新规则

### 2026-08-31 继续执行前置审查（checkpoint）

- 继续执行前先复核：主仓库分支 `MrYu/reader-optimization-m1`，HEAD `6e0dae7`；已创建本地恢复标签 `reader-optimization-continue-checkpoint-20260831-0020`。当前未提交改动来自 M3/M4/M5 兼容补强和既有 Windows 生成文件，不能用 reset/checkout 清理。
- 外部 Rust 工作树 `D:\Cat\jmcomic3-rust-backend` 分支 `MrYu/m5-page-batch-contract` 保留用户 dirty 的 `rust/README.md`；批量尺寸字段修复提交 `96f6a6c` 已独立记录，后续构建需固定该 SHA 或明确使用旧兼容行为。
- 本轮新增的硬门禁：M5 Dart 批量响应必须校验版本、数量和顺序，任一异常整体回退旧单页；M4 去重条目完成后必须可重新调度，关闭后不得启动新任务；M3/M6 在没有后端 `local_path` 之前不得猜造离线路径。
- 未运行的设备、真实 scrambled fixture、Rust 解扰失败缓存隔离、Android 双 ABI 和正式签名检查继续标记为待执行/阻塞，不因模型测试通过而宣称完成。

### 2026-08-31 M3 增量

- 在 `_ComicReaderState` 增加 `ReaderPageRepository.fromOnline` 兼容转换，维护
  source-neutral `_pageDescriptors` 元数据；现有 `chapter.images` 渲染和离线旧 API
  保持不变，便于独立回滚。离线 `DlImage` 转换仍由 repository 提供，待离线 reader
  数据入口具备后再接入。
- 验证：`flutter test test/reader_pages_test.dart` 及 reader session tests；未启用新
  元数据驱动渲染，故无行为变化。

### 2026-08-31 00:59 继续执行审计 checkpoint

- 在开始本轮代码审查前，保留当前 dirty 工作区不变，并创建恢复分支
  `MrYu/reader-optimization-audit-20260831-005916` 与标签
  `reader-optimization-preaudit-20260831-005916`；当前工作仍在
  `MrYu/reader-optimization-m1`，不改写既有提交历史。
- 本轮先处理 M5 Dart 批量测试夹具和 reader 生命周期/双页边界审查；未通过的检查继续标为待执行，不把已有模型测试当作阶段完成证据。

### 2026-08-31 01:15 持续目标前置 checkpoint

- 本轮目标仍为“完成所有可执行项并明确阻塞项”；当前线程已有 active goal，继续沿既定目标推进。
- 在继续集成前创建可回滚恢复点分支 `MrYu/reader-optimization-preintegration-20260831-011554` 与标签 `reader-optimization-preintegration-20260831-011554`；当前功能分支和已有 dirty 工作区保持不变，未改写历史。
- 并行复核 M4 reader 边界、M5 Rust availability 契约和 M6 Dart availability 接口；外部 Rust 工作树的 `rust/README.md` 与 `invoke.rs` 未提交差异继续保留，未经隔离测试不得覆盖或宣称完成。
- 本轮新增/修改代码在阶段提交前必须通过 `git diff --check`、定向测试和全量 Flutter 门禁；Android/Windows 产物仍只允许写入 `D:\Cat\jm3\build`。

### 2026-08-31 继续执行 reader/离线审查

- 继续 active goal 前先复核主仓库仍在 `MrYu/reader-optimization-m1`，保留既有 dirty 工作区与恢复标签；没有执行 reset、checkout 或覆盖用户文件。
- 并行审查结论：Webtoon/FreeZoom 的图片 State key 需要携带 source index；Rust availability 仍需 scalar/object 参数兼容、有限 header probe 和可注入测试；offline owner 尚未具备可信文件复制/校验/原子提交链路，因此 `readerOfflineOwnerV1` 继续默认关闭。
- 本轮将先完成 reader 边界修补和回归证据，再处理 Rust/offline owner；每一步先补充测试和文档，未运行的门禁不宣称通过。

### 2026-08-31 Rust availability 与主仓库回归复核

- 先在主仓库 HEAD `4ed95ce` 上创建恢复分支/标签
  `MrYu/reader-optimization-before-final-review-20260831` /
  `reader-optimization-before-final-review-20260831`；保留所有 dirty 文件，未执行
  reset、checkout、clean 或强制覆盖。
- 在独立 worktree `D:\Cat\jm3\worktrees\m5-availability-contract` 完成
  `dl_image_local_availability` 路由：参数兼容 scalar/object，使用与 canonical
  page fetch 相同的 `page_<chapter>_<name>_decoded_v1` key，有限 header probe 加
  `image_dimensions` 校验，拒绝 missing/empty/HTML/损坏文件，并返回显式
  `local_path/local_available/local_state`。提交为 `a7a8015`，标签为
  `reader-optimization-m5-availability-20260831`；原 Rust 工作树
  `D:\Cat\jmcomic3-rust-backend` 的用户 dirty `rust/README.md` 和 `invoke.rs`
  未修改。
- Rust 隔离 worktree 的 `cargo fmt --check` 通过，`cargo test --offline` 为
  126/126 通过（含 availability 合约测试）；本机未安装 `cargo-clippy`，因此
  clippy 保持“未执行”，不能写成通过。
- 主仓库定向 reader 回归命令
  `flutter test test/page_pairing_test.dart test/widget_test.dart test/reader_pages_test.dart --no-pub`
  为 13/13 通过；`flutter analyze --no-pub` 为 0 error，退出码 1 仅来自项目既有
  140 条 info/lint。所有命令使用锁定 Flutter 3.41.2，未触发 GitHub workflow。
- 逻辑复核发现两个必须先修正再扩大灰度的风险：offline descriptor 的稀疏/重复
  `imageIndex` 会与 `chapter.images` 的 0-based 索引错配；ReaderSystemUiLease 的
  异步 enter 在 release 后可能覆盖恢复状态。下一步按增量补丁修复并增加回归测试。
- M6 offline owner 仍未完成：没有下载文件复制→校验→原子 rename→completed 的
  链路、manifest、迁移中断恢复或 fetch/read/clean 共享锁；`readerOfflineOwnerV1`
  继续默认 OFF。M0 真机/网络基线、正式签名、Android 双 ABI 发布矩阵和 M7
  golden/崩溃持久化也继续标记为待执行。

### 2026-08-31 阅读优化增量审查（持续记录）

- `reader_viewlog_queue.dart` 新增有界内存队列：`maxPending` 默认 256，达到上限时丢弃最旧 snapshot，并通过 `droppedCount` 暴露诊断；失败重放同样受容量限制。该实现不等同于崩溃持久化，进程退出前仍须显式 flush 或接受丢失风险。
- `images.dart` 的尺寸缓存现拒绝 `w/h <= 0`，抛出 `FormatException` 并允许后续有效尺寸重试，避免零尺寸污染布局/cache。metadata-only 或本地文件不可读的离线页显示明确“离线图片不可用，请重新下载”占位，不得偷偷回退在线请求；真实 widget/UI 回归仍待补。
- 上述代码修改后，原有 119/119 默认与全 flags 测试、analyzer 结果均需重新执行；旧证据不能覆盖本轮变更（已在 03:35 门禁中重跑，更新结果见 0.5 与最终门禁记录）。验证命令和产物仍必须使用锁定 Flutter 环境及 `D:\Cat\jm3\build`，不触发 GitHub Actions。
- 未完成/高风险边界再次确认：M0 真机与网络性能基线、真实 scrambled fixture、正式签名和 Android 双 ABI 发布矩阵；M6 offline owner（复制/校验/原子 rename、manifest、迁移恢复、fetch/read/clean 共享锁）；M7 双页窗口化 golden、真实 list reader 和崩溃持久化。所有对应开关保持 OFF。
- Rust availability 提交 `a7a8015` 及 M6 helper 仅存在隔离 worktree `D:\Cat\jm3\worktrees\m5-availability-contract`；原 Rust 工作树 `D:\Cat\jmcomic3-rust-backend` 的 `rust/README.md`、`rust/src/api/invoke.rs` 用户 dirty 修改不得覆盖，未获维护者审查前不宣称已合并。
- 一致性复核快照：主仓库当时为 `MrYu/reader-optimization-m1`、HEAD `4ed95ce`，相对远端领先 16 个提交；工作区仍包含功能代码、测试及未跟踪文件，另有 Flutter/Windows 生成文件（不得顺手提交）。因此本文件中的 69/69、旧 analyzer 数字和历史 HEAD 仅代表当时证据，不是当前门禁结果；已在后续提交 `b59e139`/`fe83871` 后重新执行门禁。

### 2026-08-31 03:35 最终本地门禁（提交前）

- 在主仓库保持 dirty 变更不变的前提下，创建恢复分支/标签
  `MrYu/reader-optimization-pre-finalize-20260831-032500`；未执行 reset、clean、
  force-push，也未触发 GitHub Actions。
- 使用 `D:\Cat\jm3\scripts\enter_build_env.ps1` 加载 Flutter 3.41.2/Dart 3.11.0、
  Rust 1.98、JDK 21、NDK 25.2.9519653；Flutter 测试日志和诊断输出写入
  `D:\Cat\jm3\build\reader-optimization-validation-final`。
- 默认与全部 reader flags 两组 `flutter test --no-pub` 均为 123/123；新增批量
  响应非字符串字段回归后再次通过。功能提交为 `b59e139`，测试提交为 `fe83871`；
  `dart format --set-exit-if-changed`（28 个文件）
  与 `git diff --check` 通过。
- `flutter analyze --no-pub` 发现 0 error、137 条项目既有 info/lint（退出码 1）；
  analyzer 不接受 `--dart-define`，故没有把“不支持该参数”误记为全 flags analyzer 结果。
- Rust availability 仍只在隔离 worktree 的提交 `a7a8015` 中验证：`cargo fmt --check`
  通过，`cargo test --offline` 128/128；原 Rust 工作树及隔离 worktree 的未提交
  M6 helper 均保留，未合并或覆盖。
- 当前可交付边界：安全回滚的 M1/M2/M3/M4/M5/M7 实现子集及回归测试已具备；
  M0 真机/网络/签名、M2 真实 scrambled fixture 与跨设备内存、M4 真实取消、M5
  跨版本 smoke、M6 offline owner 复制/校验/原子迁移/共享锁、M7 golden/真实 list
  reader/崩溃持久化仍是待执行项，相关开关保持默认关闭。构建脚本仍可能把 JNI/
  Windows staging 文件写入其 checkout；因此不宣称“所有平台产物已完全外置”，只
  认可本记录中明确的 `D:\Cat\jm3\build` 测试/诊断输出。

### 2026-08-31 03:52 当前 HEAD 最终本地门禁（提交文档前）

- 固定环境入口为 `D:\Cat\jm3\scripts\enter_build_env.ps1`，自检脚本
  `D:\Cat\jm3\scripts\verify_build_env.ps1`；Flutter 3.41.2/Dart 3.11.0、
  Rust 1.98、JDK 21、NDK 25.2.9519653、MSVC/CMake/Ninja 和 Android SDK
  均通过自检，`flutter doctor -v` 报 `No issues found!`。
- 测试基线为主仓库 HEAD `015fcf9`。默认命令
  `flutter test --no-pub` 完成 **124/124**；全开以下 8 个编译开关的同一命令也完成
  **124/124**：
  `JM_READER_PAGE_DESCRIPTOR_V1`、`JM_READER_PREFETCH_SCHEDULER_V1`、
  `JM_READER_BATCH_API_V1`、`JM_READER_OFFLINE_OWNER_V1`、
  `JM_READER_TWO_PAGE_WINDOW_V1`、`JM_READER_PRECISE_PROGRESS_V1`、
  `JM_READER_VIEWLOG_QUEUE_V1`、`JM_READER_TARGET_DECODE_V1`。
  完整日志分别为
  `D:\Cat\jm3\build\reader-optimization-validation-final-20260831\flutter-test-default.log`
  和 `...\flutter-test-all-reader-flags.log`。
- `flutter analyze --no-pub` 本轮发现 0 error、137 条项目既有 info/lint，退出码
  为 1（Flutter analyzer 的既有诊断行为）；输出保存为
  `...\flutter-analyze.log`。Analyzer 不接受 `--dart-define`，因此没有虚构“全 flags
  analyzer”结果；全 flags 至少由上面的完整测试编译并执行覆盖。
- `dart format --set-exit-if-changed` 检查 28 个变更 Dart 文件，0 文件被改写；
  `git diff --check` 退出码 0。日志和文件清单保存在同一 `D:\Cat\jm3\build` 验证目录。
- 本轮没有触碰或清理主仓库现有生成文件
  `windows/flutter/generated_plugin_registrant.{cc,h}`、
  `windows/flutter/generated_plugins.cmake`、`windows/rust.h`；外部 Rust 工作树
  `D:\Cat\jmcomic3-rust-backend` 的用户 dirty `rust/README.md`、
  `rust/src/api/invoke.rs`，以及隔离 worktree 的 M6 helper 均保留原状。
- 该证据只证明安全可回滚的实现子集和本地回归门禁；M0 真机/网络/签名、M2 真实
  scrambled fixture、M4 真实取消、M5 跨版本 smoke、M6 offline owner 的复制/校验/
  原子迁移/共享锁、M7 golden/真实 list reader/崩溃持久化仍未完成，相关开关继续 OFF。
- 后续动作固定为：仅提交本文件（不带生成物）→ 创建最终恢复 tag
  `reader-optimization-final-local-gates-20260831-035300` → 普通 push
  `MrYu/reader-optimization-m1` → 只核对 Draft PR #2；不触发 GitHub Actions。

### 2026-08-31 03:55 收尾同步核对（已完成）

- 文档刷新提交 `dba86f796b82b78a1b00dc2fb20a9e110c869b0d`（短 SHA
  `dba86f7`）及其收尾记录提交 `f4f056508ddd3d74ff433395027ff6eb89c2708f`
  （短 SHA `f4f0565`）均已用普通 `git push` 推送到
  `origin/MrYu/reader-optimization-m1`；`git fetch --prune` 后本地与远端无领先差异。
- 回滚 tag `reader-optimization-final-local-gates-20260831-035300` 已创建并推送，
  指向 `dba86f7`；回滚 tag `reader-optimization-final-local-gates-20260831-035600`
  也已创建并推送，指向 `f4f0565`。本条收尾提交后将再创建
  `reader-optimization-final-local-gates-20260831-035800` 作为最新文档快照。
- 只读 PR 核对：`https://github.com/MrYu-JMComic/JMcomic3-flutter/pull/2`，
  `state=OPEN`、`isDraft=true`、head=`MrYu/reader-optimization-m1`、base=`main`。
  仓库工作流均为 `workflow_dispatch`，本轮 push 未启动 GitHub 构建。
- 收尾后工作区仍只包含既有生成/暂存文件
  `windows/flutter/generated_plugin_registrant.{cc,h}`、
  `windows/flutter/generated_plugins.cmake`、`windows/rust.h`；这些文件和外部
  Rust 用户 dirty 修改均未清理、未覆盖、未提交。
- 目标完成判定采用“安全可回滚子集完成 + 阻塞项显式保留”，不是把整个长期计划
  误报为完成。若后续继续，先读取本文件，再从未完成项和最新 tag 分支恢复。

### 2026-09-01 13:27 PR #2 合并后核对

- 合并前已创建并推送 checkpoint 分支/tag：
  `MrYu/reader-optimization-pre-merge-20260901-132232` /
  `reader-optimization-pre-merge-20260901-132232`，指向功能分支 head
  `9d9873b`；外部 Rust 工作树用户 dirty 修改和主仓库生成文件未触碰。
- PR #2 先从 Draft 转为 Ready，再使用 `--merge --match-head-commit
  9d9873b0a6b78c49c4c19fe7f8268af4e210528a` 合并；GitHub 返回成功，merge commit
  为 `c1cd690410b27ef0fa842a7ed781beafb4dcf647`，没有删除源分支或改写历史。
- `git fetch --prune origin` 后，`origin/main` 指向 `c1cd690`，且
  `git merge-base --is-ancestor 9d9873b origin/main` 通过；源分支和合并前 checkpoint
  仍指向 `9d9873b`。合并后回滚 tag
  `reader-optimization-post-merge-20260901-132400` 已创建并推送，指向 `c1cd690`。
- PR 只读状态为 `state=MERGED`、`isDraft=false`；主分支无保护规则，合并时没有
  required checks，`statusCheckRollup=[]`。本地门禁证据仍是固定环境下默认/全 flags
  124/124；本轮没有重新跑平台构建，也没有主动触发 GitHub Actions。
- 远端历史中可见的是 2026-08-30 的旧 `Flutter CI` 失败记录；它们发生在本次合并前，
  不是本次合并触发的构建。仓库 workflow 均保持 `workflow_dispatch`，本轮没有新增运行。
- 合并边界不变：只合并安全可回滚子集；R-02/R-08/R-14/R-18/R-26/R-27/R-29/
  R-32/R-33 等未完成或阻塞风险，以及真实设备/网络/解扰 fixture/签名/golden/崩溃
  持久化证据，仍需后续独立阶段处理，高风险开关保持默认关闭。

### 2026-09-01 13:28 合并后文档同步

- 将合并状态、merge commit `c1cd690`、源分支保留策略和 post-merge 回滚点写回本文件。
- 文档同步提交为 `1fe20882d2290f94b612c39415845b57f3588df5`（短 SHA `1fe2088`），
  已从 `origin/main` 的 merge commit 快进推送到 `main`；独立备份分支
  `MrYu/reader-optimization-post-merge-docs-20260901-132500` 和 tag
  `reader-optimization-post-merge-docs-20260901-132800` 均保留。
- 本次仅变更文档，未重新执行代码测试；此前针对代码/测试基线 `015fcf9` 的默认与全 flags
  124/124 门禁证据继续有效。生成文件和外部 Rust dirty 修改未纳入。

### 2026-09-01 13:58 M2 阶段：view-log 持久化契约与双页回归

- 从 `origin/main`/`94a8bcc` 创建阶段分支 `MrYu/reader-optimization-m2`，并创建本地
  起点 tag `reader-optimization-m2-start-20260901-133345`；没有改写 PR #2 历史，
  主仓库生成文件和外部 Rust dirty 修改继续保留。
- 提交 `1270602` 增加 `ReaderViewlogStore` 与版本化的
  `ReaderViewlogPropertyStore`：session key 使用窄字符白名单，journal 校验 schema、
  事件字段、256 条/64 KiB 上限，读取失败只保留内存事件并记录错误；`ReaderViewlogQueue`
  在 `JM_READER_VIEWLOG_QUEUE_V1=true` 时恢复同 session 的 pending 事件，ack 后清空，
  失败事件跨实例保留。默认 flag 仍为 OFF。
- 提交 `8b96fd5` 增加双页窗口 widget 回归：默认 legacy static gallery 与实验 builder
  分支分别校验，实验分支覆盖 cover、RTL、奇数页、单页和初始 slot；同一测试还捕获并
  修复了双页 legacy `initState` 提前依赖 `MediaQuery` 的 Flutter 生命周期断言。
- `1270602` 同时收紧 journal key 校验，避免任意属性 key 被持久化适配器使用；
  `85034cf` 仅将 schema prefix 声明收紧为编译期常量。
- 定向持久化/双页测试通过；固定环境下当前 HEAD `85034cf` 的默认全量测试和 8 个 reader
  flags 全量测试均为 **132/132**，日志位于
  `D:\Cat\jm3\build\reader-optimization-m2-validation`。目标文件 format 检查通过，
  analyzer 0 error/137 条既有 info-lint，`git diff --check` 通过。
- 逻辑后果和边界：该 journal 解决正常进程重启前后的 pending 事件恢复，不证明操作系统
  强杀瞬间的原子落盘，也不定义 WebDAV/跨设备事件合并；因此 M7 崩溃持久化只标记为
  “契约与本地属性适配已完成，真实 crash/native 原子演练待执行”，不能将 M6 offline
  owner 或 Rust R-32/R-33 安全项标记完成。
- 本阶段 PR 只包含上述六个文件/测试变更；工作区已有 `README.md`、`docs/`、
  `scripts/setup_android_emulator.ps1` 和 Windows generated files 未纳入提交。

### 2026-09-01 14:04 PR #3 创建后核对

- 文档提交 `9600298` 之后创建并推送恢复 tag
  `reader-optimization-m2-final-local-gates-20260901-140139`；阶段分支
  `MrYu/reader-optimization-m2` 与 `origin` 同步，未使用 force-push。
- 已创建 Draft PR #3：
  `https://github.com/MrYu-JMComic/JMcomic3-flutter/pull/3`，base=`main`、
  head=`9600298`、`state=OPEN`、`isDraft=true`、`statusCheckRollup=[]`。
  仓库 workflow 仍仅 `workflow_dispatch`，没有因 push/建 PR 触发 GitHub 构建。
- 本地工作区继续保留 `README.md`、`docs/`、`scripts/setup_android_emulator.ps1`、
  `windows/flutter/generated_plugin_registrant.{cc,h}`、
  `windows/flutter/generated_plugins.cmake` 和 `windows/rust.h` 的用户/生成差异，
  均未纳入 PR；外部 Rust 工作树 dirty 文件也未触碰。

### 2026-09-01 14:10 M2 最终门禁与只读审查

- 在固定环境重新运行默认全量测试和全部 8 个 reader flags 全量测试，当前代码行为
  均为 **132/132**；最新日志为
  `D:\Cat\jm3\build\reader-optimization-m2-validation\flutter-test-default-final-rerun.log`
  和 `flutter-test-all-reader-flags-final-rerun.log`。
- `verify_build_env.ps1` 通过；目标文件 `dart format --set-exit-if-changed` 为 0 changed；
  `git diff --check`、`git show --check` 通过。`flutter analyze --no-pub` 报 0 error、
  137 条仓库既有 info/lint（项目现状导致退出码 1），没有新增 analyzer error。
- 对 `ReaderViewlogQueue` 的恢复/重排、flush/close 并发、持久化请求合并和失败保留，及
  `ReaderViewlogPropertyStore` 的 key/schema/大小边界进行了只读审查，未发现当前阶段
  阻塞问题。稳定 chapter key 的多实例覆盖、属性桥非原子写入和 dispose 后异步落盘仍是
  已知风险，必须由后续 native atomic/共享锁与 crash 演练阶段处理。
- PR #3 当前仍为 Draft：base=`main`、head=`0fc4251`、`state=OPEN`、
  `statusCheckRollup=[]`；本轮没有触发 GitHub workflow。后续最终标签应指向文档收尾提交，
  并继续使用普通 push，不得 force-push。
- 本阶段交付边界仍是默认关闭、可独立回滚的 M2/M7 实现子集；M0 真机/网络/签名、M2
  真实 scrambled fixture、M4 真实取消、M5 跨版本 smoke、M6 offline owner/迁移/锁、
  M7 native crash/golden/list-reader，以及 Rust R-32/R-33 仍未完成，不得标记为计划全部完成。

每次继续工作时，按以下顺序更新本文档：

1. 在“任务状态”或“变更记录”中写明本轮做了什么。
2. 记录新增证据、假设和未验证项。
3. 若任务的优先级、依赖、后果或回滚方式改变，先修改对应审查表。
4. 实现后补充实际测试命令、设备、结果和失败样本；未运行的项目保持“待执行”。
5. 完成一个阶段后再开启下一个阶段，避免同时发布多个高风险开关。
