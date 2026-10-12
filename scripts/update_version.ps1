param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

$raw = $Version.Trim()
if ($raw.StartsWith('v')) {
  $raw = $raw.Substring(1)
}
if ($raw -notmatch '^\d+\.\d+\.\d+\+[1-9]\d*$') {
  throw "Invalid version format. Expected like 1.7.26+55 or v1.7.26+55"
}

$pubVersion = $raw
$txtVersion = "v$raw"

function Replace-Line($path, $pattern, $replacement) {
  $path = Join-Path $repoRoot $path
  if (-not (Test-Path $path)) { return $false }
  $content = Get-Content $path -Raw
  $updated = [regex]::Replace($content, $pattern, $replacement, 'Multiline')
  if ($updated -ne $content) {
    [System.IO.File]::WriteAllText($path, $updated, $utf8)
    return $true
  }
  return $false
}

# pubspec.yaml
Replace-Line "pubspec.yaml" '^version:\s*.*$' "version: $pubVersion" | Out-Null

# assets version
[System.IO.File]::WriteAllText((Join-Path $repoRoot 'lib/assets/version.txt'), "$txtVersion`n", $utf8)

# ci version.code.txt
if (Test-Path (Join-Path $repoRoot 'ci/version.code.txt')) {
  [System.IO.File]::WriteAllText((Join-Path $repoRoot 'ci/version.code.txt'), "$txtVersion`n", $utf8)
}

# ci version.info.txt (update first line only)
if (Test-Path (Join-Path $repoRoot 'ci/version.info.txt')) {
  Replace-Line 'ci/version.info.txt' '\A[^\r\n]*' $txtVersion | Out-Null
}

# Android local builds read versionName/versionCode from android/local.properties.
# Keep it in sync when the local file exists.
if (Test-Path (Join-Path $repoRoot 'android/local.properties')) {
  $versionName = $raw.Split('+')[0]
  $versionCode = if ($raw.Contains('+')) { $raw.Split('+')[1] } else { $null }
  Replace-Line "android\local.properties" '^flutter\.versionName\s*=.*$' "flutter.versionName=$versionName" | Out-Null
  if ($versionCode -ne $null) {
    Replace-Line "android\local.properties" '^flutter\.versionCode\s*=.*$' "flutter.versionCode=$versionCode" | Out-Null
  }
}

Write-Host "Updated version to $txtVersion"
