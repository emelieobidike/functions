param($Timer)

function Main() {
    $unmovedVSSubscriptions = Get-UnmovedVSSubs
    if ($unmovedVSSubscriptions -eq $false) {
        return
    }
    else {
        $context = Get-Context
        $cloudTable = Get-CloudTable $context
        $newVSSubs = Compare-VSSubs $unmovedVSSubscriptions $cloudTable
        if ($newVSSubs -eq $false) {
            return
        }
        else {
            $clientSecretCredential = Get-ClientSecretCredential
            Send-Email $clientSecretCredential $newVSSubs $cloudTable
        }
    }
}

function Get-UnmovedVSSubs() {
    try {
        $query = 'resourcecontainers | where type == "microsoft.resources/subscriptions" | project name, subscriptionId, properties.managementGroupAncestorsChain[0].name , properties.subscriptionPolicies.quotaId'
        $subscriptions = Search-AzGraph -Query $query
        $prefix = "MSDN_"
        $unmovedVSSubscriptions = @()
        foreach ($subscription in $subscriptions) {
            if ($subscription.properties_subscriptionPolicies_quotaId.StartsWith($prefix) -and $subscription.properties_managementGroupAncestorsChain_0_name -ne "vs-mg") {
                $unmovedVSSubscriptionObject = addProperties $subscription
                $unmovedVSSubscriptions += $unmovedVSSubscriptionObject
            }
        }
        if ($unmovedVSSubscriptions.Length -gt 0) {
            return $unmovedVSSubscriptions
        }
        else {
            return $false
        }
    }
    catch {
        Write-Host "An error occurred on getCurrentVSSUbs:"
        Write-Host $_
    }
    
}

function Add-Properties($subscription) {
    $PropertyHash = [ordered]@{
        subscriptionId   = $subscription.subscriptionId
        subscriptionName = if ($null -eq $subscription.subscriptionName) { $subscription.name } else {
            $subscription.subscriptionName
        }
    }
    return New-Object -TypeName PSObject -Property $PropertyHash
}

function Get-Context() {
    $token = Get-AzKeyVaultSecret -VaultName "secrets773" -Name "SASToken" -AsPlainText
    return New-AzStorageContext -StorageAccountName "testb5f0" -SasToken $token
}

function Get-CloudTable($ctx) {
    try {
        $tableName = 'vssubscriptions'
        $storageTable = Get-AzStorageTable -Name $tableName -Context $ctx
        $cloudTable = $storageTable.CloudTable
        return $cloudTable
    }
    catch {
        Write-Host "An error occurred on getCloudTable:"
        Write-Host $_
    }
}

function Compare-VSSubs($unmovedVSSubscriptions, $cloudTable) {
    try {
        $newVSSubs = @()
        foreach ($subscription in $unmovedVSSubscriptions) {
            $newVSSub = Get-AzTableRow -table $cloudTable `
                -columnName "subscriptionid" `
                -value $subscription.subscriptionId `
                -operator Equal
            if ($null -eq $newVSSub) {
                $newVSSubObject = addProperties $subscription
                $newVSSubs += $newVSSubObject
            }
        }
        if ($newVSSubs.Length -eq 0) {
            return $false
        }
        else {
            return $newVSSubs
        }
    }
    catch {
        Write-Host "An error occurred on checkVSSubs:"
        Write-Host $_
    }
}

function Get-ClientSecretCredential() {
    $client_secret = Get-AzKeyVaultSecret -VaultName "secrets773" -Name "moveVSSubsSecret" -AsPlainText
    $appID = "fa86c8a0-231d-423f-84ee-02b119aa066d"
    $clientSecretPass = ConvertTo-SecureString -String $client_secret -AsPlainText -Force
    return New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appID, $clientSecretPass
}

function Send-Email($clientSecret, $newVSSubs, $cloudTable) {
    try {
        $subject = $newVSSubs.Length -eq 1 ? "A New Visual Studio Subscription has been Created" : "New Visual Studio Subscriptions have been Created"
        $params = @{
            Message = @{
                Subject      = $subject
                Body         = @{
                    ContentType = "Text"
                    Content     = "Hello Admins,`n$subject. Please check the attached spreadsheet and move to the correct management group. `n`nRegards."
                }
                ToRecipients = @(
                    @{
                        EmailAddress = @{
                            Address = "challspaceonline@gmail.com"
                        }
                    }
                )
            }
        }
        $tenantID = "c6b24d18-bbd0-4aec-b84c-e791e95a76e3"
        Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $clientSecret
        Send-MgUserMail -UserId 'challspaceonline_live.com#EXT#@chiemelieobidikegmail.onmicrosoft.com' -BodyParameter $params -ErrorAction Stop
        Remove-TableEntities $cloudTable
        Add-TableEntities $newVSSubs $cloudTable
    }
    catch {
        Write-Host "An error occurred on sendEmail:"
        Write-Host $_
    }
}

function Remove-TableEntities($cloudTable) {
    try {
        Get-AzTableRow `
            -table $cloudTable | Remove-AzTableRow -table $cloudTable 
    }
    catch {
        Write-Host "An error occurred on deleteEntities:"
        Write-Host $_
    }
}

function Add-TableEntities($newVSSubs, $cloudTable) {
    try {
        for ($index = 0; $index -lt $newVSSubs.Length; $index++) {
            Add-AzTableRow `
                -table $cloudTable `
                -partitionKey "partition$index" `
                -rowKey ("row$index") -property @{"subsriptionname" = $newVSSubs[$index].subscriptionName; "subscriptionid" = $newVSSubs[$index].subscriptionId }
        }
    }
    catch {
        Write-Host "An error occurred on addTableEntities:"
        Write-Host $_
    }
}

Main