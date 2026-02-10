$basePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$productCode = 'Self-Healing Pagefile'
$programRegistryPath = Join-Path $basePath $productCode

# Check if the application is installed
if (!(Test-Path $programRegistryPath)) {
    $Context.Log("RegistryKey does not exist: " + $programRegistryPath)
    return $false
}

# Check if the instaled version has the correct value
$installedVersion = (Get-ItemProperty -Path $programRegistryPath -Name 'InstalledVersion').InstalledVersion

$Context.Log("InstalledVersion: " + $Context.TargetVersion)
$Context.Log("TargetVersion: " + $Context.TargetVersion)

if ($installedVersion -eq $Context.TargetVersion) {
    $Context.Log("Installed version is identical to the target version")
    return $true
} else {
    $Context.Log("Installed version is not the same as the target version")
    return $false
}