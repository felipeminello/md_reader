# Builds the MD Reader release and packages it into an MSI using the WiX v3
# toolset.
#
# Prerequisites:
#   - Flutter (stable) with the Windows desktop toolchain.
#   - Windows Developer Mode enabled (needed to build apps that use plugins).
#   - WiX v3 binaries extracted to tools\wix (candle.exe, heat.exe, light.exe).
#     Download: https://github.com/wixtoolset/wix3/releases (wix314-binaries.zip)
#
# Usage (from anywhere):  powershell -File installer\build_msi.ps1

$ErrorActionPreference = "Stop"

# Resolve repo root (this script lives in installer\) and work from there.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$wix     = "tools\wix"
$release = "build\windows\x64\runner\Release"
$obj     = "installer\obj"
$out     = "dist"
$msi     = "$out\md_reader-1.0.0-x64.msi"

foreach ($exe in @("heat.exe", "candle.exe", "light.exe")) {
  if (-not (Test-Path "$wix\$exe")) {
    throw "WiX tool '$exe' not found in $wix. Download wix314-binaries.zip and extract it there."
  }
}

Write-Host "==> flutter build windows --release"
flutter build windows --release
if (-not (Test-Path "$release\md_reader.exe")) {
  throw "Release build not found at $release\md_reader.exe"
}

# Bundle the Visual C++ runtime DLLs next to the executable so the app runs on
# machines that do not have the VC++ Redistributable installed. Prefer the
# official redistributable copies shipped with Visual Studio; fall back to the
# system copies.
Write-Host "==> bundling Visual C++ runtime"
$vcDlls = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$redist = $null
if (Test-Path $vswhere) {
  $vs = & $vswhere -latest -property installationPath
  if ($vs) {
    $verFile = Join-Path $vs 'VC\Auxiliary\Build\Microsoft.VCRedistVersion.default.txt'
    if (Test-Path $verFile) {
      $redist = Join-Path $vs ("VC\Redist\MSVC\" + (Get-Content $verFile).Trim() + "\x64")
    }
  }
}
foreach ($d in $vcDlls) {
  $src = $null
  if ($redist -and (Test-Path $redist)) {
    $hit = Get-ChildItem $redist -Recurse -Filter $d -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { $src = $hit.FullName }
  }
  if (-not $src) {
    $sys = Join-Path "$env:SystemRoot\System32" $d
    if (Test-Path $sys) { $src = $sys }
  }
  if ($src) { Copy-Item $src -Destination $release -Force }
  else { Write-Warning "Visual C++ runtime DLL not found: $d (app may fail on clean machines)" }
}

New-Item -ItemType Directory -Force -Path $obj, $out | Out-Null

Write-Host "==> heat: harvesting $release"
& "$wix\heat.exe" dir $release -nologo `
  -cg AppFiles -dr INSTALLFOLDER -gg -scom -sreg -sfrag -srd `
  -var var.SourceDir -out installer\AppFiles.wxs

Write-Host "==> candle: compiling"
& "$wix\candle.exe" -nologo -arch x64 -dSourceDir="$release" -out "$obj\" `
  installer\md_reader.wxs installer\AppFiles.wxs

Write-Host "==> light: linking $msi"
# ICE60 is a benign warning about the versioned .exe/.dll lacking a Language
# column; it does not affect installation, so it is suppressed.
& "$wix\light.exe" -nologo -sice:ICE60 -out $msi "$obj\md_reader.wixobj" "$obj\AppFiles.wixobj"

Write-Host "==> Done: $msi"
