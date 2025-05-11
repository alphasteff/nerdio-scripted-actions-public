#description: Enable a existing vm as a hybrid worker for the Nerdio automation account
#tags: beckmann.ch, Nerdio, Preview

<# Notes:

Use this scripted action  to enable an existing VM as a hybrid worker for the Nerdio automation account.
The VM must be in the same subscription as the Nerdio Manager and the automation account. This is necessary
for the Azure runbooks functionality when using private endpoints on Nerdio's scripted actions storage account.

The hybrid worker can join either the runbooks automation account or the nerdio manager automation
account; use the "AutomationAccount" parameter to specify which automation account to join the
hybrid worker. After creating a hybrid worker for the Azure runbooks scripted actions, you will
need to go to Settings -> Nerdio Environment and select "enabled" under "Azure runbooks scripted
actions" to tell Nerdio to use the new hybrid worker.

#>

<# Variables:
{
  "VMName": {
    "Description": "Name of new hybrid worker VM. Must be fewer than 15 characters, or will be truncated.",
    "IsRequired": true,
    "DefaultValue": "nerdio-hw-vm"
  },
  "VMResourceGroup": {
    "Description": "Resource group for the new vm. If not specified, rg of Nerdio Manager will be used.",
    "IsRequired": false
  },
  "HybridWorkerGroupName": {
    "Description": "Name of new hybrid worker group created in the Azure automation account",
    "IsRequired": true,
    "DefaultValue": "nerdio-hybridworker-group"
  },
  "AutomationAccount": {
    "Description": "Which automation account will the hybrid worker be used with. Valid values are ScriptedActions or NerdioManager",
    "IsRequired": true,
    "DefaultValue": "ScriptedActions"
  }
}
#>

$ErrorActionPreference = 'Stop'

$Prefix = ($KeyVaultName -split '-')[0]
$NMEIdString = ($KeyVaultName -split '-')[3]
$KeyVault = Get-AzKeyVault -VaultName $KeyVaultName
$Context = Get-AzContext
$NMEResourceGroupName = $KeyVault.ResourceGroupName

if ($AutomationAccount -eq 'ScriptedActions') {
    $AA = Get-AzAutomationAccount -ResourceGroupName $NMEResourceGroupName | Where-Object AutomationAccountName -Match '(runbooks)|(scripted-actions)'
} elseif ($AutomationAccount -eq 'NerdioManager') {
    $AA = Get-AzAutomationAccount -ResourceGroupName $NMEResourceGroupName -Name "$Prefix-app-automation-$NMEIdString"
} else {
    Throw "AutomationAccount parameter must be either 'ScriptedActions' or 'NerdioManager'"
}

##### Script Logic #####

