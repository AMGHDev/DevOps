
# log into the subscription
$subscriptionId = "your-sub-id"
$location = "azure location"
Login-AzureRmAccount -SubscriptionId $subscriptionId

$masterPrefix = "prfx"
$randomMix = "R8X3S"
$eventStoreAdminUsername = "admin"
$jumpBoxAdminUsername = "admin"
$eventStoreAdminPassword = ConvertTo-SecureString -String "todo" -AsPlainText -Force
$eventStoreJumpBoxAdminPassword = ConvertTo-SecureString -String "todo" -AsPlainText -Force
$certificatePassword = ""
$certificateContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("c:\path\to\x.pfx"))

# create the resource group for ES
$eventStoreResourceGroupName = "$masterPrefix-$randomMix-resource-group"
New-AzureRmResourceGroup -Name $eventStoreResourceGroupName  -Location $location 

# build out the ES resources
# note that anything passed here overrides the parameters.json file
New-AzureRmResourceGroupDeployment -Name "$masterPrefix-$randomMix-esdeploy-01" -ResourceGroupName $eventStoreResourceGroupName `
            -TemplateFile ".\event-store.json" -TemplateParameterFile ".\event-store.parameters.json" `
            -eventStoreAdminUsername $eventStoreAdminUsername -eventStoreAdminPassword $eventStoreAdminPassword `
            -jumpBoxAdminUsername $jumpBoxAdminUsername -jumpBoxAdminPassword $eventStoreJumpBoxAdminPassword -randomMix $randomMix `
            -certificatePassword $certificatePassword -certificateBase64EncodedValue $certificateContent -masterPrefix $masterPrefix