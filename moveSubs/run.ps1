param($Timer)

Connect-AzAccount
$sendEmail = $null

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
            $sendEmail = $false 
            Write-Host "No new subscriptions. Send email:" $sendEmail
            return $sendEmail, $currentVSSubs | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
        }
        else {
            $sendEmail = $true
            Write-Host "New subscriptions. Send email:" $sendEmail
            return $sendEmail, $newVSSubs | Select-Object SubscriptionName, SubscriptionID | Export-Csv .\newVSSubscriptions.csv -NoTypeInformation
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

function getAccessToken() {
    #region Authentication
    #We use the client credentials flow as an example. For production use, REPLACE the code below with your preferred auth method. NEVER STORE CREDENTIALS IN PLAIN TEXT!!!

    #Variables to configure
    $tenantID = "c6b24d18-bbd0-4aec-b84c-e791e95a76e3" #your tenantID or tenant root domain
    $appID = "fa86c8a0-231d-423f-84ee-02b119aa066d" #the GUID of your app.
    $client_secret = "nM.8Q~BLfGGj6b1HIOuoxvoyDSxMARrew796Cbzm" #client secret for the app

    #Prepare token request
    $url = 'https://login.microsoftonline.com/' + $tenantId + '/oauth2/v2.0/token'

    $body = @{
        grant_type    = "client_credentials"
        client_id     = $appID
        client_secret = $client_secret
        scope         = "https://graph.microsoft.com/.default"
    }

    #Obtain the token
    Write-Verbose "Authenticating..."
    try { $tokenRequest = Invoke-WebRequest -Method Post -Uri $url -ContentType "application/x-www-form-urlencoded" -Body $body -UseBasicParsing -ErrorAction Stop }
    catch { Write-Host "Unable to obtain access token, aborting..."; return }

    $token = ($tokenRequest.Content | ConvertFrom-Json).access_token | ConvertTo-SecureString -AsPlainText -Force
    return $token 

    # $authHeader = @{
    #     'Content-Type'  = 'application\json'
    #     'Authorization' = "Bearer $token"
    # }
    #endregion Authentication
}

function sendEmail($token) {
    try {
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
        Connect-MgGraph -AccessToken $token
        Send-MgUserMail -UserId 'challspaceonline_live.com#EXT#@chiemelieobidikegmail.onmicrosoft.com' -BodyParameter $params
        .\Send-GraphMail.ps1 -To 'chiemelieobidike@gmail.com' -Subject "New Subscriptions have been Created" -MessageFormat HTML -Body "I love PowerShell Center" -DeliveryReport -ReadReport -Attachments .\newVSSubscriptions.csv -DocumentType 'text/plain'
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
    $token = getAccessToken
    if ($sendEmail -eq $true) {
        sendEmail $token
    }
    
}

function cleanUp() {
    Remove-Item .\subs\currentVSSubscriptions.csv
    Remove-Item .\subs\oldVSSubscriptions.csv
    Remove-Item .\newVSSubscriptions.csv
}

main
cleanUp