[CmdletBinding()]
param(
    [string]$DeviceId = 'emulator-5556'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1') -SkipVisualStudio
$outputRoot = Join-Path $env:JM3_BUILD_ROOT 'dist\device-test'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

# 本命令仅执行 Android 回归，跳过 Windows 插件软链接创建并保留原环境。
$oldWindowsFlag = $env:FLUTTER_WINDOWS
$env:FLUTTER_WINDOWS = 'false'
Start-Transcript -LiteralPath (Join-Path $outputRoot 'reader_android.log') -Force
try {
    # 在已启动的设备上构建真实阅读器测试 APK，输出截图、测试结果和超时截图。
    & flutter drive --debug --no-pub `
        --driver=test_driver/reader_android_driver.dart `
        --target=integration_test/reader_android_test.dart `
        --dart-define=READER_TEST_DEVICE_ID=$DeviceId `
        --device-id=$DeviceId --timeout=240 --keep-app-running `
        --screenshot=$outputRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Android reader regression failed with exit code $LASTEXITCODE"
    }
    # 测试结束保留退出阅读器后的进程，记录 Android 侧实际内存辅助数据。
    & adb -s $DeviceId shell dumpsys meminfo com.jmcomic3.yee |
        Out-File -LiteralPath (Join-Path $outputRoot 'reader_exit_memory.txt') -Encoding utf8
} finally {
    Stop-Transcript
    $env:FLUTTER_WINDOWS = $oldWindowsFlag
}
