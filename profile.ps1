Clear-Host # Clear PowerShell banner

# Configuration
$profileUrl = 'https://raw.githubusercontent.com/koresent/pwsh-profile/main/profile.ps1'
$checkUrl = ([System.Uri]$profileUrl).Host
$updateInterval = 7 # Days
$configDir = Split-Path $PROFILE.CurrentUserCurrentHost -Parent
$configPath = "$configDir\config.yml"
$statusPath = "$configDir\.status.json"
$oldPwsh = if ($PSVersionTable.PSVersion.Major -eq 5) { $true } else { $false }
$globalInstallFilter = "system32|Program Files|7/modules"
$requiredModules = @(
    'Terminal-Icons',
    'PSReadLine',
    'PSFzf',
    'posh-git',
    'powershell-yaml'
)
$requiredPackages = @(
    'zoxide',
    'fzf',
    'bat',
    'neovim'
)

# Common functions
function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Update-Profile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileUrl,
        
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Status,
        
        [Parameter(Mandatory = $true)]
        [string]$StatusPath,
        
        [Parameter(Mandatory = $true)]
        [bool]$IsAdmin
    )
    
    if (Test-Connection -ComputerName $checkUrl -Count 1 -ErrorAction SilentlyContinue) {
        Write-Host "📡 Checking for profile updates..." -ForegroundColor Cyan

        $tempProfile = Join-Path ([System.IO.Path]::GetTempPath()) "profile_temp.ps1"

        if ($Status.updatePending -and (Test-Path $tempProfile)) {
            if ($IsAdmin) {
                Write-Host "🔄 Found a new version. Updating..." -ForegroundColor Magenta
                Copy-Item -Path $tempProfile -Destination $PROFILE.AllUsersAllHosts -Force -ErrorAction Stop
                Write-Host "✅ Profile updated successfully! Please restart PowerShell" -ForegroundColor Green
                $Status.pkgs = $false
                $Status.modules = $false
                $Status.updatePending = $false
                $Status | ConvertTo-Json | Out-File $StatusPath -Force
            }
            else {
                Write-Host "⚠️ A new profile version was found, but it can’t be updated without admin rights. Restart PowerShell as administrator" -ForegroundColor Yellow
            }
        }
        else {
            try {
                $currentHash = Get-FileHash -Path $PROFILE.AllUsersAllHosts -Algorithm SHA256

                try {
                    Invoke-RestMethod -Uri $ProfileUrl -OutFile $tempProfile -ErrorAction Stop
                }
                catch {
                    Write-Host "😞 Remote server returned an error: $($_.Exception.StatusCode)" -ForegroundColor Yellow
                    return
                }

                $remoteHash = Get-FileHash -Path $tempProfile -Algorithm SHA256
        
                if ($currentHash -ne $remoteHash) {
                    if ($IsAdmin) {
                        Write-Host "🔄 Found a new version. Updating..." -ForegroundColor Magenta
                        Copy-Item -Path $tempProfile -Destination $PROFILE.AllUsersAllHosts -Force -ErrorAction Stop
                        Write-Host "✅ Profile updated successfully! Please restart PowerShell" -ForegroundColor Green
                        $Status.pkgs = $false
                        $Status.modules = $false
                        $Status | ConvertTo-Json | Out-File $StatusPath -Force
                    }
                    else {
                        Write-Host "⚠️ A new profile version was found, but it can’t be updated without admin rights. Restart PowerShell as administrator" -ForegroundColor Yellow
                        $Status.updatePending = $true
                        $Status | ConvertTo-Json | Out-File $StatusPath -Force
                    }
                }
                else {
                    Write-Host "✅ Profile is up to date" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "❌ Failed to update profile" -ForegroundColor Yellow
            }
        }
    }
    elseif (!($Status.updatePending)) {
        $Status.updatePending = $true
        $Status | ConvertTo-Json | Out-File $StatusPath -Force
    }
}

# Permission check
if ($IsWindows -or $oldPwsh) {
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $isAdmin = $true
    } 
}
elseif ($IsLinux) {
    if ((Invoke-Expression 'id -u') -eq '0') { 
        $isAdmin = $true
    }
}
else {
    throw "❌ macOS unsupported"
}

# Make sure the required directories exist
@("$(Split-Path $PROFILE.AllUsersAllHosts -Parent)", $configDir) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

# Create status file
if (!(Test-Path $statusPath)) {
    @{
        pkgs          = $false
        modules       = $false
        updatePending = $false
        lastCheck     = $null
    } | ConvertTo-Json | Out-File $statusPath
}
if ($IsWindows -or $oldPwsh) {
    $statusFile = Get-Item $statusPath -Force
    $statusFile.Attributes = $statusFile.Attributes -band (-bnot [System.IO.FileAttributes]::Hidden)
}

# Load status file
$status = Get-Content $statusPath | ConvertFrom-Json