try {
    #Get the virtual machine.
    Write-Output "Get the VM"
    $VM = Get-AzVM -ResourceGroupName $VMResourceGroup -Name $VMName

    $azureLocation = $VM.Location

    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
    $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token.AccessToken
    }

    Write-Output "Creating new hybrid worker group in automation account"

    $CreateWorkerGroup = Invoke-WebRequest `
        -Uri "https://$azureLocation.management.azure.com/subscriptions/$($context.subscription.id)/resourceGroups/$NMEResourceGroupName/providers/Microsoft.Automation/automationAccounts/$($AA.AutomationAccountName)/hybridRunbookWorkerGroups/$HybridWorkerGroupName`?api-version=2021-06-22" `
        -Headers $authHeader `
        -Method PUT `
        -ContentType 'application/json' `
        -Body '{}' `
        -UseBasicParsing


    $Body = "{ `"properties`": {`"vmResourceId`": `"$($vm.id)`"} }"

    $VmGuid = New-Guid

    Write-Output "Associating VM with automation account"
    $AddVmToAA = Invoke-WebRequest `
        -Uri "https://$azureLocation.management.azure.com/subscriptions/$($context.subscription.id)/resourceGroups/$NMEResourceGroupName/providers/Microsoft.Automation/automationAccounts/$($AA.AutomationAccountName)/hybridRunbookWorkerGroups/$HybridWorkerGroupName/hybridRunbookWorkers/$VmGuid`?api-version=2021-06-22" `
        -Headers $authHeader `
        -Method PUT `
        -ContentType 'application/json' `
        -Body $Body `
        -UseBasicParsing


    Write-Output "Get automation hybrid service url"
    $Response = Invoke-WebRequest `
        -Uri "https://$azureLocation.management.azure.com/subscriptions/$($context.subscription.id)/resourceGroups/$NMEResourceGroupName/providers/Microsoft.Automation/automationAccounts/$($AA.AutomationAccountName)?api-version=2021-06-22" `
        -Headers $authHeader `
        -UseBasicParsing

    $AAProperties = ($response.Content | ConvertFrom-Json).properties
    $AutomationHybridServiceUrl = $AAProperties.automationHybridServiceUrl

    $settings = @{
        "AutomationAccountURL" = "$AutomationHybridServiceUrl"
    }

    Write-Output "Adding VM to hybrid worker group"
    $SetExtension = Set-AzVMExtension -ResourceGroupName $VMResourceGroup `
        -Location $azureLocation `
        -VMName $VMName `
        -Name "HybridWorkerExtension" `
        -Publisher "Microsoft.Azure.Automation.HybridWorker" `
        -ExtensionType HybridWorkerForWindows `
        -TypeHandlerVersion 1.1 `
        -Settings $settings

    if ($SetExtension.StatusCode -eq 'OK') {
        Write-Output "VM successfully added to hybrid worker group"
    }

    if ($AutomationAccount -eq 'ScriptedActions') {
        $AzureAutomationCertificateName = 'ScriptedActionRunAsCert'
    } else {
        $AzureAutomationCertificateName = 'AzureRunAsCertificate'
    }

    $Script = @"
  function Ensure-AutomationCertIsImported
  {
      # ------------------------------------------------------------
      # Import Azure Automation certificate if it's not imported yet
      # ------------------------------------------------------------

      Param (
          [Parameter(mandatory=`$true)]
          [string]`$AzureAutomationCertificateName
      )

      # Get the management certificate that will be used to make calls into Azure Service Management resources
      `$runAsCert = Get-AutomationCertificate -Name `$AzureAutomationCertificateName

      # Check if cert is already imported
      `$certStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "\\`$(`$env:COMPUTERNAME)\My", "LocalMachine"
      `$certStore.Open('ReadOnly') | Out-Null
      if (`$certStore.Certificates.Contains(`$runAsCert)) {
          return
      }

      # Generate the password
      Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue | Out-Null
      `$password = [System.Web.Security.Membership]::GeneratePassword(25, 10)

      # location to store temporary certificate in the Automation service host
      `$certPath = Join-Path `$env:TEMP "`$AzureAutomationCertificateName.pfx"

      # Save the certificate
      `$cert = `$runAsCert.Export("pfx", `$password)
      try {
          Set-Content -Value `$cert -Path `$certPath -Force -Encoding Byte | Out-Null

          `$securePassword = ConvertTo-SecureString `$password -AsPlainText -Force
          Import-PfxCertificate -FilePath `$certPath -CertStoreLocation Cert:\LocalMachine\My -Password `$securePassword | Out-Null
      }
      finally {
          Remove-Item -Path `$certPath -ErrorAction SilentlyContinue | Out-Null
      }
  }
  function Ensure-RequiredAzModulesInstalled
  {
      # ------------------------------------------------------------------------------
      # Install Az modules if Az.Accounts or Az.KeyVault modules are not installed yet
      # ------------------------------------------------------------------------------

      `$modules = Get-Module -ListAvailable
      if (!(`$modules.Name -Contains "Az.Accounts") -or !(`$modules.Name -Contains "Az.KeyVault")) {
          `$policy = Get-ExecutionPolicy -Scope CurrentUser
          try {
              Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser | Out-Null
              `$nugetProvider = Get-PackageProvider -ListAvailable | Where-Object { `$_.Name -eq "Nuget" }
              if (!`$nugetProvider -or (`$nugetProvider.Version | Where-Object { `$_ -ge [Version]::new("2.8.5.201") }).length -eq 0) {
                  Install-PackageProvider -Name "Nuget" -Scope CurrentUser -Force | Out-Null
              }
              Install-Module -Name "Az" -Scope CurrentUser -Repository "PSGallery" -Force | Out-Null
          }
          finally
          {
              Set-ExecutionPolicy -ExecutionPolicy `$policy -Scope CurrentUser | Out-Null
          }
          Import-Module -Name "Az.Accounts" | Out-Null
          Import-Module -Name "Az.KeyVault" | Out-Null
      }
  }
  Ensure-AutomationCertIsImported -AzureAutomationCertificateName $AzureAutomationCertificateName
  Ensure-RequiredAzModulesInstalled
"@

    Write-Output "Creating runbook to import automation certificate to hybrid worker vm"
    $Script > .\Ensure-CertAndModulesAreImported.ps1
    $ImportRunbook = Import-AzAutomationRunbook -ResourceGroupName $NMEResourceGroupName -AutomationAccountName $aa.AutomationAccountName -Path .\Ensure-CertAndModulesAreImported.ps1 -Type PowerShell -Name "Import-CertAndModulesToHybridRunbookWorker" -Force
    $PublishRunbook = Publish-AzAutomationRunbook -ResourceGroupName $NMEResourceGroupName -AutomationAccountName $aa.AutomationAccountName -Name "Import-CertAndModulesToHybridRunbookWorker"
    Write-Output "Importing certificate to hybrid worker vm"
    $Job = Start-AzAutomationRunbook -Name "Import-CertAndModulesToHybridRunbookWorker" -ResourceGroupName $NMEResourceGroupName -AutomationAccountName $aa.AutomationAccountName -RunOn $HybridWorkerGroupName

    Do {
        if ($job.status -eq 'Failed') {
            Write-Output "Job to import certificate and az modules to hybrid worker failed"
            Throw $job.Exception
        }
        if ($job.Status -eq 'Stopped') {
            Write-Output "Job to import certificate to hybrid worker was stopped in Azure. Please import the Nerdio manager certificate and az modules to hybrid worker vm manually"
        }
        Write-Output "Waiting for job to complete"
        Start-Sleep 30
        $job = Get-AzAutomationJob -Id $job.JobId -ResourceGroupName $NMEResourceGroupName -AutomationAccountName $aa.AutomationAccountName
    }
    while ($job.status -notmatch 'Completed|Stopped|Failed')

    if ($job.status -eq 'Completed') {
        Write-Output "Installed certificate and az modules on hybrid runbook worker vm"
    }

    $HybridWorkerJoined = $true

} catch {
    $ErrorActionPreference = 'Continue'
    Write-Output "Encountered error. $_"
    Write-Output "Rolling back changes"

    if ($SetExtension) {
        Write-Output "Removing worker from hybrid worker group"
        $RemoveHybridRunbookWorker = Invoke-WebRequest `
            -Uri "https://$azureLocation.management.azure.com/subscriptions/$($context.subscription.id)/resourceGroups/$NMEResourceGroupName/providers/Microsoft.Automation/automationAccounts/$($AA.AutomationAccountName)/hybridRunbookWorkerGroups/$HybridWorkerGroupName/hybridRunbookWorkers/$VmGuid`?api-version=2021-06-22" `
            -Headers $authHeader `
            -Method Delete  `
            -ContentType 'application/json' `
            -UseBasicParsing `
            -ErrorAction Continue
    }

    if ($CreateWorkerGroup) {
        Write-Output "Removing hybrid worker group"
        $RemoveWorkerGroup = Invoke-WebRequest `
            -Uri "https://$azureLocation.management.azure.com/subscriptions/$($context.subscription.id)/resourceGroups/$NMEResourceGroupName/providers/Microsoft.Automation/automationAccounts/$($AA.AutomationAccountName)/hybridRunbookWorkerGroups/$HybridWorkerGroupName`?api-version=2021-06-22" `
            -Headers $authHeader `
            -Method Delete `
            -ContentType 'application/json' `
            -UseBasicParsing `
            -ErrorAction Continue
    }

    Throw $_
}


if ($HybridWorkerJoined) {
    Write-Output "Hybrid worker group '$HybridWorkerGroupName' has been created. Please update Nerdio Manager to use the new hybrid worker. (Settings->Nerdio Environment->Azure runbooks scripted actions. Click `"Enabled`" and select the new hybrid worker.)"
    Write-Warning "Hybrid worker group '$HybridWorkerGroupName' has been created. Please update Nerdio Manager to use the new hybrid worker. (Settings->Nerdio Environment->Azure runbooks scripted actions. Click `"Enabled`" and select the new hybrid worker.)"
}