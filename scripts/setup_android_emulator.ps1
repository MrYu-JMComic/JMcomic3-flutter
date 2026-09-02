[CmdletBinding()]
param(
    [string]$AvdName = 'jmcomic3-api35-x86_64',
    [ValidateRange(21, 99)]
    [int]$ApiLevel = 35,
    [string]$DeviceProfile = 'pixel_7',
    [ValidateRange(5554, 5584)]
    [int]$Port = 5554,
    [ValidateRange(30, 900)]
    [int]$BootTimeoutSeconds = 300,
    [string]$ApkPath,
    [switch]$BuildDebug,
    [switch]$SkipApkInstall,
    [switch]$SkipBoot,
    [switch]$ForceRecreate,
    [switch]$ShutdownAfterTest
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$localPropertiesPath = Join-Path $repoRoot 'android/local.properties'

function Get-LocalProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $localPropertiesPath -PathType Leaf)) {
        return $null
    }

    $line = Get-Content -LiteralPath $localPropertiesPath -Encoding UTF8 |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -First 1
    if ($null -eq $line) {
        return $null
    }

    $value = $line.Substring($line.IndexOf('=') + 1).Trim()
    # local.properties uses Java properties escaping for Windows backslashes.
    return $value.Replace('\\', '\')
}

function Resolve-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    $candidate = $Value
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $BasePath $candidate
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Find-SdkTool {
    param(
        [Parameter(Mandatory = $true)][string]$SdkRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $direct = Join-Path $SdkRoot $RelativePath
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    $toolName = Split-Path $RelativePath -Leaf
    $toolParent = Split-Path $RelativePath -Parent
    $toolRootName = ($toolParent -split '[\\/]')[0]
    $parentPath = Join-Path $SdkRoot $toolRootName
    if (Test-Path -LiteralPath $parentPath -PathType Container) {
        $fallback = Get-ChildItem -LiteralPath $parentPath -Directory |
            Sort-Object Name -Descending |
            ForEach-Object {
                $candidate = Join-Path $_.FullName (Join-Path 'bin' $toolName)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $candidate
                }
            } |
            Select-Object -First 1
        if ($fallback) {
            return $fallback
        }
    }

    return $null
}

function Set-AvdConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $pattern = '^' + [regex]::Escape($Key) + '='
    $index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $index = $i
            break
        }
    }
    $newLine = "$Key=$Value"
    if ($index -ge 0) {
        $lines[$index] = $newLine
    } else {
        $lines += $newLine
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Get-AdbState {
    param(
        [Parameter(Mandatory = $true)][string]$Adb,
        [Parameter(Mandatory = $true)][string]$Serial
    )

    $line = & $Adb devices | Select-String ("^{0}\s+([^\s]+)" -f [regex]::Escape($Serial)) | Select-Object -First 1
    if ($line) {
        return ([regex]::Match($line.Line, "^{0}\s+([^\s]+)" -f [regex]::Escape($Serial))).Groups[1].Value
    }
    return $null
}

$propertiesBase = Split-Path $localPropertiesPath -Parent
$sdkFromProperties = Get-LocalProperty 'sdk.dir'
$sdkRootValue = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} else {
    $sdkFromProperties
}
if ([string]::IsNullOrWhiteSpace($sdkRootValue)) {
    throw 'Android SDK not configured. Set ANDROID_SDK_ROOT or android/local.properties sdk.dir.'
}
$sdkRoot = Resolve-ConfiguredPath $sdkRootValue $propertiesBase

# Reuse a repository-local Gradle cache when the checked-in build environment
# provides one. This keeps the documented command usable on an offline machine
# without overriding an explicit GRADLE_USER_HOME from the caller.
if ([string]::IsNullOrWhiteSpace($env:GRADLE_USER_HOME)) {
    $toolchainRoot = Split-Path (Split-Path $sdkRoot -Parent) -Parent
    $localGradleHome = Join-Path $toolchainRoot '_cache/gradle'
    if (Test-Path -LiteralPath $localGradleHome -PathType Container) {
        $env:GRADLE_USER_HOME = $localGradleHome
    }
}

$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
$emulator = Join-Path $sdkRoot 'emulator/emulator.exe'
$sdkManager = Find-SdkTool $sdkRoot 'cmdline-tools/latest/bin/sdkmanager.bat'
$avdManager = Find-SdkTool $sdkRoot 'cmdline-tools/latest/bin/avdmanager.bat'
foreach ($tool in @(@{ Path = $adb; Name = 'adb' },
                   @{ Path = $emulator; Name = 'emulator' },
                   @{ Path = $sdkManager; Name = 'sdkmanager' },
                   @{ Path = $avdManager; Name = 'avdmanager' })) {
    if ([string]::IsNullOrWhiteSpace($tool.Path) -or
            -not (Test-Path -LiteralPath $tool.Path -PathType Leaf)) {
        throw "Android $($tool.Name) was not found under $sdkRoot. Install the Android command-line tools."
    }
}

