$ErrorActionPreference = "Stop"

Write-Host "=== Lumea Steam Plugin Installer ===" -ForegroundColor Cyan
Write-Host ""

# ==================================================
#   Millennium Direct Install (No Git Required)
#   Based on https://github.com/SteamClientHomebrew/Millennium
# ==================================================

$GITHUB_ACCOUNT = "SteamClientHomebrew/Millennium"
$RELEASES_URI = "https://api.github.com/repos/$GITHUB_ACCOUNT/releases"
$DOWNLOAD_URI = "https://github.com/$GITHUB_ACCOUNT/releases/download"

function Write-Log { param([string]$Message) Write-Host $Message }

function Get-SteamPath {
    $regPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )
    foreach ($path in $regPaths) {
        try {
            $reg = Get-ItemProperty -Path $path -ErrorAction Stop
            if ($reg.InstallPath -and (Test-Path -LiteralPath $reg.InstallPath)) {
                return $reg.InstallPath
            }
        } catch { continue }
    }
    $commonPaths = @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "$env:LOCALAPPDATA\Steam"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Get-LatestMillenniumRelease {
    try {
        $releases = Invoke-RestMethod -Uri $RELEASES_URI -Headers @{ "User-Agent" = "LumeaSteamPluginInstaller" }
        $release = $releases | Where-Object { -not $_.prerelease } | Select-Object -First 1
        if (-not $release) {
            $release = $releases | Select-Object -First 1
        }
        return $release
    } catch {
        Write-Log "Failed to fetch Millennium releases: $_"
        return $null
    }
}

function Install-Millennium {
    param([string]$SteamPath)
    
    $release = Get-LatestMillenniumRelease
    if (-not $release) {
        throw "Could not find Millennium release"
    }
    
    $tag = $release.tag_name
    $version = $tag -replace '^v', ''
    Write-Log "Found Millennium $tag"
    
    # Windows asset names
    $assetNames = @(
        "millennium-v$version-windows-x86_64.zip",
        "millennium-v$version-win32.zip",
        "millennium-v$version-windows.zip",
        "millennium-$version-windows-x86_64.zip",
        "millennium-$version-win32.zip",
        "millennium-windows-x86_64.zip",
        "millennium-windows.zip"
    )
    
    $asset = $null
    foreach ($name in $assetNames) {
        $asset = $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($asset) { break }
    }
    
    if (-not $asset) {
        # Try pattern matching
        $asset = $release.assets | Where-Object { $_.name -match 'windows.*\.zip$' -or $_.name -match 'win32.*\.zip$' -or $_.name -match 'win64.*\.zip$' } | Select-Object -First 1
    }
    
    if (-not $asset) {
        throw "Could not find Windows release asset. Available: $($release.assets.name -join ', ')"
    }
    
    Write-Log "Downloading $($asset.name)..."
    $downloadUrl = $asset.browser_download_url
    $tempDir = Join-Path $env:TEMP "millennium-install"
    $zipPath = Join-Path $tempDir $asset.name
    
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        throw "Failed to download Millennium: $_"
    }
    
    Write-Log "Extracting Millennium..."
    $extractPath = Join-Path $tempDir "extracted"
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    
    # Find millennium.dll and related files
    $millenniumFiles = Get-ChildItem -Path $extractPath -Recurse -Include "millennium.dll", "libmillennium*.dll", "millennium.exe" -ErrorAction SilentlyContinue
    
    if (-not $millenniumFiles) {
        # List what we found
        Write-Log "Contents of extracted archive:"
        Get-ChildItem -Path $extractPath -Recurse | ForEach-Object { Write-Log "  $($_.FullName)" }
        throw "Could not find Millennium files in the archive"
    }
    
    Write-Log "Installing Millennium to Steam directory..."
    
    # Copy all files from the extracted root to Steam path
    $sourceRoot = if ($millenniumFiles[0].DirectoryName -ne $extractPath) { $millenniumFiles[0].DirectoryName } else { $extractPath }
    
    Get-ChildItem -Path $sourceRoot | ForEach-Object {
        $dest = Join-Path $SteamPath $_.Name
        try {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
            Write-Log "  Installed: $($_.Name)"
        } catch {
            Write-Log "  Warning: Could not install $($_.Name): $_"
        }
    }
    
    # Cleanup
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Log "Millennium installation completed!"
}

# ---------------------------
# Detect Steam install path
# ---------------------------
Write-Host "Detecting Steam installation..." -ForegroundColor Cyan

$steamInstallPath = Get-SteamPath

if (-not $steamInstallPath) {
    Write-Host "Steam installation not detected." -ForegroundColor Red
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
    try {
        Install-Millennium -SteamPath $steamInstallPath
    } catch {
        Write-Host "Failed to install Millennium: $_" -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to close this window..." | Out-Null
        return
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
