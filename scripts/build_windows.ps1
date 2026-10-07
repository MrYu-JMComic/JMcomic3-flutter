[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1')
Set-Location -LiteralPath $env:JM3_BUILD_ROOT
$outputRoot = Join-Path $env:JM3_BUILD_ROOT 'build\windows'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$env:FLUTTER_BUILD_DIR = $outputRoot
Write-Host "Flutter output: $env:FLUTTER_BUILD_DIR"

& (Join-Path $PSScriptRoot 'build_windows_rust.ps1')
if ($LASTEXITCODE -ne 0) { throw "Rust Windows build failed with exit code $LASTEXITCODE" }
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed with exit code $LASTEXITCODE" }
Write-Host 'Windows package build completed.' -ForegroundColor Green
