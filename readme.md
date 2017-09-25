# DevOps Open Source

# Azure ARM Templates for EventStore

The Azure\ARM\EventStore folder contains the ARM template for creating an Event Store cluster. This is intended for the www.geteventstore.com Linux package. You will need to have the Azure PowerShell tools installed and edit the build.ps1 to provide the appropriate inputs.
Following the installation, you will need to add and mount the secondary drives and install EventStore. This will eventually be automated with BASH scripts.