# Windows-specific block
if ($IsWindows -or $oldPwsh) {
    
    # Install package manager if not installed
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        if ($isAdmin) {
            Write-Host "⬇️ Installing Chocolatey package manager..." -ForegroundColor Cyan
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        }
        else {
            throw "❌ It is not possible to install package manager. Restart PowerShell as an admin to continue"
        }
    }

    # Installing required packages
    if ($status.pkgs -eq $false) {
        #$packagesInstalled = $false
        foreach ($pkg in $requiredPackages) {
            if (!(choco list -e -r $pkg | Where-Object { $_ -match $pkg })) {
                if ($isAdmin) {
                    choco install $pkg -y --no-progress
                    #$packagesInstalled = $true
                }
                else {
                    throw "❌ It is not possible to install required packages. Restart PowerShell as an admin to continue"
                }
            }
        }
        #if ($packagesInstalled) {
        #    Write-Host "🔄 Updating environment variables..." -ForegroundColor Yellow
        #}
        $status.pkgs = $true
        $status | ConvertTo-Json | Out-File $statusPath
    }
}
# Linux-specific block
elseif ($isAdmin) {
    $pkgMgr = $null
    $installCmd = $null
    $checkCmd = $null

    if (Get-Command apt-get -ErrorAction SilentlyContinue) {
        $pkgMgr = "apt-get"
        $installCmd = "install -y"
        $checkCmd = { param($p) dpkg -s $p *>$null }
        if (!(Test-Path "/var/lib/apt/periodic/update-success-stamp")) { apt-get update }
    }
    elseif (Get-Command dnf -ErrorAction SilentlyContinue) {
        $pkgMgr = "dnf"
        $installCmd = "install -y"
        $checkCmd = { param($p) rpm -q $p *>$null }
    }
    elseif (Get-Command pacman -ErrorAction SilentlyContinue) {
        $pkgMgr = "pacman"
        $installCmd = "-S --noconfirm"
        $checkCmd = { param($p) pacman -Qi $p *>$null }
    }
    elseif (Get-Command zypper -ErrorAction SilentlyContinue) {
        $pkgMgr = "zypper"
        $installCmd = "install -n"
        $checkCmd = { param($p) rpm -q $p *>$null }
    }
    else {
        throw "❌ Unsupported Linux distribution. Could not find apt, dnf, pacman, or zypper."
    }

    if ($status.pkgs -eq $false) {
        foreach ($pkg in $requiredPackages) {
            if (!(& $checkCmd $pkg)) {
                Write-Host "⬇️ Installing $pkg via $pkgMgr..." -ForegroundColor Cyan
            
                $fullCommand = "$pkgMgr $installCmd $pkg"
                Invoke-Expression $fullCommand
            
                if ($LASTEXITCODE -ne 0) {
                    throw "❌ Failed to install $pkg using $pkgMgr."
                }
            }
            $status.pkgs = $true
            $status | ConvertTo-Json | Out-File $statusPath
        }
    }
}
else {
    throw "❌ It is not possible to install required packages. Restart PowerShell as root to continue"
}

# Install required modules
if (!($status.modules)) {
    $allModulesInstalled = $true
    $requiredModules | ForEach-Object {
        if (!(Get-Module -ListAvailable -Name $_ | Where-Object { $_.ModuleBase -match $globalInstallFilter })) {
            if ($isAdmin) {
                try {
                    Install-Module -Name $_ -Scope AllUsers -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                }
                catch {
                    Write-Host "⚠️ Failed to install module $_. Will try again on next launch." -ForegroundColor Yellow
                    $allModulesInstalled = $false
                }
            }
            else {
                throw "❌ It is not possible to install the required modules. Restart PowerShell as an admin to continue"
            }
        }
    }
    if ($allModulesInstalled) {
        $status.modules = $true
        $status | ConvertTo-Json | Out-File $statusPath
    }
}

# Import modules
$requiredModules | ForEach-Object {
    try { Import-Module $_ -ErrorAction Stop } catch {}
}

# Check profile updates
$checkNeeded = $false
if ($null -eq $status.lastCheck) {
    $checkNeeded = $true
}
elseif ($status.updatePending) {
    $checkNeeded = $true
}
else {
    $lastCheckDate = [datetime]::ParseExact($status.lastCheck, 'yyyy-MM-dd', $null)
    if (((Get-Date) - $lastCheckDate).TotalDays -ge $updateInterval) {
        $checkNeeded = $true
    }
}

if ($checkNeeded) {
    Update-Profile -ProfileUrl $profileUrl -Status $status -StatusPath $statusPath -IsAdmin $isAdmin
    if (!($status.updatePending)) {
        $status.lastCheck = (Get-Date).ToString('yyyy-MM-dd')
        $status | ConvertTo-Json | Out-File -FilePath $statusPath -Force
    }
}

