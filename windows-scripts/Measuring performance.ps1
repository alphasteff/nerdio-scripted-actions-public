#name: Measuring  performance
#description: Measures the performance
#execution mode: Combined
#tags: beckmann.ch

<# Notes:

Use this script to measure the performance. This script will download the required files, execute the script, and upload the results to the storage account.

There are four types of files that can be downloaded:
- DataFiles: These files are downloaded only.
- BinaryFiles: These files are downloaded only.
- Scripts: These files are downloaded and executed.
- ZipFiles: These files are downloaded and the integrated script is executed.

#>

Start-Transcript -Path "$($Env:windir)\Logs\Measuring_disc_performance_Transscript.log"

$ErrorActionPreference = 'Stop'

# Define the name of the variables that contain the values
$ManagedIdentityVariable = 'PerfTestIdentity'
$StorageAccountVariable = 'PerfTestStorage'
$ScriptConfigVariable = 'PerfTestConfig'

# Convert the secure variables to JSON
$ManagedIdentity = $SecureVars.$ManagedIdentityVariable | ConvertFrom-Json
$StorageAccount = $SecureVars.$StorageAccountVariable | ConvertFrom-Json
$config = $SecureVars.$ScriptConfigVariable | ConvertFrom-Json

# Define the timestamp
$now = Get-Date
$now = $now.ToUniversalTime()
$timestamp = $now.ToString('yyyy-MM-ddTHH-mm-ssZ')

# Define the "installation" directory
$InstallDirectory = $Env:SystemDrive + '\PerfDir'
$LogDirectory = "$InstallDirectory\Logs"
if (-not (Test-Path $InstallDirectory)) {
    $null = New-Item -Path $InstallDirectory -ItemType Directory
}

If (-not (Test-Path $LogDirectory)) {
    $null = New-Item -Path $LogDirectory -ItemType Directory
}

Write-Output "InstallDirectory: $InstallDirectory"
Write-Output "LogDirectory: $LogDirectory"

##### Files #####
# Need to be stored within the data container
$DataFiles = [System.Collections.ArrayList]@()
$null = $DataFiles.Add(@{Name = 'Install-WPR.ps1' })

##### Binary Files #####
# Need to be stored within the binary container
$BinaryFiles = [System.Collections.ArrayList]@()
$null = $BinaryFiles.Add(@{Name = 'WADK - WPR Only.zip' })

##### Scripts #####
# Need to be stored within the data container, script is then executed
$Scripts = [System.Collections.ArrayList]@()
$null = $Scripts.Add(@{Script = ('DiskPerformanceTest_1.0.ps1'); Arguments = @{"RootFolder" = $InstallDirectory; "LogDirectory" = $LogDirectory; "Configuration" = $config } })

##### Packages #####
# Need to be stored within the binary container, binary is then executed
$ZipFiles = [System.Collections.ArrayList]@()
#$null = $ZipFiles.Add(@{Name = 'ZibFileName'; Script = 'ApplicationName.exe'; Arguments = '' })

##### Script Logic #####
$subscriptionId = $StorageAccount.subscriptionId
$resourceGroupName = $StorageAccount.resourceGroup
$storageAccountName = $StorageAccount.name
$containerResultsName = $StorageAccount.results
$containerDataName = $StorageAccount.data
$containerBinName = $StorageAccount.bin

Write-Output "SubscriptionId: $subscriptionId"
Write-Output "ResourceGroupName: $resourceGroupName"
Write-Output "StorageAccountName: $storageAccountName"
Write-Output "ContainerResultsName: $containerResultsName"
Write-Output "ContainerDataName: $containerDataName"
Write-Output "ContainerBinName: $containerBinName"

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
        $TokenLifeTime = 60,
        [Parameter(
            Mandatory = $false,
            HelpMessage = "The permission to grant the SAS token.",
            ValueFromPipeline = $true
        )]
        $Permission = 'r'
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
        $params = @{canonicalizedResource = "/blob/$StorageAccountName/$ContainerName"; signedResource = "c"; signedPermission = $Permission; signedProtocol = "https"; signedExpiry = "$expiringDate" }
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
    param(
        [string]$zipfile,
        [string]$outpath)
    $Null = Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Null = [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Function Start-Zip {
    param(
        [string]$SourcePath,
        [string]$ZipFile,
        [bool]$Overwrite = $false
    )

    $Null = Add-Type -AssemblyName System.IO.Compression.FileSystem

    If ($Overwrite -and (Test-Path $ZipFile)) {
        Remove-Item -Path $ZipFile
    } ElseIf (Test-Path $ZipFile) {
        [System.IO.Compression.ZipFile]::Open($zipFile, [System.IO.Compression.ZipArchiveMode]::Update).Dispose()
    } Else {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipFile)
    }
}

