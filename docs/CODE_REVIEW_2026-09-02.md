# 代码审查与修改建议（2026-09-02）

## 结论摘要

本次审查覆盖：

- 主仓库：D:\Cat\jmcomic3，分支 MrYu/reader-optimization-m2；
- Rust/FRB 仓库：D:\Cat\jmcomic3-rust-backend，分支 MrYu/m5-page-batch-contract；
- 当前工作区的未提交代码、测试、Android/Windows 构建配置和 FRB 迁移文件。

建议暂缓把当前状态作为“可发布/可合并”基线，先处理 P1 项。最需要优先修复的是：

1. Release 工作流的 Flutter/NDK 版本冲突；
2. Rust FRB 同步入口阻塞 Flutter 主 isolate；
3. WebDAV Merge 在任意读取错误时覆盖远端快照；
4. logout 后复用仍持有旧 Cookie 的 HTTP client；
5. 下载图片合并遗漏 album_id，造成跨专辑串图/状态串扰；
6. 多处异步 UI 回调缺少 mounted 保护；
7. Rust store 的失败写入不会回滚内存状态。

## 优先级定义

- P0：发布前必须阻断；可能造成安全/授权绕过、不可逆数据损失或必现崩溃。
- P1：高概率或高影响故障；应在合并/灰度前修复。
- P2：中等影响、边界条件或可靠性/性能风险；应纳入近期迭代。
- P3：维护性、可观测性或低风险改进。

## 发现总表

| ID | 级别 | 位置 | 主要影响 |
|---|---|---|---|
| R-01 | P1 | Release.yml:12,129-159；android/app/build.gradle:46-52 | Release 安装 NDK 与 Gradle 选用版本不一致，干净 runner 可能无法配置 |
| R-02 | P1 | Build.yml:28,32；Release.yml:13-14；.fvmrc；pubspec.lock:581-583 | 发布工作流使用 Flutter 3.7.3，无法满足当前 Dart/Flutter SDK 约束 |
| R-03 | P1 | .github/workflows/CI.yml:3-7,35-39 | 手动 CI 的 flutter analyze 当前因 137 条 info 退出码为 1，且 push/PR 不触发 |
| R-04 | P1 | Rust 测试 invoke.rs:13726-13761 | 单元测试访问公网，当前现场 137 个测试中 1 个失败，CI 不确定 |
| R-05 | P1 | FRB invoke.rs:894-904,1054-1065；生成 Dart API；bridge factory | #[frb(sync)] 等待阻塞任务，网络/导出会冻结 Flutter 主 isolate |
| R-06 | P1 | Rust invoke.rs:8077-8090 | WebDAV Merge 把“读取失败”当成“远端不存在”，可能覆盖远端数据 |
| R-07 | P1 | Rust invoke.rs:6384-6408,4672-4681 | logout 只清 store，不清 reqwest CookieStore，旧账号会话可继续发送 |
| R-08 | P1 | Rust invoke.rs:8208-8284,3765-3775；Dart reader_pages.dart:128-155 | 图片合并/availability key 缺少专辑维度，跨专辑共享 chapter 时串图 |
| R-09 | P1 | 多个 Flutter 页面 | await 后对已卸载 State 调 setState、Toast 或 Navigator，快速返回可崩溃 |
| R-10 | P1 | Rust invoke.rs:686-698,10372-10395 | 持久化失败不回滚内存；主 store 与分片非事务写入，可能覆盖/丢数据 |
| R-11 | P1 | rust_builder/windows/CMakeLists.txt:12 | Windows CMake 的 Rust 相对路径越出仓库，干净 FRB 构建找不到 manifest |
| R-12 | P1/P2 | windows/runner/main.cpp:13-21；methods_plugin.cpp:8-11,53-60 | FFI 参数/返回值未校验，异常通道或退出竞态可导致 native 崩溃 |
| R-13 | P1 | Rust invoke.rs:2951-2972,531-561,6384-6408 | 任意 URL/重定向/未限制响应体形成 SSRF、重定向和 OOM 风险 |
| R-14 | P1/P2 | methods.dart:904-928；download_album_screen.dart:335-360 | 新调用改成 object 参数但无旧后端 scalar fallback，离线入口可能失败 |
| R-15 | P2 | Rust 网络/导入/图片路径 | bytes/text/read_to_end 和图片解码缺少大小/像素上限，可被大响应拖垮 |
| R-16 | P2 | Rust invoke.rs:7379-7400 | 递归扫描跟随 symlink/junction，可能越界读取、循环或打包敏感文件 |
| R-17 | P2 | Rust page_batch_contract.rs:43-73；Dart batch entity；Rust batch endpoint | 版本契约未接入实际路由；版本溢出和 0 尺寸响应会触发整批 fallback |
| R-18 | P2 | Rust invoke.rs:8397-8447,181-215 | WebDAV 允许 HTTP Basic Auth；账号密码以明文 JSON 保存 |
| R-19 | P2 | Dart methods.dart:53-129 | 清 cache/换账号时旧 in-flight Future 可删除新 Future、回写旧数据 |
| R-20 | P2 | Dart comic_pager.dart:23-28,149-164；comments list | 首页空列表但 total>0 时把最大页数设为 1，后续分页停止 |
| R-21 | P2 | reader_viewlog_queue.dart:27-35；reader state:729-739 | 同一漫画/章节的多个实例共享持久化 key，可能互相覆盖待发送事件 |
| R-22 | P2 | Android MainActivity.kt:235-280 | onAuthenticationFailed 立即写入 false，用户随后成功也不会放行 |
| R-23 | P2 | Rust invoke.rs:4593-4597 | 登录密码在发送前 trim，合法的首尾空格密码无法登录 |
| R-24 | P2 | Flutter images.dart:187-262,1352-1370 | 目标解码仍重复复制压缩字节；shared buildFile 只按宽度采样，内存收益不稳定 |
| R-25 | P2 | Rust invoke.rs:8218-8284；3941-3949 | legacy album_id<=0 记录可抑制补抓或被错误归属，下载列表可能不完整 |
| R-26 | P2 | Release/Build workflow | backend checkout 未固定 commit，发布产物不可复现且有供应链漂移 |
| R-27 | P2 | FRB bridge 与主仓库 | 主仓库 Methods 仍直接走 MethodChannel，FRB bridge 未接入实际运行路径 |
| R-28 | P3 | Flutter/Rust 工具链 | Clippy 未纳入 CI；启用 avif 还依赖系统 dav1d/pkg-config |

