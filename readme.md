# DevOps Open Source

## Azure ARM Templates for EventStore

The Azure\ARM\EventStore folder contains the ARM template for creating an Event Store cluster. This is intended for the www.geteventstore.com Linux package. You will need to have the Azure PowerShell tools installed and edit the build.ps1 to provide the appropriate inputs.
Following the installation, you will need to add and mount the secondary drives and install EventStore. This will eventually be automated with BASH scripts.

### event-store.parameters.json (also available in build.ps1)

* masterPrefix - this is the initial prefix for all resources created
* randomMix - this is second prefix group for resource names
* eventStoreAdminUsername - the Linux user name for Event Store cluster machines
* eventStoreAdminPassword - the password for Event Store cluster machines
* jumpBoxAdminUsername - the Linux user name for jump box machine
* jumpBoxAdminPassword - the password for jump box machine
* instanceCount - the number of Event Store machines to create

### build.ps1
* You must set your subscription Id to your Azure account
* You will need the SSL certificate password and pfx file path; if you want to skip SSL, you will need to edit the main event-store.json and remove the SSL nodes

Note that what is provided in build.ps1 when calling New-AzureRmResourceGroupDeployment **will override the settings in the parameters.json** file!
