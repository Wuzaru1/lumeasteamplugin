$ErrorActionPreference = "Stop"

Write-Host "=== Lumea Steam Plugin Installer (PowerShell) ===" -ForegroundColor Cyan

# ---------------------------

# Detect Steam install path

# ---------------------------

Write-Host "Detecting Steam installation path..."

$SteamPaths = @(
"HKCU:\Software\Valve\Steam",
"HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
)

$SteamPath = $null
foreach ($reg in $SteamPaths) {
try {
$SteamPath = (Get-ItemProperty -Path $reg -ErrorAction Stop).SteamPath
if ($SteamPath -and (Test-Path $SteamPath)) { break }
} catch { }
}

if (-not $SteamPath) {
Write-Host "ERROR: Could not find Steam installation folder." -ForegroundColor Red
exit 1
}

Write-Host "Steam detected at: $SteamPath"

$PluginsDir = Join-Path $SteamPath "plugins"
if (-not (Test-Path $PluginsDir)) {
Write-Host "Creating plugins directory..."
New-Item -ItemType Directory -Path $PluginsDir | Out-Null
}

# ---------------------------

# Check if Millennium exists

# ---------------------------

$MillenniumDll = Join-Path $SteamPath "millenium.dll"
if (-not (Test-Path $MillenniumDll)) {
Write-Host "Millennium not detected. Installing Millennium..." -ForegroundColor Yellow
iwr -useb [https://steambrew.app/install.ps1](https://steambrew.app/install.ps1) | iex
} else {
Write-Host "Millennium already installed." -ForegroundColor Green
}

# ---------------------------

# Fetch latest GitHub release directly

# ---------------------------

$Owner = "Wuzaru1"
$Repo = "lumeasteamplugin"
$AssetName = "lumeasteamplugin.zip"

$ApiUrl = "[https://api.github.com/repos/$Owner/$Repo/releases/latest](https://api.github.com/repos/$Owner/$Repo/releases/latest)"
Write-Host "Fetching latest release info from GitHub..."
$Release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "PowerShell" }

$Asset = $Release.assets | Where-Object { $_.name -eq $AssetName }
if (-not $Asset) {
Write-Host "ERROR: Could not find plugin ZIP in latest release." -ForegroundColor Red
exit 1
}

$DownloadUrl = $Asset.browser_download_url
$TempZip = Join-Path $env:TEMP $AssetName

Write-Host "Downloading: $($Asset.name)"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempZip -UseBasicParsing

# ---------------------------

# Install plugin

# ---------------------------

Write-Host "Installing plugin..."
$PluginName = "LumeaPlugin"
$PluginPath = Join-Path $PluginsDir $PluginName

if (Test-Path $PluginPath) {
Write-Host "Removing old plugin version..."
Remove-Item -Recurse -Force $PluginPath
}

Expand-Archive -Path $TempZip -DestinationPath $PluginPath -Force
Remove-Item $TempZip
Write-Host "Plugin files extracted."

# ---------------------------

# Write version.json

# ---------------------------

$VersionDir = Join-Path $PluginPath "backend"
if (-not (Test-Path $VersionDir)) {
New-Item -ItemType Directory -Path $VersionDir | Out-Null
}

$VersionFile = Join-Path $VersionDir "version.json"
$VersionContent = @{ version = $Release.tag_name } | ConvertTo-Json
$VersionContent | Set-Content $VersionFile
Write-Host "Version saved to version.json"

# ---------------------------

# Restart Steam

# ---------------------------

Write-Host "Restarting Steam..."
Get-Process "steam" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process "$SteamPath\steam.exe"

# ---------------------------

# Done

# ---------------------------

Write-Host "Lumea Steam Plugin installed successfully!" -ForegroundColor Green
Write-Host "You may now launch Steam normally."
