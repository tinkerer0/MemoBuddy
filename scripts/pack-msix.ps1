# Builds MemoPet for Windows and packs it as MSIX with Microsoft's winapp CLI.
# UNVERIFIED: written on macOS from Microsoft's Tauri guide
# (learn.microsoft.com/windows/apps/dev-tools/winapp-cli/guides/tauri);
# not yet run on Windows.
#
# Run on Windows 11 with Node.js, Rust (rustup) and winapp installed:
#   winget install OpenJS.NodeJS --source winget
#   winget install Rustlang.Rustup --source winget
#   winget install microsoft.winappcli --source winget
#
# Store build: pass the three values Partner Center shows under
# "Product identity". The Store signs the package itself.
#   .\scripts\pack-msix.ps1 -IdentityName "12345Name.MemoPet" -Publisher "CN=..." -PublisherDisplayName "Name" -Version 1.0.0.0
# Local test build signed with a development certificate that winapp
# generates (see docs/RELEASE.md for installing it once as administrator):
#   .\scripts\pack-msix.ps1 -DevCert
param(
  [string]$IdentityName = "MemoPet.Dev",
  [string]$Publisher = "CN=MemoPetDev",
  [string]$PublisherDisplayName = "MemoPet (dev)",
  [string]$Version = "1.0.0.0",
  [switch]$DevCert
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

npm ci
npm run tauri -- build --no-bundle

$packaging = "packaging/windows"
$stage = Join-Path $packaging "stage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "src-tauri/target/release/memopet.exe" $stage

$manifest = (Get-Content (Join-Path $packaging "appxmanifest.xml") -Raw).
  Replace("__IDENTITY_NAME__", $IdentityName).
  Replace("__PUBLISHER__", $Publisher).
  Replace("__PUBLISHER_DISPLAY_NAME__", $PublisherDisplayName).
  Replace('Version="1.0.0.0"', "Version=`"$Version`"")
Set-Content -Encoding utf8 -Path (Join-Path $packaging "Package.appxmanifest") -Value $manifest

Push-Location $packaging
try {
  if ($DevCert) {
    # Creates the development certificate next to the manifest if missing.
    winapp cert generate --if-exists skip
    $cert = Get-ChildItem -Filter "devcert.*" | Select-Object -First 1
    winapp pack .\stage --cert $cert.FullName
  } else {
    winapp pack .\stage
  }
} finally {
  Pop-Location
}
Write-Host "MSIX written to $packaging"
