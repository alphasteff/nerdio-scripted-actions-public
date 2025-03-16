#name: Assign User-Assigned Managed Identity to Storage Account
#description: Assign a user-assigned managed identity to a Storage Account to get a SAS Token.
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to authorize a user-assigned managed identity on a storage account to create a SAS token.

Requires:
- A variable with the name DeployIdentity and the value for the User-Assigned Managed Identity used for the deployment.
- A variable with the name DeployStorageAccount and the value for the storage account used for the deployment.
#>

<# Variables:
{
  "ManagedIdentityVariable": {
    "Description": "Name of the secure variable or variable for the managed identity.",
    "IsRequired": true,
    "DefaultValue": "DeployIdentity"
  },
  "StorageAccountVariable": {
    "Description": "Name of the secure variable or variable for the storage account.",
    "IsRequired": true,
    "DefaultValue": "DeployStorageAccount"
  }
}
#>

$ErrorActionPreference = 'Stop'

$Prefix = ($KeyVaultName -split '-')[0]
$NMEIdString = ($KeyVaultName -split '-')[3]
$KeyVault = Get-AzKeyVault -VaultName $KeyVaultName
$Context = Get-AzContext
$NMEResourceGroupName = $KeyVault.ResourceGroupName

# Get secure variables for the managed identity and storage account
# Check if the variable is a valid JSON object and convert it to a PowerShell object
# If not, try to get the variable from the secure variables and convert it to a PowerShell object
# If the variable is not a valid JSON object, exit the script
# If the variable is a valid JSON object, continue with the script

Write-Output "Get secure variables"

If ($ManagedIdentityVariable -like "{*}") {
    Write-Output "Convert ManagedIdentityVariable to JSON object"
    $ManagedIdentity = $ManagedIdentityVariable | ConvertFrom-Json
} Else {
    Write-Output "Get Secure Variable for ManagedIdentityVariable and convert to JSON object"
    $ManagedIdentity = $SecureVars.$ManagedIdentityVariable | ConvertFrom-Json
}

If ([string]::IsNullOrEmpty($ManagedIdentity.name)) {
    Write-Output "ManagedIdentityVariable is not a valid JSON object"
    Exit
} Else {
    Write-Output ("Managed Identity Name: " + $ManagedIdentity.name)
}

If ($StorageAccountVariable -like "{*}") {
    Write-Output "Convert StorageAccountVariable to JSON object"
    $StorageAccount = $StorageAccountVariable | ConvertFrom-Json
} Else {
    Write-Output "Get Secure Variable for StorageAccountVariable and convert to JSON object"
    $StorageAccount = $SecureVars.$StorageAccountVariable | ConvertFrom-Json
}

If ([string]::IsNullOrEmpty($StorageAccount.name)) {
    Write-Output "StorageAccountVariable is not a valid JSON object"
    Exit
} Else {
    Write-Output ("Storage Account Name : " + $StorageAccount.name | Out-String)
}

##### Script Logic #####
try {
    #Assign the user-assigned managed identity.
    $actContext = Get-AzContext
    If ($actContext.Subscription.Id -ne $ManagedIdentity.subscriptionid) {
        Set-AzContext -SubscriptionId $ManagedIdentity.subscriptionid
    }
    $objIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $ManagedIdentity.ResourceGroup -Name $ManagedIdentity.Name

    $actContext = Get-AzContext
    If ($actContext.Subscription.Id -ne $StorageAccount.subscriptionid) {
        Set-AzContext -SubscriptionId $StorageAccount.subscriptionid
    }
    $objStorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccount.ResourceGroup -Name $StorageAccount.Name

    # $objIdentity.ObjectId does not work, use $objIdentity.PrincipalId
    Write-Output ("Assign user-assigned managed identity " + $objIdentity.Name + " to storage account " + $objStorageAccount.StorageAccountName)
    New-AzRoleAssignment -ObjectId $objIdentity.PrincipalId -Scope $objStorageAccount.Id -RoleDefinitionName  "Storage Account Contributor"

} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Throw $_
}
