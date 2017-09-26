
# log into the subscription
$subscriptionId = "your-subscription-id"
$location = "Azure Location Name"
Login-AzureRmAccount -SubscriptionId $subscriptionId

$masterPrefix = "prfx"
$randomMix = "XJDL"
$eventStoreAdminUsername = "admin"
$jumpBoxAdminUsername = "admin"
$eventStoreAdminPassword = ConvertTo-SecureString -String "" -AsPlainText -Force
$eventStoreJumpBoxAdminPassword = ConvertTo-SecureString -String "" -AsPlainText -Force
$certificatePassword = "cert-pw"
$certificateContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("c:\path\to\x.pfx"))

# create the resource group for ES
$eventStoreResourceGroupName = "$masterPrefix-$randomMix-rg"
New-AzureRmResourceGroup -Name $eventStoreResourceGroupName  -Location $location 

# build out the ES resources
# note that anything passed here overrides the parameters.json file
New-AzureRmResourceGroupDeployment -Name "$masterPrefix-$randomMix-esdeploy-01" -ResourceGroupName $eventStoreResourceGroupName `
            -TemplateFile ".\event-store.json" -TemplateParameterFile ".\event-store.parameters.json" `
            -eventStoreAdminUsername $eventStoreAdminUsername -eventStoreAdminPassword $eventStoreAdminPassword `
            -jumpBoxAdminUsername $jumpBoxAdminUsername -jumpBoxAdminPassword $eventStoreJumpBoxAdminPassword -randomMix $randomMix `
            -certificatePassword $certificatePassword -certificateBase64EncodedValue $certificateContent -masterPrefix $masterPrefix -randomMix $randomMix