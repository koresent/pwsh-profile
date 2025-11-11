# Configuration
$profileUrl = 'https://raw.githubusercontent.com/koresent/pwsh-profile/main/profile.ps1'
$checkUrl = ([System.Uri]$profileUrl).Host
$profilePath = $PROFILE.AllUsersAllHosts
$profileDir = Split-Path $profilePath -Parent

# Permission check
if ($IsWindows -or ($PSVersionTable.PSVersion.Major -eq 5)) {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "❌ This script requires Administrator privileges"
    } 
}
elseif ($IsLinux) {
    if ((Invoke-Expression 'id -u') -ne '0') { throw "❌ This script requires root privileges" }
}
else {
    throw "❌ macOS unsupported"
}

# Network check
try {
    $null = Test-Connection -ComputerName $checkUrl -Count 1 -ErrorAction Stop
}
catch {
    throw "❌ Could not connect to $checkUrl. Please check your internet connection."
}

Write-Host "🔰 Starting Profile Setup..." -ForegroundColor Cyan

# Backup existing profile 
if (Test-Path $profilePath) {
    $backupPath = "$profileDir/oldprofile_$(Get-Date -Format 'yyyy-MM-dd').ps1"
    try { Move-Item -Path $profilePath -Destination $backupPath -Force -ErrorAction Stop } catch { throw "❌ Unable to create a backup of the profile: $_" }
    Write-Host "📦 Existing profile backed up to: $backupPath" -ForegroundColor Yellow
}
# Ensure directory exists
else {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    Write-Host "📂 Profile directory created"
}

# Download Profile
Write-Host "⬇️ Downloading profile..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri $profileUrl -OutFile $profilePath -ErrorAction Stop
    Write-Host "✅ Profile successfully installed to $profilePath" -ForegroundColor Green
}
catch {
    Write-Error "❌ Failed to download profile! Error: $_"
    if ($backupPath) {
        Move-Item -Path $backupPath -Destination $profilePath -Force
        Write-Warning "🔄 Restored original profile due to download failure."
    }
    break
}

Write-Host "🎉 Setup complete! Please restart your PowerShell session." -ForegroundColor Green