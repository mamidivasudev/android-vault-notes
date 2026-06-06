# Run vault_notes on USB-connected Android device
$ErrorActionPreference = "Continue"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "=== vault_notes: deploy to phone ===" -ForegroundColor Cyan

function Find-Tool($name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$flutter = Find-Tool "flutter"
if (-not $flutter) {
    foreach ($p in @(
        "C:\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "$env:USERPROFILE\flutter\bin\flutter.bat",
        "$env:USERPROFILE\develop\flutter\bin\flutter.bat"
    )) {
        if (Test-Path $p) { $flutter = $p; break }
    }
}

$adb = Find-Tool "adb"
if (-not $adb) {
    $sdkAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $sdkAdb) { $adb = $sdkAdb }
}

if (-not $flutter) {
    Write-Host "ERROR: Flutter not found. Install Flutter and add it to PATH." -ForegroundColor Red
    exit 1
}
Write-Host "Flutter: $flutter"

if ($adb) {
    Write-Host "`n--- adb devices ---"
    & $adb devices
} else {
    Write-Host "WARNING: adb not found. Install Android SDK platform-tools." -ForegroundColor Yellow
}

Write-Host "`n--- flutter pub get ---"
& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n--- flutter devices ---"
& $flutter devices

Write-Host "`n--- flutter run (debug on connected phone) ---"
& $flutter run
exit $LASTEXITCODE
