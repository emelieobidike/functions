param($Timer)

function getCurrentVSSubs() {
    try {
        $query = 'resourcecontainers | where type == "microsoft.resources/subscriptions" | project name, subscriptionId, properties.managementGroupAncestorsChain[0].name , properties.subscriptionPolicies.quotaId'
        $subscriptions = Search-AzGraph -Query $query
        $prefix = "MSDN_"
        $vsSubscriptions = @()
        foreach ($subscription in $subscriptions) {
            if ($subscription.properties_subscriptionPolicies_quotaId.StartsWith($prefix) -and $subscription.properties_managementGroupAncestorsChain_0_name -ne "vs-mg") {
                $vsSubscriptionObject = addVSSubProperties $item
                $vsSubscriptions += $vsSubscriptionObject
            }
        }
        if ($vsSubscriptions.Length -ne 0) {
            $path = '.\currentVSSubscriptions.csv'
            $vsSubscriptions | Export-Csv -Path $path -NoTypeInformation >$null 2>&1 -Force
        }
        return $vsSubscriptions.Length
    }
    catch {
        Write-Host "An error occurred on getCurrentVSSUbs:"
        Write-Host $_
    }
    
}

function addVSSubProperties($subscription) {
    $PropertyHash = [ordered]@{
        SubscriptionID   = $subscription.subscriptionId
        SubscriptionName = $subscription.name
    }
    return New-Object -TypeName PSObject -Property $PropertyHash
}

function getContext() {
    $token = Get-AzKeyVaultSecret -VaultName "secrets773" -Name "SASToken" -AsPlainText
    return New-AzStorageContext -StorageAccountName "testb5f0" -SasToken $token
}

function getOldVSSubs($context) {
    try {
        $DLBlob1HT = @{
            Blob        = 'oldVSSubscriptions.csv'
            Container   = 'subscriptions'
            Destination = '.\'
            Context     = $context
        }
        return Get-AzStorageBlobContent @DLBlob1HT -Force
    }
    catch {
        Write-Host "An error occurred on getOldVSSubs:"
        Write-Host $_
    }
}

function compareVSSubs() {
    try {
        $oldVSSubs = Import-Csv .\oldVSSubscriptions.csv
        $currentVSSubs = Import-Csv .\currentVSSubscriptions.csv
        $newVSSubs = Compare-Object -ReferenceObject @($currentVSSubs | Select-Object) -DifferenceObject @($oldVSSubs | Select-Object) -Property SubscriptionName, SubscriptionID | Where-Object SideIndicator -eq '<='
        if ($null -eq $newVSSubs) {
            $currentVSSubs | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
            return $false
        }
        else {
            $newVSSubs | Select-Object SubscriptionName, SubscriptionID | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
            return $true
        }
    }
    catch {
        Write-Host "An error occurred on compareVSSubs:"
        Write-Host $_
    }
}

function getClientSecretCredential() {
    $client_secret = Get-AzKeyVaultSecret -VaultName "secrets773" -Name "moveVSSubsSecret" -AsPlainText
    $appID = "fa86c8a0-231d-423f-84ee-02b119aa066d"
    $clientSecretPass = ConvertTo-SecureString -String $client_secret -AsPlainText -Force
    return New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appID, $clientSecretPass
}

function sendEmail($newVSSubs, $clientSecret, $context) {
    try {
        $attachment = ".\newVSSubscriptions.csv"
        $messageAttachement = [Convert]::ToBase64String([IO.File]::ReadAllBytes($attachment))
        $subject = $newVSSubs -eq 1 ? "A New Visual Studio Subscription has been Created" : "New Visual Studio Subscriptions have been Created"
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
                Attachments  = @(
                    @{
                        "@odata.type" = "#microsoft.graph.fileAttachment"
                        Name          = $attachment
                        ContentType   = "text/plain"
                        ContentBytes  = $messageAttachement
                    }
                )
            }
        }
        $tenantID = "c6b24d18-bbd0-4aec-b84c-e791e95a76e3"
        Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $clientSecret
        Send-MgUserMail -UserId 'challspaceonline_live.com#EXT#@chiemelieobidikegmail.onmicrosoft.com' -BodyParameter $params -ErrorAction Stop
        writeNewVSSubsToStorageAccount $context
    }
    catch {
        Write-Host "An error occurred on sendEmail:"
        Write-Host $_
    }
}

function writeNewVSSubsToStorageAccount($context) {
    try {
        return Set-AzStorageBlobContent -Container 'subscriptions' -Context $context -File '.\newVSSubscriptions.csv' -Blob 'oldVSSubscriptions.csv' -Force
    }
    catch {
        Write-Host "An error occurred on writeNewVSSubsToStorageAccount:"
        Write-Host $_
    }
}

function main() {
    $vsSubscriptions = getCurrentVSSubs
    if ($vsSubscriptions -eq 0) {
        return
    }
    else {
        $context = getContext
        getOldVSSubs $context
        $newVSSubs = compareVSSubs
        if ($newVSSubs -eq $true) {
            $clientSecretCredential = getClientSecretCredential
            sendEmail $vsSubscriptions $clientSecretCredential $context
        }
        cleanUp
    }
}

function cleanUp() {
    Remove-Item .\currentVSSubscriptions.csv
    Remove-Item .\oldVSSubscriptions.csv
    Remove-Item .\newVSSubscriptions.csv
}

main