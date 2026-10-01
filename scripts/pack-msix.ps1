# Builds MemoBuddy for Windows and packs it as MSIX for the Microsoft Store.
# CI runs it on every push (.github/workflows/ci.yml, artifact MemoBuddy-msix)
# with the Store's product identity; it packs with MakeAppx from the Windows
# SDK. On a PC with Microsoft's winapp CLI installed it uses winapp instead,
# which can also sign a local test build with a development certificate.
#
# Store build (the Store signs the package itself):
#   .\scripts\pack-msix.ps1 -IdentityName "12345Name.AppName" -Publisher "CN=..." -PublisherDisplayName "Name" -Version 1.0.0.0
# Already built (memopet.exe in src-tauri/target/release): add -SkipBuild.
# Local test build signed with a winapp development certificate (see
# docs/RELEASE.md for installing it once as administrator):
#   .\scripts\pack-msix.ps1 -DevCert
param(
  [string]$IdentityName = "MemoBuddy.Dev",
  [string]$Publisher = "CN=MemoBuddyDev",
  [string]$PublisherDisplayName = "MemoBuddy (dev)",
  [string]$Version = "1.0.0.0",
  [switch]$DevCert,
  [switch]$SkipBuild
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not $SkipBuild) {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
  npm run tauri -- build --no-bundle
  if ($LASTEXITCODE -ne 0) { throw "tauri build failed" }
}

$packaging = "packaging/windows"
$stage = Join-Path $packaging "stage"
$out = Join-Path $packaging "out"
foreach ($dir in @($stage, $out)) {
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  New-Item -ItemType Directory $dir | Out-Null
}
Copy-Item "src-tauri/target/release/memopet.exe" $stage
# Open-source license notices ship with the app (scripts/third-party-licenses.py).
Copy-Item "THIRD_PARTY_LICENSES.md" $stage

$manifest = (Get-Content (Join-Path $packaging "appxmanifest.xml") -Raw).
  Replace("__IDENTITY_NAME__", $IdentityName).
  Replace("__PUBLISHER__", $Publisher).
  Replace("__PUBLISHER_DISPLAY_NAME__", $PublisherDisplayName).
  Replace('Version="1.0.0.0"', "Version=`"$Version`"")

if (Get-Command winapp -ErrorAction SilentlyContinue) {
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
    if ($LASTEXITCODE -ne 0) { throw "winapp pack failed" }
  } finally {
    Pop-Location
  }
  Write-Host "MSIX written to $packaging"
  exit 0
}

if ($DevCert) { throw "-DevCert needs the winapp CLI (winget install microsoft.winappcli)" }
# MakeAppx wants the manifest and the images inside the folder it packs.
Set-Content -Encoding utf8 -Path (Join-Path $stage "AppxManifest.xml") -Value $manifest
Copy-Item -Recurse (Join-Path $packaging "Assets") (Join-Path $stage "Assets")
$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" |
  Sort-Object FullName | Select-Object -Last 1
if (-not $makeappx) { throw "makeappx.exe not found: install the Windows SDK, or winapp" }
$package = Join-Path $out "MemoBuddy_${Version}_x64.msix"
& $makeappx.FullName pack /d $stage /p $package /o
if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed" }
Write-Host "MSIX written to $package"