$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot
$imagePackage = "system-images;android-$ApiLevel;google_apis;x86_64"
$imagePath = Join-Path $sdkRoot "system-images/android-$ApiLevel/google_apis/x86_64"

if (-not (Test-Path -LiteralPath (Join-Path $imagePath 'package.xml') -PathType Leaf)) {
    Write-Host "Installing Android Emulator and $imagePackage..."
    & $sdkManager --install 'emulator' $imagePackage
    if ($LASTEXITCODE -ne 0) {
        throw "sdkmanager failed with exit code $LASTEXITCODE. Check SDK licenses and network access."
    }
}
if (-not (Test-Path -LiteralPath $imagePath -PathType Container)) {
    throw "System image was not installed: $imagePath"
}

$avdHome = if ($env:ANDROID_AVD_HOME) {
    $env:ANDROID_AVD_HOME
} else {
    Join-Path $env:USERPROFILE '.android/avd'
}
New-Item -ItemType Directory -Force -Path $avdHome | Out-Null
$avdConfigPath = Join-Path $avdHome "$AvdName.avd/config.ini"
$avdIniPath = Join-Path $avdHome "$AvdName.ini"
$avdList = (& $avdManager list avd 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "avdmanager could not list virtual devices: $avdList"
}
$avdPattern = '(?m)^\s*Name:\s*' + [regex]::Escape($AvdName) + '\s*$'
$avdExists = $avdList -match $avdPattern

if ($ForceRecreate -and $avdExists) {
    Write-Host "Deleting existing AVD $AvdName..."
    & $avdManager delete avd --name $AvdName
    if ($LASTEXITCODE -ne 0) {
        throw "Could not delete AVD $AvdName. Stop it first if it is running."
    }
    $avdExists = $false
}

$createdAvd = $false
if (-not $avdExists) {
    Write-Host "Creating AVD $AvdName ($imagePackage, $DeviceProfile)..."
    "no`n" | & $avdManager create avd --name $AvdName --package $imagePackage --device $DeviceProfile --force
    if ($LASTEXITCODE -ne 0) {
        throw "avdmanager failed to create AVD $AvdName."
    }
    $createdAvd = $true
}

if (-not (Test-Path -LiteralPath $avdConfigPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $avdIniPath -PathType Leaf)) {
    throw "AVD files were not created under $avdHome."
}

# Keep this AVD predictable across machines and CLI-tool versions. These
# settings are picked up on the next emulator start if it is already running.
Set-AvdConfigValue $avdConfigPath 'avd.id' $AvdName
Set-AvdConfigValue $avdConfigPath 'avd.name' $AvdName
Set-AvdConfigValue $avdConfigPath 'hw.ramSize' '4096'
Set-AvdConfigValue $avdConfigPath 'hw.cpu.ncore' '4'
Set-AvdConfigValue $avdConfigPath 'hw.keyboard' 'yes'
Set-AvdConfigValue $avdConfigPath 'showDeviceFrame' 'no'

$serial = "emulator-$Port"
$packageName = 'com.jmcomic3.yee'
$stderrLog = $null
& $adb start-server | Out-Null
$runningState = Get-AdbState $adb $serial
$startedEmulator = $false
if ($runningState -eq 'device') {
    $runningAvd = (& $adb -s $serial emu avd name 2>$null |
        Select-Object -First 1 | Out-String).Trim()
    if ($runningAvd -and $runningAvd -ne $AvdName) {
        throw "$serial is already running AVD '$runningAvd', expected '$AvdName'."
    }
} elseif (-not $SkipBoot) {
    $logDir = Join-Path $repoRoot 'build'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $safeAvdName = $AvdName -replace '[^A-Za-z0-9_.-]', '_'
    $stdoutLog = Join-Path $logDir "$safeAvdName.log"
    $stderrLog = Join-Path $logDir "$safeAvdName.err.log"
    $emulatorArguments = @(
        '-avd', $AvdName,
        '-port', $Port,
        '-no-snapshot',
        '-no-boot-anim',
        '-noaudio',
        '-gpu', 'swiftshader_indirect',
        '-accel', 'auto',
        '-netdelay', 'none',
        '-netspeed', 'full'
    )
    $process = Start-Process -FilePath $emulator -ArgumentList $emulatorArguments -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    $startedEmulator = $true
    Write-Host "Started $AvdName as $serial (pid $($process.Id))."
    Write-Host "Emulator logs: $stdoutLog"
} elseif ($runningState -ne 'device') {
    throw "$serial is not running. Remove -SkipBoot or start the AVD manually."
}

