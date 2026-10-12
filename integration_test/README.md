# Android 阅读器设备回归

`reader_android_test.dart` 在真实 Android Flutter 引擎上复用
`test/reader_regression_test.dart` 的控件回归。测试覆盖缩放后单指拖动、缩放复原、
正反向连续阅读、图库与奇数双页、快速跳页、可见页进度保存、切章和图片资源释放。
实际数量以本次测试日志为准。

图片与后端响应由确定性夹具提供；设备实际执行手势、布局、帧调度、文件解码和缓存。
此回归无需个人账号，也不代替在线登录、服务器可用性或不同机型验收。
截图直接捕获设备引擎渲染的阅读器 RepaintBoundary，避免调整测试视口后 Android
ImageView 截图等待下一 native 帧而阻塞；截图不包含系统状态栏。

## 前置条件

1. 从仓库根目录加载 `scripts/enter_build_env.ps1` 并运行 `flutter pub get`。
2. 使用 `adb devices` 确认设备在线。默认设备为 `emulator-5556`，本机回归 AVD 为
   `jmcomic3-api35-regression`（Android API 35 / x86_64）。
3. 如需普通模拟器应用，运行 `scripts/build_android_emulator.ps1`，该脚本重建
   x86_64 JNI。集成回归使用自己的测试入口。
4. 同一项目没有其他 Gradle 构建或设备安装任务运行。

```powershell
. .\scripts\enter_build_env.ps1 -SkipVisualStudio
.\scripts\test_reader_android.ps1 -DeviceId emulator-5556
```

脚本构建并安装测试 APK。结束后保留退出阅读器后的进程；继续使用普通应用前应重新
安装普通应用 APK。发布版本在对应 ABI 设备上另行验证安装和签名更新兼容性。

## 输出

脚本的 transcript 和驱动截图保存在 `dist/device-test/`，包括
`reader_android.log`、`reader_exit_memory.txt` 和截图。日志中的 `All tests passed`
及命令退出码是本次结果；同目录历史报告不作为当前测试通过的依据。

退出后的 `dumpsys meminfo` 包含引擎、JNI 和运行时分配，其数值不等于图片缓存容量。
报告、截图及日志按版本归档，避免下次回归覆盖发布证据。
