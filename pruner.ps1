param($Timer)

function Main() {
    $storageAccounts = @(
        "zw2etsdevcorvussta01",
        "zw2etsprdcorvussta01",
        "zw2etssbxcorvussta01",
        "zw2isdevinfstadiag01",
        "zw2isprdinfstadiag01",
        "zw2isprdinfstadiag02",
        "zw2issbxinfstadiag01",
        "zw2tldevinfstadiag01",
        "zw2tlprdinfstadiag01",
        "zw2wpdevinfstadiag01",
        "zw2wpprdinfstadiag01"
    )

    $retentionDays = 365

    foreach ($storageAccount in $storageAccounts) {
        $context = Get-StorageContext $storageAccount
        if ($storageAccount -like "*corvus*") { $retentionDays = 180 }
        Write-Host "Working on" $storageAccount
        Remove-Data $context $retentionDays
        Remove-Container $context $retentionDays
        Remove-TableRows $context 
    }

}

function Get-StorageContext($storageAccount) {
    $token = Get-AzKeyVaultSecret -VaultName "prunner-keyvault-prd" -Name $storageAccount -AsPlainText
    return New-AzStorageContext -StorageAccountName $storageAccount -SasToken $token
}

function Remove-Data($context, $retentionDays) {
    $currentDate = Get-Date

    Get-AzStorageContainer -Context $context | ForEach-Object {
        $containerName = $_.Name

        Get-AzStorageBlob -Container $containerName -Context $context | ForEach-Object {
            $blobName = $_.Name
            $lastModifiedDate = $_.LastModified

            $daysDifference = ([System.DateTimeOffset]$currentDate - $lastModifiedDate).Days

            if ($daysDifference -ge $retentionDays) {
                Write-Host "Removing" $blobName
                Remove-AzStorageBlob -Container $containerName -Blob $blobName -Context $context
            }
        }
    }
}

function Remove-Container($context, $retentionDays) {
    $currentDate = Get-Date
    $storageContainers = Get-AzStorageContainer -Context $context 

    foreach ($storageContainer in $storageContainers) {
        $lastModifiedDate = $storageContainer.LastModified
        $daysDifference = ([System.DateTimeOffset]$currentDate - $lastModifiedDate).Days
        if ($daysDifference -ge $retentionDays) {
            if ($null -eq $storageContainer.CloudBlobContainer.ListBlobs().Count) {
                Write-Host "Removing" $storageContainer.name
                Remove-AzStorageContainer -Name $storageContainer.name -Context $context -Force
            }
        }
    }

}

function Remove-TableRows($context) {
    $tables = Get-AzStorageTable -Context $context
    $currentDate = Get-Date
    foreach ($table in $tables) {
        Write-Host "Working on table" $table.Name
        $storageTable = Get-AzStorageTable -Name $table.Name -Context $context
        Get-AzTableRow -table $storageTable.CloudTable | ForEach-Object {
            $row = $_
            $roww = [String]$row
            $timestamp = $row.TableTimestamp
            $daysDifference = ([System.DateTimeOffset]$currentDate - $timestamp).Days
            if ($daysDifference -ge 365) {
                Write-Host "Row has been stale for" $daysDifference "days."
                $row | Remove-AzTableRow -table $storageTable.CloudTable
                Write-Host "Removed one row." $roww
            }
        }
    }
}

Main
