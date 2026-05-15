param(
    [string[]]$Abi = @("arm64-v8a", "armeabi-v7a"),
    [switch]$ApkOnly,
    [switch]$AabOnly,
    [switch]$NoPubGet,
    [string]$SplitDebugInfoDir = "build/symbols/android",
    [switch]$Obfuscate,
    [switch]$NoObfuscate
)

$ErrorActionPreference = "Stop"

if ($ApkOnly -and $AabOnly) {
    throw "-ApkOnly and -AabOnly cannot be used together."
}

if ($Obfuscate -and $NoObfuscate) {
    throw "-Obfuscate and -NoObfuscate cannot be used together."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$jniRoot = Join-Path $repoRoot "android/app/src/main/jniLibs"

$normalizedAbi = @()
$targetPlatformList = @()
foreach ($item in $Abi) {
    $abi = $item.Trim()
    if ([string]::IsNullOrWhiteSpace($abi)) {
        continue
    }
    $targetPlatform = switch ($abi) {
        "armeabi-v7a" { "android-arm"; break }
        "arm64-v8a" { "android-arm64"; break }
        default { $null }
    }
    if ([string]::IsNullOrWhiteSpace($targetPlatform)) {
        throw "Unsupported ABI: '$abi'. Supported values: arm64-v8a, armeabi-v7a"
    }
    if ($normalizedAbi -contains $abi) {
        continue
    }
    $normalizedAbi += $abi
    $targetPlatformList += $targetPlatform
}

if ($normalizedAbi.Count -eq 0) {
    throw "At least one ABI is required."
}

foreach ($abi in $normalizedAbi) {
    $soPath = Join-Path $jniRoot "$abi/librust.so"
    if (-not (Test-Path -LiteralPath $soPath -PathType Leaf)) {
        throw "Missing Rust so: $soPath`nRun scripts/build_android_rust_jnilibs.sh or scripts/sync_android_jnilibs.ps1 first."
    }
}

$targetPlatforms = $targetPlatformList -join ","
$sizeArgs = @()
if (-not [string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
    $sizeArgs += "--split-debug-info=$SplitDebugInfoDir"
}
$shouldObfuscate = -not $NoObfuscate
if ($Obfuscate) {
    $shouldObfuscate = $true
}
if ($shouldObfuscate) {
    if ([string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
        throw "Dart obfuscation requires -SplitDebugInfoDir so symbols can be archived separately."
    }
    # 默认混淆 Dart AOT 名称，进一步缩小 libapp.so；符号目录必须随版本保存用于崩溃还原。
    $sizeArgs += "--obfuscate"
}

Push-Location $repoRoot
try {
    if (-not $NoPubGet) {
        flutter pub get
    }

    # Split APK per ABI to reduce single-package size.
    if (-not $AabOnly) {
        flutter build apk --release --target-platform $targetPlatforms --split-per-abi @sizeArgs
    }

    # AAB for app store distribution.
    if (-not $ApkOnly) {
        flutter build appbundle --release --target-platform $targetPlatforms @sizeArgs
    }
}
finally {
    Pop-Location
}

Write-Host "Done. ABI: $($normalizedAbi -join ', '), target-platform: $targetPlatforms"
if (-not [string]::IsNullOrWhiteSpace($SplitDebugInfoDir)) {
    Write-Host "Dart debug symbols: $SplitDebugInfoDir"
}
Write-Host "Dart obfuscation: $shouldObfuscate"
