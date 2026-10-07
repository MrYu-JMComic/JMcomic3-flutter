[CmdletBinding()]
param(
    [string]$RustBackendDir = '',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$OutputName = 'android-emulator'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1')

# 默认使用独立仓库中的当前后端源码，允许调用方显式指定其他源码目录。
if ([string]::IsNullOrWhiteSpace($RustBackendDir)) {
    $RustBackendDir = Join-Path $env:JM3_BUILD_ROOT '..\jmcomic3-rust-backend\rust'
}
$rustCrate = (Resolve-Path -LiteralPath $RustBackendDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $rustCrate 'Cargo.toml') -PathType Leaf)) {
    throw "Rust crate manifest not found: $rustCrate"
}
# 只允许 build 目录下的单级输出名，创建文件前再次确认规范路径没有越界。
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $env:JM3_BUILD_ROOT 'build'))
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $buildRoot $OutputName))
if (-not $outputRoot.StartsWith(($buildRoot + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The emulator output directory must be inside the build directory: $outputRoot"
}
$jniOutputRoot = Join-Path $outputRoot 'jni'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$artifactRoot = Join-Path $env:JM3_BUILD_ROOT 'dist\device-test'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

function Get-RustSourceHashes([string]$CrateRoot) {
    # 记录所有 Rust 源文件及依赖锁定信息，避免只检查入口文件遗漏其他编译模块。
    $sourcePaths = @('Cargo.toml', 'Cargo.lock')
    $sourcePaths += @(Get-ChildItem -LiteralPath (Join-Path $CrateRoot 'src') -Recurse -File -Filter '*.rs' |
        ForEach-Object { $_.FullName.Substring($CrateRoot.Length + 1).Replace('\', '/') })
    if (Test-Path -LiteralPath (Join-Path $CrateRoot 'build.rs') -PathType Leaf) {
        $sourcePaths += 'build.rs'
    }
    $hashes = [ordered]@{}
    foreach ($source in ($sourcePaths | Sort-Object)) {
        $hashes[$source] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $CrateRoot $source)).Hash
    }
    return $hashes
}

# 构建日志直接保存在归档目录，清理 Flutter build 缓存后仍能复查来源和失败原因。
Start-Transcript -LiteralPath (Join-Path $artifactRoot 'android-emulator-build.log') -Force
try {

# 模拟器只更新 x86_64 JNI 库；记录现有 ARM 发布库哈希，构建后验证没有被改写。
$armHashes = @{}
foreach ($abi in @('arm64-v8a', 'armeabi-v7a')) {
    $armPath = Join-Path $env:JM3_BUILD_ROOT "android\app\src\main\jniLibs\$abi\librust.so"
    $armHashes[$armPath] = (Get-FileHash -Algorithm SHA256 -LiteralPath $armPath).Hash
}
$sourceHashes = Get-RustSourceHashes $rustCrate
$ndkRevision = ((Get-Content -LiteralPath (Join-Path $env:ANDROID_NDK_HOME 'source.properties') |
    Where-Object { $_ -match '^Pkg\.Revision\s*=' }) -split '=', 2)[1].Trim()
$toolchains = [ordered]@{
    rustc = ((& rustc --version --verbose) -join "`n")
    cargo = ((& cargo --version) -join "`n")
    cargo_ndk = ((& cargo ndk --version) -join "`n")
    android_ndk = $ndkRevision
    flutter = (& flutter --version --machine | ConvertFrom-Json)
}

# x86_64 Android 标准库属于 Rust 工具链；不依赖模拟器中的 ARM 翻译层。
$installedTargets = & rustup target list --installed
if ($LASTEXITCODE -ne 0) { throw 'Could not read installed Rust targets.' }
if ($installedTargets -notcontains 'x86_64-linux-android') {
    & rustup target add x86_64-linux-android
    if ($LASTEXITCODE -ne 0) { throw 'Installing the x86_64 Android Rust target failed.' }
}
Push-Location -LiteralPath $rustCrate
try {
    & cargo ndk -t x86_64 -o $jniOutputRoot build --release --locked --lib
    if ($LASTEXITCODE -ne 0) { throw "Rust x86_64 JNI build failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}
$finalSourceHashes = Get-RustSourceHashes $rustCrate
if (($sourceHashes | ConvertTo-Json -Compress) -ne ($finalSourceHashes | ConvertTo-Json -Compress)) {
    throw 'Rust sources changed during the build; rebuild from a stable source snapshot.'
}
& (Join-Path $PSScriptRoot 'sync_android_jnilibs.ps1') -Source $jniOutputRoot -Abi @('x86_64') -SkipGitSetCheck

# 按架构拆分 Debug APK，确保模拟器安装的是完整的原生 x86_64 应用。
Set-Location -LiteralPath $env:JM3_BUILD_ROOT
$oldWindowsFlag = $env:FLUTTER_WINDOWS
$env:FLUTTER_WINDOWS = 'false'
try {
    # 本次只构建 Android，跳过 Windows 插件软链接处理并恢复调用方环境。
    & flutter build apk --debug --target-platform android-x64 --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "Flutter emulator APK build failed: $LASTEXITCODE" }
} finally {
    $env:FLUTTER_WINDOWS = $oldWindowsFlag
}
$builtApk = Join-Path $env:JM3_BUILD_ROOT 'build\app\outputs\flutter-apk\app-x86_64-debug.apk'
$apkPath = Join-Path $outputRoot 'jmcomic3-x86_64-debug.apk'
Copy-Item -LiteralPath $builtApk -Destination $apkPath -Force

# 分别核验 Gradle 输入和去符号产物，防止旧库混入并兼容正常的打包符号处理。
$jniPath = Join-Path $env:JM3_BUILD_ROOT 'android\app\src\main\jniLibs\x86_64\librust.so'
$jniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $jniPath).Hash
$mergedJniPath = Join-Path $env:JM3_BUILD_ROOT 'build\app\intermediates\merged_native_libs\debug\mergeDebugNativeLibs\out\lib\x86_64\librust.so'
$strippedJniPath = Join-Path $env:JM3_BUILD_ROOT 'build\app\intermediates\stripped_native_libs\debug\stripDebugDebugSymbols\out\lib\x86_64\librust.so'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $mergedJniPath).Hash -ne $jniHash) {
    throw 'The Gradle merged Rust JNI library does not match the freshly built library.'
}
$strippedJniHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $strippedJniPath).Hash
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $rustEntry = $archive.GetEntry('lib/x86_64/librust.so')
    if ($null -eq $rustEntry) { throw 'The APK has no x86_64 Rust JNI library.' }
    $unexpectedAbi = $archive.Entries | Where-Object { $_.FullName -match '^lib/(?!x86_64/)[^/]+/' }
    if ($unexpectedAbi) { throw 'The emulator APK contains native libraries for an unexpected ABI.' }
    $rustStream = $rustEntry.Open()
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $packagedHash = [System.BitConverter]::ToString($hasher.ComputeHash($rustStream)).Replace('-', '')
    } finally {
        $hasher.Dispose()
        $rustStream.Dispose()
    }
    if ($packagedHash -ne $strippedJniHash) { throw 'The APK Rust JNI library does not match the Gradle packaging output.' }
} finally {
    $archive.Dispose()
}
foreach ($armPath in $armHashes.Keys) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $armPath).Hash -ne $armHashes[$armPath]) {
        throw "An ARM release JNI library changed during the emulator build: $armPath"
    }
}