## 详细说明与修改建议

### R-01 / R-02：发布工作流版本不一致（P1）

证据：

- D:\Cat\jmcomic3\.github\workflows\Release.yml:12 设置 NDK_VERSION: 27.2.12479018，并在 129-133 只安装这个 NDK；
- D:\Cat\jmcomic3\android\app\build.gradle:52 硬编码 ndkVersion 25.2.9519653；
- Build workflow 使用 25.2，而 Release workflow 使用 27.2，两个发布入口行为不一致；
- Build.yml:28,32 和 Release.yml:14 固定 Flutter 3.7.3；
- D:\Cat\jmcomic3\.fvmrc 为 Flutter 3.41.2，pubspec.lock:581-583 要求 Dart >=3.10、Flutter >=3.38。

影响：

- Release runner 安装的 NDK 目录与 Gradle 解析的 NDK 目录不匹配，干净环境可能在 Gradle configuration 阶段失败；
- Flutter 3.7.3 自带的 Dart 版本低于 lockfile 约束，pub get/构建会在依赖解析阶段失败；
- 本地固定环境通过不能证明 GitHub runner 可复现。

建议：

1. 只保留一个版本来源，例如 workflow 使用 flutter-version-file: .fvmrc，不要再写 3.7.3；
2. 把 NDK 版本放入单一 Gradle property 或 workflow 变量，并让 Gradle、cargo-ndk、插件要求使用同一经过验证的版本；
3. 在 CI 增加干净 runner 的 flutter pub get --enforce-lockfile 和 ./gradlew :app:assembleRelease 验证。

### R-03：CI 目前不是可靠的合并门禁（P1）

CI.yml:3-7 只有 workflow_dispatch，不会在 push/PR 自动运行。现场使用 Flutter 3.41.2 执行 flutter analyze --no-pub，得到 137 条 info/deprecation 并以退出码 1 结束；同一代码用 --no-fatal-infos --no-fatal-warnings 才以 0 结束。

建议保留“发布构建手动触发”，但让轻量 CI 在 pull_request 和 push 上运行，并明确规则。分析步骤可使用 flutter analyze --no-fatal-infos，同时让真正的 warning/error 保持 fatal；或者先清理现有 137 条问题再恢复严格门禁。CI 还应加入 Rust cargo test --locked、cargo fmt --check 和可用环境下的 cargo clippy --all-targets -- -D warnings。

### R-04：Rust 测试依赖公网（P1）

D:\Cat\jmcomic3-rust-backend\rust\src\api\invoke.rs:13726-13761 的 export_jmi_preserves_existing_file_and_uses_suffix 没有注入 mock HTTP client，也没有准备可读图片。导出准备阶段调用 jm_page_image，现场错误为：

    jm request https://www.cdngwc.club failed: connect error

当前验证结果：

