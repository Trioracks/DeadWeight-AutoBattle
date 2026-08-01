param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseRoot,
    [string]$GameExe = 'H:\Steam\steamapps\common\Dead Weight\Dead_weight.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$probe = Join-Path $PSScriptRoot 'auto_battle_ui_regression_probe.gd'
$sourceManager = Join-Path $projectRoot 'mod\launcher\auto_battle_external_v3.gd'
$runtimeManager = Join-Path $ReleaseRoot 'installer-verify\runtime\launcher\auto_battle_external_v3.gd'
$runtimeVersion = Join-Path $ReleaseRoot 'installer-verify\runtime\version.json'

foreach ($path in @($GameExe, $probe, $sourceManager, $runtimeManager, $runtimeVersion)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "AUTO UI regression gate is missing: $path" }
}

$runtimeManifest = Get-Content -LiteralPath $runtimeVersion -Raw | ConvertFrom-Json
if ([string]$runtimeManifest.version -cne $Version) {
    throw "Release runtime version '$($runtimeManifest.version)' does not match requested '$Version'."
}

$requiredSourceContracts = @(
    'const MOD_VERSION := "__AUTO_BATTLE_VERSION__"',
    '_button = Button.new()',
    '_button.name = "auto_battle_button"',
    'root.add_child(_button)',
    '_companions_button = Button.new()',
    '_companions_button.name = "auto_companions_button"',
    '_companions_button.text = "ONLY COMPANIONS"',
    'root.add_child(_companions_button)',
    'func _on_auto_toggled(is_enabled: bool) -> void:',
    'func _on_companions_toggled(is_enabled: bool) -> void:'
)
$sourceText = Get-Content -LiteralPath $sourceManager -Raw
foreach ($contract in $requiredSourceContracts) {
    if (-not $sourceText.Contains($contract)) { throw "AUTO UI source contract is missing: $contract" }
}

function Invoke-UiProbe([string]$ManagerPath, [string]$Label) {
    $safeLabel = ($Label -replace '[^A-Za-z0-9]+', '-').Trim('-')
    $resultPath = Join-Path $ReleaseRoot ("ui-regression-$safeLabel.txt")
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    $argumentLine = @(
        '--headless',
        '--script',
        ('"{0}"' -f $probe),
        '--',
        ('"--manager={0}"' -f $ManagerPath),
        ('"--result={0}"' -f $resultPath)
    ) -join ' '
    $process = Start-Process -FilePath $GameExe -ArgumentList $argumentLine -WorkingDirectory (Split-Path -Parent $GameExe) -WindowStyle Hidden -Wait -PassThru
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "AUTO UI regression probe produced no result for ${Label} (exit $($process.ExitCode))."
    }
    $result = Get-Content -LiteralPath $resultPath -Raw
    if ($process.ExitCode -ne 0 -or $result -cne 'PASS') {
        throw "AUTO UI regression probe failed for ${Label} (exit $($process.ExitCode)): $result"
    }
}

Invoke-UiProbe $sourceManager 'source manager'
Invoke-UiProbe $runtimeManager 'packaged runtime'
Write-Host "AUTO UI regression gate passed for v$Version."
