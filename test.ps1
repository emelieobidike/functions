$object1 = @(1,2,3)
$object2 = @(1,2,3,4)
$output = Compare-Object -ReferenceObject @($object1 | Select-Object) -DifferenceObject @($object2 | Select-Object) | Where-Object SideIndicator -eq '<=' 

if ($null -eq $output) {
    Write-Host "Empty"
}