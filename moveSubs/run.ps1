param($Timer)

Connect-AzAccount

function getContext() {
    return New-AzStorageContext -StorageAccountName "testb5f0" -SasToken "?sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiyx&se=2023-09-17T16:48:03Z&st=2023-09-10T08:48:03Z&spr=https&sig=cTUIxPjLj8h96cBYK%2BSy%2BYGI94m8qoP%2BWUYMahK5WEQ%3D"
}

function getOldVSSubs($context) {
    try {
        $DLBlob1HT = @{
            Blob        = 'oldVSSubscriptions.csv'
            Container   = 'subscriptions'
            Destination = '.\subs'
            Context     = $context
        }
        return Get-AzStorageBlobContent @DLBlob1HT -Force
    }
    catch {
        Write-Host "An error occurred on getOldVSSubs:"
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

function getCurrentVSSubs() {
    try {
        $query = 'resourcecontainers | where type == "microsoft.resources/subscriptions" | project name, subscriptionId, properties.managementGroupAncestorsChain[0].name , properties.subscriptionPolicies.quotaId'
        $result = Search-AzGraph -Query $query
        $prefix = "MSDN_"
        # $vsSubscriptions = New-Object System.Collections.ArrayList
        $vsSubscriptions = @()

        foreach ($item in $result) {
            if ($item.properties_subscriptionPolicies_quotaId.StartsWith($prefix) && $item.properties_managementGroupAncestorsChain_0_name -ne "vs-mg") {
                $vsSubscriptionObject = addVSSubProperties $item
                $vsSubscriptions += $vsSubscriptionObject
            }
        }
        $path = '.\subs\currentVSSubscriptions.csv'
        return $vsSubscriptions | Export-Csv -Path $path -NoTypeInformation >$null 2>&1 -Force
    }
    catch {
        Write-Host "An error occurred on getCurrentVSSUbs:"
        Write-Host $_
    }
    
}

function compareVSSubs() {
    try {
        $oldVSSubs = Import-Csv .\subs\oldVSSubscriptions.csv
        $currentVSSubs = Import-Csv .\subs\currentVSSubscriptions.csv
        $newVSSubs = Compare-Object -ReferenceObject @($currentVSSubs | Select-Object) -DifferenceObject @($oldVSSubs | Select-Object) -Property SubscriptionName, SubscriptionID | Where-Object SideIndicator -eq '<='
        if ($null -eq $newVSSubs) {
            Write-Host "No new subscriptions"
            return $currentVSSubs | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
        } else {
            return $newVSSubs | Select-Object SubscriptionName, SubscriptionID | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
        }
    }
    catch {
        Write-Host "An error occurred on compareVSSubs:"
        Write-Host $_
    }
}

function writeNewVSSubsToStorageAccount($context) {
    try {
        Set-AzStorageBlobContent -Container 'subscriptions' -Context $context -File '.\newVSSubscriptions.csv' -Blob 'oldVSSubscriptions.csv' -Force
    }
    catch {
        Write-Host "An error occurred on writeNewVSSubsToStorageAccount:"
        Write-Host $_
    }
}

function sendEmail($newVSSubs) {
    try {
        Connect-MgGraph -Scopes Mail.Read
        # $table = @()
        # foreach ($item in $newVSSubs) {
        #     $row = "" | Select-Object SubscriptionID, SubscriptionName
        #     $row.id = $item.id
        #     $row.name = $item.name
        #     $table += $row
        # }
        $attachment = ".\newVSSubscriptions.csv"
        $messageAttachement = [Convert]::ToBase64String([IO.File]::ReadAllBytes($attachment))
        $params = @{
            Message = @{
                Subject      = "New Visual Studio Suscriptions have been Created"
                Body         = @{
                    ContentType = "Text"
                    Content     = "Hello Admins,`n"
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
        # A UPN can also be used as -UserId.
        Send-MgUserMail -UserId 'chiemelieobidike@gmail.com' -BodyParameter $params
    }
    catch {
        Write-Host "An error occurred on sendEmail:"
        Write-Host $_
    }
}

function main() {
    $context = getContext
    getOldVSSubs $context
    getCurrentVSSubs
    compareVSSubs
    writeNewVSSubsToStorageAccount $context
    sendEmail
}

main