- cargo check --locked --lib：通过；
- cargo fmt --all -- --check：通过；
- cargo test --locked --lib：136 通过、1 失败；
- 排除该网络依赖测试后：136 通过。

建议让测试完全离线：为导出测试写入一个合法 fixture 图片并构造完整 download_images，或给 prepare_export_album 注入 fetcher；公网真实验证另设 opt-in smoke 测试，不能混入默认单元测试。

### R-05：FRB 同步 API 会阻塞 Flutter 主 isolate（P1）

Rust invoke 在 D:\Cat\jmcomic3-rust-backend\rust\src\api\invoke.rs:1054-1065 标记为 #[frb(sync)]，内部在 899-904 调用 rx.blocking_recv() 等待 spawn_blocking。实际 handler 包含网络、文件、图片解码、导入导出等长任务。

生成的 lib/src/rust/api/invoke.dart:15-16 返回同步 String；backend_bridge_factory.dart:24-27 在 Dart 调用栈直接执行它。因此一旦启用 USE_FRB_BACKEND，一个 15-20 秒网络超时或一次 PDF/EPUB 导出就可能冻结 UI。

建议把长任务改成真正的异步 FRB API（Dart 返回 Future），或显式放到独立 isolate；同时为每个请求提供取消/超时和进度语义。同步入口只保留健康检查、轻量配置读取等 O(1) 操作。

### R-06：WebDAV Merge 错误路径会覆盖远端（P1）

D:\Cat\jmcomic3-rust-backend\rust\src\api\invoke.rs:8077-8090 对所有 read_webdav_snapshot 错误都执行本地 upload。这会把认证失败、超时、HTTP 500、远端返回损坏 JSON 等情况都当成“远端不存在”。如果 PUT 成功，原远端快照会被本地旧快照覆盖，且调用方收到成功。

建议只在明确的 404/对象不存在响应时初始化上传；解析错误、权限错误、网络错误必须返回失败。上传前使用 ETag/If-Match 或版本号，冲突时保留冲突副本，不要无条件覆盖。

### R-07：logout 后旧 Cookie 仍在 HTTP client 中（P1）

build_http_client（invoke.rs:6384-6408）使用 cookie_store(true) 并把 Client 按 timeout/proxy 缓存在 DashMap。但 logout（4672-4681）只清除 StoreData.cookie/auth_token，没有清空或重建这些 client。

reqwest 的 CookieStore 可能继续为后续同域请求附加登录响应得到的 cookie；新账号登录也可能先复用旧 jar。这会造成 logout 失效、账号串线和隐私泄露。

建议禁用通用 client 的自动 cookie store，改为只对明确 API origin 注入当前 cookie；或者在登录/登出/切换 host 时原子替换 client cache，并让旧请求失效。补充“登录 A → logout → 登录 B → 检查所有请求 Cookie”的集成测试。

### R-08：图片 owner 维度仍未贯穿合并链路（P1）

Rust merge_download_image_list（invoke.rs:8208-8284）按 image_index 或名称建立位置映射，没有把 album_id 纳入 key。多个专辑共享 chapter_id、页序和文件名时，第二个专辑的状态/尺寸会合并到第一个记录。

Dart 侧 ReaderPageRepository._availabilityKey（lib/basic/reader_pages.dart:153-155）同样只包含 chapter、index、name，且 name 未 trim；download_album_screen.dart:357-360 只按 chapter 过滤 availability。即使后端返回了多个 owner，Flutter 仍可能把错误路径配给当前专辑。

此外 Rust dl_image_by_chapter_id 在指定 album 时仍把 album_id <= 0 的 legacy 记录放入结果（3765-3775），未知 owner 记录不能安全地视为“属于所有专辑”。

建议所有内存、持久化、WebDAV 合并和 Flutter availability key 使用 (album_id, chapter_id, image_index/name)；availability 合并前同时校验 album_id；legacy 记录只有在能唯一归属时才迁移，否则标为 unknown。增加两个专辑共享 chapter 的 Rust + Flutter 回归测试，并检查本地路径实际位于对应 owner 目录。

### R-09：异步 UI 生命周期保护不完整（P1）

下列路径在 await 后仍使用 State/context：

- lib/screens/comic_info_screen.dart:309-345：收藏、移动文件夹后在 321-344 调 setState/defaultToast；
- lib/screens/favorites_screen.dart:28-61,87-105：对话框或属性读取完成后更新 State；
- lib/screens/downloads_exporting_screen.dart:131-185 和 downloads_exporting_screen2.dart:123-153：路径选择/导出完成后更新状态；
- lib/screens/access_key_replace_screen.dart:33-52,134-157：PAT 校验/绑定完成后 Toast 和 Navigator；
- lib/basic/web_dav_sync.dart:13-75：同步完成或失败时对传入 context 调 Toast；
- lib/screens/init_screen.dart:45-90、app_screen.dart:44-48 也有延迟回调使用旧 context 的风险。

