#name: Configure session lock behavior
#description: Configure the session lock behavior
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

When single sign-on is enabled and the remote session is locked, either by the user or by policy,
the session is instead disconnected and a dialog is shown to let users know they were disconnected.
Users can choose the Reconnect option from the dialog when they are ready to connect again.
This is done for security reasons and to ensure full support of passwordless authentication.

If you prefer to show the remote lock screen instead of disconnecting the session,
you can change the behavior by setting the following registry key:

Key: HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services
Type: REG_DWORD
Value name: fdisconnectonlockmicrosoftidentity

0	Show the remote lock screen.
1	Disconnect the session.

More information, like supported OS versions, can be found here:
https://learn.microsoft.com/azure/virtual-desktop/configure-session-lock-behavior

More additional background information can be found here:
https://learn.microsoft.com/en-us/azure/virtual-desktop/configure-single-sign-on?tabs=registry#session-lock-behavior

#>

param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Set the session lock behavior. 0 = Show the remote lock screen. 1 = Disconnect the session."
    )]
    [ValidateSet('0', '1')]
    [int]$lockScreen = 1
)

$ErrorActionPreference = 'Stop'

Write-Output "Configure session lock behavior"

Write-Output "Setting session lock behavior to $lockScreen"

$regPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
$regName = "fdisconnectonlockmicrosoftidentity"
$regValue = $lockScreen

try {
    If (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force
    }

    Write-Output "Setting registry key: $regPath\$regName to $regValue"
    If (Get-ItemProperty -Path $regpath -Name $regName -ErrorAction SilentlyContinue) {
        Write-Output "Registry key $regPath\$regName already exists. Updating value to $regValue"
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type DWORD
    } Else {
        Write-Output "Registry key $regPath\$regName does not exist. Creating key with value $regValue"
        New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType DWORD
    }


} catch {
    Write-Output "Encountered error. $_"
    Throw $_
}

Write-Output "Session lock behavior configured"
