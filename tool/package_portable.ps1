<#
.SYNOPSIS
    Packages the Windows release bundle into a single, standalone self-extracting
    executable (SFX) so the whole app can be shipped as one .exe file.

.DESCRIPTION
    A Flutter Windows build produces md_reader.exe plus flutter_windows.dll and a
    data\ folder that must travel together. This script compresses that bundle and
    prepends the 7-Zip SFX module, producing dist\md_reader_portable.exe.

    When the recipient runs that single file, it silently extracts the bundle to a
    temporary folder, launches the app, and removes the temp folder when the app
    closes. Nothing is installed.

.NOTES
    Requires 7-Zip (https://www.7-zip.org/) installed at the default location.
    Run `flutter build windows --release` first.
#>
$ErrorActionPreference = 'Stop'

$root      = Split-Path $PSScriptRoot                          # project root
$release   = Join-Path $root 'build\windows\x64\runner\Release'
$dist      = Join-Path $root 'dist'
$sevenZip  = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$sfxModule = Join-Path $env:ProgramFiles '7-Zip\7z.sfx'

if (-not (Test-Path $release))   { throw "Release build not found at '$release'. Run: flutter build windows --release" }
if (-not (Test-Path $sevenZip))  { throw "7-Zip not found at '$sevenZip'. Install it from https://www.7-zip.org/" }
if (-not (Test-Path $sfxModule)) { throw "7-Zip SFX module not found at '$sfxModule'." }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$archive = Join-Path $dist 'app.7z'
$config  = Join-Path $dist 'sfx_config.txt'
$output  = Join-Path $dist 'md_reader_portable.exe'

if (Test-Path $archive) { Remove-Item $archive -Force }
if (Test-Path $output)  { Remove-Item $output  -Force }

# 1. Compress the release bundle's CONTENTS (so paths are relative to the exe).
& $sevenZip a -t7z -mx=9 $archive "$release\*" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7-Zip archiving failed (exit $LASTEXITCODE)." }

# 2. SFX config: extract to a temp dir and launch the app, no install prompts.
$cfgText = @'
;!@Install@!UTF-8!
Title="MD Reader"
RunProgram="md_reader.exe"
;!@InstallEnd@!
'@
# Must be written WITHOUT a BOM for the SFX header to parse correctly.
[System.IO.File]::WriteAllText($config, $cfgText, (New-Object System.Text.UTF8Encoding($false)))

# 3. Concatenate: SFX module + config + archive  ->  single standalone exe.
$bytes = [System.IO.File]::ReadAllBytes($sfxModule) +
         [System.IO.File]::ReadAllBytes($config)    +
         [System.IO.File]::ReadAllBytes($archive)
[System.IO.File]::WriteAllBytes($output, $bytes)

# 4. Clean up intermediates.
Remove-Item $archive, $config -Force

$mb = (Get-Item $output).Length / 1MB
Write-Output ("Created standalone executable: {0} ({1:N1} MB)" -f $output, $mb)
