#name: Create Performance Testing Storage Account
#description: Create a Storage Account for performance testing over Scripted Actions
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to create a Storage Account for performance testing over Scripted Actions.

#>

<# Variables:
{
  "StorageAccountName": {
    "Description": "Name of the storage account to be created.",
    "IsRequired": true
  },
  "SkuName": {
    "Description": "SKU of the storage account. (Standard_ZRS, Standard_GRS, Standard_LRS)",
    "IsRequired": true,
    "DefaultValue": "Standard_ZRS"
  },
  "ResultsContainerName": {
    "Description": "Name of the container to be created for results.",
    "IsRequired": true,
    "DefaultValue": "results"
  },
  "DataContainerName": {
    "Description": "Name of the container to be created for data.",
    "IsRequired": true,
    "DefaultValue": "data"
  },
  "BinContainerName": {
    "Description": "Name of the container to be created for binaries.",
    "IsRequired": true,
    "DefaultValue": "bin"
  },
  "ResourceGroupName": {
    "Description": "Name of the resource group where the storage account will be created.",
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
$SubscriptionId = $Context.Subscription.Id
$ResultsContainerName = $ResultsContainerName.ToLower()
$DataContainerName = $DataContainerName.ToLower()
$BinContainerName = $BinContainerName.ToLower()

try {
    # Creating the storage account
    Write-Output "Create storage account"
    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $NMELocation -SkuName $SkuName -Kind StorageV2 -EnableHttpsTrafficOnly $true -AllowBlobPublicAccess $true -PublicNetworkAccess Enabled -ErrorAction Stop

    # Create a container for the deloyment scripts
    Write-Output "Create container for results data"
    $resultsContainer = New-AzStorageContainer -Name $ResultsContainerName -Permission Off -Context $storageAccount.Context -ErrorAction Stop

    # Create a container for the prerequisites
    Write-Output "Create container for prerequisites"
    $dataContainer = New-AzStorageContainer -Name $DataContainerName -Permission Blob -Context $storageAccount.Context -ErrorAction Stop

    # Create a container for the binaries
    Write-Output "Create container for binaries"
    $binContainer = New-AzStorageContainer -Name $BinContainerName -Permission Blob -Context $storageAccount.Context -ErrorAction Stop

    # Create Output for export the information
    $Output = "{`"name`":`"$StorageAccountName`",`"resourceGroup`":`"$ResourceGroupName`",`"subscriptionid`":`"$SubscriptionId`",`"results`":`"$ResultsContainerName`",`"data`":`"$DataContainerName`",`"bin`":`"$BinContainerName`"}"
} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Write-Output "Rolling back changes"

    if ($storageAccount) {
        Write-Output "Removing storage account $StorageAccountName"
        Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force
    }
    Throw $_
}

Write-Output "Storage Account created successfully."
Write-Output "Storage Account Name: $StorageAccountName"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "Subscription ID: $SubscriptionId"
Write-Output "Result Container: $ResultsContainerName"
Write-Output "Data Container: $DataContainerName"
Write-Output "Bin Container: $BinContainerName"

Write-Output "Conten of Secute Varaible 'PerfTestStorage' = $Output"