# Template config
if (!(Test-Path $configPath)) {
    ConvertTo-Yaml @{
        editor       = 'nvim'    # Default text editor
        pager        = 'bat'     # Default pager
        editMode     = 'Windows' # Edit mode for PSReadLine: Emacs, Vi, Windows
        historyCount = 10000     # History items count
    } | Out-File $configPath
}

# Load config
$config = ConvertFrom-Yaml (Get-Content $configPath -Raw)

# Preferences
$env:EDITOR = $config.editor
$env:VISUAL = $config.editor
$env:PAGER = $config.pager

# PSReadLine configuration
Set-PSReadLineOption -EditMode $config.editMode -HistoryNoDuplicates -HistorySearchCursorMovesToEnd -MaximumHistoryCount $config.historyCount -ShowToolTips -BellStyle Visual -HistorySaveStyle SaveIncrementally -ViModeIndicator Cursor -PredictionViewStyle ListView -PredictionSource HistoryAndPlugin

# PSFzf configuration
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' `
                -PSReadlineChordReverseHistory 'Ctrl+r' `
                -PSReadlineChordSetLocation 'Alt+c' `
                -PSReadlineChordReverseHistoryArgs 'Alt+a'

# Prompt
function prompt {
    $runTime = 0
    $lastCommand = Get-History -Count 1

    if ($lastCommand) {
        $runTime = ($lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime).TotalSeconds
    }

    if ($runTime -ge 60) {
        $ts = [timespan]::fromseconds($runTime)
        $min, $sec = ($ts.ToString("mm\:ss")).Split(":")
        $elapsedTime = "$min min $sec sec"
    }
    else {
        $elapsedTime = "$([math]::Round($runTime, 2)) sec"
    }

    $global:GitPromptSettings.DefaultPromptPath.ForegroundColor = [ConsoleColor]::Yellow
    $global:GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true

    $global:GitPromptSettings.DefaultPromptBeforeSuffix.Text = " [$elapsedTime]"
    $global:GitPromptSettings.DefaultPromptBeforeSuffix.ForegroundColor = [ConsoleColor]::Magenta

    if ($isAdmin) {
        $global:GitPromptSettings.DefaultPromptSuffix.Text = " > "
        $global:GitPromptSettings.DefaultPromptSuffix.ForegroundColor = [ConsoleColor]::Red
    }
    else {
        $global:GitPromptSettings.DefaultPromptSuffix.Text = " > "
        $global:GitPromptSettings.DefaultPromptSuffix.ForegroundColor = [ConsoleColor]::Green
    }

    & $GitPromptScriptBlock
}

# Windows specific aliases
if ($IsWindows -or $oldPwsh) {
    function Get-Ports { netstat }
    function unzip {
        param(
            [Parameter(Mandatory = $true)]
            [string]$p,
            
            [string]$d = $PWD.Path
        )
        Expand-Archive -Path $p -DestinationPath $d -Force
    }
    
}
# Linux specific aliases
else {
    function Get-Ports { ss -ap }
    function cls { Clear-Host }
    function web { Set-Location /var/www/html }
    function x { chmod +x }
}

# This alias is needed because in Linux ls is a separate program, not an alias to Get-ChildItem
function l { Get-ChildItem -Force }

# Quickly jump to upper directories
function .. { Set-Location .. }
function ... { Set-Location ... }
function .... { Set-Location .... }
function ..... { Set-Location ..... }

# Jump to home
function h { Set-Location ~ }

# Count files in directory
function count { (Get-ChildItem -Force).Count }

# Editor alias
function e {
    if ($null -or [string]::IsNullOrWhiteSpace($env:EDITOR)) {
        Write-Error "The EDITOR variable is not set"
        return
    }
    
    & $env:EDITOR @args
}

# Zoxide + Get-ChildItem
function c ($path) {
    z $path; if ($?) {
        Get-ChildItem -Force
    }
}

# Remembering the commands for unpacking different types of archives is no longer necessary
function extract ($archive) {
    switch -Wildcard ($archive) {
        "*.tar.bz2" { tar xvjf $archive }
        "*.tar.gz" { tar xvzf $archive }
        "*.bz2" { bunzip2 $archive }
        "*.rar" { rar x $archive }
        "*.gz" { gunzip $archive }
        "*.tar" { tar xvf $archive }
        "*.tbz2" { tar xvjf $archive }
        "*.tgz" { tar xvzf $archive }
        "*.zip" { unzip $archive }
        "*.Z" { uncompress $archive }
        "*.7z" { 7z x $archive }
        default { Write-Output "Don't know how to extract $archive..." }
    }
}

# Get public IP
function Get-PublicIP {
    (Invoke-WebRequest http://ifconfig.me/ip).Content
}

# Hide status file
if ($IsWindows -or $oldPwsh) {
    $statusFile = Get-Item $statusPath -Force
    $statusFile.Attributes = $statusFile.Attributes -bor [System.IO.FileAttributes]::Hidden
}

# Should be in the end of the profile
if (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}