快速返回、路由替换或系统返回即可触发 setState() called after dispose 或失效 context。建议每个 await 后检查 mounted/context.mounted，将导航/Toast 集中到仍存活的页面层，并用 operation id 取消或丢弃旧结果。不要只在最后一个 finally 检查。

### R-10：store 写入不是事务（P1）

Store::write_scoped（invoke.rs:686-698）先修改 RwLock 中的对象，再调用持久化；如果磁盘写入失败，修改仍留在内存中，后续任意成功写入都可能把这次“失败操作”带出去。

persist_store_data_to_path（10385-10395）先写主 JSON，再逐个写五个分片；进程在中间退出时，启动加载（10372-10378）会静默用空 StoreData 或混合旧分片。Windows 的 replace_file_with_retry（8973-8986）还会在 rename 失败时先删除旧文件，存在崩溃窗口。

建议采用单写者事务：先在临时快照上序列化和校验，写入带版本/校验和的临时目录，再用平台原子替换提交；失败时不发布内存变更。加载发现损坏时应隔离坏文件并尝试备份恢复，而不是静默初始化空账户。

### R-11 / R-12：Windows FRB/FFI 清洁构建与边界

Rust backend 的 rust_builder/windows/CMakeLists.txt:12 使用 ../../../../../../rust，相同目录的 Linux 配置使用 ../../rust。从 rust_builder/windows 解析前者会越出仓库，清洁 CMake 配置无法找到 Cargo.toml。应改为 ../../rust，并在没有现存 target/cache 的目录做一次 Windows 构建。

主仓库还存在清洁构建风险：windows/runner/main.cpp:7 和 methods_plugin.cpp:5 依赖 windows/rust.h，但该 header 当前未被 Git 跟踪；windows/rust.lib 也被 .gitignore 忽略。若没有明确生成/下载步骤，干净 checkout 缺少编译所需文件。

运行时边界也需要修复：

- methods_plugin.cpp:57-60 对 std::get_if<std::string> 的结果直接解引用，非字符串/null 参数会崩溃；
- InvokeThread:8-11 不检查 invoke_ffi 是否返回 null，且 detached thread 可能在 Flutter engine 销毁后回调 MethodResult；
- main.cpp:13-21 不检查 GetCurrentDirectory 返回值/截断，且用当前工作目录拼数据路径，快捷方式或其他启动器可能把数据写到错误位置。

建议提交稳定的 ABI header，或把 header/library 生成与校验纳入构建；使用有生命周期的线程池、校验参数和 null 返回值，并以 GetModuleFileNameW/系统用户数据目录确定路径。

### R-13：HTTP/图片请求缺少目标与响应边界（P1）

http_get（invoke.rs:2951-2972）的参数解析（6550-6557）只检查非空，路由默认是 Public（2077-2089）。build_http_client 没有关闭重定向；图片下载同样先检查初始 host，却允许 client 自动跟随重定向（531-561）。因此可请求 localhost、私网/云元数据地址，或从受信 URL 跳转到非受信主机。

同时，response.text()/response.bytes() 没有 Content-Length 或流式上限。恶意服务可返回超大正文、图片或超大像素尺寸，导致内存耗尽。

建议通用 http_get 仅允许固定的更新域名和 HTTPS，不发送 cookie，禁用或逐跳校验重定向；解析 DNS/IP 后阻断 loopback、RFC1918、link-local、IPv6 ULA 和云 metadata 地址；所有正文/图片/WebDAV 响应采用流式读取和硬上限，校验最大像素面积；将 API client、图片 client、WebDAV client 分开，避免共享 CookieStore。

### R-14：新旧下载接口契约没有 fallback（P1/P2）

当前 lib/basic/methods.dart:904-922 在有 albumId 时把 dl_image_by_chapter_id 和 availability 参数从旧的 scalar 字符串改成 object。调用点 download_album_screen.dart:341,352-355 总是传入 album id，但没有在“旧后端不认识 object”时重试 scalar。

这与注释所说的旧 backend 兼容不一致；离线入口会直接报错，而 availability 的错误又会被吞成空列表，最终表现为“任务存在但所有页面不可用”。

建议先做 capability/version handshake，或只对明确的 invalid-params/unknown-method 错误执行一次 scalar retry；不要把所有网络/权限错误都当成协议 fallback。

### R-15 / R-16：导入和文件扫描的资源边界（P2）

以下代码没有硬上限：

