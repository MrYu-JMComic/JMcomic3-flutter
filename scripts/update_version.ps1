param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$raw = $Version.Trim()
if ($raw.StartsWith('v')) {
  $raw = $raw.Substring(1)
}
if ($raw -notmatch '^\d+\.\d+\.\d+(\+\d+)?$') {
  throw "Invalid version format. Expected like 1.7.17+45 or v1.7.17+45"
}

$pubVersion = $raw
$txtVersion = "v$raw"

function Replace-Line($path, $pattern, $replacement) {
  if (-not (Test-Path $path)) { return $false }
  $content = Get-Content $path -Raw
  $updated = [regex]::Replace($content, $pattern, $replacement, 'Multiline')
  if ($updated -ne $content) {
    Set-Content -Path $path -Value $updated
    return $true
  }
  return $false
}

# pubspec.yaml
Replace-Line "pubspec.yaml" '^version:\s*.*$' "version: $pubVersion" | Out-Null

# assets version
Set-Content -Path "lib\assets\version.txt" -Value $txtVersion

# ci version.code.txt
if (Test-Path "ci\version.code.txt") {
  Set-Content -Path "ci\version.code.txt" -Value $txtVersion
}

# ci version.info.txt (update first line only)
if (Test-Path "ci\version.info.txt") {
  $lines = Get-Content "ci\version.info.txt"
  if ($lines.Length -gt 0) {
    $lines[0] = $txtVersion
    Set-Content -Path "ci\version.info.txt" -Value $lines
  }
}

# Android local builds read versionName/versionCode from android/local.properties.
# Keep it in sync when the local file exists.
if (Test-Path "android\local.properties") {
  $versionName = $raw.Split('+')[0]
  $versionCode = if ($raw.Contains('+')) { $raw.Split('+')[1] } else { $null }
  Replace-Line "android\local.properties" '^flutter\.versionName\s*=.*$' "flutter.versionName=$versionName" | Out-Null
  if ($versionCode -ne $null) {
    Replace-Line "android\local.properties" '^flutter\.versionCode\s*=.*$' "flutter.versionCode=$versionCode" | Out-Null
  }
}

Write-Host "Updated version to $txtVersion"
