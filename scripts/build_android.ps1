[CmdletBinding()]
param(
    [ValidateSet('both', 'arm64-v8a', 'armeabi-v7a')]
    [string]$Abi = 'both',
    [switch]$SkipRust,
    [switch]$AppBundle,
    [string]$OutputName = 'android'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1')
Set-Location -LiteralPath $env:JM3_BUILD_ROOT
$outputRoot = Join-Path $env:JM3_BUILD_ROOT (Join-Path 'build' $OutputName)
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$env:FLUTTER_BUILD_DIR = $outputRoot
Write-Host "Flutter output: $env:FLUTTER_BUILD_DIR"

if (-not $SkipRust) {
    $bashCandidates = @(
        (Join-Path ${env:ProgramFiles} 'Git\usr\bin\bash.exe'),
        (Join-Path ${env:LocalAppData} 'Programs\Git\usr\bin\bash.exe')
    )
    $bash = $bashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $bash) {
        $bashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue
        if ($bashCommand) { $bash = $bashCommand.Source }
    }
    if (-not $bash) { throw 'Git Bash (bash.exe) is required to run build_android_rust_jnilibs.sh.' }

    # Git Bash needs POSIX paths for variables consumed by the shell script.
    $posixRoot = '/' + $env:JM3_BUILD_ROOT.Substring(0, 1).ToLowerInvariant() + ($env:JM3_BUILD_ROOT.Substring(2) -replace '\\', '/')
    $posixMsvc = '/' + $env:JM3_MSVC_BIN.Substring(0, 1).ToLowerInvariant() + ($env:JM3_MSVC_BIN.Substring(2) -replace '\\', '/')
    $abiValue = if ($Abi -eq 'both') { 'arm64-v8a armeabi-v7a' } else { $Abi }
    # Git Bash places /usr/bin before inherited Windows PATH entries and has a
    # GNU `link.exe` shim. Put the MSVC linker first and also pin Cargo's host
    # linker explicitly so Rust build scripts do not accidentally use the shim.
    $bashCommandLine = "cd '${posixRoot}' && export PATH='${posixMsvc}:${posixRoot}/toolchains/cargo/bin:${posixRoot}/toolchains/cmake/bin:${posixRoot}/toolchains/ninja:/usr/bin:/bin' CARGO_HOME='${posixRoot}/toolchains/cargo' RUSTUP_HOME='${posixRoot}/toolchains/rustup' RUST_BACKEND_RUST_DIR='${posixRoot}/rust-backend/rust' ANDROID_NDK_HOME='${posixRoot}/toolchains/android-sdk/ndk/25.2.9519653' RUST_ANDROID_JNILIBS_SOURCE='${posixRoot}/build/rust-android-jni' CARGO_TARGET_DIR='${posixRoot}/_cache/rust-target' CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER='${posixMsvc}/link.exe' RUST_ANDROID_ABIS='${abiValue}' && bash scripts/build_android_rust_jnilibs.sh"
    Write-Host "Building Rust JNI libraries ($abiValue)..."
    & $bash -lc $bashCommandLine
    if ($LASTEXITCODE -ne 0) { throw "Rust Android build failed with exit code $LASTEXITCODE" }
}

& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }

$targetPlatforms = switch ($Abi) {
    'arm64-v8a' { 'android-arm64' }
    'armeabi-v7a' { 'android-arm' }
    default { 'android-arm,android-arm64' }
}

if ($AppBundle) {
    & flutter build appbundle --release --target-platform $targetPlatforms
} else {
    # Keep the APK set aligned with the Rust JNI libraries we build above.
    # Omitting --target-platform would also emit x86_64/x86 APKs, which do not
    # contain a matching Rust library in this project.
    & flutter build apk --release --target-platform $targetPlatforms --split-per-abi
}
if ($LASTEXITCODE -ne 0) { throw "Flutter Android build failed with exit code $LASTEXITCODE" }
Write-Host 'Android package build completed.' -ForegroundColor Green