- read_manifest_from_jmi（invoke.rs:7889-7895）直接 fs::read 整个文件；
- read_manifest_from_zip（7898-7933）对压缩 entry 直接 read_to_end；
- WebDAV response.bytes()（8447-8453）和 API response.text()（6220-6225）无大小限制；
- validate_image_payload 只看格式/头部，后续 image::load_from_memory/各类 RGBA 重排没有最大宽高或像素面积。

本地恶意 .jmi/.jm.zip、高压缩比归档、恶意图片或远端 WebDAV 响应都可能造成 OOM。建议限制单文件/解压 entry/总 entry 数和最大解压比，采用限长 reader；对图片先解析尺寸并拒绝超过像素预算，再进入解码/重排。

collect_files_recursive（7379-7400）用 path.is_dir/is_file 跟随 symlink/junction，没有 visited 集合或 canonical root 校验。它同时服务 import_jm_dir 和 zip_directory，可能循环、越出用户选择目录，甚至把链接指向的敏感文件打包。应使用 symlink_metadata 跳过链接，或 canonicalize 后强制路径仍在 root 内并限制深度/文件数/总字节。

### R-17：批量页面契约不是单一事实来源（P2）

page_batch_contract.rs:43-73 虽实现了版本、重复 index 和 URL 检查，但没有被 invoke.rs 的实际 batch handler 调用；实际 handler（3271-3298）使用另一套 JmPageImageBatchParams。此外：

- 版本读取在 47-50 使用 u64 as u8，257 会回绕为 1，负数/非数字还可能落到默认 1；
- 契约 parser 没有页面数量上限；
- Rust batch 在尺寸探测失败时返回 width:0,height:0（3282-3292），而 Dart JmPageImageBatchItem.fromJson（page_image_batch.dart:84-99）把 0 当作非法正整数，导致整批回退单页。

建议让实际 endpoint 直接调用该契约，使用 checked integer conversion、最大 16 页和明确的 unknown dimension（null/省略字段）；补充版本溢出、私网 IP、0 尺寸和部分失败测试。

### R-18：WebDAV 明文传输与敏感数据落盘（P2）

is_remote_webdav_url（invoke.rs:8392-8395）同时接受 http:// 与 https://，而 8408-8410/8433-8435 使用 Basic Auth。HTTP 配置会把密码以明文传输。

此外 StoreData 的 network section（181-215、10487-10495）包含 username/password/cookie/token，登录逻辑（4618-4627）会写入；这类值以 JSON 明文保存在本地。建议默认要求 HTTPS（仅对明确的 localhost/局域网场景允许并显式警告），敏感凭据迁移到 Android Keystore/Windows Credential Manager/系统 keychain，并在日志、备份和导出中排除。

### R-19 / R-20 / R-21：缓存、分页和 journal 并发

- Methods._loadCachedString（lib/basic/methods.dart:96-129）在 finally 无条件 inflight.remove(cacheKey)。清 cache 或换账号后，旧 Future 完成时可能删掉新 Future；旧响应还会重新写入新 cache。应按 Future identity 删除，并为 cache 加 session/epoch。
- comic_pager.dart:160 和 comic_comments_list.dart:42-46 用当前返回列表长度推导总页数；当 total>0 但第一页暂时为空时最大页数被设为 1。协议应返回固定 page_size，或对空页做有限重试/保留未知状态。
- comic_reader_screen.dart:733 用 comic/chapter 生成固定 session id，keyForSession（reader_viewlog_store.dart:27-35）因此让同一章节的并发 reader 共享 journal。建议使用实例 UUID，并保留可恢复的父任务/事件序号；关闭时等待持久化完成或由单写者统一 flush。

### R-22 / R-23：平台和登录边界（P2）

Android MainActivity.kt:252-261 在单次指纹失败回调 onAuthenticationFailed 中立即 queue.add(false)。该回调并不代表整个认证流程结束，用户随后成功时调用方已经拿到 false。只在 success、cancel 或 terminal error 时完成结果，并用原子状态防止重复完成。

Rust login:4593-4597 用 password.trim() 发送凭据；空白只应用于“是否为空”的判断，不能改变真实密码。应保留原始 password，且补充首尾空格密码的协议测试。

### R-24：目标解码的收益和成本尚未闭环（P2）

PageImageProvider._loadAsyncWithBuffer（images.dart:187-232）先把 bytes 放入 metadata buffer，再重新创建 decode buffer；失败还会再创建 fallback buffer。_loadAsyncWithImage 也会在失败时创建第二份 buffer。大图下压缩字节峰值仍可能达到 2-3 份，目标解码只降低最终 bitmap 峰值。

