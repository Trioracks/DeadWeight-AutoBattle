param(
    [string]$GameDirectory = '',
    [switch]$NoDesktopShortcut,
    [switch]$NoInteractive,
    [switch]$VerifyOnly,
    [switch]$SkipSteamLaunchOption
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

function Find-VdfBlock([string]$Text, [string]$Key) {
    $needle = '"' + $Key + '"'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $keyAt = $Text.IndexOf($needle, $offset, [StringComparison]::OrdinalIgnoreCase)
        if ($keyAt -lt 0) { return $null }

        $openAt = $keyAt + $needle.Length
        while ($openAt -lt $Text.Length -and [char]::IsWhiteSpace($Text[$openAt])) { $openAt++ }
        if ($openAt -ge $Text.Length -or $Text[$openAt] -ne '{') {
            $offset = $keyAt + $needle.Length
            continue
        }

        $depth = 0
        $inString = $false
        $escaped = $false
        for ($cursor = $openAt; $cursor -lt $Text.Length; $cursor++) {
            $character = $Text[$cursor]
            if ($inString) {
                if ($escaped) {
                    $escaped = $false
                } elseif ($character -eq '\') {
                    $escaped = $true
                } elseif ($character -eq '"') {
                    $inString = $false
                }
                continue
            }
            if ($character -eq '"') {
                $inString = $true
            } elseif ($character -eq '{') {
                $depth++
            } elseif ($character -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    return [pscustomobject]@{ Open = $openAt; Close = $cursor }
                }
            }
        }
        throw "Steam configuration has an unterminated '$Key' block."
    }
    return $null
}

function Escape-VdfValue([string]$Value) {
    # VDF consumes backslash escape sequences. Both the Windows path
    # separators and quote delimiters must survive Steam's read/write cycle.
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Set-LaunchOptionInVdf([string]$ConfigPath, [string]$LaunchOption) {
    $text = [IO.File]::ReadAllText($ConfigPath)
    $block = Find-VdfBlock $text $appId
    if ($null -eq $block) { return $false }

    $bodyStart = $block.Open + 1
    $bodyLength = $block.Close - $bodyStart
    $body = $text.Substring($bodyStart, $bodyLength)
    $launchMatch = [regex]::Match($body, '(?m)^(?<indent>[\t ]*)"LaunchOptions"\s+"(?<value>(?:\\.|[^"\\])*)"')
    $escapedOption = Escape-VdfValue $LaunchOption
    if ($launchMatch.Success) {
        $replacement = $launchMatch.Groups['indent'].Value + '"LaunchOptions"' + '  ' + '"' + $escapedOption + '"'
        $body = $body.Remove($launchMatch.Index, $launchMatch.Length).Insert($launchMatch.Index, $replacement)
    } else {
        $indentMatch = [regex]::Match($body, '(?m)^(?<indent>[\t ]+)"')
        $indent = if ($indentMatch.Success) { $indentMatch.Groups['indent'].Value } else { '    ' }
        $body += [Environment]::NewLine + $indent + '"LaunchOptions"' + '  ' + '"' + $escapedOption + '"'
    }

    $updated = $text.Substring(0, $bodyStart) + $body + $text.Substring($block.Close)
    if ($updated -ceq $text) { return $true }
    $backup = "$ConfigPath.autobattle-backup"
    Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
    [IO.File]::WriteAllText($ConfigPath, $updated, [Text.UTF8Encoding]::new($false))
    $verified = [IO.File]::ReadAllText($ConfigPath)
    if (-not $verified.Contains($escapedOption)) { throw "Steam launch option could not be verified in $ConfigPath." }
    return $true
}

function Configure-SteamLaunchOption([string]$LauncherPath) {
    $steamProcesses = @(Get-Process -Name 'steam' -ErrorAction SilentlyContinue)
    if ($steamProcesses.Count -gt 0) {
        return [pscustomobject]@{
            configured = $false
            reason = 'Steam is running. Close Steam completely, then run this installer once more.'
        }
    }

    $steamOption = 'cmd /d /s /c ""{0}" %command%"' -f $LauncherPath
    $configured = 0
    foreach ($steamRoot in Get-SteamRoots) {
        $userdata = Join-Path $steamRoot 'userdata'
        if (-not (Test-Path -LiteralPath $userdata)) { continue }
        foreach ($config in Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'config\localconfig.vdf' }) {
            if ((Test-Path -LiteralPath $config) -and (Set-LaunchOptionInVdf $config $steamOption)) { $configured++ }
        }
    }

    if ($configured -eq 0) {
        return [pscustomobject]@{
            configured = $false
            reason = 'No Steam account configuration containing Dead Weight was found. The launch command remains on the clipboard.'
        }
    }
    return [pscustomobject]@{ configured = $true; reason = "Configured $configured Steam account(s)." }
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

    $steamConfiguration = if ($SkipSteamLaunchOption) {
        [pscustomobject]@{ configured = $false; reason = 'Steam launch-option setup was skipped.' }
    } else {
        Configure-SteamLaunchOption $steamLauncher
    }

    Add-Type -AssemblyName System.Windows.Forms
    $launchStatus = if ($steamConfiguration.configured) {
        'Steam Play is configured to start AUTO Battle.'
    } else {
        "Steam Play was not changed: $($steamConfiguration.reason)"
    }
    $message = "Installed in:`n$destination`n`nA desktop shortcut was created: $shortcut`n`n$launchStatus`n`nThe Steam launch command is also copied to the clipboard as a fallback.`n`nFrom now on, this launch path checks the official GitHub release before every start. Updates are SHA-256 verified; only DeadWeightAutoBattle is replaced."
    if ($NoInteractive) {
        Write-Output "STEAM_LAUNCH_OPTION_CONFIGURED=$($steamConfiguration.configured)"
        Write-Output "STEAM_LAUNCH_OPTION_STATUS=$($steamConfiguration.reason)"
    }
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
