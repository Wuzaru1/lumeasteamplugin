$ErrorActionPreference = "Stop"

Write-Host "=== Lumea Steam Plugin Installer ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------
# Detect Steam install path
# ---------------------------
Write-Host "Detecting Steam installation path from registry..." -ForegroundColor Cyan

$steamRegPath = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
$steamInstallPath = $null

try {
    $reg = Get-ItemProperty -Path $steamRegPath -ErrorAction Stop
    $steamInstallPath = $reg.InstallPath
} catch {
    $steamInstallPath = $null
}

if (-not $steamInstallPath -or -not (Test-Path -LiteralPath $steamInstallPath)) {
    Write-Host "Steam installation not detected." -ForegroundColor Red
    Write-Host "The registry key 'Computer\HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam' with value 'InstallPath' was not found or is invalid." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Steam must be installed before running this installer." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close this window..." | Out-Null
    return
}

Write-Host "Steam detected at: $steamInstallPath" -ForegroundColor Green

$pluginsDir = Join-Path $steamInstallPath "plugins"
if (-not (Test-Path -LiteralPath $pluginsDir)) {
    Write-Host "Creating plugins directory at '$pluginsDir'..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
}

# ---------------------------
# Check if Millennium exists
# ---------------------------
$millenniumDllPath = Join-Path $steamInstallPath "millennium.dll"

if (-not (Test-Path -LiteralPath $millenniumDllPath)) {
    Write-Host "Millennium not detected. Installing Millennium..." -ForegroundColor Yellow
    
    # Fetch latest Millennium installer from GitHub
    $millenniumOwner = "SteamClientHomebrew"
    $millenniumRepo = "Installer"
    $millenniumApiUrl = "https://api.github.com/repos/$millenniumOwner/$millenniumRepo/releases/latest"
    
    Write-Host "Fetching latest Millennium installer release..." -ForegroundColor Cyan
    try {
        $millenniumRelease = Invoke-RestMethod -Uri $millenniumApiUrl -Headers @{ "User-Agent" = "LumeaSteamPluginInstaller" }
    } catch {
        Write-Host "Failed to query GitHub for the latest Millennium installer release." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        Write-Host ""
        Read-Host "Press Enter to close this window..." | Out-Null
        return
    }
    
    # Find the .exe asset
    $millenniumAsset = $millenniumRelease.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1
    if (-not $millenniumAsset) {
        Write-Host "ERROR: Could not find an executable in the latest Millennium installer release." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to close this window..." | Out-Null
        return
    }
    
    $millenniumDownloadUrl = $millenniumAsset.browser_download_url
    $millenniumInstallerPath = Join-Path $env:TEMP $millenniumAsset.name
    
    Write-Host "Downloading Millennium installer from: $millenniumDownloadUrl" -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $millenniumDownloadUrl -OutFile $millenniumInstallerPath -UseBasicParsing
    } catch {
        Write-Host "Failed to download the Millennium installer." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        Write-Host ""
        Read-Host "Press Enter to close this window..." | Out-Null
        return
    }
    
    Write-Host "Running Millennium installer..." -ForegroundColor Cyan
    try {
        $process = Start-Process -FilePath $millenniumInstallerPath -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Write-Host "Millennium installer exited with code $($process.ExitCode)." -ForegroundColor Yellow
        }
        Write-Host "Millennium installation completed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to run Millennium installer." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        Write-Host ""
        Read-Host "Press Enter to close this window..." | Out-Null
        return
    } finally {
        # Clean up installer
        if (Test-Path -LiteralPath $millenniumInstallerPath) {
            Remove-Item -LiteralPath $millenniumInstallerPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "Millennium already installed." -ForegroundColor Green
}

# ---------------------------
# Fetch latest Lumea plugin release from GitHub
# ---------------------------
$owner = "Wuzaru1"
$repo = "lumeasteamplugin"
$assetName = "lumeasteamplugin.zip"
$apiUrl = "https://api.github.com/repos/$owner/$repo/releases/latest"

Write-Host "Fetching latest Lumea plugin release information..." -ForegroundColor Cyan
try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "LumeaSteamPluginInstaller" }
} catch {
    Write-Host "Failed to query GitHub for the latest release." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    Write-Host ""
    Read-Host "Press Enter to close this window..." | Out-Null
    return
}

$asset = $release.assets | Where-Object { $_.name -eq $assetName }
if (-not $asset) {
    Write-Host "ERROR: Could not find '$assetName' in the latest GitHub release." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close this window..." | Out-Null
    return
}

$downloadUrl = $asset.browser_download_url
$tempZip = Join-Path $env:TEMP $assetName

Write-Host "Downloading plugin archive from: $downloadUrl" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
} catch {
    Write-Host "Failed to download the plugin archive." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    Write-Host ""
    Read-Host "Press Enter to close this window..." | Out-Null
    return
}

# ---------------------------
# Install plugin into steam/plugins/lumeasteamplugin
# ---------------------------
$pluginFolderName = "lumeasteamplugin"
$pluginDestination = Join-Path $pluginsDir $pluginFolderName

# Remove any existing Lumea-related plugin folders/files (case-insensitive match on name)
Write-Host "Searching for existing Lumea plugin folders/files in '$pluginsDir'..." -ForegroundColor Cyan
try {
    $existingLumeaItems = Get-ChildItem -LiteralPath $pluginsDir -Force -ErrorAction Stop | Where-Object { $_.Name -match '(?i)lumea' }
    foreach ($item in $existingLumeaItems) {
        Write-Host "Removing '$($item.FullName)'" -ForegroundColor Yellow
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "WARNING: Failed to remove '$($item.FullName)'. Some old plugin files may remain." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "WARNING: Failed while scanning for existing Lumea plugin folders/files." -ForegroundColor Yellow
}

Write-Host "Extracting plugin to '$pluginDestination'..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $tempZip -DestinationPath $pluginDestination -Force
} catch {
    Write-Host "Failed to extract the plugin archive." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    Write-Host ""
    Read-Host "Press Enter to close this window..." | Out-Null
    return
} finally {
    if (Test-Path -LiteralPath $tempZip) {
        Remove-Item -LiteralPath $tempZip -Force
    }
}

# ---------------------------
# Restart / launch Steam
# ---------------------------
Write-Host "Restarting / launching Steam..." -ForegroundColor Cyan
try {
    $steamProcesses = Get-Process "steam" -ErrorAction SilentlyContinue
    if ($steamProcesses) {
        $steamProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Host "Warning: Failed to stop existing Steam processes (if any)." -ForegroundColor Yellow
}

$steamExePath = Join-Path $steamInstallPath "steam.exe"
if (Test-Path -LiteralPath $steamExePath) {
    try {
        Start-Process $steamExePath
    } catch {
        Write-Host "Warning: Failed to launch Steam from '$steamExePath'." -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: 'steam.exe' not found at '$steamExePath'." -ForegroundColor Yellow
}

# ---------------------------
# Done
# ---------------------------
Write-Host ""
Write-Host "Lumea Plugin Installation Successful" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close this window..." | Out-Null