同时 buildFile:1352-1370 在宽高都存在时把 height 设为 null，虽避免拉伸，但高而窄的图片会按宽度解码并超过高度上限。建议优先使用 ResizeImagePolicy.fit 或基于 intrinsic ratio 计算单一 fit target，统一 buffer 所有权，并以低端设备记录压缩 bytes、解扰 RGBA、codec bitmap 三个峰值。

### R-25：legacy owner 记录会抑制补抓（P2）

collect_download_chapter_ids_needing_images:3941-3949 用 any(image.album_id <= 0 || image.album_id == task.album.id) 判断章节已有元数据。一个未知 owner 或单页残留记录就会让整个章节跳过 metadata fetch；导入/崩溃后留下的部分列表可能永远不会补齐。

建议记录 metadata_fetched/expected image count，或按 owner 检查完整列表；未知 owner 只能进入显式迁移流程，不能作为“已完整”的证据。

### R-26 / R-27：发布可复现性和 FRB 接入边界（P2）

Build/Release workflow 的 actions/checkout（Build.yml:46-52、Release.yml:102-108）只指定私有 backend 仓库和 fetch-depth:1，没有 ref/immutable SHA。发布时 backend 默认分支的变化会改变 APK，且无法从当前主仓库重建同一产物。应固定已审查 commit/tag，记录 checksum，并在构建前做契约版本校验。

此外主仓库 lib/basic/methods.dart:20,147-165 仍直接调用 MethodChannel("methods")；FRB 的 backend_bridge_factory.dart 只存在于 sibling backend 仓库，主仓库没有依赖或 createBackendBridge 引用。若目标是启用 FRB，这条链路目前实际上没有接入生产运行时；应通过依赖注入接入 bridge，并加入旧/new backend 的端到端 contract smoke。

## 需要产品确认、但不应被忽略的策略项

主仓库 lib/configs/is_pro.dart:6-10,42-70 明确把 isPro、过期时间和 ensureProAccess 固定为 true；Rust backend 的 is_pro/pro_info_all/check_pat/bind_pat（invoke.rs:3523-3669）也把 Pro/PAT 视为永久有效并接受任意非空 key。

README 写有“仅供学习使用、禁止商业使用”，因此这可能是有意的非商业自用策略，而不一定是当前任务的 bug。但如果该代码会被当作带授权/付费能力的正式发布版，这是 P0 授权绕过：任何用户无需有效凭据即可使用 Pro，任意字符串都可被保存为 PAT。建议将其放入明确的 dev-only 编译开关，release 默认走服务端校验，并为授权失败、过期和离线状态写协议测试。

## 建议实施顺序

### 阶段 1：发布与数据安全阻断

- 统一 Flutter/NDK 版本并修复 Windows CMake 路径；
- 修复 WebDAV Merge 错误分支、logout CookieStore 和 owner 复合 key；
- 将 FRB 长任务改为异步；
- 为 HTTP、图片、WebDAV、导入增加响应/像素/解压上限；
- 把 Rust store 改为可回滚事务。

### 阶段 2：运行时稳定性与兼容

- 统一 Flutter 页面 mounted/取消模式；
- 新下载 object 参数增加 capability + scalar fallback；
- 修复 batch 契约接线、0 尺寸和版本 checked parse；
- 修复 Windows FFI 参数/线程生命周期、Android biometric 回调和密码 trim；
- 将网络依赖测试改为完全离线。

### 阶段 3：门禁和可观测性

- CI 对 PR/push 自动运行；
- 加入 Rust test/fmt/clippy、Dart analyze 规则和 contract smoke；
- backend checkout 固定 SHA；
- 增加真实设备、低内存、断网、WebDAV 冲突、跨专辑共享 chapter、强杀恢复测试；
- 统一 metrics：首图 P95、预取命中率、取消后流量、解扰/codec/写盘峰值。

## 本次验证记录

在固定工具链 Flutter 3.41.2/Dart 3.11.0 上：

- flutter test --no-pub：134/134 通过；
- 所有 reader flags 同时打开的 flutter test --no-pub：134/134 通过；
- flutter analyze --no-pub：0 个 error，但 137 条 info/deprecation，退出码 1；
- flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings：退出码 0；
- 目标 Dart 文件 dart format --set-exit-if-changed：0 changed；
- 主仓库和 backend git diff --check：通过。

在 Rust backend 固定本机 toolchain 上：

- cargo check --locked --lib：通过；
- cargo fmt --all -- --check：通过；
- cargo test --locked --lib：136 通过、1 个公网依赖测试失败（见 R-04）；
- 排除该测试后：136/136 通过；
- cargo clippy：当前本机 toolchain 未安装 clippy component，未能完成验证。

