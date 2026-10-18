param(
    [string]$IsccPath = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$artifactDir = Join-Path $projectRoot 'dist'
$appExe = Join-Path $releaseDir 'gdut_network_helper.exe'

if (!(Test-Path -LiteralPath $appExe)) { throw 'Build the Windows release before packaging.' }
if (!(Test-Path -LiteralPath $IsccPath)) { throw 'Inno Setup 6 ISCC.exe was not found.' }
$pubspecText = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspecText, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$')
if (!$versionMatch.Success) { throw 'Cannot read application version from pubspec.yaml.' }
$appVersion = $versionMatch.Groups[1].Value

# Flutter's documented app-local distribution: ship the release runtime DLLs
# from the licensed Visual Studio runner, alongside every Flutter/plugin DLL.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio redistributable directory was not found.' }
$vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vsPath) { throw 'Visual Studio C++ tools were not found.' }
$crtCandidates = @(Get-ChildItem -LiteralPath (Join-Path $vsPath 'VC\Redist\MSVC') -Directory |
    Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
    Where-Object { Test-Path -LiteralPath $_ })
if (!$crtCandidates.Count) { throw 'The Visual Studio x64 release CRT was not found.' }
foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $source = Join-Path $crtCandidates[0] $name
    if (!(Test-Path -LiteralPath $source)) { throw "Required runtime is missing: $name" }
    Copy-Item -LiteralPath $source -Destination $releaseDir -Force
}

New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
$portableName = "gdut-network-helper-$appVersion-windows-x64-portable.zip"
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath (Join-Path $artifactDir $portableName) -Force
& $IsccPath "/DAppVersion=$appVersion" "/DSourceDir=$releaseDir" "/DArtifactDir=$artifactDir" (Join-Path $projectRoot 'packaging\windows\installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup installer compilation failed.' }

$checksums = Get-ChildItem -LiteralPath $artifactDir -File | Where-Object { $_.Extension -in @('.exe', '.zip') } |
    Sort-Object Name | ForEach-Object { "{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name }
Set-Content -LiteralPath (Join-Path $artifactDir 'SHA256SUMS.txt') -Value $checksums -Encoding utf8
Write-Output "Windows setup and portable archive are ready in $artifactDir"
