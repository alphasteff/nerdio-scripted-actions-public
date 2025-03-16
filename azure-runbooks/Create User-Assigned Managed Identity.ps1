#name: Create User-Assigned Managed Identity
#description: Create a user-assigned managed identity to use in scripted actions.
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to create a user-assigned managed identity in the resource group of Nerdio.

#>

<# Variables:
{
  "UserManagedIdentityName": {
    "Description": "Name of the user-assigned managed identity.",
    "IsRequired": true,
    "DefaultValue": "uami-nerdio-scripted-actions"
  },
  "ResourceGroupName": {
    "Description": "Name of the resource group where the user assigned identity will be created.",
    "IsRequired": true
  }
}
#>

$ErrorActionPreference = 'Stop'

$Prefix = ($KeyVaultName -split '-')[0]
$NMEIdString = ($KeyVaultName -split '-')[3]
$KeyVault = Get-AzKeyVault -VaultName $KeyVaultName
$Context = Get-AzContext
$NMEResourceGroupName = $KeyVault.ResourceGroupName
$NMELocation = $KeyVault.Location

##### Script Logic #####

try {


    #Creating the user-assigned managed identity.
    Write-Output "Create user-assigned managed identity"
    $identity = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $UserManagedIdentityName -Location $NMELocation

    $clientId = $identity.ClientId
    $objectId = $identity.PrincipalId
    $subscriptionId = $Context.Subscription.Id

    # Create Output for export the information
    $Output = "{`"name`":`"$UserManagedIdentityName`", `"client_id`":`"$clientId`", `"object_id`":`"$objectId`", `"subscriptionid`":`"$subscriptionId`", `"resourcegroup`":`"$ResourceGroupName`"}"

} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Write-Output "Rolling back changes"

    if ($identity) {
        Write-Output "Removing user-assigned managed identity $UserManagedIdentityName"
        Remove-AzUserAssignedIdentity -ResourceGroupName $NMEResourceGroupName -Name $UserManagedIdentityName -Force -ErrorAction Continue
    }
    Throw $_
}

Write-Output "User-assigned managed identity created successfully."
Write-Output "User-assigned managed identity name: $UserManagedIdentityName"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "Subscription ID: $subscriptionId"
Write-Output "Client ID: $clientId"
Write-Output "Object ID: $objectId"

Write-Output "Content of Secure Variable 'DeployIdentity' = $Output"