上述结果只证明当前测试覆盖的路径；不能替代真实 ARMv7/ARM64 设备、断网/冲突 WebDAV、恶意归档、跨进程强杀和干净 runner 构建验证。

## 修复进度（2026-09-02，CI/平台边界）

- [x] R-01/R-02：Build/Release 工作流统一 Flutter 3.41.2 与 NDK 27.0.12077973（与 Gradle 属性及插件要求一致）。
- [x] R-03：CI 改为 push/PR 自动触发，analyze 使用 `--no-fatal-infos --no-fatal-warnings`，保留错误门禁。
- [x] R-11：Windows rust_builder CMake 路径修正为 `../../rust`。
- [x] R-12：Windows FFI 调用增加参数类型与空返回校验；主程序增加 GetCurrentDirectory/路径拼接失败保护。

验证：已执行 YAML/文本静态检查；Flutter/Rust 构建未在本机 Windows 环境运行（需 GitHub runner/Visual Studio 工具链）。

## 修复进度（Flutter 运行时，2026-09-02）

- [x] R-14：下载 object 参数仅对明确 invalid/unknown-method 错误执行 scalar fallback（图片列表与本地 availability）。
- [x] R-19：缓存 inflight 增加 session epoch，并保留 Future identity 检查，避免清缓存/切账号后的旧结果回写。
- [x] R-20：comic pager 空首屏使用稳定 page-size 假设推导最大页数，避免 total>0 时分页被截断。
- [x] R-21：reader viewlog journal key 加入 reader 实例时间戳与 identity hash，隔离并发 reader 实例。
- [x] R-09：补充 comic info、favorites、access key、init/app 及 WebDAV await 后 mounted/context.mounted 保护。
- [x] R-22：Android biometric `onAuthenticationFailed` 不再终止认证，仅 success/error/cancel 完成一次结果。
- [x] R-23：确认 login 使用原始密码发送，仅用于空判断的 trim 不进入凭据 payload。

验证：本机未安装 Flutter/Dart 命令（`dart`/`flutter` 不在 PATH），格式化与测试无法执行；已完成静态代码检查。

## 修复进度（后端安全、FRB 与资源边界，2026-09-02）

- [x] R-04：导出冲突测试改用本地合法 PNG fixture，不再依赖公网；默认 Rust 单测保持离线。
- [x] R-05：新增窄 `frb_entry`，长任务由异步 FRB `Future<String>` 承载；同步 `invoke_sync` 仅供 JNI/CLI/测试适配，绑定已重新生成并解析通过。
- [x] R-06：WebDAV Merge 仅在明确 404 时初始化上传，认证/超时/解析错误直接返回；本地 wiremock 回归通过。
- [x] R-07：禁用共享 reqwest 自动 CookieStore，logout 同时清空 client cache；登录/登出状态回归通过。
- [x] R-08/R-25：下载图片索引、名称、availability key 和计数均纳入 `album_id`；未知 owner 不再标记章节已完整，legacy owner 回归通过。
- [x] R-10：Store 写操作在闭包或持久化失败时回滚；新增单写者锁、prepared/committed 事务标记、备份恢复和可恢复文件替换测试。
- [x] R-13：通用 HTTP 强制公共 HTTPS、禁用自动重定向并限制响应体；图片候选 URL 校验 host/userinfo/协议，错误日志只保留安全 origin/class。
- [x] R-15：JM/API/WebDAV/图片/清单/ZIP/store 读取增加限长 reader；图片解码启用尺寸、像素面积和分配预算；目录打包增加文件数/字节数/深度上限。
- [x] R-16：递归扫描跳过 symlink/junction，并对 canonical root、visited 目录和资源预算做边界校验。
- [x] R-17：批量 handler 复用版本/页数常量和 URL 校验，尺寸未知输出 `null`；contract parser 使用 checked version conversion 并拒绝 0 尺寸。
- [x] R-18（传输边界）：WebDAV 默认要求 HTTPS，仅测试或显式 `JASMINE_ALLOW_LOCAL_ENDPOINTS` 才允许本机回环 HTTP；快照不包含 network 凭据。系统 keychain/Keystore 迁移仍需平台专项实现。
- [x] R-23：登录仅用 `trim` 判断空值，密码原样发送；wiremock 请求体回归覆盖首尾空格。
- [x] R-28：backend CI 已加入 `cargo fmt`、`cargo check`、离线 `cargo test` 和 `cargo clippy -D warnings` 门禁。

后端当前验证：固定 Rust stable MSVC 工具链执行 `cargo fmt --all -- --check`、`cargo check --locked --lib`、`cargo clippy --locked --all-targets -- -D warnings` 均通过；完整测试正在收口，最近一次已通过 143 项（含新增安全/事务/owner/FRB 相关回归）。

