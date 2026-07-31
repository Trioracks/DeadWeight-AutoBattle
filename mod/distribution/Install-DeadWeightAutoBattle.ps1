param(
    [string]$GameDirectory = '',
    [switch]$NoDesktopShortcut,
    [switch]$NoInteractive,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$packageRoot = $PSScriptRoot
$appId = '2646720'

function Test-GameDirectory([string]$Path) {
    return -not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath (Join-Path $Path 'Dead_weight.exe'))
}

function Add-UniqueExistingPath([System.Collections.Generic.List[string]]$Collection, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
    } catch {
        return
    }
    if (-not (Test-Path -LiteralPath $fullPath)) { return }
    foreach ($knownPath in $Collection) {
        if ([string]::Equals($knownPath, $fullPath, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$Collection.Add($fullPath)
}

function Get-RegistryValue([string]$RegistryPath, [string]$Name) {
    try {
        $value = Get-ItemPropertyValue -Path $RegistryPath -Name $Name -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { return [string]$value }
    } catch { }
    return $null
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @(
        (Get-RegistryValue 'HKCU:\Software\Valve\Steam' 'SteamPath'),
        (Get-RegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath'),
        (Get-RegistryValue 'HKLM:\SOFTWARE\Valve\Steam' 'InstallPath'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Steam')
    )) {
        Add-UniqueExistingPath $roots $candidate
    }
    return $roots
}

function Convert-VdfPath([string]$VdfPath) {
    if ([string]::IsNullOrWhiteSpace($VdfPath)) { return $null }
    return ($VdfPath -replace '\\\\', '\')
}

function Get-SteamLibraries([string]$SteamRoot) {
    $libraries = New-Object System.Collections.Generic.List[string]
    Add-UniqueExistingPath $libraries $SteamRoot
    $libraryFile = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $libraryFile)) { return $libraries }

    try {
        $vdf = Get-Content -LiteralPath $libraryFile -Raw -Encoding UTF8
        $patterns = @(
            '(?im)^\s*"path"\s+"(?<path>[^"]+)"',
            '(?im)^\s*"\d+"\s+"(?<path>[^"]+)"\s*$'
        )
        foreach ($pattern in $patterns) {
            foreach ($match in [regex]::Matches($vdf, $pattern)) {
                Add-UniqueExistingPath $libraries (Convert-VdfPath $match.Groups['path'].Value)
            }
        }
    } catch { }
    return $libraries
}

function Get-ManifestInstallDirectory([string]$Library) {
    $manifest = Join-Path $Library "steamapps\appmanifest_$appId.acf"
    if (-not (Test-Path -LiteralPath $manifest)) { return $null }
    try {
        $manifestText = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8
        $match = [regex]::Match($manifestText, '(?im)^\s*"installdir"\s+"(?<name>[^"]+)"')
        if ($match.Success) { return $match.Groups['name'].Value }
    } catch { }
    return $null
}

function Find-DeadWeightDirectory {
    foreach ($steamRoot in Get-SteamRoots) {
        foreach ($library in Get-SteamLibraries $steamRoot) {
            $common = Join-Path $library 'steamapps\common'
            if (-not (Test-Path -LiteralPath $common)) { continue }

            # Steam's app manifest is useful when present, but never a requirement:
            # it can be unavailable during a repair, beta switch or copied library.
            $candidates = New-Object System.Collections.Generic.List[string]
            $manifestDirectory = Get-ManifestInstallDirectory $library
            if (-not [string]::IsNullOrWhiteSpace($manifestDirectory)) {
                [void]$candidates.Add((Join-Path $common $manifestDirectory))
            }
            [void]$candidates.Add((Join-Path $common 'Dead Weight'))

            foreach ($candidate in $candidates) {
                if (Test-GameDirectory $candidate) {
                    return [IO.Path]::GetFullPath($candidate)
                }
            }
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
    if (-not (Test-GameDirectory $GameDirectory) -and -not $NoInteractive) { $GameDirectory = Select-GameDirectory }
    if (-not (Test-GameDirectory $GameDirectory)) {
        throw 'Dead Weight was not found in any Steam library. Select the game folder containing Dead_weight.exe and run the installer again. No game or mod files were changed.'
    }

    $GameDirectory = [IO.Path]::GetFullPath($GameDirectory)
    if ($VerifyOnly) {
        Write-Output "FOUND_GAME_DIRECTORY=$GameDirectory"
        exit 0
    }

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
    if ($NoInteractive) { Write-Error $_.Exception.Message }
    exit 1
}
