# Builds the BillFlow release APK and renames it automatically to
# BillFlow-v<versionName>.apk so the app version is visible in the file name.
#
# Usage (from cashier_app/):
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

Write-Host "==> flutter build apk --release" -ForegroundColor Cyan
& flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Gradle build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

$apkDir = Join-Path (Get-Location) "build\app\outputs\flutter-apk"
$srcApk = Join-Path $apkDir "app-release.apk"
if (-not (Test-Path -LiteralPath $srcApk)) {
    Write-Host "Output APK not found: $srcApk" -ForegroundColor Red
    exit 1
}

# Read versionName (the X.Y.Z part before '+' in `version:` from pubspec).
$pubspec = Get-Content (Join-Path (Get-Location) "pubspec.yaml") -Raw
if ($pubspec -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)(\+\d+)?') {
    $versionName = $Matches[1]
} else {
    $versionName = "1.4.1"
}

$destApk = Join-Path $apkDir "BillFlow-v$versionName.apk"
Copy-Item -LiteralPath $srcApk -Destination $destApk -Force

Write-Host "==> Release APK ready:" -ForegroundColor Green
Write-Host "    $destApk" -ForegroundColor Green