if (-not $SkipBoot) {
    $deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
    $booted = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $deviceState = (& $adb -s $serial get-state 2>$null | Out-String).Trim()
        $bootCompleted = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        if ($deviceState -eq 'device' -and $bootCompleted -match '1') {
            $booted = $true
            break
        }
        Write-Host "Waiting for ${serial}: state=$deviceState boot=$bootCompleted"
    }
    if (-not $booted) {
        if ($stderrLog -and (Test-Path -LiteralPath $stderrLog -PathType Leaf)) {
            Get-Content -LiteralPath $stderrLog -Tail 40
        }
        throw "$serial did not finish booting within $BootTimeoutSeconds seconds."
    }
}

$sdkVersion = (& $adb -s $serial shell getprop ro.build.version.sdk | Out-String).Trim()
$abiList = (& $adb -s $serial shell getprop ro.product.cpu.abilist | Out-String).Trim()
$nativeBridge = (& $adb -s $serial shell getprop ro.dalvik.vm.native.bridge | Out-String).Trim()
Write-Host "Device ready: $serial, API $sdkVersion, ABI $abiList, native bridge '$nativeBridge'."

# Disable animations so repeated smoke tests are less timing-sensitive.
& $adb -s $serial shell settings put global window_animation_scale 0 | Out-Null
& $adb -s $serial shell settings put global transition_animation_scale 0 | Out-Null
& $adb -s $serial shell settings put global animator_duration_scale 0 | Out-Null

if (-not $SkipApkInstall) {
    if ($BuildDebug) {
        $flutterValue = Get-LocalProperty 'flutter.sdk'
        if ([string]::IsNullOrWhiteSpace($flutterValue)) {
            throw '-BuildDebug requires flutter.sdk in android/local.properties.'
        }
        $flutterRoot = Resolve-ConfiguredPath $flutterValue $propertiesBase
        $flutter = Join-Path $flutterRoot 'bin/flutter.bat'
        if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
            throw "Flutter was not found: $flutter"
        }
        Write-Host 'Building a signed debug APK for emulator testing...'
        Push-Location $repoRoot
        try {
            & $flutter build apk --debug --target-platform android-arm64,android-arm
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter debug APK build failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    }

    if ([string]::IsNullOrWhiteSpace($ApkPath)) {
        $defaultApk = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
        if (Test-Path -LiteralPath $defaultApk -PathType Leaf) {
            $ApkPath = $defaultApk
        } else {
            throw "No signed debug APK found at $defaultApk. Build one with -BuildDebug or pass -ApkPath."
        }
    } elseif (-not [IO.Path]::IsPathRooted($ApkPath)) {
        $ApkPath = Join-Path $repoRoot $ApkPath
    }
    if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw "APK not found: $ApkPath"
    }
    $ApkPath = (Resolve-Path -LiteralPath $ApkPath).Path

    & $adb -s $serial logcat -c
    Write-Host "Installing $ApkPath..."
    $installOutput = & $adb -s $serial install -r -d $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "APK installation failed:`n$($installOutput -join [Environment]::NewLine)"
    }

    & $adb -s $serial shell monkey -p $packageName 1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not launch package $packageName."
    }
    Start-Sleep -Seconds 8
    $appProcessId = (& $adb -s $serial shell pidof $packageName 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($appProcessId)) {
        $recentLog = & $adb -s $serial logcat -d -t 300 2>$null
        throw "Package $packageName exited after launch:`n$($recentLog -join [Environment]::NewLine)"
    }

    $crashLines = @(& $adb -s $serial logcat -d -t 400 2>$null |
        Select-String -Pattern 'FATAL EXCEPTION|UnsatisfiedLinkError')
    if ($crashLines.Count -gt 0) {
        throw "Package $packageName reported a startup crash:`n$($crashLines -join [Environment]::NewLine)"
    }
    Write-Host "APK smoke test passed: $packageName is running (pid $appProcessId)."
}

if ($ShutdownAfterTest -and $startedEmulator) {
    & $adb -s $serial emu kill | Out-Null
    Write-Host "Stopped $serial."
}

Write-Host "AVD: $AvdName"
Write-Host "Serial: $serial"
Write-Host "Use: $adb -s $serial logcat"
