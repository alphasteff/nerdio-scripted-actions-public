#name: Assign User-Assigned Managed Identity to VM
#description: Assign a user-assigned managed identity to a VM.
#execution mode: Individual
#tags: beckmann.ch

<# Notes:

Use this script to assign a user-assigned managed identity to a VM.

Requires:
- A variable with the name DeployIdentity and the value for the User-Assigned Managed Identity used for the deployment.

#>

$ManagedIdentityVariable = 'DeployIdentity'

$ErrorActionPreference = 'Stop'

Write-Output "AzureSubscriptionId = $AzureSubscriptionId"
Write-Output "AzureSubscriptionName = $AzureSubscriptionName"
Write-Output "AzureResourceGroupName = $AzureResourceGroupName"
Write-Output "AzureVMName = $AzureVMName"

Write-Output "Get Secure Variable for ManagedIdentityVariable and convert to JSON object"
$ManagedIdentity = $SecureVars.$ManagedIdentityVariable | ConvertFrom-Json

If ([string]::IsNullOrEmpty($ManagedIdentity.name)) {
    Write-Output "ManagedIdentityVariable is not a valid JSON object"
    Exit
} Else {
    Write-Output ("Managed Identity Name: " + $ManagedIdentity.name)
}

##### Script Logic #####

try {
    #Assign the user-assigned managed identity.
    Write-Output "Assign user-assigned managed identity"
    $umidentity = Get-AzUserAssignedIdentity -ResourceGroupName $ManagedIdentity.resourcegroup -Name $ManagedIdentity.name -SubscriptionId $ManagedIdentity.subscriptionid
    Write-Output ("umidentity = {0}" -f ($umidentity | Out-String))

    $vm = Get-AzVM -ResourceGroupName $AzureResourceGroupName -VM $AzureVMName
    Write-Output ("VM = {0}" -f ($vm | Out-String))

    If ($vm.Identity.Type -eq 'SystemAssigned') {
        Write-Output ('System Assigned Identeity exists, add the User Assigned Identity.')
        Update-AzVM -ResourceGroupName $AzureResourceGroupName -VM $vm -IdentityType "SystemAssignedUserAssigned" -IdentityId $umidentity.Id
    } ElseIf ($vm.Identity.Type -eq 'SystemAssignedUserAssigned') {
        Write-Output ("System Assigned Identeity and User Assigned Identity exists, add an additional User Assigned Identity.")

        # Get the existing User Assigned Identities
        [array]$umidentities = $vm.Identity.UserAssignedIdentities.Keys

        if ($umidentities -notcontains $umidentity.Id) {
            # Add the User Assigned Identity to the existing User Assigned Identities
            $umidentities += $umidentity.Id
            Update-AzVM -ResourceGroupName $AzureResourceGroupName -VM $vm -IdentityType "SystemAssignedUserAssigned" -IdentityId $umidentities
        }
    } ElseIf ($vm.Identity.Type -eq 'UserAssigned') {
        Write-Output ("User Assigned Identity exists, add an additional User Assigned Identity.")

        # Get the existing User Assigned Identities
        [array]$umidentities = $vm.Identity.UserAssignedIdentities.Keys

        if ($umidentities -notcontains $umidentity.Id) {
            # Add the User Assigned Identity to the existing User Assigned Identities
            $umidentities += $umidentity.Id
            Update-AzVM -ResourceGroupName $AzureResourceGroupName -VM $vm -IdentityType "UserAssigned" -IdentityId $umidentities
        }
    } Else {
        Write-Output ("System Assigned Identeity doesn't exists, add only the User Assigned Identity.")
        Update-AzVM -ResourceGroupName $AzureResourceGroupName -VM $vm -IdentityType "UserAssigned" -IdentityId $umidentity.Id
    }
} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Throw $_
}