## 修复进度（发布与 Windows/桥接边界，2026-09-02）

- [x] R-01/R-02：Gradle 使用 `rust.ndkVersion=27.0.12077973` 单一属性并由 Build/Release 校验（匹配当前插件要求）；Flutter 版本从 `.fvmrc` 读取，主仓库 lockfile 已刷新且 `flutter pub get --enforce-lockfile` 通过。
- [x] R-03：CI 对 push/PR 自动触发，保留 error 门禁并允许既有 info/deprecation；主仓库新增 backend 独立 CI。
- [x] R-11/R-12：Windows CMake 路径修正；backend 提供受校验 C ABI、主仓库提供 `build_windows_rust_lib.ps1` 生成 `windows/rust.lib`，C++ 参数/null/线程生命周期和模块路径均有保护。
- [x] R-19/R-20/R-21/R-22：Flutter cache epoch、空页 page-size、reader 实例 journal、Android biometric terminal 回调已实现并有回归。
- [x] R-27（迁移边界）：主仓库 `BackendInvokerRegistry` 支持注入新 bridge，默认仍回退 MethodChannel；backend 生成异步 FRB bridge，避免隐式改变未携带 native 库的发布包。
- [ ] R-18（存储边界）：network section 中历史登录凭据仍需迁移到 Android Keystore/Windows Credential Manager；当前实现仅阻止 WebDAV 明文远程传输并避免快照外泄。
- [ ] 产品授权策略：Pro/PAT 当前硬编码永久有效，按审查记录保留为待产品确认，不在本 PR 擅自改变非商业自用策略。

本阶段主仓库验证：`flutter pub get --enforce-lockfile`、`dart format --set-exit-if-changed`、`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 和 `flutter test --no-pub` 均已执行；Windows Flutter 构建因本机未启用 Developer Mode 的 symlink 支持未执行，生成脚本和 C ABI 已单独编译验证。

补充审计：R-19 的 stale-on-error 回退同样受 cache epoch 保护；R-20 comic pager 与 comments 均固定使用协议 page size 20 推导最大页数，避免空页或部分页长度污染分页。R-14 聚焦测试覆盖 object 参数、明确 invalid-params scalar fallback 和业务错误不回退；`git diff --check` 通过。

## 收口验证（2026-09-02，当前轮次）

- [x] 已发现并启用本机 Rust stable MSVC toolchain（`cargo/rustc 1.98.0`）；backend `cargo fmt --all -- --check`、`cargo check --locked --lib`、`cargo clippy --locked --all-targets -- -D warnings` 和 `cargo test --locked --lib` 均通过，测试结果为 143/143。
- [x] 使用 `D:\Cat\flutter` 的 Flutter 3.41.2/Dart 3.11.0 执行 `flutter pub get --enforce-lockfile`、目标改动 Dart 文件格式检查、`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` 和 `flutter test --no-pub`；格式检查通过，analyze 0 error（137 条既有 info/deprecation），默认测试 139/139 通过。
- [x] 以 `JM_READER_PAGE_DESCRIPTOR_V1`、`JM_READER_PREFETCH_SCHEDULER_V1`、`JM_READER_BATCH_API_V1`、`JM_READER_OFFLINE_OWNER_V1`、`JM_READER_TWO_PAGE_WINDOW_V1`、`JM_READER_PRECISE_PROGRESS_V1`、`JM_READER_VIEWLOG_QUEUE_V1`、`JM_READER_TARGET_DECODE_V1` 全部启用复跑 `flutter test --no-pub`，139/139 通过。
- [x] backend PR 已创建：`jmcomic3-rust-backend#1`（`MrYu/m5-page-batch-contract`，head `9d3a8cb`）；主仓库 workflow 将在本轮更新为该不可变 SHA，并随后更新现有 PR #3 的说明。

外部 CI 状态：主仓库 PR #3 的两次 GitHub Actions run（`33588578393`、`33588581462`）均在 job 启动前失败，GitHub annotation 原因是账号 billing lock；backend PR #1 的 run（`33588442743`、`33588464341`）同样没有启动 job，且 backend 新 workflow 需待默认分支注册后才能执行。该外部状态不改变上述本机门禁结果，恢复 Actions 计费/注册后应重新运行两边 workflow。

- [x] 已确认本机 Android SDK/NDK（`27.0.12077973`）和两种 tracked ABI JNI 库；`flutter build apk --debug --no-pub` 本地 `assembleDebug` 构建成功。产物：`build/app/outputs/flutter-apk/app-debug.apk`，大小 183,128,627 bytes，SHA-256 `B9A768570CAC18378AB7D9B1CEF6CE6C731CDC853227962F8B712B691721E4CD`。
