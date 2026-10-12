# 构建与测试

当前支持本地发布 Android ARM64 / ARM32 和 Windows x64。命令从仓库根目录运行。

## 固定环境

| 工具 | 当前发布使用的版本 |
| --- | --- |
| Flutter / Dart | 3.41.2 / 3.11.0，见 `.fvmrc` |
| Rust | 1.98.0，MSVC 工具链 |
| Android NDK | 25.2.9519653，与 `android/app/build.gradle` 一致 |
| Java | JDK 21；Android 编译目标为 Java 17 |
| cargo-ndk | 4.1.2 |
| Windows C++ | Visual Studio Build Tools 2022 / MSVC 14.44 |

本机环境脚本从当前仓库位置查找 `_flutter/flutter`、`toolchains/`、`_cache/` 和
`rust-backend/rust`。这些本地目录已忽略；换机器时需要自行准备同版本工具链。
`enter_build_env.ps1` 不是自动安装器。

Rust 后端单独检出到 `rust-backend/`，使用 `ci/backend.commit.txt` 的固定 SHA。
如果已有后端检出，先检查未提交改动，再切换版本；不要覆盖本地修改。

```powershell
git clone https://github.com/MrYu-JMComic/jmcomic3-rust-backend.git rust-backend
git -C rust-backend checkout --detach (Get-Content ci/backend.commit.txt).Trim()
. .\scripts\enter_build_env.ps1
.\scripts\verify_build_env.ps1
flutter pub get --enforce-lockfile
```

后端仓库访问权限由 GitHub 账号决定。Windows 需要 Developer Mode 以创建 Flutter
插件软链接。Android 发布需要已有的 `android/key.properties` 和 keystore；参考
`android/key.properties.example`，密钥和口令不得提交。

## 测试

```powershell
. .\scripts\enter_build_env.ps1
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub --concurrency=1
cargo test --locked --manifest-path .\rust-backend\rust\Cargo.toml -- --test-threads=1
```

分析必须没有 error / warning；现有风格和弃用 info 单独记录。Android 真机或模拟器
回归见 [integration_test/README.md](../integration_test/README.md)。测试使用合成数据，
在线服务和账号功能需要另外验收。

## Android

完整重建 Rust JNI 和两种架构的 APK：

```powershell
.\scripts\build_android.ps1
```

该脚本生成并同步 `librust.so`，随后构建 ABI split APK。已有经验证的 JNI 后，生成
混淆发布 APK 和 AAB：

```powershell
. .\scripts\enter_build_env.ps1
.\scripts\build_android_release_split.ps1
```

可用 `-ApkOnly` 或 `-AabOnly` 选择格式。发布版默认启用 R8、资源压缩、Dart 混淆和
外置调试符号；保留每版符号以还原崩溃堆栈。`-DebugSign` 只用于本地测试安装。

产物在 `build/app/outputs/flutter-apk/` 和 `build/app/outputs/bundle/release/`。
项目与 Gradle 使用默认的 `build/` 目录，发布脚本的 `OutputName` 用于符号归档目录。
每个 APK 只能包含其目标 ABI 的
`librust.so`、`libflutter.so`、`libapp.so`，发布前校验签名和包内版本。
ABI split APK 的实际 versionCode 带架构前缀，不能仅用 `pubspec.yaml` 的 build number
推断；更新时同时比较包内 versionCode。

## Windows

```powershell
.\scripts\build_windows.ps1
```

脚本构建 Rust 静态库、准备 `windows/rust.h` 与 `windows/rust.lib`，再编译 Flutter。
静态库不提交。完整分发 `build/windows/x64/runner/Release/` 中的 EXE、DLL 和 `data`
目录，不可只复制 EXE。

## 已知环境边界

部分 Flutter 插件提示需要更新的 NDK；当前发布仍固定 25.2.9519653，并以 JNI / APK
实测结果为准。升级 NDK 或 Flutter 应放在独立 PR 中，重建 native 依赖后重新验证。
本仓库没有 iOS、macOS、Linux、鸿蒙的平台工程，本次不提供这些平台的构建流程。
