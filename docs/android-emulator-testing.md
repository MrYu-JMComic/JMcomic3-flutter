# Android emulator testing

The repository includes `scripts/setup_android_emulator.ps1` for a repeatable
local APK smoke test. It uses the SDK configured by `android/local.properties`,
installs the Android Emulator and an API 35 Google APIs x86_64 system image if
they are missing, creates `jmcomic3-api35-x86_64`, boots it, and can install a
signed debug APK.

From PowerShell at the repository root:

```powershell
.\scripts\setup_android_emulator.ps1 -BuildDebug
```

To only create and boot the emulator when a debug APK already exists:

```powershell
.\scripts\setup_android_emulator.ps1
```

To test a specific APK:

```powershell
.\scripts\setup_android_emulator.ps1 -ApkPath .\path\to\app-debug.apk
```

The emulator is left running after the smoke test. Its ADB serial is
`emulator-5554` by default. Useful commands are:

```powershell
$adb = 'D:\Cat\jm3\toolchains\android-sdk\platform-tools\adb.exe'
& $adb -s emulator-5554 logcat
& $adb -s emulator-5554 shell am force-stop com.jmcomic3.yee
& $adb -s emulator-5554 shell monkey -p com.jmcomic3.yee 1
```

The APK contains ARM Rust JNI libraries. The selected x86_64 Google APIs image
uses Android NDK translation (`libndk_translation.so`), so the same APK can be
smoke-tested without producing a separate x86 Rust build. Use
`-ForceRecreate` to reset the AVD data, or `-ShutdownAfterTest` to stop an
emulator started by the script.
