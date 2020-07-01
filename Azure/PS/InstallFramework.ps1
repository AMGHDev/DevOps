#Requires -Version 3.0

<#
.DESCRIPTION
    Install .Net Framework 4.7
#>


[CmdletBinding()]
Param(
    [string]$certName,
    [string]$Channel="LTS",
    [string]$JSonFile,
    [switch]$norestart,
    [string]$Version="3.1.102",
     [string]$Runtime,
    [string]$InstallDir="c:\program files\dotnet",
    [string]$Architecture="<auto>",
    [switch]$SharedRuntime,
   [switch]$DryRun,
   [switch]$NoPath,
   [string]$AzureFeed="https://dotnetcli.azureedge.net/dotnet",
   [string]$UncachedFeed="https://dotnetcli.blob.core.windows.net/dotnet",
   [string]$FeedCredential,
   [string]$ProxyAddress,
   [switch]$ProxyUseDefaultCredentials,
   [switch]$SkipNonVersionedFiles,
   [switch]$NoCdn
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

## NET CORE
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"

if ($NoCdn) {
    $AzureFeed = $UncachedFeed
}

$BinFolderRelativePath=""

if ($SharedRuntime -and (-not $Runtime)) {
    $Runtime = "dotnet"
}

# example path with regex: shared/1.0.0-beta-12345/somepath
$VersionRegEx="/\d+\.\d+[^/]+/"
$OverrideNonVersionedFiles = !$SkipNonVersionedFiles
function Say($str) {
    Write-Host "dotnet-install: $str"
}

function Say-Verbose($str) {
    Write-Verbose "dotnet-install: $str"
}

function Say-Invocation($Invocation) {
    $command = $Invocation.MyCommand;
    $args = (($Invocation.BoundParameters.Keys | foreach { "-$_ `"$($Invocation.BoundParameters[$_])`"" }) -join " ")
    Say-Verbose "$command $args"
}

function Invoke-With-Retry([ScriptBlock]$ScriptBlock, [int]$MaxAttempts = 3, [int]$SecondsBetweenAttempts = 1) {
    $Attempts = 0

    while ($true) {
        try {
            return $ScriptBlock.Invoke()
        }
        catch {
            $Attempts++
            if ($Attempts -lt $MaxAttempts) {
                Start-Sleep $SecondsBetweenAttempts
            }
            else {
                throw
            }
        }
    }
}

function Get-Machine-Architecture() {
    Say-Invocation $MyInvocation

    # possible values: amd64, x64, x86, arm64, arm
    return $ENV:PROCESSOR_ARCHITECTURE
}

function Get-CLIArchitecture-From-Architecture([string]$Architecture) {
    Say-Invocation $MyInvocation

    switch ($Architecture.ToLower()) {
        { $_ -eq "<auto>" } { return Get-CLIArchitecture-From-Architecture $(Get-Machine-Architecture) }
        { ($_ -eq "amd64") -or ($_ -eq "x64") } { return "x64" }
        { $_ -eq "x86" } { return "x86" }
        { $_ -eq "arm" } { return "arm" }
        { $_ -eq "arm64" } { return "arm64" }
        default { throw "Architecture not supported. If you think this is a bug, report it at https://github.com/dotnet/sdk/issues" }
    }
}

# The version text returned from the feeds is a 1-line or 2-line string:
# For the SDK and the dotnet runtime (2 lines):
# Line 1: # commit_hash
# Line 2: # 4-part version
# For the aspnetcore runtime (1 line):
# Line 1: # 4-part version
function Get-Version-Info-From-Version-Text([string]$VersionText) {
    Say-Invocation $MyInvocation

    $Data = -split $VersionText

    $VersionInfo = @{
        CommitHash = $(if ($Data.Count -gt 1) { $Data[0] })
        Version = $Data[-1] # last line is always the version number.
    }
    return $VersionInfo
}

function Load-Assembly([string] $Assembly) {
    try {
        Add-Type -Assembly $Assembly | Out-Null
    }
    catch {
        # On Nano Server, Powershell Core Edition is used.  Add-Type is unable to resolve base class assemblies because they are not GAC'd.
        # Loading the base class assemblies is not unnecessary as the types will automatically get resolved.
    }
}

function GetHTTPResponse([Uri] $Uri)
{
    Invoke-With-Retry(
    {

        $HttpClient = $null

        try {
            # HttpClient is used vs Invoke-WebRequest in order to support Nano Server which doesn't support the Invoke-WebRequest cmdlet.
            Load-Assembly -Assembly System.Net.Http

            if(-not $ProxyAddress) {
                try {
                    # Despite no proxy being explicitly specified, we may still be behind a default proxy
                    $DefaultProxy = [System.Net.WebRequest]::DefaultWebProxy;
                    if($DefaultProxy -and (-not $DefaultProxy.IsBypassed($Uri))) {
                        $ProxyAddress = $DefaultProxy.GetProxy($Uri).OriginalString
                        $ProxyUseDefaultCredentials = $true
                    }
                } catch {
                    # Eat the exception and move forward as the above code is an attempt
                    #    at resolving the DefaultProxy that may not have been a problem.
                    $ProxyAddress = $null
                    Say-Verbose("Exception ignored: $_.Exception.Message - moving forward...")
                }
            }

            if($ProxyAddress) {
                $HttpClientHandler = New-Object System.Net.Http.HttpClientHandler
                $HttpClientHandler.Proxy =  New-Object System.Net.WebProxy -Property @{Address=$ProxyAddress;UseDefaultCredentials=$ProxyUseDefaultCredentials}
                $HttpClient = New-Object System.Net.Http.HttpClient -ArgumentList $HttpClientHandler
            }
            else {

                $HttpClient = New-Object System.Net.Http.HttpClient
            }
            # Default timeout for HttpClient is 100s.  For a 50 MB download this assumes 500 KB/s average, any less will time out
            # 20 minutes allows it to work over much slower connections.
            $HttpClient.Timeout = New-TimeSpan -Minutes 20
            $Response = $HttpClient.GetAsync("${Uri}${FeedCredential}").Result
            if (($Response -eq $null) -or (-not ($Response.IsSuccessStatusCode))) {
                 # The feed credential is potentially sensitive info. Do not log FeedCredential to console output.
                $ErrorMsg = "Failed to download $Uri."
                if ($Response -ne $null) {
                    $ErrorMsg += "  $Response"
                }

                throw $ErrorMsg
            }

             return $Response
        }
        finally {
             if ($HttpClient -ne $null) {
                $HttpClient.Dispose()
            }
        }
    })
}

function Get-Latest-Version-Info([string]$AzureFeed, [string]$Channel, [bool]$Coherent) {
    Say-Invocation $MyInvocation

    $VersionFileUrl = $null
    if ($Runtime -eq "dotnet") {
        $VersionFileUrl = "$UncachedFeed/Runtime/$Channel/latest.version"
    }
    elseif ($Runtime -eq "aspnetcore") {
        $VersionFileUrl = "$UncachedFeed/aspnetcore/Runtime/$Channel/latest.version"
    }
    # Currently, the WindowsDesktop runtime is manufactured with the .Net core runtime
    elseif ($Runtime -eq "windowsdesktop") {
        $VersionFileUrl = "$UncachedFeed/Runtime/$Channel/latest.version"
    }
    elseif (-not $Runtime) {
        if ($Coherent) {
            $VersionFileUrl = "$UncachedFeed/Sdk/$Channel/latest.coherent.version"
        }
        else {
            $VersionFileUrl = "$UncachedFeed/Sdk/$Channel/latest.version"
        }
    }
    else {
        throw "Invalid value for `$Runtime"
    }
    try {
        $Response = GetHTTPResponse -Uri $VersionFileUrl
    }
    catch {
        throw "Could not resolve version information."
    }
    $StringContent = $Response.Content.ReadAsStringAsync().Result

    switch ($Response.Content.Headers.ContentType) {
        { ($_ -eq "application/octet-stream") } { $VersionText = $StringContent }
        { ($_ -eq "text/plain") } { $VersionText = $StringContent }
        { ($_ -eq "text/plain; charset=UTF-8") } { $VersionText = $StringContent }
        default { throw "``$Response.Content.Headers.ContentType`` is an unknown .version file content type." }
    }

    $VersionInfo = Get-Version-Info-From-Version-Text $VersionText

    return $VersionInfo
}

function Parse-Jsonfile-For-Version([string]$JSonFile) {
    Say-Invocation $MyInvocation

    If (-Not (Test-Path $JSonFile)) {
        throw "Unable to find '$JSonFile'"
    }
    try {
        $JSonContent = Get-Content($JSonFile) -Raw | ConvertFrom-Json | Select-Object -expand "sdk" -ErrorAction SilentlyContinue
    }
    catch {
        throw "Json file unreadable: '$JSonFile'"
    }
    if ($JSonContent) {
        try {
            $JSonContent.PSObject.Properties | ForEach-Object {
                $PropertyName = $_.Name
                if ($PropertyName -eq "version") {
                    $Version = $_.Value
                    Say-Verbose "Version = $Version"
                }
            }
        }
        catch {
            throw "Unable to parse the SDK node in '$JSonFile'"
        }
    }
    else {
        throw "Unable to find the SDK node in '$JSonFile'"
    }
    If ($Version -eq $null) {
        throw "Unable to find the SDK:version node in '$JSonFile'"
    }
    return $Version
}

function Get-Specific-Version-From-Version([string]$AzureFeed, [string]$Channel, [string]$Version, [string]$JSonFile) {
    Say-Invocation $MyInvocation

    if (-not $JSonFile) {
        switch ($Version.ToLower()) {
            { $_ -eq "latest" } {
                $LatestVersionInfo = Get-Latest-Version-Info -AzureFeed $AzureFeed -Channel $Channel -Coherent $False
                return $LatestVersionInfo.Version
            }
            { $_ -eq "coherent" } {
                $LatestVersionInfo = Get-Latest-Version-Info -AzureFeed $AzureFeed -Channel $Channel -Coherent $True
                return $LatestVersionInfo.Version
            }
            default { return $Version }
        }
    }
    else {
        return Parse-Jsonfile-For-Version $JSonFile
    }
}

function Get-Download-Link([string]$AzureFeed, [string]$SpecificVersion, [string]$CLIArchitecture) {
    Say-Invocation $MyInvocation

    if ($Runtime -eq "dotnet") {
        $PayloadURL = "$AzureFeed/Runtime/$SpecificVersion/dotnet-runtime-$SpecificVersion-win-$CLIArchitecture.zip"
    }
    elseif ($Runtime -eq "aspnetcore") {
        $PayloadURL = "$AzureFeed/aspnetcore/Runtime/$SpecificVersion/aspnetcore-runtime-$SpecificVersion-win-$CLIArchitecture.zip"
    }
    elseif ($Runtime -eq "windowsdesktop") {
        $PayloadURL = "$AzureFeed/Runtime/$SpecificVersion/windowsdesktop-runtime-$SpecificVersion-win-$CLIArchitecture.zip"
    }
    elseif (-not $Runtime) {
        $PayloadURL = "$AzureFeed/Sdk/$SpecificVersion/dotnet-sdk-$SpecificVersion-win-$CLIArchitecture.zip"
    }
    else {
        throw "Invalid value for `$Runtime"
    }

    Say-Verbose "Constructed primary named payload URL: $PayloadURL"

    return $PayloadURL
}

function Get-LegacyDownload-Link([string]$AzureFeed, [string]$SpecificVersion, [string]$CLIArchitecture) {
    Say-Invocation $MyInvocation

    if (-not $Runtime) {
        $PayloadURL = "$AzureFeed/Sdk/$SpecificVersion/dotnet-dev-win-$CLIArchitecture.$SpecificVersion.zip"
    }
    elseif ($Runtime -eq "dotnet") {
        $PayloadURL = "$AzureFeed/Runtime/$SpecificVersion/dotnet-win-$CLIArchitecture.$SpecificVersion.zip"
    }
    else {
        return $null
    }

    Say-Verbose "Constructed legacy named payload URL: $PayloadURL"

    return $PayloadURL
}

function Get-User-Share-Path() {
    Say-Invocation $MyInvocation

    $InstallRoot = $env:DOTNET_INSTALL_DIR
    if (!$InstallRoot) {
        $InstallRoot = "$env:LocalAppData\Microsoft\dotnet"
    }
    return $InstallRoot
}

function Resolve-Installation-Path([string]$InstallDir) {
    Say-Invocation $MyInvocation

    if ($InstallDir -eq "<auto>") {
        return Get-User-Share-Path
    }
    return $InstallDir
}

function Is-Dotnet-Package-Installed([string]$InstallRoot, [string]$RelativePathToPackage, [string]$SpecificVersion) {
    Say-Invocation $MyInvocation

    $DotnetPackagePath = Join-Path -Path $InstallRoot -ChildPath $RelativePathToPackage | Join-Path -ChildPath $SpecificVersion
    Say-Verbose "Is-Dotnet-Package-Installed: DotnetPackagePath=$DotnetPackagePath"
    return Test-Path $DotnetPackagePath -PathType Container
}

function Get-Absolute-Path([string]$RelativeOrAbsolutePath) {
    # Too much spam
    # Say-Invocation $MyInvocation

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RelativeOrAbsolutePath)
}

function Get-Path-Prefix-With-Version($path) {
    $match = [regex]::match($path, $VersionRegEx)
    if ($match.Success) {
        return $entry.FullName.Substring(0, $match.Index + $match.Length)
    }

    return $null
}

function Get-List-Of-Directories-And-Versions-To-Unpack-From-Dotnet-Package([System.IO.Compression.ZipArchive]$Zip, [string]$OutPath) {
    Say-Invocation $MyInvocation

    $ret = @()
    foreach ($entry in $Zip.Entries) {
        $dir = Get-Path-Prefix-With-Version $entry.FullName
        if ($dir -ne $null) {
            $path = Get-Absolute-Path $(Join-Path -Path $OutPath -ChildPath $dir)
            if (-Not (Test-Path $path -PathType Container)) {
                $ret += $dir
            }
        }
    }

    $ret = $ret | Sort-Object | Get-Unique

    $values = ($ret | foreach { "$_" }) -join ";"
    Say-Verbose "Directories to unpack: $values"

    return $ret
}

# Example zip content and extraction algorithm:
# Rule: files if extracted are always being extracted to the same relative path locally
# .\
#       a.exe   # file does not exist locally, extract
#       b.dll   # file exists locally, override only if $OverrideFiles set
#       aaa\    # same rules as for files
#           ...
#       abc\1.0.0\  # directory contains version and exists locally
#           ...     # do not extract content under versioned part
#       abc\asd\    # same rules as for files
#            ...
#       def\ghi\1.0.1\  # directory contains version and does not exist locally
#           ...         # extract content
function Extract-Dotnet-Package([string]$ZipPath, [string]$OutPath) {
    Say-Invocation $MyInvocation

    Load-Assembly -Assembly System.IO.Compression.FileSystem
    Set-Variable -Name Zip
    try {
        $Zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

        $DirectoriesToUnpack = Get-List-Of-Directories-And-Versions-To-Unpack-From-Dotnet-Package -Zip $Zip -OutPath $OutPath

        foreach ($entry in $Zip.Entries) {
            $PathWithVersion = Get-Path-Prefix-With-Version $entry.FullName
            if (($PathWithVersion -eq $null) -Or ($DirectoriesToUnpack -contains $PathWithVersion)) {
                $DestinationPath = Get-Absolute-Path $(Join-Path -Path $OutPath -ChildPath $entry.FullName)
                $DestinationDir = Split-Path -Parent $DestinationPath
                $OverrideFiles=$OverrideNonVersionedFiles -Or (-Not (Test-Path $DestinationPath))
                if ((-Not $DestinationPath.EndsWith("\")) -And $OverrideFiles) {
                    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DestinationPath, $OverrideNonVersionedFiles)
                }
            }
        }
    }
    finally {
        if ($Zip -ne $null) {
            $Zip.Dispose()
        }
    }
}

function DownloadFile($Source, [string]$OutPath) {
    if ($Source -notlike "http*") {
        #  Using System.IO.Path.GetFullPath to get the current directory
        #    does not work in this context - $pwd gives the current directory
        if (![System.IO.Path]::IsPathRooted($Source)) {
            $Source = $(Join-Path -Path $pwd -ChildPath $Source)
        }
        $Source = Get-Absolute-Path $Source
        Say "Copying file from $Source to $OutPath"
        Copy-Item $Source $OutPath
        return
    }

    $Stream = $null

    try {
        $Response = GetHTTPResponse -Uri $Source
        $Stream = $Response.Content.ReadAsStreamAsync().Result
        $File = [System.IO.File]::Create($OutPath)
        $Stream.CopyTo($File)
        $File.Close()
    }
    finally {
        if ($Stream -ne $null) {
            $Stream.Dispose()
        }
    }
}

function Prepend-Sdk-InstallRoot-To-Path([string]$InstallRoot, [string]$BinFolderRelativePath) {
    $BinPath = Get-Absolute-Path $(Join-Path -Path $InstallRoot -ChildPath $BinFolderRelativePath)
    if (-Not $NoPath) {
        $SuffixedBinPath = "$BinPath;"
        if (-Not $env:path.Contains($SuffixedBinPath)) {
            Say "Adding to current process PATH: `"$BinPath`". Note: This change will not be visible if PowerShell was run as a child process."
            $env:path = $SuffixedBinPath + $env:path
        } else {
            Say-Verbose "Current process PATH already contains `"$BinPath`""
        }
    }
    else {
        Say "Binaries of dotnet can be found in $BinPath"
    }
}
$CLIArchitecture = Get-CLIArchitecture-From-Architecture $Architecture
$SpecificVersion = Get-Specific-Version-From-Version -AzureFeed $AzureFeed -Channel $Channel -Version $Version -JSonFile $JSonFile
$DownloadLink = Get-Download-Link -AzureFeed $AzureFeed -SpecificVersion $SpecificVersion -CLIArchitecture $CLIArchitecture
$LegacyDownloadLink = Get-LegacyDownload-Link -AzureFeed $AzureFeed -SpecificVersion $SpecificVersion -CLIArchitecture $CLIArchitecture

$InstallRoot = Resolve-Installation-Path $InstallDir
Say-Verbose "InstallRoot: $InstallRoot"
$ScriptName = $MyInvocation.MyCommand.Name

if ($DryRun) {
    Say "Payload URLs:"
    Say "Primary named payload URL: $DownloadLink"
    if ($LegacyDownloadLink) {
        Say "Legacy named payload URL: $LegacyDownloadLink"
    }
    $RepeatableCommand = ".\$ScriptName -Version `"$SpecificVersion`" -InstallDir `"$InstallRoot`" -Architecture `"$CLIArchitecture`""
    if ($Runtime -eq "dotnet") {
       $RepeatableCommand+=" -Runtime `"dotnet`""
    }
    elseif ($Runtime -eq "aspnetcore") {
       $RepeatableCommand+=" -Runtime `"aspnetcore`""
    }
    foreach ($key in $MyInvocation.BoundParameters.Keys) {
        if (-not (@("Architecture","Channel","DryRun","InstallDir","Runtime","SharedRuntime","Version") -contains $key)) {
            $RepeatableCommand+=" -$key `"$($MyInvocation.BoundParameters[$key])`""
        }
    }
    Say "Repeatable invocation: $RepeatableCommand"
    exit 0
}

if ($Runtime -eq "dotnet") {
    $assetName = ".NET Core Runtime"
    $dotnetPackageRelativePath = "shared\Microsoft.NETCore.App"
}
elseif ($Runtime -eq "aspnetcore") {
    $assetName = "ASP.NET Core Runtime"
    $dotnetPackageRelativePath = "shared\Microsoft.AspNetCore.App"
}
elseif ($Runtime -eq "windowsdesktop") {
    $assetName = ".NET Core Windows Desktop Runtime"
    $dotnetPackageRelativePath = "shared\Microsoft.WindowsDesktop.App"
}
elseif (-not $Runtime) {
    $assetName = ".NET Core SDK"
    $dotnetPackageRelativePath = "sdk"
}
else {
    throw "Invalid value for `$Runtime"
}

#  Check if the SDK version is already installed.
$isAssetInstalled = Is-Dotnet-Package-Installed -InstallRoot $InstallRoot -RelativePathToPackage $dotnetPackageRelativePath -SpecificVersion $SpecificVersion
if ($isAssetInstalled) {
    Say "$assetName version $SpecificVersion is already installed."
    Prepend-Sdk-InstallRoot-To-Path -InstallRoot $InstallRoot -BinFolderRelativePath $BinFolderRelativePath
    exit 0
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$installDrive = $((Get-Item $InstallRoot).PSDrive.Name);
$diskInfo = Get-PSDrive -Name $installDrive
if ($diskInfo.Free / 1MB -le 100) {
    Say "There is not enough disk space on drive ${installDrive}:"
    exit 0
}

$ZipPath = [System.IO.Path]::combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
Say-Verbose "Zip path: $ZipPath"

$DownloadFailed = $false
Say "Downloading link: $DownloadLink"
try {
    DownloadFile -Source $DownloadLink -OutPath $ZipPath
}
catch {
    Say "Cannot download: $DownloadLink"
    if ($LegacyDownloadLink) {
        $DownloadLink = $LegacyDownloadLink
        $ZipPath = [System.IO.Path]::combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
        Say-Verbose "Legacy zip path: $ZipPath"
        Say "Downloading legacy link: $DownloadLink"
        try {
            DownloadFile -Source $DownloadLink -OutPath $ZipPath
        }
        catch {
            Say "Cannot download: $DownloadLink"
            $DownloadFailed = $true
        }
    }
    else {
        $DownloadFailed = $true
    }
}

if ($DownloadFailed) {
    throw "Could not find/download: `"$assetName`" with version = $SpecificVersion`nRefer to: https://aka.ms/dotnet-os-lifecycle for information on .NET Core support"
}

Say "Extracting zip from $DownloadLink"
Extract-Dotnet-Package -ZipPath $ZipPath -OutPath $InstallRoot

#  Check if the SDK version is installed; if not, fail the installation.
$isAssetInstalled = $false

# if the version contains "RTM" or "servicing"; check if a 'release-type' SDK version is installed.
if ($SpecificVersion -Match "rtm" -or $SpecificVersion -Match "servicing") {
    $ReleaseVersion = $SpecificVersion.Split("-")[0]
    Say-Verbose "Checking installation: version = $ReleaseVersion"
    $isAssetInstalled = Is-Dotnet-Package-Installed -InstallRoot $InstallRoot -RelativePathToPackage $dotnetPackageRelativePath -SpecificVersion $ReleaseVersion
}

#  Check if the SDK version is installed.
if (!$isAssetInstalled) {
    Say-Verbose "Checking installation: version = $SpecificVersion"
    $isAssetInstalled = Is-Dotnet-Package-Installed -InstallRoot $InstallRoot -RelativePathToPackage $dotnetPackageRelativePath -SpecificVersion $SpecificVersion
}

if (!$isAssetInstalled) {
    throw "`"$assetName`" with version = $SpecificVersion failed to install with an unknown error."
}

Remove-Item $ZipPath

Prepend-Sdk-InstallRoot-To-Path -InstallRoot $InstallRoot -BinFolderRelativePath $BinFolderRelativePath

Say "Installation finished"

## END netcore


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

