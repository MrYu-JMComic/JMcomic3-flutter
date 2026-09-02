param(
    [string]$BackendRoot = (Join-Path $PSScriptRoot "..\..\jmcomic3-rust-backend"),
    [string]$Cargo = "cargo",
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$backendRoot = (Resolve-Path $BackendRoot).Path
$manifest = Join-Path $backendRoot "rust\Cargo.toml"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Rust backend manifest not found: $manifest"
}

$targetRoot = if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    Join-Path $backendRoot "rust\target"
} else {
    [System.IO.Path]::GetFullPath($TargetDir)
}

Write-Host "Building Windows Rust static library from $manifest"
& $Cargo build --locked --release --manifest-path $manifest --target-dir $targetRoot
if ($LASTEXITCODE -ne 0) {
    throw "Rust backend build failed with exit code $LASTEXITCODE"
}

$source = Join-Path $targetRoot "release\rust_lib_jasmine.lib"
$destination = Join-Path $repoRoot "windows\rust.lib"
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Rust static library was not produced: $source"
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot "windows\rust.h") -PathType Leaf)) {
    throw "Stable FFI header is missing: $(Join-Path $repoRoot 'windows\rust.h')"
}
Copy-Item -LiteralPath $source -Destination $destination -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
Write-Host "Generated $destination ($hash)"
