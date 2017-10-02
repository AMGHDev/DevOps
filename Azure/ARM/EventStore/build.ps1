

Login-AzureRmAccount -SubscriptionId "subscription id"

$location = "azure location"
$masterPrefix = "pfx"
$randomSubPrefix = "sub"
$eventStoreAdminPassword = ConvertTo-SecureString -String "" -AsPlainText -Force
$eventStoreJumpBoxAdminPassword = ConvertTo-SecureString -String "" -AsPlainText -Force
$certificatePassword = ""
$eventStoreResourceGroupName = "$masterPrefix-$randomSubPrefix-es-rg"
$certificateContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("c:\path\to\cert.pfx"))

# create the resource group for ES
New-AzureRmResourceGroup -Name $eventStoreResourceGroupName  -Location $location

Set-location "path to the json files"

# build out the ES resources
New-AzureRmResourceGroupDeployment -Name "deploy-name" -ResourceGroupName $eventStoreResourceGroupName `
            -TemplateFile ".\event-store.json" -TemplateParameterFile ".\event-store.parameters.json" `
            -eventStoreAdminUsername "admin" -eventStoreAdminPassword $eventStoreAdminPassword `
            -jumpBoxAdminUsername "admin" -jumpBoxAdminPassword $eventStoreJumpBoxAdminPassword `
            -randomSubPrefix $randomSubPrefix `
            -certificatePassword $certificatePassword -certificateBase64EncodedValue $certificateContent -masterPrefix $masterPrefix
            



             