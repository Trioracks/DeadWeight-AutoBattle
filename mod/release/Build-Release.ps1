param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutputRoot = 'D:\Codex\Builds\Mod-Dead-Weight'
)

$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be a three-part number, for example 0.1.0.' }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$distribution = Join-Path $projectRoot 'mod\distribution'
$launcherSource = Join-Path $projectRoot 'mod\launcher'
$releaseRoot = Join-Path $OutputRoot "v$Version"
$runtimePackageName = "DeadWeight_AutoBattle_Runtime_v$Version.zip"
$installerPackageName = "DeadWeight_AutoBattle_v$Version.zip"
$runtimeStage = Join-Path $releaseRoot 'runtime-package'
$installerStage = Join-Path $releaseRoot 'installer-package'
$runtimeZip = Join-Path $releaseRoot $runtimePackageName
$installerZip = Join-Path $releaseRoot $installerPackageName
$releaseManifest = Join-Path $releaseRoot 'deadweight-autobattle-update.json'

Remove-Item -LiteralPath $releaseRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $runtimeStage, $installerStage | Out-Null

# The downloadable runtime contains only scripts written for the mod. No game
# binary, PCK, save or original asset is ever included in a release.
$runtimeRoot = Join-Path $runtimeStage 'runtime'
$runtimeLaunchers = Join-Path $runtimeRoot 'launcher'
New-Item -ItemType Directory -Force -Path $runtimeLaunchers | Out-Null
Copy-Item -LiteralPath (Join-Path $launcherSource 'dead_weight_auto_launcher.gd') -Destination $runtimeLaunchers -Force
$runtimeTacticsScript = Join-Path $runtimeLaunchers 'auto_battle_external_v3.gd'
Copy-Item -LiteralPath (Join-Path $launcherSource 'auto_battle_external_v3.gd') -Destination $runtimeTacticsScript -Force
$runtimeTacticsText = Get-Content -LiteralPath $runtimeTacticsScript -Raw
$versionToken = '__AUTO_BATTLE_VERSION__'
if (-not $runtimeTacticsText.Contains($versionToken)) { throw 'Runtime tactics script has no version token.' }
[System.IO.File]::WriteAllText($runtimeTacticsScript, $runtimeTacticsText.Replace($versionToken, $Version), [System.Text.UTF8Encoding]::new($false))
[ordered]@{
    schemaVersion = 1
    version = $Version
    channel = 'stable'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeRoot 'version.json') -Encoding UTF8

Compress-Archive -LiteralPath $runtimeRoot -DestinationPath $runtimeZip -CompressionLevel Optimal
$runtimeHash = (Get-FileHash -LiteralPath $runtimeZip -Algorithm SHA256).Hash

$manifest = [ordered]@{
    schemaVersion = 1
    version = $Version
    package = $runtimePackageName
    sha256 = $runtimeHash
    url = "https://github.com/Trioracks/DeadWeight-AutoBattle/releases/download/v$Version/$runtimePackageName"
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath $releaseManifest -Encoding UTF8

Copy-Item -LiteralPath (Join-Path $distribution 'Install-DeadWeightAutoBattle.ps1') -Destination $installerStage -Force
Copy-Item -LiteralPath (Join-Path $distribution 'Install-DeadWeightAutoBattle.cmd') -Destination $installerStage -Force
Copy-Item -LiteralPath (Join-Path $distribution 'Launch via Steam.cmd') -Destination $installerStage -Force
Copy-Item -LiteralPath (Join-Path $distribution 'bootstrap') -Destination (Join-Path $installerStage 'bootstrap') -Recurse -Force
Copy-Item -LiteralPath $runtimeRoot -Destination (Join-Path $installerStage 'runtime') -Recurse -Force
foreach ($documentation in @('README.md', 'README_EN.md')) {
    $source = Join-Path $projectRoot $documentation
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $installerStage -Force }
}
Compress-Archive -Path (Join-Path $installerStage '*') -DestinationPath $installerZip -CompressionLevel Optimal

Expand-Archive -LiteralPath $runtimeZip -DestinationPath (Join-Path $releaseRoot 'runtime-verify') -Force
Expand-Archive -LiteralPath $installerZip -DestinationPath (Join-Path $releaseRoot 'installer-verify') -Force
$required = @(
    'runtime\version.json',
    'runtime\launcher\dead_weight_auto_launcher.gd',
    'runtime\launcher\auto_battle_external_v3.gd'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $releaseRoot 'runtime-verify') $relative))) {
        throw "Runtime package verification failed: missing $relative"
    }
}
foreach ($name in @('Dead_weight.exe', 'Dead_weight.console.exe', 'GameAnalytics.dll', 'GameAssembly.dll')) {
    if (Get-ChildItem -LiteralPath $releaseRoot -Recurse -File -Filter $name) { throw "Release must not include game file $name." }
}

$installerHash = (Get-FileHash -LiteralPath $installerZip -Algorithm SHA256).Hash
Write-Host "Runtime package: $runtimeZip"
Write-Host "Runtime SHA-256: $runtimeHash"
Write-Host "Installer package: $installerZip"
Write-Host "Installer SHA-256: $installerHash"
Write-Host "Update manifest: $releaseManifest"
