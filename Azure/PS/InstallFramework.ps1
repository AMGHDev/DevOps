#Requires -Version 3.0

<#
.DESCRIPTION
    Install .Net Framework 4.7
#>


[CmdletBinding()]
Param(
    [string]$certName,
    [switch]$norestart    
)

Set-StrictMode -Version Latest
$logFile = Join-Path $env:TEMP -ChildPath "InstallNetFx47ScriptLog.txt"

## cert install
if ($certname -ne $null -and $certname -ne "") {
    $subject=$certName
    $userGroup="NETWORK SERVICE"

    "Checking permissions to certificate $subject.." | Tee-Object -FilePath $logFile -Append

    $cert = (gci Cert:\LocalMachine\My\ | where { $_.Subject.Contains($subject) })[-1]

    if ($cert -eq $null)
    {
        $message="Certificate with subject:"+$subject+" does not exist at Cert:\LocalMachine\My\"
        $message | Tee-Object -FilePath $logFile -Append
    }elseif($cert.HasPrivateKey -eq $false){
        $message="Certificate with subject:"+$subject+" does not have a private key"
        $message | Tee-Object -FilePath $logFile -Append
    }else
    {
        $keyName=$cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName

        $keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\"
        $fullPath=$keyPath+$keyName
        $acl=(Get-Item $fullPath).GetAccessControl('Access')

        $hasPermissionsAlready = ($acl.Access | where {$_.IdentityReference.Value.Contains($userGroup.ToUpperInvariant()) -and $_.FileSystemRights -eq [System.Security.AccessControl.FileSystemRights]::FullControl}).Count -eq 1

        if ($hasPermissionsAlready){
            "Account $userGroup already has permissions to certificate '$subject'." | Tee-Object -FilePath $logFile -Append
        } else {
            "Need add permissions to '$subject' certificate..." | Tee-Object -FilePath $logFile -Append

	        $permission=$userGroup,"Full","Allow"
	        $accessRule=new-object System.Security.AccessControl.FileSystemAccessRule $permission
	        $acl.AddAccessRule($accessRule)
	        Set-Acl $fullPath $acl

	        "Permissions were added" | Tee-Object -FilePath $logFile -Append
        }
    }
}
### end cert


# Check if the latest NetFx47 version exists
$netFxKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full\\" -ErrorAction Ignore

if($netFxKey -and $netFxKey.Version.StartsWith("4.7")) {
    "$(Get-Date): The machine already has NetFx 4.7 or later version installed." | Tee-Object -FilePath $logFile -Append
    exit 0
}

# Download the latest NetFx47
$setupFileSourceUri = "https://download.microsoft.com/download/D/D/3/DD35CC25-6E9C-484B-A746-C5BE0C923290/NDP47-KB3186497-x86-x64-AllOS-ENU.exe"
$setupFileLocalPath = Join-Path $env:TEMP -ChildPath "NDP47-KB3186497-x86-x64-AllOS-ENU.exe"

"$(Get-Date): Start to download NetFx 4.7 to $setupFileLocalPath." | Tee-Object -FilePath $logFile -Append

if(Test-Path $setupFileLocalPath)
{
    Remove-Item -Path $setupFileLocalPath -Force
}

$webClient = New-Object System.Net.WebClient

$retry = 0

do
{
    try {
        $webClient.DownloadFile($setupFileSourceUri, $setupFileLocalPath)
        break
    }
    catch [Net.WebException] {
        $retry++

        if($retry -gt 3) {
            "$(Get-Date): Download failed as the network connection issue. Exception detail: $_" | Tee-Object -FilePath $logFile -Append
            break
        }

        $waitInSecond = $retry * 30
        "$(Get-Date): It looks the Internet network is not available now. Simply wait for $waitInSecond seconds and try again." | Tee-Object -FilePath $logFile -Append
        Start-Sleep -Second $waitInSecond
    }
} while ($true)


if(!(Test-Path $setupFileLocalPath))
{
    "$(Get-Date): Failed to download NetFx 4.7 setup package." | Tee-Object -FilePath $logFile -Append
    exit -1
}

# Install NetFx47
$setupLogFilePath = Join-Path $env:TEMP -ChildPath "NetFx47SetupLog.txt"
if($norestart) {
    $arguments = "/q /norestart /serialdownload /log $setupLogFilePath"
}
else {
    $arguments = "/q /serialdownload /log $setupLogFilePath"
}
"$(Get-Date): Start to install NetFx 4.7" | Tee-Object -FilePath $logFile -Append
$process = Start-Process -FilePath $setupFileLocalPath -ArgumentList $arguments -Wait -PassThru

if(-not $process) {
    "$(Get-Date): Install NetFx failed." | Tee-Object -FilePath $logFile -Append
    exit -1
}
else {
    $exitCode = $process.ExitCode

    # 0, 1641 and 3010 indicate success. See https://msdn.microsoft.com/en-us/library/ee390831(v=vs.110).aspx for detail.
    if($exitCode -eq 0 -or $exitCode -eq 1641 -or $exitCode -eq 3010) {
        "$(Get-Date): Install NetFx succeeded with exit code : $exitCode." | Tee-Object -FilePath $logFile -Append
        exit 0
    }
    else {
        "$(Get-Date): Install NetFx failed with exit code : $exitCode." | Tee-Object -FilePath $logFile -Append
        exit -1
    }
}

