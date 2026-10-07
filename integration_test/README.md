# Android 设备回归

`reader_android_test.dart` 在真实 Android Flutter 引擎上执行 19 项确定性测试：

- 6 项收藏分页：接口容量、末页限制和无效容量回退。
- 1 项每周必看：刷新缓存和切换期刊的请求参数。
- 12 项阅读器：双击缩放后的单指移动、缩放复原后的翻页/滚动、动画跳页目标、异高图片定位、双页边界、退出进度、预加载顺序和图片内存释放。

阅读器使用应用缓存目录中生成的 PNG，并模拟 `methods` 通道响应。手势、布局、帧调度、文件解码和缓存都由设备实际执行，接口测试无需账号或网络。此回归验证不包含在线登录和服务器可用性。

## 前置条件

1. 已运行 `flutter pub get`。
2. Android 设备已经启动，并可通过 `adb devices` 看到。
3. 模拟器使用 x86_64，`android/app/src/main/jniLibs/x86_64/librust.so` 已从本次后端源码构建。`scripts/build_android_emulator.ps1` 可生成该 JNI 库和普通应用 APK。
4. 同一项目没有其他 Gradle 构建或设备安装任务正在运行。

项目使用独立回归 AVD `jmcomic3-api35-regression`，默认设备 ID 为 `emulator-5556`。在项目根目录执行：

```powershell
.\scripts\test_reader_android.ps1
```

使用其他设备 ID：

```powershell
.\scripts\test_reader_android.ps1 -DeviceId emulator-5556
```

测试会构建并安装集成测试 APK，结束后保留 `Reader closed` 画面及应用进程。继续在线体验时需重新安装普通应用 APK。

## 输出文件

结果持久保存到 `dist/device-test`：

- `reader_android.log`：完整设备运行日志和成功/失败明细。
- `reader_android_report.json`：设备尺寸、测试结果、动画中间采样、图片缓存计数和预加载顺序。
- `reader_*.png`：设备截图。
- `reader_exit_memory.txt`：退出阅读器后 Android 进程的 `dumpsys meminfo`，作为 Flutter 缓存断言的辅助证据。

脚本还启用 Flutter Driver 超时截图。进程内存包含引擎、JNI 和运行时分配，其数值不能直接等同于图片缓存容量。
