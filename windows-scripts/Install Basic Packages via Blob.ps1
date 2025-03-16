#name: Install Basic Packages via Blob
#description: Deploy Basic packages to the Desktop Image via Blob.
#execution mode: Individual with restart
#tags: beckmann.ch

<# Notes:

Use this script to prepare a Desktop Image and install Basic Packages via Blob.

#>

$ErrorActionPreference = 'Stop'

##### Packages #####
$Scripts = [System.Collections.ArrayList]@()
$null = $Scripts.Add(@{Script = ('bes_TattooingReferenceImage_1.0.ps1'); Arguments = '' })
$null = $Scripts.Add(@{Script = ('bes_DisabelShutdown_1.0.ps1'); Arguments = '' })

$ZipFiles = [System.Collections.ArrayList]@()
#$null = $ZipFiles.Add(@{Name = 'bes_CreateSysDir_1.0'; Script = 'Deploy-Application.exe'; Arguments = '' })

##### Start Logging #####
$runingScriptName = (Get-Item $PSCommandPath ).Name
$logFile = Join-Path -Path $env:InstallLogDir -ChildPath "$runingScriptName-$(Get-Date -f 'yyyy-MM-dd').log"

$paramSetPSFLoggingProvider = @{
    Name         = 'logfile'
    InstanceName = $runingScriptName
    FilePath     = $logFile
    FileType     = 'CMTrace'
    Enabled      = $true
}
If (!(Get-PSFLoggingProvider -Name logfile).Enabled) { $Null = Set-PSFLoggingProvider @paramSetPSFLoggingProvider }

Write-PSFMessage -Level Host -Message ("Start " + $runingScriptName)

##### Script Logic #####

$ErrorActionPreference = 'Stop'

$StorageAccountVariable = 'DeployStorageAccount'
$ManagedIdentityVariable = 'DeployIdentity'

$StorageAccount = $SecureVars.$StorageAccountVariable | ConvertFrom-Json
$ManagedIdentity = $SecureVars.$ManagedIdentityVariable | ConvertFrom-Json

$storageAccountName = $StorageAccount.name
$resourceGroupName = $StorageAccount.resourceGroup
$containerName = $StorageAccount.container
$subscriptionId = $StorageAccount.subscriptionid

function Get-BesSasToken {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            HelpMessage = "The Subscription Id of the subscription on which the storage account is located.",
            ValueFromPipeline = $true
        )]
        [string]
        $SubscriptionId,
        [Parameter(
            Mandatory = $true,
            HelpMessage = "The name of the resource group in which the storage account resides.",
            ValueFromPipeline = $true
        )]
        [string]
        $ResourceGroupName,
        [Parameter(
            Mandatory = $true,
            HelpMessage = "The name of the storage account.",
            ValueFromPipeline = $true
        )]
        [string]
        $StorageAccountName,
        [Parameter(
            Mandatory = $true,
            HelpMessage = "Name of the blob container.",
            ValueFromPipeline = $true
        )]
        [string]
        $ContainerName,
        [Parameter(
            Mandatory = $false,
            HelpMessage = "The Identity to use to acces the storage account.",
            ValueFromPipeline = $true
        )]
        [PScustomObject]
        $Identity,
        [Parameter(
            Mandatory = $false,
            HelpMessage = "How long the token should be valid, in minutes.",
            ValueFromPipeline = $true
        )]
        [int]
        $TokenLifeTime = 60
    )

    begin {
        $date = Get-Date
        $actDate = $date.ToUniversalTime()
        $expiringDate = $actDate.AddMinutes($TokenLifeTime )
        $expiringDate = (Get-Date $expiringDate -Format 'yyyy-MM-ddTHH:mm:ssZ')
        $api = 'http://169.254.169.254/metadata/identity/oauth2/token'
        $apiVersion = '2018-02-01'
        $resource = 'https://management.azure.com/'

        $webUri = "$api`?api-version=$apiVersion&resource=$resource"


        if ($Identity) {
            if ($Identity.client_id) {
                $webUri = $webUri + '&client_id=' + $Identity.client_id
            } elseif ($Identity.object_id) {
                $webUri = $webUri + '&object_id=' + $Identity.object_id
            }
        }

    }

    process {
        $response = Invoke-WebRequest -Uri $webUri -Method GET -Headers @{ Metadata = "true" } -UseBasicParsing
        $content = $response.Content | ConvertFrom-Json
        $armToken = $content.access_token

        # Convert the parameters to JSON, then call the storage listServiceSas endpoint to create the SAS credential:
        $params = @{canonicalizedResource = "/blob/$StorageAccountName/$ContainerName"; signedResource = "c"; signedPermission = "r"; signedProtocol = "https"; signedExpiry = "$expiringDate" }
        $jsonParams = $params | ConvertTo-Json
        $sasResponse = Invoke-WebRequest `
            -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName/listServiceSas/?api-version=2017-06-01" `
            -Method POST `
            -Body $jsonParams `
            -Headers @{Authorization = "Bearer $armToken" } `
            -UseBasicParsing

        # Extract the SAS credential from the response:
        $sasContent = $sasResponse.Content | ConvertFrom-Json
        $sasCred = $sasContent.serviceSasToken
    }

    end {
        return $sasCred
    }
}

Function Start-Unzip {
    param([string]$zipfile, [string]$outpath)
    $Null = Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Null = [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

$sasCred = Get-BesSasToken -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName $containerName -Identity $ManagedIdentity -TokenLifeTime 60

$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasCred

$InstallDirectory = $Env:InstallDir

ForEach ($Script in $Scripts) {
    $ScriptName = $Script.Script
    $ScriptArguemts = $Script.Arguments

    Write-PSFMessage -Level Host -Message ("Download Script: " + $ScriptName)
    Get-AzStorageBlobContent -Blob $ScriptName -Container $containerName -Destination "$InstallDirectory\$ScriptName" -Context $ctx -Force -ErrorAction SilentlyContinue

    Write-PSFMessage -Level Host -Message ("Execute Script: " + "$InstallDirectory\$ScriptName")
    & "$InstallDirectory\$ScriptName" @ScriptArguemts
}

ForEach ($ZipFile in $ZipFiles) {
    $ScriptArchiv = $ZipFile.Name
    $ScriptName = $ZipFile.Script
    $ScriptArguemts = $ZipFile.Arguments

    $FolderName = $ScriptArchiv
    $File = $ScriptArchiv + '.zip'

    Write-PSFMessage -Level Host -Message ("Download File: " + $File)
    Get-AzStorageBlobContent -Blob $File -Container $containerName -Destination "$InstallDirectory\$File" -Context $ctx -Force -ErrorAction SilentlyContinue
    Start-Unzip "$InstallDirectory\$File" "$InstallDirectory\$FolderName"

    Write-PSFMessage -Level Host -Message ("Execute Script: " + "$InstallDirectory\$FolderName\$ScriptName")
    & "$InstallDirectory\$FolderName\$ScriptName" @ScriptArguemts
}

Write-PSFMessage -Level Host -Message ("Stop " + $runingScriptName)

Stop-PSFRunspace
