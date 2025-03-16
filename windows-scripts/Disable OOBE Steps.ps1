#name: Disable OOBE Steps
#description: Disables OOBE steps during the first logon
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Since Windows 11 24H2 Multi User the OOBE steps are shown during the first logon as an Administrator. Before I did not see them.

This script will disable the following OOBE setps during the first logon:
- "Let Microsoft and apps use your location"
- "Find my device"
- "Send diagnostic data to Microsoft"
- "Improve inking & typing"
- "Get tailored experiences with diagnostic data"
- "Let apps use advertising ID"
- "Let Microsoft and apps use your location"

The following blog post was the answer to the question how to disable the OOBE steps:
https://call4cloud.nl/autopilot-device-preparation-hide-privacy-settings/

#>


$registryPaths = @{
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"            = @{
        "DisablePrivacyExperience" = 1
        "DisableVoice"             = 1
        "PrivacyConsentStatus"     = 1
        "Protectyourpc"            = 3
        "HideEULAPage"             = 1
    }
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" = @{
        "EnableFirstLogonAnimation" = 1
    }
}

foreach ($path in $registryPaths.Keys) {
    foreach ($name in $registryPaths[$path].Keys) {
        New-ItemProperty -Path $path -Name $name -Value $registryPaths[$path][$name] -PropertyType DWord -Force
    }
}
