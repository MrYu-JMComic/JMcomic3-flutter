# JMcomic3 本地打包环境

环境根目录：`D:\Cat\jm3`

已配置的工具链（均位于目标目录，系统 JDK 除外）：

- Flutter 3.41.2（Dart 3.11.0）：`_flutter\flutter`
- Rust stable 1.98.0（MSVC，含 rustfmt）：`toolchains\rustup` / `toolchains\cargo`
- `cargo-ndk` 4.1.2、`flutter_rust_bridge_codegen` 2.11.1
- Android command-line tools、platform-tools、SDK 32/35/36、Build Tools 28.0.3/30.0.2/35.0.0、NDK 25.2.9519653：`toolchains\android-sdk`
- Visual Studio Build Tools 2022 C++（MSVC 14.44.35207）：`toolchains\vs2022`
- CMake 4.4.3、Ninja 1.13.2：`toolchains\cmake`、`toolchains\ninja`
- Java 21：`C:\Program Files\Java\jdk-21`

Windows 端所需的 Rust C ABI 头文件和静态库会由脚本自动生成：
`windows\rust.h`、`windows\rust.lib`。静态库不提交到仓库，换机器或清理后
重新运行 Windows 构建脚本即可恢复。

## 使用

在 PowerShell 中进入项目后先加载环境（点源后变量会留在当前窗口）：

```powershell
Set-Location D:\Cat\jm3
. .\scripts\enter_build_env.ps1
.\scripts\verify_build_env.ps1
```

构建 Android（默认同时生成 arm64-v8a 与 armeabi-v7a 的 Rust JNI 库及 APK）：

```powershell
.\scripts\build_android.ps1
```

只构建一个 ABI，或构建 AAB：

```powershell
.\scripts\build_android.ps1 -Abi arm64-v8a
.\scripts\build_android.ps1 -AppBundle
```

构建 Windows：

```powershell
.\scripts\build_windows.ps1
```

Windows 产物目录为 `build\windows\x64\runner\Release`（请连同同目录的 DLL
和 `data` 目录一起分发），入口文件是其中的 `jmcomic3.exe`。目标机器若未安装
MSVC 运行库，还需要安装对应的 Visual C++ Redistributable。

已验证的 Android release 产物位于 `build\app\outputs\flutter-apk`：

- `app-arm64-v8a-release.apk`（arm64-v8a）
- `app-armeabi-v7a-release.apk`（armeabi-v7a）

`build_android.ps1` 默认只构建这两个与 Rust JNI 对应的 ABI，不会额外生成没有
Rust 库的 x86/x86_64 APK。

Rust 后端单元测试：

```powershell
. .\scripts\enter_build_env.ps1
cargo test --manifest-path .\rust-backend\rust\Cargo.toml
```

首次安装已接受 Android SDK 许可证，并启用了当前用户的 Windows Developer
Mode（Flutter 插件需要创建符号链接）。如果系统策略要求重启，请重启后重新
打开 PowerShell 并再次点源环境脚本。若看到 Rustup 的默认安装提示，本环境已
有 `D:\Cat\jm3\toolchains\rustup`，可选择 `3` 取消，避免重复安装到
`C:\Users\34214`。

发布签名仍需要用户自己的 `android\key.properties` 和 keystore；没有签名配置
时不要直接分发构建输出。需要可在设备上测试安装的包时，使用：

```powershell
. .\scripts\enter_build_env.ps1
.\scripts\build_android_release_split.ps1 -ApkOnly -DebugSign
```

`-DebugSign` 使用本机 Android debug keystore，仅适合测试安装；如果设备上已有
相同包名但由正式 keystore 签名的旧版本，需要先卸载旧版本。正式发布仍必须配置
自己的 `android\key.properties` 和 keystore，不能用 debug 签名替代。

## Android 模拟器验证

使用独立的 `jmcomic3-api35-regression` AVD，复用本机 API 35 / Google APIs /
x86_64 镜像，通过 Windows Hypervisor Platform（WHPX）加速；设备配置为 2 GiB
数据分区、2 GiB 内存和 2 核。可在 Android Studio 的 Device
Manager 中启动该 AVD；也可在加载构建环境后隐藏启动：

```powershell
Start-Process -FilePath "$env:ANDROID_SDK_ROOT\emulator\emulator.exe" `
  -WindowStyle Hidden -ArgumentList @('-avd', 'jmcomic3-api35-regression',
  '-port', '5556', '-no-window', '-no-audio', '-no-snapshot',
  '-no-boot-anim', '-memory', '2048', '-cores', '2', '-gpu', 'swiftshader')
adb -s emulator-5556 wait-for-device
adb -s emulator-5556 shell getprop sys.boot_completed
```

已有模拟器正在运行时直接复用。确认 `sys.boot_completed` 输出 `1` 后，构建并安装
普通应用 APK：

```powershell
.\scripts\build_android_emulator.ps1
adb -s emulator-5556 install -r .\dist\device-test\jmcomic3-x86_64-debug.apk
adb -s emulator-5556 shell am start -n com.jmcomic3.yee/com.jmcomic3.yee.MainActivity
```

该脚本使用普通应用 `lib/main.dart` 入口，生成 **x86_64 Debug APK**；其中的
Rust JNI 使用独立后端仓库 `..\jmcomic3-rust-backend\rust` 当前源码以 **Release**
配置编译。普通 APK、`build-info.json` 和 `android-emulator-build.log` 归档到
`dist\device-test`，来源记录包含全部 Rust 源文件、依赖文件和工具链版本。

阅读器设备回归在普通 APK 构建完成后执行，首次运行先解析依赖：

```powershell
$env:FLUTTER_WINDOWS = 'false'
flutter pub get
.\scripts\test_reader_android.ps1 -DeviceId emulator-5556
```

设备回归使用 `integration_test/reader_android_test.dart` 专用入口，运行真实阅读器
控件和图片解码，通过 mock MethodChannel 后端返回固定章节及本地生成的测试图片，
以确定性数据验证手势、进度、图片顺序和缓存释放；在线 API 登录和域名连通性由
普通应用另行验证。测试日志、JSON 报告及截图保存在 `dist\device-test`。回归会安装
专用测试 APK，恢复普通应用时重新执行上面的 `adb install` 和启动命令。
