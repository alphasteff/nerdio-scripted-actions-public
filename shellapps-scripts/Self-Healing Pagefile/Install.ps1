#name: Self-Healing Pagefile
#description: Self-Healing Pagefile for v6 VM Skus
#execution mode: Combined
#tags: baseVISION AG

<# Notes:

Use this script to install the Self-Healing Pagefile solution on a VM. The script will copy the Set-Pagefile.ps1 script to the local disk and create a scheduled task to run the script at startup. The script will also create a registry key to store the installed version of the solution.

#>

$ErrorActionPreference = 'Stop'

$fileName = 'Set-Pagefile.ps1'
$targetpath = "$Env:ScriptDir"

$Context.Log('Install Self-Healing Pagefile')

[string]$Script:sourceFilePath = $Context.GetAttachedBinary($Context.TargetVersion)
$destinationFilePath = Join-Path $targetpath $fileName

$Context.Log("SourceFilePath: " + $sourceFilePath)
$Context.Log("DestinationFilePath: " + $destinationFilePath)

# Copy the script to the local disk
Copy-Item -Path $sourceFilePath -Destination $destinationFilePath -Force

# Create a scheduled task to run the script at startup
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$destinationFilePath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
Register-ScheduledTask -TaskName 'Packer-SetPagefile' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

##*===============================================
##* POST-INSTALLATION
##*===============================================
# Create the registry key and set the version
$basePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$productCode = 'Self-Healing Pagefile'
$programRegistryPath = Join-Path $basePath $productCode

New-Item -Path $programRegistryPath -Force -ErrorAction SilentlyContinue
New-ItemProperty -Path $programRegistryPath -Name 'InstalledVersion' -Value $Context.TargetVersion -PropertyType String -Force