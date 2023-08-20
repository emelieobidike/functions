param($Timer)

$query = 'resourcecontainers | where type == "microsoft.resources/subscriptions" | project name, subscriptionId, properties.managementGroupAncestorsChain[0].name , properties.subscriptionPolicies.quotaId'
$result = Search-AzGraph -Query $query

$prefix = "MSDN_"

try {
    for ($item = 0; $item -lt $result.Length; $item++) {
        if ($result[$item].properties_subscriptionPolicies_quotaId.StartsWith($prefix) && $result[$item].properties_managementGroupAncestorsChain_0_name -ne "vs-mg") {
            New-AzManagementGroupSubscription -GroupId 'vs-mg' -SubscriptionId $result[$item].subscriptionId
        }
    }
}
catch {
    Write-Host "An error occurred:"
    Write-Host $_
}