$sasBinCred = Get-BesSasToken -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName $containerBinName -Identity $ManagedIdentity -TokenLifeTime 60 -Permission 'r'
$sasDataCred = Get-BesSasToken -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName $containerDataName -Identity $ManagedIdentity -TokenLifeTime 60 -Permission 'r'
$sasResultsCred = Get-BesSasToken -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName $containerResultsName -Identity $ManagedIdentity -TokenLifeTime 60 -Permission 'w'

$ctxBin = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasBinCred
$ctxData = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasDataCred
$ctxResults = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasResultsCred

# Download the files and execute if needed
Try {
    ForEach ($DataFile in $DataFiles) {
        Write-Output "Downloading $($DataFile.Name)"
        $FileName = $DataFile.Name
        Get-AzStorageBlobContent -Blob $FileName -Container $containerDataName -Destination "$InstallDirectory\$FileName" -Context $ctxData -Force -ErrorAction SilentlyContinue
    }

    ForEach ($BinaryFile in $BinaryFiles) {
        Write-Output "Downloading $($BinaryFile.Name)"
        $FileName = $BinaryFile.Name
        Get-AzStorageBlobContent -Blob $FileName -Container $containerBinName -Destination "$InstallDirectory\$FileName" -Context $ctxBin -Force -ErrorAction SilentlyContinue
    }

    ForEach ($Script in $Scripts) {
        Write-Output "Downloading $($Script.Script) and executing with arguments $($Script.Arguments)"

        $ScriptName = $Script.Script
        $ScriptArguemts = $Script.Arguments

        Get-AzStorageBlobContent -Blob $ScriptName -Container $containerDataName -Destination "$InstallDirectory\$ScriptName" -Context $ctxData -Force -ErrorAction SilentlyContinue

        & "$InstallDirectory\$ScriptName" @ScriptArguemts
    }

    ForEach ($ZipFile in $ZipFiles) {

        Write-Output "Downloading $($ZipFile.Name) and executing script $($ZipFile.Script) with arguments $($ZipFile.Arguments)"

        $ScriptArchiv = $ZipFile.Name
        $ScriptName = $ZipFile.Script
        $ScriptArguemts = $ZipFile.Arguments

        $FolderName = $ScriptArchiv
        $File = $ScriptArchiv + '.zip'

        Get-AzStorageBlobContent -Blob $File -Container $containerBinName -Destination "$InstallDirectory\$File" -Context $ctxBin -Force -ErrorAction SilentlyContinue
        Start-Unzip "$InstallDirectory\$File" "$InstallDirectory\$FolderName"

        & "$InstallDirectory\$FolderName\$ScriptName" @ScriptArguemts
    }
} catch {
    $_ | Out-File "$InstallDirectory\ERRORS.log"
}

# Zip the Log Directory
Write-Output "Zipping the log directory"
$zipFile = $InstallDirectory + "\Results_$timestamp.zip"
Start-Zip -SourcePath $LogDirectory -ZipFile $zipFile -overwrite $true

# Upload the content
Write-Output "Uploading the results"
$blobName = "Results_$($Env:COMPUTERNAME)_$timestamp.zip"
Set-AzStorageBlobContent -Container $containerResultsName -File $zipFile -Blob $blobName -Context $ctxResults -Force -ErrorAction SilentlyContinue

# Clean up
Write-Output "Cleaning up"
Remove-Item -Path $zipFile
Remove-Item -Path $LogDirectory -Recurse
Remove-Item -Path $InstallDirectory -Recurse

Stop-Transcript