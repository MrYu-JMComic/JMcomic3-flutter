[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter_build_env.ps1')
$root = $env:JM3_BUILD_ROOT
$crate = Join-Path $root 'rust-backend/rust'
$header = Join-Path $root 'windows/rust.h'

# The runner includes this small C ABI declaration directly.  Keep the header
# reproducible even when a fresh checkout does not contain generated desktop
# artifacts yet.
if (-not (Test-Path -LiteralPath $header -PathType Leaf)) {
  @'
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void init_ffi(const char* path);
char* invoke_ffi(const char* params);
void free_str_ffi(char* ptr);

#ifdef __cplusplus
}
#endif
'@ | Set-Content -LiteralPath $header -Encoding ascii
  Write-Host "Generated Windows Rust header: $header"
}

Push-Location $crate
try {
  & cargo build --locked --lib --release --target x86_64-pc-windows-msvc
  if ($LASTEXITCODE -ne 0) { throw "cargo build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
$targetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $crate 'target' }
$lib = Join-Path $targetDir 'x86_64-pc-windows-msvc/release/rust_lib_jasmine.lib'
if (!(Test-Path $lib)) { throw "Rust static library not found: $lib" }
Copy-Item -LiteralPath $lib -Destination (Join-Path $root 'windows/rust.lib') -Force
Write-Host "Rust Windows library ready: $lib" -ForegroundColor Green
