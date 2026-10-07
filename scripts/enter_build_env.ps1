[CmdletBinding()]
param(
    [switch]$SkipVisualStudio
)

$ErrorActionPreference = 'Stop'

# Dot-source this file (`. .\scripts\enter_build_env.ps1`) when the
# variables should remain in the calling PowerShell session. Build wrappers in
# this directory dot-source it automatically.
$BuildRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-ExistingDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Add-PathEntries {
    param([Parameter(Mandatory = $true)][string[]]$Entries)
    $current = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $all = @($Entries + $current)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deduped = foreach ($entry in $all) {
        if ($seen.Add($entry)) { $entry }
    }
    $env:Path = $deduped -join ';'
}

$FlutterRoot = Resolve-ExistingDirectory (Join-Path $BuildRoot '_flutter\flutter') 'Flutter SDK'
$AndroidSdk = Resolve-ExistingDirectory (Join-Path $BuildRoot 'toolchains\android-sdk') 'Android SDK'
$AndroidNdk = Resolve-ExistingDirectory (Join-Path $AndroidSdk 'ndk\25.2.9519653') 'Android NDK'
$CargoHome = Resolve-ExistingDirectory (Join-Path $BuildRoot 'toolchains\cargo') 'Cargo home'
$RustupHome = Resolve-ExistingDirectory (Join-Path $BuildRoot 'toolchains\rustup') 'Rustup home'
$VsRoot = Join-Path $BuildRoot 'toolchains\vs2022'
$VsDevCmd = Join-Path $VsRoot 'Common7\Tools\VsDevCmd.bat'
$CMakeBin = Resolve-ExistingDirectory (Join-Path $BuildRoot 'toolchains\cmake\bin') 'CMake'
$NinjaRoot = Resolve-ExistingDirectory (Join-Path $BuildRoot 'toolchains\ninja') 'Ninja'
$PubCache = Join-Path $BuildRoot '_cache\pub-cache'
$GradleHome = Join-Path $BuildRoot '_cache\gradle'
$RustTarget = Join-Path $BuildRoot '_cache\rust-target'
$RustBackend = Resolve-ExistingDirectory (Join-Path $BuildRoot 'rust-backend\rust') 'Rust backend crate'

$JavaCandidates = @(
    'C:\Program Files\Java\jdk-21',
    'C:\Program Files\Java\jdk-17',
    'C:\Program Files\Eclipse Adoptium\jdk-17*'
)
$JavaHome = $null
foreach ($candidate in $JavaCandidates) {
    $matches = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
    if (-not $matches -and $candidate.Contains('*')) {
        $matches = Get-ChildItem -Path $candidate -Directory -ErrorAction SilentlyContinue
    }
    $first = @($matches | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1)
    if ($first) {
        $JavaHome = $first.FullName
        break
    }
}
if (-not $JavaHome) {
    throw 'A JDK 17+ installation was not found. Install JDK 17 or 21 and set JAVA_HOME.'
}

New-Item -ItemType Directory -Force -Path $PubCache, $GradleHome, $RustTarget | Out-Null

$env:JM3_BUILD_ROOT = $BuildRoot
$env:FLUTTER_ROOT = $FlutterRoot
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_NDK_HOME = $AndroidNdk
$env:JAVA_HOME = $JavaHome
$env:CARGO_HOME = $CargoHome
$env:RUSTUP_HOME = $RustupHome
$env:PUB_CACHE = $PubCache
$env:GRADLE_USER_HOME = $GradleHome
$env:CARGO_TARGET_DIR = $RustTarget
$env:RUST_BACKEND_RUST_DIR = $RustBackend
$env:RUST_ANDROID_JNILIBS_SOURCE = (Join-Path $BuildRoot 'build\rust-android-jni')
$env:RUST_ANDROID_SOURCE_LIB_NAME = 'librust_lib_jasmine.so'
# The Windows Schannel revocation endpoint is unavailable in some networks;
# Cargo otherwise fails before it can reach crates.io. Rustup and all package
# archives remain HTTPS and are hash-checked by their installers/downloaders.
$env:CARGO_HTTP_CHECK_REVOKE = 'false'
$env:CARGO_NET_GIT_FETCH_WITH_CLI = 'true'

if (-not $SkipVisualStudio) {
    if (-not (Test-Path -LiteralPath $VsDevCmd -PathType Leaf)) {
        throw "Visual Studio developer command file not found: $VsDevCmd"
    }
    # VsDevCmd sets INCLUDE/LIB/PATH for the MSVC linker and Windows SDK. It
    # runs in a child cmd.exe, so import the resulting `set` output here.
    $envDump = & cmd.exe /d /s /c "`"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "VsDevCmd failed with exit code $LASTEXITCODE"
    }
    foreach ($line in $envDump) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

$MsvcBin = $null
if (-not $SkipVisualStudio) {
    if ($env:VCToolsInstallDir) {
        $MsvcBin = Join-Path $env:VCToolsInstallDir 'bin\Hostx64\x64'
    } else {
        $MsvcBin = Get-ChildItem (Join-Path $VsRoot 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($MsvcBin) { $MsvcBin = Join-Path $MsvcBin 'bin\Hostx64\x64' }
    }
    if (-not $MsvcBin -or -not (Test-Path -LiteralPath (Join-Path $MsvcBin 'link.exe') -PathType Leaf)) {
        throw "MSVC linker was not found under $VsRoot"
    }
    $env:JM3_MSVC_BIN = $MsvcBin
}

$pathEntries = @(
    (Join-Path $FlutterRoot 'bin'),
    (Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin'),
    (Join-Path $CargoHome 'bin'),
    (Join-Path $JavaHome 'bin'),
    $CMakeBin,
    $NinjaRoot,
    (Join-Path $AndroidSdk 'platform-tools'),
    (Join-Path $AndroidSdk 'cmdline-tools\latest\bin'),
    (Join-Path $AndroidSdk 'build-tools\30.0.2'),
    (Join-Path $AndroidSdk 'build-tools\28.0.3')
)
if ($MsvcBin) { $pathEntries += $MsvcBin }
Add-PathEntries $pathEntries

Set-Location -LiteralPath $BuildRoot
Write-Host "JM3 build environment loaded: $BuildRoot"
Write-Host "  Flutter: $FlutterRoot"
Write-Host "  Rust:    $CargoHome (target $RustTarget)"
Write-Host "  Android: $AndroidSdk (NDK 25.2.9519653)"
Write-Host "  Java:    $JavaHome"
if (-not $SkipVisualStudio) {
    Write-Host "  MSVC:    $VsRoot ($MsvcBin)"
}