# 普通应用 APK 归档到 dist，避免 Flutter 清理缓存或设备测试重构建时覆盖。
$archivedApk = Join-Path $artifactRoot 'jmcomic3-x86_64-debug.apk'
Copy-Item -LiteralPath $apkPath -Destination $archivedApk -Force
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archivedApk).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash) {
    throw 'The archived emulator APK does not match the verified build output.'
}

# 生成构建来源记录，便于实机测试核对 APK、JNI 库和 Rust 源码属于同一次构建。
$buildInfo = [ordered]@{
    built_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    abi = 'x86_64'
    flutter_mode = 'debug'
    rust_profile = 'release'
    rust_crate = $rustCrate
    rust_source_sha256 = $sourceHashes
    toolchains = $toolchains
    rust_jni_sha256 = $jniHash
    packaged_rust_jni_sha256 = $packagedHash
    apk_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $apkPath).Hash
    apk = $archivedApk
}
$buildInfoJson = $buildInfo | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText((Join-Path $outputRoot 'build-info.json'), $buildInfoJson)
[System.IO.File]::WriteAllText((Join-Path $artifactRoot 'build-info.json'), $buildInfoJson)
Write-Host "Emulator APK: $archivedApk"
Write-Host "Rust JNI SHA256: $jniHash"
} finally {
    Stop-Transcript
}
