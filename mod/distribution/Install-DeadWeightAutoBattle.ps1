param(
    [string]$GameDirectory = '',
    [switch]$NoDesktopShortcut,
    [switch]$NoInteractive
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$packageRoot = $PSScriptRoot
$appId = '2646720'

function Test-GameDirectory([string]$Path) {
    return -not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath (Join-Path $Path 'Dead_weight.exe'))
}

function Find-DeadWeightDirectory {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        (Get-ItemPropertyValue -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue),
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam')
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) { $roots.Add($candidate) }
    }

    foreach ($root in ($roots | Select-Object -Unique)) {
        $libraries = @($root)
        $libraryFile = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"(?<path>[^"]+)"') {
                    $libraries += ($Matches.path -replace '\\\\', '\')
                }
            }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            $manifest = Join-Path $library "steamapps\appmanifest_$appId.acf"
            $game = Join-Path $library 'steamapps\common\Dead Weight'
            if ((Test-Path -LiteralPath $manifest) -and (Test-GameDirectory $game)) { return $game }
        }
    }
    return $null
}

function Select-GameDirectory {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Dead Weight game folder (it contains Dead_weight.exe).'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    return $null
}

function Create-DesktopShortcut([string]$Destination, [string]$GamePath) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $linkPath = Join-Path $desktop 'Dead Weight - AUTO Battle.lnk'
        $launcher = Join-Path $Destination 'Launch via Steam.cmd'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($linkPath)
        $shortcut.TargetPath = $env:ComSpec
        $shortcut.Arguments = '/d /s /c ""{0}""' -f $launcher
        $shortcut.WorkingDirectory = $GamePath
        $shortcut.IconLocation = (Join-Path $GamePath 'Dead_weight.exe') + ',0'
        $shortcut.Description = 'Dead Weight with AUTO Battle and automatic updates'
        $shortcut.Save()
        return $linkPath
    } catch {
        return $null
    }
}

try {
    if (-not (Test-GameDirectory $GameDirectory)) { $GameDirectory = Find-DeadWeightDirectory }
    if (-not (Test-GameDirectory $GameDirectory)) { $GameDirectory = Select-GameDirectory }
    if (-not (Test-GameDirectory $GameDirectory)) { throw 'Dead_weight.exe was not found. No game or mod files were changed.' }

    $GameDirectory = [IO.Path]::GetFullPath($GameDirectory)
    $destination = Join-Path $GameDirectory 'DeadWeightAutoBattle'
    $staging = "$destination.installing-" + [guid]::NewGuid().ToString('N')
    $backup = "$destination.previous-" + [guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Copy-Item -LiteralPath (Join-Path $packageRoot 'bootstrap') -Destination (Join-Path $staging 'bootstrap') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot 'runtime') -Destination (Join-Path $staging 'runtime') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Launch via Steam.cmd') -Destination (Join-Path $staging 'Launch via Steam.cmd') -Force

    $oldMoved = $false
    try {
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $backup -Force
            $oldMoved = $true
        }
        Move-Item -LiteralPath $staging -Destination $destination -Force
        if ($oldMoved) { Remove-Item -LiteralPath $backup -Recurse -Force }
    } catch {
        if ($oldMoved -and -not (Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $destination -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }

    $shortcut = if ($NoDesktopShortcut) { $null } else { Create-DesktopShortcut $destination $GameDirectory }
    $steamLauncher = Join-Path $destination 'Launch via Steam.cmd'
    $steamOption = 'cmd /d /s /c ""{0}" %command%"' -f $steamLauncher
    if (-not $NoInteractive) { try { Set-Clipboard -Value $steamOption } catch { } }

    Add-Type -AssemblyName System.Windows.Forms
    $message = "Installed in:`n$destination`n`nA desktop shortcut was created: $shortcut`n`nFor Steam: open Dead Weight > Properties > Launch Options and press Ctrl+V. The command is already copied to your clipboard.`n`nFrom now on, this launch path checks the official GitHub release before every start. Updates are SHA-256 verified; only DeadWeightAutoBattle is replaced."
    if (-not $NoInteractive) {
        [System.Windows.Forms.MessageBox]::Show($message, 'Dead Weight - AUTO Battle installed', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not $NoInteractive) { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Dead Weight - AUTO Battle installation failed', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null }
    } catch { }
    exit 1
}
