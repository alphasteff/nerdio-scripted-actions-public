#name: Exclude users from FSLogix
#description: Exclude user from FSLogix Romaing Profile.
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to exclude the local administrator from Romaing Profile.

#>

$ErrorActionPreference = 'Stop'

$exclude = @()

If (![string]::IsNullOrEmpty($SecureVars.LocalAdministrator)) {
    $localAdministrator = $SecureVars.LocalAdministrator.Split(",").Trim()
    $exclude += $localAdministrator
}

If (![string]::IsNullOrEmpty($SecureVars.FSLogixExcludeList)) {
    $excludedList = $SecureVars.FSLogixExcludeList.Split(",").Trim()
    $exclude += $excludedList
}

try {
    Write-Output ("Add users to Exclude Groups: " + ($exclude | Out-String))
    Add-LocalGroupMember -Group "FSLogix ODFC Exclude List" -Member $exclude -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "FSLogix Profile Exclude List" -Member $exclude -ErrorAction SilentlyContinue

} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Throw $_
}
