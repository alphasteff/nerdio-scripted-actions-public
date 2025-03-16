$storageAccounts = [System.Collections.ArrayList]@()
$null = $storageAccounts.add(@{storageAccountName = ''; resourceGroupName = ''; subscriptionId = ''; targetSKU = 'Premium_ZRS' })

$migrate = $false

If ($migrate) {
    ForEach ($storageAccount in $storageAccounts) {
        # Check to subscription if not the current subscription
        if ((Get-AzContext).Subscription.Id -ne $storageAccount.subscriptionId) {
            Write-Host "Switching to $($storageAccount.subscriptionId)"
            $null = Select-AzSubscription -SubscriptionId $storageAccount.subscriptionId
        }
        Write-Host "Starting migration of $($storageAccount.storageAccountName) in $($storageAccount.resourceGroupName) to $($storageAccount.targetSKU)"
        Start-AzStorageAccountMigration `
            -AccountName $storageAccount.storageAccountName `
            -ResourceGroupName $storageAccount.resourceGroupName `
            -TargetSku $storageAccount.targetSKU `
            -Name "Migration of $($storageAccount.storageAccountName)" `
            -AsJob
    }
} Else {
    ForEach ($storageAccount in $storageAccounts) {
        # Check to subscription if not the current subscription
        if ((Get-AzContext).Subscription.Id -ne $storageAccount.subscriptionId) {
            Write-Host "Switching to $($storageAccount.subscriptionId)"
            $null = Select-AzSubscription -SubscriptionId $storageAccount.subscriptionId
        }
        # Check if the migration is completed
        $migrationStatus = Get-AzStorageAccount `
            -AccountName $storageAccount.storageAccountName `
            -ResourceGroupName $storageAccount.resourceGroupName
        if ($migrationStatus.Sku.Name -eq $storageAccount.targetSKU) {
            Write-Host "Migration of $($storageAccount.storageAccountName) in $($storageAccount.resourceGroupName) to $($storageAccount.targetSKU) is completed"
            continue
        } else {
            $status = Get-AzStorageAccountMigration `
                -AccountName $storageAccount.storageAccountName `
                -ResourceGroupName $storageAccount.resourceGroupName
            Write-Host "Migration of $($storageAccount.storageAccountName) in $($storageAccount.resourceGroupName) to $($storageAccount.targetSKU) is not completed. Status: $($status.DetailMigrationStatus)"
        }
    }
}