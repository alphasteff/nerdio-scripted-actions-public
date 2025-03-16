#name: Exclude and Include FSLogix users
#description: Exclude and Include user for FSLogix Romaing Profile.
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to exclude the local administrator from Romaing Profile. You can also exclude other users by adding them to the ExcludeList.
It is also possible to include users by adding them to the IncludeList.

#>

$ErrorActionPreference = 'Stop'

$exclude = @()
$include = @()

If (![string]::IsNullOrEmpty($SecureVars.LocalAdministrator)) {
    $localAdministrator = $SecureVars.LocalAdministrator.Split(",").Trim()
    $exclude += $localAdministrator
}

If (![string]::IsNullOrEmpty($SecureVars.FSLogixExcludeList)) {
    $excludedList = $SecureVars.FSLogixExcludeList.Split(",").Trim()
    $exclude += $excludedList
}

If (![string]::IsNullOrEmpty($SecureVars.FSLogixIncludeList)) {
    $includeList = $SecureVars.FSLogixIncludeList.Split(",").Trim()
    $include += $includeList
}

Write-Output ("Exclude users: " + ($exclude | Out-String))
Write-Output ("Include users: " + ($include | Out-String))

If (![string]::IsNullOrEmpty($exclude)) {
    Write-Output ("Add users to Exclude Groups: " + ($exclude | Out-String))
    try {
        Add-LocalGroupMember -Group "FSLogix ODFC Exclude List" -Member $exclude -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "FSLogix Profile Exclude List" -Member $exclude -ErrorAction SilentlyContinue

    } catch {
        $ErrorActionPreference = 'Continue'
        Write-Output "Encountered error. $_"
        Throw $_
    }
    Write-Output ("Add users to Exclude Groups: success")
}

If (![string]::IsNullOrEmpty($include)) {
    Write-Output ("Remove users from Include Groups: NT AUTHORITY\Everyone")
    try {
        Remove-LocalGroupMember -Group "FSLogix ODFC Include List" -Member @('NT AUTHORITY\Everyone') -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group "FSLogix Profile Include List" -Member @('NT AUTHORITY\Everyone') -ErrorAction SilentlyContinue
    } catch {
        $ErrorActionPreference = 'Continue'
        Write-Output "Encountered error. $_"
        Throw $_
    }
    Write-Output ("Remove users from Include Groups: success")

    Write-Output ("Add users to Include Groups: " + ($include | Out-String))
    try {
        Add-LocalGroupMember -Group "FSLogix ODFC Include List" -Member $include -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "FSLogix Profile Include List" -Member $include -ErrorAction SilentlyContinue

    } catch {
        $ErrorActionPreference = 'Continue'
        Write-Output "Encountered error. $_"
        Throw $_
    }
    Write-Output ("Add users to Include Groups: success")
}
