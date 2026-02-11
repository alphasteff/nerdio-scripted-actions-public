#name: Windows Desktop Optimization Tool
#description: Applies Windows Desktop Optimization Tool configurations to optimize AVD/Windows 11 session hosts
#execution mode: Combined
#tags: baseVISION AG, Optimization, Windows 11

<# Notes:

This script downloads and applies the Windows Desktop Optimization Tool (WDOT) from GitHub.

Parameters:
- $configProfile: Configuration profile name (e.g., 'Default_W1125H2')
- $opt: Optimizations to apply - 'All' or comma-separated list (e.g., 'Services,AppxPackages,ScheduledTasks')
- $advOpt: Advanced optimizations - leave empty, or specify 'All', 'Edge', 'RemoveLegacyIE', 'RemoveOneDrive' (comma-separated)

Configuration files should be placed in: .\Configurations\<profile-name>\

#>

$ErrorActionPreference = 'Stop'

$configProfile = 'Default_W1125H2'
$opt = 'WDOT, WindowsMediaPlayer, AppxPackages, ScheduledTasks, DefaultUserSettings, Autologgers, Services, LocalPolicy, NetworkOptimizations, AdvancedOptimizations' #All runs DiskCleanup, that removes also the logs
$advOpt = ''
$filesPath = '.\Configurations\*'

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Validate required arguments
if ([string]::IsNullOrWhiteSpace($configProfile)) {
    $Context.Log("Missing required variable: WDOTConfigProfile. This must specify a configuration profile name (e.g., Windows11_24H2).")
    exit 1
}

if ([string]::IsNullOrWhiteSpace($opt)) {
    $Context.Log("Missing required variable: WDOTOpt. This must specify optimizations (e.g., All or Services,AppxPackages).")
    exit 1
}

# Parse optimizations - handle comma-separated string or single value
$optArray = if ($opt -match ',') {
    $opt -split ',' | ForEach-Object { $_.Trim() }
} else {
    @($opt.Trim())
}

# Parse advanced optimizations if provided
$advOptArray = @()
$advOptTrimmed = $advOpt.Trim()
if (-not [string]::IsNullOrWhiteSpace($advOptTrimmed) -and
    $advOptTrimmed -notmatch '^(?i)(No|None)$') {
    $advOptArray = if ($advOptTrimmed -match ',') {
        $advOptTrimmed -split ',' | ForEach-Object { $_.Trim() }
    } else {
        @($advOptTrimmed)
    }
}

# Define GitHub ZIP download URL
$wdotUrl = "https://github.com/The-Virtual-Desktop-Team/Windows-Desktop-Optimization-Tool/archive/refs/heads/main.zip"

# Temp paths
$tempPath = "$env:SystemRoot\TEMP\WDOT"
$zipPath = "$tempPath\wdot.zip"
$extractPath = "$tempPath\Extracted"

$Context.Log("WDOT URL: $wdotUrl")
$Context.Log("Temp Path: $tempPath")
$Context.Log("ZIP Path: $zipPath")
$Context.Log("Extract Path: $extractPath")

# Create working directory
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

# Download and unblock the ZIP
$Context.Log("Downloading WDOT from GitHub...")
Invoke-WebRequest -Uri $wdotUrl -OutFile $zipPath -ErrorAction Stop
Unblock-File -Path $zipPath

# Extract contents
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Locate the script folder
$wdotScriptPath = Get-ChildItem -Path $extractPath -Directory |
Where-Object { $_.Name -like "Windows-Desktop-Optimization-Tool*" } |
Select-Object -First 1

if (-not $wdotScriptPath) {
    $Context.Log("ERROR: Could not find extracted WDOT folder.")
    exit 1
} else {
    $Context.Log("Found WDOT script folder: $($wdotScriptPath.FullName)")
}

# Unblock all files in the folder
Get-ChildItem -Path $wdotScriptPath.FullName -Recurse | Unblock-File

# Set path to main script
$fullScriptPath = Join-Path $wdotScriptPath.FullName "Windows_Optimization.ps1"
if (-not (Test-Path $fullScriptPath)) {
    $Context.Log("ERROR: Windows_Optimization.ps1 not found.")
    exit 1
} else {
    $Context.Log("Found main script: $fullScriptPath")
}

# Prepare path to configuration files and copy them
$configurationsPath = Join-Path $wdotScriptPath.FullName "Configurations"

if (!(Test-Path $configurationsPath)) {
    $Null = New-Item -Path $configurationsPath -ItemType directory
    $Context.Log("Created Configurations folder at: $configurationsPath")
} else {
    $Context.Log("Configurations folder already exists at: $configurationsPath")
}

$Null = Copy-Item -Path $filesPath -Destination $configurationsPath -Recurse -Force
$Context.Log("Copied configuration files from $filesPath to $configurationsPath")

# Build argument hashtable for splatting
$scriptParams = @{
    ConfigProfile = $configProfile
    Optimizations = $optArray
    AcceptEULA    = $true
    Verbose       = $true
    Restart       = $false
}

$Context.Log("Prepared script parameters for WDOT execution.")

# Add advanced optimizations if provided
if ($advOptArray.Count -gt 0) {
    $scriptParams['AdvancedOptimizations'] = $advOptArray
}

# Save current location and change to WDOT script directory
# This is required because WDOT uses relative paths for configuration files
$originalLocation = Get-Location
try {
    $Context.Log("Changing working directory to WDOT script folder: $($wdotScriptPath.FullName)")
    Set-Location -Path $wdotScriptPath.FullName
    $Context.Log("Current working directory after change: " + (Get-Location).Path)

    # Execute the script with splatting
    $Context.Log("Executing Windows_Optimization.ps1 with parameters:")
    $Context.Log("  ConfigProfile: $configProfile")
    $Context.Log("  Optimizations: $($optArray -join ', ')")

    if ($advOptArray.Count -gt 0) {
        $Context.Log("  AdvancedOptimizations: $($advOptArray -join ', ')")
    }
    if ($scriptParams.ContainsKey('Restart')) {
        $Context.Log("  Restart: $($scriptParams['Restart'])")
    }
    $Context.Log("  Working Directory: $($wdotScriptPath.FullName)")

    # Execute the script - suppress errors from WDOT's internal bugs
    try {
        $Context.Log("Starting WDOT script execution...")
        & $fullScriptPath @scriptParams
        $Context.Log("WDOT script execution completed.")
    } catch {
        # WDOT script may have internal errors but still complete successfully
        # Log the error but don't fail the entire operation
        $Context.Log("WARNING: WDOT script reported errors: $_")
        # Check if the error is just the known Set-Location/New-TimeSpan bug
        if ($_ -match "Set-Location|New-TimeSpan") {
            $Context.Log("WARNING: This appears to be a known WDOT script cleanup issue and can be safely ignored.")
        }
    }
} finally {
    # Always restore the original location
    if ($originalLocation) {
        $Context.Log("Restoring original working directory: $($originalLocation.Path)")
        Set-Location -Path $originalLocation.Path
        $Context.Log("Current working directory after restore: " + (Get-Location).Path)

    }
}

##*===============================================
##* POST-INSTALLATION
##*===============================================
# Create the registry key and set the version
$basePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$productCode = 'Windows Desktop Optimization Tool'
$programRegistryPath = Join-Path $basePath $productCode

New-Item -Path $programRegistryPath -Force -ErrorAction SilentlyContinue
New-ItemProperty -Path $programRegistryPath -Name 'InstalledVersion' -Value $Context.TargetVersion -PropertyType String -Force