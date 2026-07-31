param(
    [string]$GameDirectory = '',
    [switch]$NoGameStart,
    [switch]$Silent
)

# Stable bootstrap for Mod: Dead Weight. It is intentionally separate from the
# updatable runtime, so a failed download can never remove the code which
# launches the previously installed mod.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:ProjectName = 'Mod: Dead Weight - AUTO Battle'
$script:ReleaseApiUrl = 'https://api.github.com/repos/Trioracks/DeadWeight-AutoBattle/releases/latest'
$script:ModRoot = Split-Path -Parent $PSScriptRoot
$script:StatePath = Join-Path $script:ModRoot 'update-state.json'
$script:LogPath = Join-Path $script:ModRoot 'AutoBattle.update.log'
$script:Choice = 'install'

function Write-AutoLog([string]$Message) {
    try {
        $stamp = (Get-Date).ToUniversalTime().ToString('o')
        Add-Content -LiteralPath $script:LogPath -Value "$stamp [Dead Weight AUTO updater] $Message" -Encoding UTF8
    } catch { }
}

function Read-JsonFile([string]$Path) {
    try {
        if (Test-Path -LiteralPath $Path) {
            return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    } catch {
        Write-AutoLog "Could not read $Path : $($_.Exception.Message)"
    }
    return $null
}

function Write-UpdateState([string]$Version, [string]$Reason) {
    try {
        [ordered]@{
            ignoredVersion = $Version
            reason = $Reason
            recordedUtc = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    } catch {
        Write-AutoLog "Could not write updater state: $($_.Exception.Message)"
    }
}

function Remove-UpdateState {
    Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction SilentlyContinue
}

function Get-InstalledVersion {
    $localManifest = Read-JsonFile (Join-Path $script:ModRoot 'runtime\version.json')
    if ($null -eq $localManifest -or [string]::IsNullOrWhiteSpace([string]$localManifest.version)) {
        return [Version]'0.0.0'
    }
    try { return [Version]([string]$localManifest.version) }
    catch { return [Version]'0.0.0' }
}

function Get-RemoteReleaseInfo {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri $script:ReleaseApiUrl -TimeoutSec 8 -Headers @{ 'User-Agent' = 'DeadWeight-AutoBattle/1'; 'Accept' = 'application/vnd.github+json' }
    if ($null -eq $release -or [bool]$release.draft -or [bool]$release.prerelease) { throw 'The official GitHub release is unavailable.' }

    $tag = [string]$release.tag_name
    if ($tag.StartsWith('v')) { $tag = $tag.Substring(1) }
    try { [void]([Version]$tag) }
    catch { throw "The release tag is not a valid AUTO Battle version: $($release.tag_name)." }

    $packageName = "DeadWeight_AUTO_Battle_Install_v$tag.zip"
    $asset = @($release.assets | Where-Object { [string]$_.name -ceq $packageName } | Select-Object -First 1)
    if ($asset.Count -ne 1) { throw "The official release does not contain $packageName." }
    if ([string]::IsNullOrWhiteSpace([string]$asset[0].browser_download_url)) { throw 'The official installer URL is missing.' }

    $digestMatch = [regex]::Match([string]$asset[0].digest, '^sha256:(?<hash>[A-Fa-f0-9]{64})$')
    if (-not $digestMatch.Success) { throw 'GitHub did not provide a valid SHA-256 digest for the official installer.' }

    return [pscustomobject]@{
        version = $tag
        package = [string]$asset[0].name
        sha256 = $digestMatch.Groups['hash'].Value
        url = [string]$asset[0].browser_download_url
    }
}
function Test-Sha256([string]$Path, [string]$Expected) {
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ceq $Expected.ToUpperInvariant())
}

function Show-UpdateNotice([string]$Version) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Dead Weight - AUTO Battle update'
        $form.StartPosition = 'CenterScreen'
        $form.Size = New-Object System.Drawing.Size(560, 210)
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        $form.ShowInTaskbar = $true

        $title = New-Object System.Windows.Forms.Label
        $title.Text = "Found AUTO Battle v$Version / New version available"
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $title.AutoSize = $true
        $title.Location = New-Object System.Drawing.Point(20, 18)
        $form.Controls.Add($title)

        $description = New-Object System.Windows.Forms.Label
        $description.Text = 'The official package will be verified, installed and the game will start automatically.`r`nOnly the mod is changed. Dead Weight game files and saves are not touched.'
        $description.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $description.Size = New-Object System.Drawing.Size(510, 62)
        $description.Location = New-Object System.Drawing.Point(22, 48)
        $form.Controls.Add($description)

        $status = New-Object System.Windows.Forms.Label
        $status.Text = 'Installing automatically in 6 seconds...'
        $status.AutoSize = $true
        $status.Location = New-Object System.Drawing.Point(22, 120)
        $form.Controls.Add($status)

        $install = New-Object System.Windows.Forms.Button
        $install.Text = 'Update now'
        $install.Size = New-Object System.Drawing.Size(130, 29)
        $install.Location = New-Object System.Drawing.Point(260, 146)
        $install.Add_Click({ $script:Choice = 'install'; $form.Close() })
        $form.Controls.Add($install)

        $skip = New-Object System.Windows.Forms.Button
        $skip.Text = 'Skip this version'
        $skip.Size = New-Object System.Drawing.Size(140, 29)
        $skip.Location = New-Object System.Drawing.Point(400, 146)
        $skip.Add_Click({ $script:Choice = 'skip'; $form.Close() })
        $form.Controls.Add($skip)

        $remaining = 6
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.Add_Tick({
            $remaining--
            if ($remaining -le 0) {
                $timer.Stop()
                $script:Choice = 'install'
                $form.Close()
            } else {
                $status.Text = "Installing automatically in $remaining seconds..."
            }
        })
        $form.Add_Shown({ $timer.Start() })
        [void][System.Windows.Forms.Application]::Run($form)
        $timer.Dispose()
    } catch {
        Write-AutoLog "Update notice could not be displayed: $($_.Exception.Message)"
        Start-Sleep -Seconds 3
    }
}

