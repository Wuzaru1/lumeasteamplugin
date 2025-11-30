[CmdletBinding()]
param()

Write-Host "=== Lumea Steam Plugin Installer ===" -ForegroundColor Cyan

# Ensure TLS 1.2 for GitHub API
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Host "Warning: Failed to set TLS 1.2, GitHub requests may fail." -ForegroundColor Yellow
}

# --- Resolve Steam install path from registry ---

$steamPath = $null

$steamRegKeys = @(
    'HKCU:\Software\Valve\Steam',
    'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
)

foreach ($key in $steamRegKeys) {
    if (Test-Path $key) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($props.SteamPath -and (Test-Path $props.SteamPath)) {
                $steamPath = $props.SteamPath
                break
            }
        } catch {
            # Ignore and try next key
        }
    }
}

if (-not $steamPath) {
    Write-Host "Steam does not appear to be installed (no valid SteamPath in:" -ForegroundColor Red
    Write-Host "  HKCU:\Software\Valve\Steam or HKLM:\SOFTWARE\WOW6432Node\Valve\Steam)." -ForegroundColor Red
    Write-Host "Aborting installation." -ForegroundColor Red
    exit 1
}

Write-Host "Detected Steam path: $steamPath" -ForegroundColor Green

# Confirm steam.exe exists
$steamExe = Join-Path $steamPath 'steam.exe'
if (-not (Test-Path $steamExe)) {
    Write-Host "steam.exe was not found in '$steamPath'." -ForegroundColor Red
    Write-Host "The registry may be pointing to an invalid Steam install. Aborting." -ForegroundColor Red
    exit 1
}

# --- Check for Millennium (millenium.dll) next to steam.exe ---

$millenniumDll = Join-Path $steamPath 'millenium.dll'

if (-not (Test-Path $millenniumDll)) {
    Write-Host "Millennium (millenium.dll) was not found next to steam.exe in:" -ForegroundColor Red
    Write-Host "  $steamPath" -ForegroundColor Red
    Write-Host "Please install Millennium first, then re-run this installer." -ForegroundColor Yellow
    exit 1
}

Write-Host "Millennium detected at: $millenniumDll" -ForegroundColor Green

# --- Ensure plugins folder exists ---

$pluginsDir = Join-Path $steamPath 'plugins'

if (-not (Test-Path $pluginsDir)) {
    Write-Host "Plugins folder not found at '$pluginsDir'." -ForegroundColor Yellow
    Write-Host "Creating plugins folder..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    } catch {
        Write-Host "Failed to create plugins folder: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Plugins folder found at '$pluginsDir'." -ForegroundColor Green
}

# --- Download latest lumeasteamplugin.zip from GitHub ---

$apiUrl = 'https://api.github.com/repos/Wuzaru1/lumeasteamplugin/releases/latest'
Write-Host "Fetching latest Lumea Steam Plugin release info from GitHub..." -ForegroundColor Cyan

try {
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'LumeaSteamPluginInstaller' }
} catch {
    Write-Host "Failed to get release info from GitHub:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $releaseInfo.assets) {
    Write-Host "No assets were found in the latest GitHub release." -ForegroundColor Red
    Write-Host "Cannot continue installation." -ForegroundColor Red
    exit 1
}

$asset = $releaseInfo.assets |
    Where-Object { $_.name -eq 'lumeasteamplugin.zip' } |
    Select-Object -First 1

if (-not $asset) {
    Write-Host "The latest release does not contain 'lumeasteamplugin.zip'." -ForegroundColor Red
    Write-Host "Cannot continue installation." -ForegroundColor Red
    exit 1
}

$tempZip = Join-Path $env:TEMP 'lumeasteamplugin.zip'
Write-Host "Downloading lumeasteamplugin.zip to '$tempZip'..." -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -UseBasicParsing
} catch {
    Write-Host "Failed to download lumeasteamplugin.zip:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $tempZip)) {
    Write-Host "Download failed: '$tempZip' does not exist." -ForegroundColor Red
    exit 1
}

# --- Extract the zip directly into Steam\plugins ---

Write-Host "Extracting lumeasteamplugin.zip into '$pluginsDir'..." -ForegroundColor Cyan

try {
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $tempZip -DestinationPath $pluginsDir -Force
    } else {
        # Fallback for very old PowerShell versions without Expand-Archive
        $shell = New-Object -ComObject Shell.Application
        $zip   = $shell.NameSpace($tempZip)
        $dest  = $shell.NameSpace($pluginsDir)

        if (-not $zip -or -not $dest) {
            throw "Shell.Application could not open zip or destination."
        }

        $dest.CopyHere($zip.Items(), 0x10)  # 0x10 = respond "Yes to All" to any dialogs
    }
} catch {
    Write-Host "Failed to extract lumeasteamplugin.zip:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Clean up temp zip (best-effort)
try {
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
} catch {
    # ignore
}

Write-Host ""
Write-Host "Lumea Steam Plugin has been installed to:" -ForegroundColor Green
Write-Host "  $pluginsDir" -ForegroundColor Green
Write-Host ""
Write-Host "No changes were made to Millennium's version.json; the plugin files are" -ForegroundColor Green
Write-Host "already preformatted for Millennium and were just extracted as-is." -ForegroundColor Green
Write-Host ""
Write-Host "You can now launch Steam (with Millennium) and it should load the Lumea plugin." -ForegroundColor Green
