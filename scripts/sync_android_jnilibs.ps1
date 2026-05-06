param(
    [string]$Source = "build/rust-android-jni",
    [string]$TargetDir = "",
    [string]$SourceLibName = "librust_lib_jasmine.so",
    [string]$DestLibName = "librust.so",
    [string[]]$Abi = @("arm64-v8a", "armeabi-v7a"),
    [switch]$ValidateOnly,
    [switch]$SkipGitSetCheck
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$destRoot = Join-Path $repoRoot "android/app/src/main/jniLibs"

$abiMetadata = @{
    "arm64-v8a"   = @{ CargoTarget = "aarch64-linux-android"; ElfClass = 2; Machine = 183 }
    "armeabi-v7a" = @{ CargoTarget = "armv7-linux-androideabi"; ElfClass = 1; Machine = 40 }
    "x86"         = @{ CargoTarget = "i686-linux-android"; ElfClass = 1; Machine = 3 }
    "x86_64"      = @{ CargoTarget = "x86_64-linux-android"; ElfClass = 2; Machine = 62 }
}

function Resolve-RepoPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $repoRoot $Path)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-ElfInfo([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Android Rust JNI lib is missing: $Path"
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 20) {
            throw "Android Rust JNI lib is too small to be an ELF shared object: $Path"
        }
        $header = New-Object byte[] 20
        $read = $stream.Read($header, 0, $header.Length)
        if ($read -lt $header.Length) {
            throw "Failed to read ELF header from $Path"
        }
    } finally {
        $stream.Dispose()
    }

    if ($header[0] -ne 0x7f -or $header[1] -ne 0x45 -or $header[2] -ne 0x4c -or $header[3] -ne 0x46) {
        throw "Android Rust JNI lib is not an ELF file: $Path"
    }
    if ($header[5] -ne 1) {
        throw "Only little-endian Android ELF libs are supported: $Path"
    }

    return @{
        ElfClass = [int]$header[4]
        Machine = ([int]$header[18]) -bor (([int]$header[19]) -shl 8)
    }
}

function Test-ElfForAbi([string]$AbiName, [string]$Path) {
    if (-not $abiMetadata.ContainsKey($AbiName)) {
        throw "No ELF validation metadata configured for Android ABI '$AbiName'"
    }

    $info = Get-ElfInfo $Path
    $expected = $abiMetadata[$AbiName]
    if ($info.ElfClass -ne $expected.ElfClass -or $info.Machine -ne $expected.Machine) {
        throw "Android Rust JNI lib ABI mismatch for $AbiName`: $Path (ELF class=$($info.ElfClass), machine=$($info.Machine); expected class=$($expected.ElfClass), machine=$($expected.Machine))"
    }
}

function Get-SourceCandidates([string]$AbiName) {
    $metadata = $abiMetadata[$AbiName]
    $names = @($SourceLibName, $DestLibName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $candidates = New-Object System.Collections.Generic.List[string]

    $sourceRoot = Resolve-RepoPath $Source
    if ($sourceRoot) {
        foreach ($name in $names) {
            $candidates.Add((Join-Path (Join-Path $sourceRoot $AbiName) $name))
        }
    }

    $targetRoots = New-Object System.Collections.Generic.List[string]
    $resolvedTarget = Resolve-RepoPath $TargetDir
    if ($resolvedTarget) {
        $targetRoots.Add($resolvedTarget)
    }
    $targetRoots.Add((Join-Path $repoRoot "rust-backend/rust/target"))
    $targetRoots.Add((Join-Path $repoRoot "rust/target"))
    $targetRoots.Add((Join-Path $repoRoot "target"))

    foreach ($root in ($targetRoots | Select-Object -Unique)) {
        foreach ($name in $names) {
            $candidates.Add((Join-Path (Join-Path (Join-Path $root $metadata.CargoTarget) "release") $name))
        }
    }

    return $candidates | Select-Object -Unique
}

function Test-GitAbiChangeSet {
    if ($SkipGitSetCheck -or $env:RUST_ALLOW_PARTIAL_JNILIB_CHANGE -eq "true") {
        return
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return
    }

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($abiName in $Abi) {
        $path = "android/app/src/main/jniLibs/$abiName/$DestLibName"
        $status = & git -C $repoRoot status --porcelain --untracked-files=no -- $path
        if ($LASTEXITCODE -ne 0) {
            return
        }
        if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
            $changed.Add($abiName)
        }
    }

    if ($changed.Count -ne 0 -and $changed.Count -ne $Abi.Count) {
        $missing = $Abi | Where-Object { $changed -notcontains $_ }
        throw "Partial Android Rust JNI update detected. Changed ABI(s): $($changed -join ', '); missing ABI(s): $($missing -join ', '). Run this script without -ValidateOnly after rebuilding every tracked ABI."
    }
}

if (-not $ValidateOnly) {
    $resolvedSources = @{}
    foreach ($abiName in $Abi) {
        $sourcePath = Get-SourceCandidates $abiName | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $sourcePath) {
            $looked = (Get-SourceCandidates $abiName | ForEach-Object { "  - $_" }) -join "`n"
            throw "Missing Android Rust JNI source for $abiName. Looked for:`n$looked"
        }
        Test-ElfForAbi $abiName $sourcePath
        $resolvedSources[$abiName] = $sourcePath
    }

    foreach ($abiName in $Abi) {
        $sourcePath = $resolvedSources[$abiName]
        $destDir = Join-Path $destRoot $abiName
        $destPath = Join-Path $destDir $DestLibName
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        $sourceFullPath = (Resolve-Path -LiteralPath $sourcePath).Path
        $destFullPath = if (Test-Path -LiteralPath $destPath -PathType Leaf) {
            (Resolve-Path -LiteralPath $destPath).Path
        } else {
            [System.IO.Path]::GetFullPath($destPath)
        }
        if ($sourceFullPath -ne $destFullPath) {
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
        }
        $stalePath = Join-Path $destDir $SourceLibName
        if ($SourceLibName -ne $DestLibName -and (Test-Path -LiteralPath $stalePath -PathType Leaf)) {
            Remove-Item -LiteralPath $stalePath -Force
        }
        if ((Get-Sha256 $sourcePath) -ne (Get-Sha256 $destPath)) {
            throw "Hash mismatch after copying $abiName`: $sourcePath -> $destPath"
        }
        Test-ElfForAbi $abiName $destPath
        Write-Host "Synced $abiName`: $sourcePath -> $destPath"
    }
}

foreach ($abiName in $Abi) {
    Test-ElfForAbi $abiName (Join-Path (Join-Path $destRoot $abiName) $DestLibName)
}
Test-GitAbiChangeSet
Write-Host "Android Rust JNI libs verified for ABI set: $($Abi -join ', ')"