function Install-RuntimeUpdate($Release) {
    $workRoot = Join-Path $script:ModRoot '.update-work'
    $staging = Join-Path $workRoot ("v$($Release.version)-" + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $staging ([string]$Release.package)
    $expanded = Join-Path $staging 'expanded'
    $target = Join-Path $script:ModRoot 'runtime'
    $backup = "$target.previous-" + [guid]::NewGuid().ToString('N')
    $targetMoved = $false
    try {
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Write-AutoLog "Downloading v$($Release.version) from the official GitHub release."
        Invoke-WebRequest -Uri ([string]$Release.url) -OutFile $zipPath -UseBasicParsing -TimeoutSec 45 -Headers @{ 'User-Agent' = 'DeadWeight-AutoBattle/1' }
        if (-not (Test-Sha256 $zipPath ([string]$Release.sha256))) { throw 'Downloaded installer SHA-256 does not match the official GitHub release.' }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $expanded -Force
        $newRuntime = Join-Path $expanded 'runtime'
        $versionPath = Join-Path $newRuntime 'version.json'
        $launcherPath = Join-Path $newRuntime 'launcher\dead_weight_auto_launcher.gd'
        $managerPath = Join-Path $newRuntime 'launcher\auto_battle_external_v3.gd'
        if (-not (Test-Path -LiteralPath $versionPath) -or -not (Test-Path -LiteralPath $launcherPath) -or -not (Test-Path -LiteralPath $managerPath)) {
            throw 'Update package does not contain the expected runtime layout.'
        }
        $packageVersion = Read-JsonFile $versionPath
        if ($null -eq $packageVersion -or [string]$packageVersion.version -cne [string]$Release.version) {
            throw 'Runtime version does not match the requested official release.'
        }

        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination $backup -Force
            $targetMoved = $true
        }
        Move-Item -LiteralPath $newRuntime -Destination $target -Force
        if ($targetMoved) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Remove-UpdateState
        Write-AutoLog "Installed AUTO Battle v$($Release.version); only the mod runtime was replaced."
        return $true
    } catch {
        if ($targetMoved -and -not (Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $target -Force -ErrorAction SilentlyContinue
        }
        Write-AutoLog "Update failed; keeping the installed runtime. $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Start-DeadWeight([string]$GamePath) {
    $gameExe = Join-Path $GamePath 'Dead_weight.exe'
    if (-not (Test-Path -LiteralPath $gameExe)) { throw "Dead_weight.exe was not found: $gameExe" }
    $running = Get-Process -Name 'Dead_weight' -ErrorAction SilentlyContinue
    if ($null -ne $running) {
        Write-AutoLog 'Game is already running; a second process was not started.'
        return
    }
    $launcher = Join-Path $script:ModRoot 'runtime\launcher\dead_weight_auto_launcher.gd'
    if (-not (Test-Path -LiteralPath $launcher)) {
        Write-AutoLog 'Mod runtime is unavailable; starting Dead Weight without AUTO Battle.'
        Start-Process -FilePath $gameExe -WorkingDirectory $GamePath
        return
    }
    $arguments = '--script "{0}"' -f $launcher
    Start-Process -FilePath $gameExe -WorkingDirectory $GamePath -ArgumentList $arguments
    Write-AutoLog 'Dead Weight started with AUTO Battle runtime.'
}

try {
    if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
        $GameDirectory = Split-Path -Parent $script:ModRoot
    }
    $GameDirectory = [IO.Path]::GetFullPath($GameDirectory)
    $installedVersion = Get-InstalledVersion
    try {
        $remote = Get-RemoteReleaseInfo
        $remoteVersion = [Version]([string]$remote.version)
        $state = Read-JsonFile $script:StatePath
        $isIgnored = $null -ne $state -and [string]$state.ignoredVersion -ceq [string]$remote.version
        if ($remoteVersion -gt $installedVersion -and -not $isIgnored) {
            $script:Choice = 'install'
            if (-not $Silent) {
                Show-UpdateNotice ([string]$remote.version)
            }
            if ($script:Choice -eq 'skip') {
                Write-UpdateState ([string]$remote.version) 'user-skipped'
                Write-AutoLog "User skipped v$($remote.version)."
            } elseif (-not (Install-RuntimeUpdate $remote)) {
                Write-UpdateState ([string]$remote.version) 'apply-failed'
            }
        } else {
            Write-AutoLog "Installed v$installedVersion is current, unavailable remotely, or v$($remote.version) was explicitly skipped."
        }
    } catch {
        # Internet errors and a bad release must never block the local mod.
        Write-AutoLog "Update check failed open: $($_.Exception.Message)"
    }
    if ($NoGameStart) {
        Write-AutoLog 'Bootstrap verification completed without starting the game.'
    } else {
        Start-DeadWeight $GameDirectory
    }
} catch {
    Write-AutoLog "Bootstrap failed: $($_.Exception.Message)"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("Dead Weight AUTO Battle could not start.`n$($_.Exception.Message)", 'Dead Weight - AUTO Battle') | Out-Null
    } catch { }
    exit 1
}
