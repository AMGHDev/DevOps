

Login-AzureRmAccount -SubscriptionId "your-subscription-id"

$masterPrefix = "prefix"
$randomMix = "X123"
$eventStoreAdminPassword = ConvertTo-SecureString -String "to-do" -AsPlainText -Force
$eventStoreJumpBoxAdminPassword = ConvertTo-SecureString -String "to-do" -AsPlainText -Force
$certificatePassword = "your cert pw"
$eventStoreResourceGroupName = "$randomMix-rg"
$certificateContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("c:\path\to\pfx"))

# create the resource group for ES
New-AzureRmResourceGroup -Name $eventStoreResourceGroupName  -Location $location

# build out the ES resources
New-AzureRmResourceGroupDeployment -Name "$randomMix-esdeploy-01" -ResourceGroupName $eventStoreResourceGroupName `
            -TemplateFile ".\event-store.json" -TemplateParameterFile ".\event-store.parameters.json" `
            -eventStoreAdminUsername "es-admin" -eventStoreAdminPassword $eventStoreAdminPassword `
            -jumpBoxAdminUsername "es-jumpbox" -jumpBoxAdminPassword $eventStoreJumpBoxAdminPassword -randomMix $randomMix `
            -certificatePassword $certificatePassword -certificateBase64EncodedValue $certificateContent -masterPrefix $masterPrefix