<#
    .SYNOPSIS
    Checks the machine for Sitecore Container compatibility.

    .DESCRIPTION

    Quickly verify Sitecore Container:
        - Hardware requirements (CPU, RAM, DISK STORAGE and TYPES)
        - Operating system compatibility (OS Build Version, Hyper-V/Containers Feature Check, IIS Running State)
        - Software requirements (Docker Desktop, Docker engine OS type Linux vs Windows Containers, DNS setting, Docker network access, SitecoreDockerTools PSModule)
        - Host Network Port Check (443, 8079, 8984, 14330)

    Download and Install required software:
        - Chocolatey
        - Docker Desktop
        - mkcert

    Enable required Windows Features
        - Containers
        - Hyper-V

    Download latest 10.X.X
        - Container Package ZIP
        - Local Development Installation Guide (accessed through browser)

    Open Container Docs

    .AUTHOR
     @GabeStreza
#>

[CmdletBinding()]
param (
    # Run script in unattended mode (no prompts)
    [Parameter()]
    [switch]
    $Unattended,

    # Execute specified menu option in unattended mode; default is full prerequisite check
    [Parameter()]
    [int]
    $menuSelection = 0,

    # Suppress all output
    [Parameter()]
    [switch]
    $Quiet,

    # Suppress Docker DNS test passing requirement
    [Parameter()]
    [switch]
    $SuppressDockerDNSRequirement
)

function Invoke-Menu () {
    # 'Invoke-Menu' is inspired by Josiah Deal: https://community.spiceworks.com/scripts/show/4656-powershell-create-menu-easily-add-arrow-key-driven-menu-to-scripts
    param(
        [Parameter(Mandatory = $True)][String]$MenuTitle,
        [Parameter(Mandatory = $True)][array]$MenuOptions
    )

    $MaxValue = $MenuOptions.count - 1
    $Selection = 0
    $EnterPressed = $false
    
    Clear-Host


    while ($EnterPressed -eq $false) {
        
        Write-Host "`n$MenuTitle`n" -ForegroundColor Cyan
        Write-Host "Script developed by @GabeStreza`nhttps://streza.dev`n" -ForegroundColor Magenta
        Write-Host "Enhanced by the Sitecore community `n" -ForegroundColor Magenta
        Write-Host "Sitecore Container Docs`n > https://containers.doc.sitecore.com/`n" -ForegroundColor DarkCyan

        for ($i = 0; $i -le $MaxValue; $i++) {
            
            if ($i -eq $Selection) {
                Write-Host -BackgroundColor Cyan -ForegroundColor Black "$($MenuOptions[$i])"
            }
            else {
                Write-Host "  $($MenuOptions[$i])  "
            }
        }

        $KeyInput = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").virtualkeycode

        switch ($KeyInput) {
            13 {
                $EnterPressed = $True
                return $Selection
                Clear-Host
                break
            }

            38 {
                if ($Selection -eq 0) {
                    $Selection = $MaxValue
                }
                else {
                    $Selection -= 1
                }
                Clear-Host
                break
            }

            40 {
                if ($Selection -eq $MaxValue) {
                    $Selection = 0
                }
                else {
                    $Selection += 1
                }
                Clear-Host
                break
            }
            default {
                Clear-Host
            }
        }
    }
}

function Invoke-HardwareCheck {
    ########## Checking number of CPU cores */
    Write-Host "`n`nCHECKING CORES..." -ForegroundColor Cyan

    $cores = Get-CimInstance -class Win32_processor
    if ($cores.NumberOfCores -ge 4) {
        Write-Host "+ Minimum number of cores (4) confirmed: " $cores.NumberOfCores " cores installed." -ForegroundColor Green
        $script:HwCoresCheckPassed = $true
    }
    else {
        Write-Host "X Minimum number of cores (4) not available." -ForegroundColor Red
        Write-Host "Currently installed: " $cores.NumberOfCores -ForegroundColor Red
    }

    ########## Checking minimum RAM requirements */
    Write-Host "`n`nCHECKING RAM..." -ForegroundColor Cyan
    $RAMinGB = [Math]::Round((Get-CimInstance -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($RAMinGB -ge 16.0) {
        Write-Host "+ Minimum RAM (16GB) confirmed: " $RAMinGB "GB installed." -ForegroundColor Green
        $script:hwRAMCheckPassed = $true
        if ($RAMinGB -ge 32.0) {
            Write-Host "+ Recommended RAM (32GB) confirmed: " $RAMinGB "GB installed." -ForegroundColor Green
        }
    }
    else {
        Write-Host "X Minimum RAM not available." -ForegroundColor Red
    }

    ########## Checking minimum disk drive requirements */
    Write-Host "`n`nCHECKING DISK TYPE & STORAGE..." -ForegroundColor Cyan

    $AvailableDiskSpace = Get-CimInstance -Class Win32_LogicalDisk -Filter 'DriveType = 3' 
    $driveCount = 0;
    $ssdCount = 0;
    $DeviceDrives = $AvailableDiskSpace | Select-Object DeviceID, DeviceType, @{n = 'FreeSpace'; e = { [int]($_.FreeSpace / 1GB) } }, @{n = 'Size'; e = { [int]($_.Size / 1GB) } } 
    $DeviceDrives | ForEach-Object {
        if ($_.Size -ge 25) {
            Write-Host "+ Minimum Disk space available for '$($_.DeviceID)' drive ($($_.FreeSpace) GB / $($_.Size) GB) met." -ForegroundColor Green
            $driveCount++
        }
    }

    # Check number of SSDs 
    Get-PhysicalDisk | Select-Object MediaType | ForEach-Object { 
        $ssdCount++
    }

    if ($driveCount -ge 1) {
        Write-Host "+ At least one drive with required 25 GB free space is available." -ForegroundColor Green
        $script:diskStorageCheckPassed = $true
    }
    else {
        Write-Host "X Minimum disk space (25 GB) not available." -ForegroundColor Red
    }

    if ($ssdCount -eq $driveCount) {
        Write-Host "+ All disks are SSD." -ForegroundColor Green
        $script:diskTypeCheckPassed = $true
    }
    elseif ($ssdCount -ge 1) {
        Write-Host "+ At least one disk is an SSD out of $driveCount drives detected." -ForegroundColor Yellow
        $script:diskTypeCheckPassed = $true
    }
    else {
        Write-Host "X No SSD drives detected. Sitecore recommends running Docker environments on SSDs over HDDs." -ForegroundColor Red
    }
}

function Invoke-OperatingSystemCheck {
    ########## Check OS version Windows 10/Server 1903 or later */
    Write-Host "`n`nCHECKING OPERATING SYSTEM COMPATIBILITY..." -ForegroundColor Cyan

    $OSVersion    = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName
    $OSProductName = $OSVersion.ProductName
    $build        = [System.Environment]::OSVersion.Version.Build

    # initialize flags
    $script:OSCheckPassed             = $false
    $script:ProcessIsolationSupported = $false

    # only Pro / Enterprise / Education qualify
    if ($OSProductName -notmatch 'Enterprise|Professional|Education|Pro') {
        Write-Host "X $OSProductName detected.`n  > Docker requires Windows 10/11 Professional, Enterprise, or Education." -ForegroundColor Red
        return
    }

    if ($OSProductName -match 'Windows 10') {

        # need 1903 (build 18362)+ for Docker
        if ($build -lt 18362) {
            Write-Host "X $OSProductName build $build detected.`n  > Requires Windows 10 1903 (build 18362) or later." -ForegroundColor Red
            return
        }

        # at this point general Docker support is OK
        $script:OSCheckPassed = $true

        # need 1909 (build 18363)+ for process isolation
        if ($build -ge 18363) {
            Write-Host "+ $OSProductName build $build detected; Docker & Process Isolation supported." -ForegroundColor Green
            $script:ProcessIsolationSupported = $true
        }
        else {
            Write-Host "⚠ $OSProductName build $build detected (1903). Docker OK; Process Isolation requires 1909 (build 18363) or later." -ForegroundColor Yellow
        }
    }
    elseif ($OSProductName -match 'Windows 11') {
        # any Windows 11 Pro/Ent/Edu build is fine
        Write-Host "+ $OSProductName build $build detected; Docker & Process Isolation supported." -ForegroundColor Green
        $script:OSCheckPassed             = $true
        $script:ProcessIsolationSupported = $true
    }
    else {
        Write-Host "X Unsupported Windows version: $OSProductName detected." -ForegroundColor Red
    }

    if ($script:OSCheckPassed) {
        Write-Host "+ Operating system is compatible." -ForegroundColor Green
    }
    else {
        Write-Host "X Operating system is not compatible." -ForegroundColor Red
    }

    ########## Check Containers Windows Feature is enabled */
    Write-Host "`n`nVERIFYING CONTAINERS FEATURE STATE..." -ForegroundColor Cyan

    $containersService = Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "Containers" }
    if ($containersService.State -eq "Enabled") {
        Write-Host "+ The 'Containers' feature is enabled." -ForegroundColor Green
        $script:containersFeatureEnabled = $true
    }
    else {
        Write-Host "X The 'Containers' feature is disabled." -ForegroundColor Red
    }
    
    ########## Check Hyper-V Windows Feature is enabled */
    Write-Host "`n`nVERIFYING HYPER-V FEATURE STATE..." -ForegroundColor Cyan

    $hyperVService = Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "Microsoft-Hyper-V" }
    if ($hyperVService.State -eq "Enabled") {
        Write-Host "+ The 'Microsoft-Hyper-V' feature is enabled." -ForegroundColor Green
        $script:hyperVEnabled = $true
    }
    else {
        Write-Host "X The 'Microsoft-Hyper-V' feature is disabled." -ForegroundColor Red
    }

    ########## Check that IIS is turned OFF  */
    Write-Host "`n`nDETECTING IIS RUNNING STATE..." -ForegroundColor Cyan

    $iis = (Get-CimInstance Win32_Service -Filter "Name='W3svc'")
    if ($iis.State -eq "Running") {
        Write-Host "X IIS is running.  Turn off IIS." -ForegroundColor Red
    } 
    else {
        $script:IISOffCheckPassed = $true
        Write-Host "+ IIS not running." -ForegroundColor Green
    }

    ########## Check for problematic cbfsconnect2017 driver  */
    Write-Host "`n`nDETECTING CBFSCONNECT2017 DRIVER VERSION..." -ForegroundColor Cyan
    $driver = Get-CimInstance Win32_SystemDriver -filter "name='cbfsconnect2017'"
    if (-not $driver) {
        Write-Host "+ cbfsconnect2017 not installed (this is good)." -ForegroundColor Green
    }
    else {
        $driverFile = Get-Item $driver.PathName.Substring(4) # PathName has a \??\ prefix
        if ($driverFile.VersionInfo.FileVersionRaw.Build -lt 27) {
            Write-Host "X You have a conflicting cbfsconnect2017 driver version from Box or other software. Install software with an updated driver version." -ForegroundColor Red
            Write-Host "More information: https://github.com/docker/for-win/issues/3884" -ForegroundColor Red
        }
        else {
            Write-Host "+ cbfsconnect2017 driver is compatible." -ForegroundColor Green
        }
    }
}

function Invoke-SoftwareCheck {
    ########## Check that Docker in installed  */
    Write-Host "`n`nVERIFYING DOCKER DESKTOP IS INSTALLED..." -ForegroundColor Cyan
    $AvailableDiskSpace = Get-CimInstance -Class Win32_LogicalDisk -Filter 'DriveType = 3' 
    $DeviceDrives = $AvailableDiskSpace | Select-Object DeviceID 
    foreach ($drive in $DeviceDrives) {
        $dockerProgramFilesPath = "$($drive.DeviceID)\Program Files\Docker";
        if (Test-Path -Path $dockerProgramFilesPath) {
            Write-Host "+ Docker found installed at '$dockerProgramFilesPath'" -ForegroundColor Green
            $script:dockerInstalled = $true
        }

        $dockerProgramDataPath = "$($drive.DeviceID)\ProgramData\Docker";
        if (Test-Path -Path $dockerProgramDataPath) {
            if ((Get-ChildItem $dockerProgramDataPath | Measure-Object).Count) {
                Write-Host "+ Docker found installed at '$dockerProgramDataPath'" -ForegroundColor Green
                $script:dockerInstalled = $true
            }
        }

        if ($script:dockerInstalled -eq $true) {
            $dockerProgramFilesPath = "$($drive.DeviceID)\Program Files\Docker";
            if (Test-Path -Path $dockerProgramFilesPath) {
                $daemonJsonFile = "$($drive.DeviceID)\ProgramData\Docker\config\daemon.json"
                if (Test-path -Path $daemonJsonFile) {
                    $dnsSetting = (Get-Content $daemonJsonFile | ConvertFrom-Json | Select-Object dns).dns 
                    if (($dnsSetting | Measure-Object).Count -gt 0 -and (($dnsSetting -match "8.8.8.8") -or ($dnsSetting -match "1.1.1.1"))) {
                        Write-Host "+ Docker DNS is set to Google's and/or CloudFlare's public DNS server(s):  $dnsSetting"  -ForegroundColor Green
                    }
                    else {
                        Write-Host "- Docker's '$($drive.DeviceID)\ProgramData\Docker\config\daemon.json' configuration is not set to Google's and/or CloudFlare's public DNS server(s): 8.8.8.8 or 1.1.1.1.`nCurrent setting:  $dnsSetting `nNote: This may not be required if network configuration works well or if DNS is specfied in docker or docker-compose." -ForegroundColor Yellow
                    }
                }                
                else {
                    Write-Host "- Cannot check DNS settings because cannot find the settings file path '$($daemonJsonFile)'. Try making sure you are running Docker Desktop in Windows Containers mode via the GUI or running '$($drive.DeviceID)\Program Files\docker\docker\DockerCLI.exe -SwitchDaemon' if you cannot access the Docker tray icon." -ForegroundColor Yellow
                }
            }
        }
    }
    if ($script:dockerInstalled -eq $false) {
        Write-Host "X Docker does not appear to be installed." -ForegroundColor Red
    }

    ########## Check if Docker services are running  */
    Write-Host "`n`nVERIFYING DOCKER SERVICES ARE RUNNING..." -ForegroundColor Cyan

    if ($script:dockerInstalled = $true) {
        $DockerDesktopServiceName = "com.docker.service"
        try {
            $dockerDesktopService = Get-Service -Name $DockerDesktopServiceName -ErrorAction SilentlyContinue
            if ($dockerDesktopService.Status -eq "Running") {
                Write-Host "+ Docker Desktop service is running." -ForegroundColor Green
                $script:dockerRunning = $true
            }
            else {
                Write-Host "X Docker Desktop service is not running." -ForegroundColor Red
                $script:dockerRunning = $false
            }
        }
        catch {
            Write-Host "X Docker Desktop service is not running." -ForegroundColor Red
            $script:dockerRunning = $false
        }
    
        $DockerDaemonServiceName = "docker"
        try {
            $dockerDaemonService = Get-Service -Name $DockerDaemonServiceName  -ErrorAction Stop
            if ($dockerDaemonService.Status -eq "Running") {
                Write-Host "+ Docker daemon service is running." -ForegroundColor Green
                $script:dockerRunning = $true
            }
            else {
                Write-Host "+ Docker daemon service not running." -ForegroundColor Red
                $script:dockerRunning = $false
            }
        }
        catch {
            Write-Host "X Docker daemon service is not running." -ForegroundColor Red
            $script:dockerRunning = $false
        }

        if ($script:dockerRunning) {
            if (((docker version) | Where-Object { $_ -match "linux" }).count) {
                Write-Host "X Docker Desktop is currently configured for Linux containers. Switch to Windows Containers." -ForegroundColor Red
                $script:dockerRunning = $false
            }
            else {
                Write-Host "+ Docker Desktop is currently configured for Windows Containers." -ForegroundColor Green
            }
        }
    }

    if ($script:dockerInstalled -and $script:dockerRunning) {
        ########## Check if Docker services are running  */
        Write-Host "`n`nVERIFYING DOCKER NETWORK ACCESS..." -ForegroundColor Cyan

        Write-Host "`Trying without forced DNS..." -ForegroundColor Cyan
        $dockerNetworkSuccess = (& docker run --rm mcr.microsoft.com/powershell:lts-nanoserver-1809 pwsh.exe -Command Test-Connection -TcpPort 80 -TargetName nuget.org)
        if ($dockerNetworkSuccess -eq "True") {
            Write-Host "+ Docker Desktop can successfully reach the internet with current workstation and/or DNS settings." -ForegroundColor Green
            $script:dockerDNSSuccess = $true
        }
        else {
            Write-Host "`Trying again with forced DNS (okay if test above without forced DNS failed as long as this next, forced DNS test works)..." -ForegroundColor Cyan
            $dockerNetworkSuccess = (& docker run --rm --dns 1.1.1.1 --dns 8.8.8.8 mcr.microsoft.com/powershell:lts-nanoserver-1809 pwsh.exe -Command Test-Connection -TcpPort 80 -TargetName nuget.org)
            if ($dockerNetworkSuccess -eq "True")
            {
                Write-Host "+ Docker Desktop can successfully reach the internet with forced Google + CloudFlare Public DNS settings. This may mean that you need to use similar settings in your Docker daemon.json (for all solutions) or the docker-compose.yml for your solution(s)." -ForegroundColor Yellow
                $script:dockerDNSSuccess = $true
            }
            else {
                Write-Host "X Docker Desktop cannot reach the internet. Check Docker network configuration and the InterfaceMetric values on your network adapter." -ForegroundColor Red
                Write-Host "https://github.com/docker/for-win/issues/2760#issuecomment-430889666" -ForegroundColor Red
            }
        }
    }

    ########## Check for SitecoreDockerTools PSModule install status  */
    Write-Host "`n`nVERIFYING 'SitecoreDockerTools' POWERSHELL MODULE IS INSTALLED..." -ForegroundColor Cyan
    Invoke-SitecoreDockerToolsCheck

    ########## Check for Sitecore License persisted in user environment variable */
    Write-Host "`n`nCHECKING FOR PERSISTENT SITECORE LICENSE USER ENVIRONMENT VARIABLE (REQUIRES RUN IN WINDOWS TERMINAL OR POWERSHELL)..." -ForegroundColor Cyan
    Invoke-SitecoreLicenseUserVariableCheck
}

function Invoke-NetworkPortCheck {

    ########## Checking required TCP port availability  */
    Write-Host "`n`nCHECKING REQUIRED TCP PORT AVAILABILITY..." -ForegroundColor Cyan

    [hashtable[]]$portsToCheck = @(
        @{
            Port = [int]443
            RequiredForDescription = 'Traefik HTTPS proxy'
        },
        @{
            Port = [int]8079
            RequiredForDescription = 'Traefik dashboard'
        },
        @{
            Port = [int]8081
            RequiredForDescription = 'xConnect'
        },
        @{
            Port = [int]8984
            RequiredForDescription = 'Solr API and dashboard'
        },
        @{
            Port = [int]14330
            RequiredForDescription = 'SQL Server'
        }          
    );

    [int]$tcpPortAvailableCount = 0
    [Microsoft.Management.Infrastructure.CimInstance[]]$netTcpConnections = Get-NetTCPConnection;
        
    foreach($curPort in $portsToCheck){

        [Microsoft.Management.Infrastructure.CimInstance[]]$curPortConnections = $netTcpConnections | Where-Object Localport -eq $curPort.Port;
        [string]$successOrFailureSymbol = $null;
        [string]$not = $null;
        [string]$textColor = $null;

        if ($null -ne $curPortConnections -and $curPortConnections.Length -gt 0){
            $successOrFailureSymbol = 'X';
            $not = ' not';
            $textColor = 'Red';
        } else{
            $successOrFailureSymbol = '+';
            $not = '';            
            $tcpPortAvailableCount++            
            $textColor = 'Green';
        };

        Write-Host "$($successOrFailureSymbol) TCP port $($curPort.Port) (required for $($curPort.RequiredForDescription)) is$($not) available." -ForegroundColor ($textColor);
    };

    if ($tcpPortAvailableCount -eq $portsToCheck.Length) {
        $script:tcpPortsAvailable = $true
    };
}

function Invoke-FullPrerequisiteCheck {
    Invoke-HardwareCheck
    Invoke-OperatingSystemCheck
    Invoke-SoftwareCheck
    Invoke-NetworkPortCheck

    Write-Host "`n**********************************************`n" -ForegroundColor Cyan 

    if ($script:HwCoresCheckPassed -and $script:hwRAMCheckPassed -and $script:diskStorageCheckPassed -and $script:OSCheckPassed -and $script:IISOffCheckPassed -and $script:hyperVEnabled -and $script:containersFeatureEnabled -and $script:dockerInstalled -and $script:dockerRunning -and $script:dockerDNSSuccess -and $script:tcpPortsAvailable -and $psModuleScDockerTools) {
        Write-Host "This machine is READY to for Sitecore Containers!`n`n" -ForegroundColor Green
    }
    else {
        Write-Host "X This machine may not be quite ready for Sitecore Containers.`n`n" -ForegroundColor Red
    }
}

function Install-Chocolatey {
    # Check if Chocolaty is installed
    if ((Get-ChildItem -Path Env:\ | Where-Object { $_.Name -match "Chocolatey" }).Count -eq 0) {
        Write-Host "X Chocolatey is not installed." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    else {
        Write-Host "+ Chocolatey is already installed." -ForegroundColor Green
    }
}

function Install-DockerDesktop {
    if ((Get-ChildItem -Path Env:\ | Where-Object { $_.Name -match "Chocolatey" }).Count -eq 0) {
        Write-Host "X Chocolatey is not installed yet.  Cannot installed 'Docker Desktop'." -ForegroundColor Yellow
    }
    else {
        choco install docker-desktop
    }
  
}

function Install-Mkcert {
    if ((Get-ChildItem -Path Env:\ | Where-Object { $_.Name -match "Chocolatey" }).Count -eq 0) {
        Write-Host "X Chocolatey is not installed yet.  Cannot installed 'mkcert'." -ForegroundColor Yellow
    }
    else {
        choco install mkcert
    }
}

function Invoke-SitecoreDockerToolsCheck {
    if (((Get-PSRepository -Name SitecoreGallery -ErrorAction SilentlyContinue) | Measure-Object).Count -gt 0) {
        Write-Host "+ 'SitecoreGallery' successfully registered." -ForegroundColor Green
    }
    else {
        Write-Host "+ 'SitecoreGallery' is not registered" -ForegroundColor Yellow
    }

    if ((Get-InstalledModule SitecoreDockerTools -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        Write-Host "+ 'SitecoreDockerTools' PowerShell Module is installed." -ForegroundColor Green
        $script:psModuleScDockerTools = $true
    }
    else {
        Write-Host "+ 'SitecoreDockerTools' PowerShell Module is not installed." -ForegroundColor Yellow
        $script:psModuleScDockerTools = $false
    }
}

function Install-SitecoreDockerTools {
    if (((Get-PSRepository -Name SitecoreGallery -ErrorAction SilentlyContinue) | Measure-Object).Count -gt 0) {
        Write-Host "`n+ 'SitecoreGallery' successfully registered.`n" -ForegroundColor Green
    }
    else {
        Write-Host "`n+ 'Registering 'SitecoreGallery' with SourceLocation set to 'https://sitecore.myget.org/F/sc-powershell/api/v2'... " -ForegroundColor Yellow
        Register-PSRepository -Name SitecoreGallery -SourceLocation https://sitecore.myget.org/F/sc-powershell/api/v2
        Write-Host "+ 'SitecoreGallery' successfully registered.`n" -ForegroundColor Green
    }

    if ((Get-InstalledModule SitecoreDockerTools -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        Write-Host "+ 'SitecoreDockerTools' PowerShell Module is installed." -ForegroundColor Green
    }
    else {
        Write-Host "+ 'SitecoreDockerTools' PowerShell Module is installing..." -ForegroundColor Yellow
        Install-Module SitecoreDockerTools
        Write-Host "+ 'SitecoreDockerTools' PowerShell Module is installed." -ForegroundColor Green
    }
    $script:psModuleScDockerTools = $true
    Import-Module SitecoreDockerTools
}

function Enable-ContainersFeature {
    Enable-WindowsOptionalFeature -Online -FeatureName containers -All
}

function Enable-HyperVFeature {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
}

function Invoke-SitecoreContainerGuideDownload {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)] [String] $Version
    )

    # Open the product's downloads page in default browser
    $parts = $Version.Split('.')
    $versionCode = "{0}{1}" -f $parts[0], $parts[1]
    $url = "https://developers.sitecore.com/downloads/Sitecore_Experience_Platform/$versionCode/Sitecore_Experience_Platform_$versionCode"
    Write-Host "Opening Sitecore Experience Platform $Version downloads page: $url" -ForegroundColor Cyan
    Start-Process $url

    Invoke-Pause
}

function Invoke-SitecoreContainerPackageDownload {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)] [String] $Version
    )

    if($Version -eq "10.0.0"){
        Invoke-PackageDownload -FullVersion "10.0.0.004346.184"
    }elseif ($Version -eq "10.0.1") {
        Invoke-PackageDownload -FullVersion "10.0.1.004842.221"
    }elseif ($Version -eq "10.0.2") {
        Invoke-PackageDownload -FullVersion "10.0.1.004842.266"
    }elseif ($Version -eq "10.1.0") {
        Invoke-PackageDownload -FullVersion "10.1.0.005207.309"
    }elseif ($Version -eq "10.1.1") {
        Invoke-PackageDownload -FullVersion "10.1.1.005862.645"
    }elseif ($Version -eq "10.1.2") {
        Invoke-PackageDownload -FullVersion "10.1.2.006578.651"
    }elseif ($Version -eq "10.2.0") {
        Invoke-PackageDownload -FullVersion "10.2.0.006766.683"
    }elseif ($Version -eq "10.3.2") {
        Invoke-PackageDownload -FullVersion "10.3.2.010837.1896"
    }elseif ($Version -eq "10.4.0") {
        Invoke-PackageDownload -FullVersion "10.4.0.010422.1819"
    }
}

function Invoke-PackageDownload{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]
        $FullVersion
    )
    $LocalFileNameFormat = "SXP_Sitecore_Container_Deployment.{0}.zip"
    $ReleasePageUrlFormat = "https://github.com/Sitecore/container-deployment/releases/tag/sxp%2F{0}"
    $RemoteFileUrlFormat = "https://github.com/Sitecore/container-deployment/releases/download/sxp%2F{0}/SitecoreContainerDeployment.{1}.zip"

    $FileName = $([string]::Format($LocalFileNameFormat, $FullVersion))
    $FileUrl = $([string]::Format($RemoteFileUrlFormat, $FullVersion, $FullVersion))
    $ReleasePageUrl = $([string]::Format($ReleasePageUrlFormat, $FullVersion))
    Write-Host "Downloading '$FileName' to $((Get-Location).Path).`n" -ForegroundColor Magenta
    Invoke-WebRequest -Uri $FileUrl -OutFile ".\$FileName"
    Invoke-Item "$((Get-Location).Path)\$FileName"
    Start-Process $ReleasePageUrl
    Invoke-Pause
}
function Invoke-OpenContainerDocs {
    $Url = "https://doc.sitecore.com/xp/en/developers/104/developer-tools/containers-in-sitecore-development.html"
    Start-Process $Url
    Invoke-Pause
}

function Invoke-SCPGithubRepo {
    $Url = "https://github.com/strezag/sitecore-containers-prerequisites"
    Start-Process $Url
    Invoke-Pause
}

function Invoke-SitecoreLicenseUserVariableCheck {
    $userVariable = [Environment]::GetEnvironmentVariable("SITECORE_LICENSE", "User")
    if (! $userVariable) {
        Write-Host "+ No Sitecore License in a persisted user environment variable found. This works well when SITECORE_LICENSE variable is set dynamically on container up." -ForegroundColor Green
    }
    else {
        Write-Host "+ A Sitecore license is stored in a persisted user environment variable. This may interfere with solutions using a license loaded dynamically when starting containers since persisted variables take precedence. Consider running Remove Sitecore License User Variable to resolve that issue on solutions." -ForegroundColor Yellow
        Write-Host "+ Sitecore License user variable found: $($userVariable)"
    }
    Invoke-Pause
}

function Remove-SitecoreLicenseUserVariable {
    $userVariable = [Environment]::GetEnvironmentVariable("SITECORE_LICENSE", "User")
    if (! $userVariable) {
        Write-Host "+ No Sitecore License user variable found to remove" -ForegroundColor Yellow
    }
    else {
        Write-Host "+ Removing Sitecore License user variable: $($userVariable)"
        [Environment]::SetEnvironmentVariable("SITECORE_LICENSE", [NullString]::Value, "User")
        Write-Host "+ User variable removed. Log out/in to Windows for environment variable changes to take effect." -ForegroundColor Green
    }
    Invoke-Pause
}

function Invoke-Pause {
    if (-not $Unattended)
    {
        Write-Host -NoNewLine "`n`nPress any key to continue..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Set-Menu
    }
    else
    {
        Return
    }
}

function Complete-Test ($testCode) {    
    if ($Unattended) {
        # Check that all tests passed for full prerequisite check and exit with result code
        if ($menuSelection -eq 0 -and $testCode -eq 0)
        {
            if ($script:HwCoresCheckPassed -and $script:hwRAMCheckPassed -and $script:diskStorageCheckPassed -and $script:OSCheckPassed -and $script:IISOffCheckPassed -and $script:hyperVEnabled -and $script:containersFeatureEnabled -and $script:dockerInstalled -and $script:dockerRunning -and $script:tcpPortsAvailable -and $psModuleScDockerTools) 
            {
                if ($SuppressDockerDNSRequirement) {
                    exit 0
                }
                elseif ($script:dockerDNSSuccess) {
                    exit 0
                }
                else {
                    exit 1
                }
            }
            else
            {
                exit 1
            }
        }

        # Check that all tests passed for hardware prerequisite check and exit with result code
        elseif ($menuSelection -eq 1 -and $testCode -eq 1)
        {
            if ($script:HwCoresCheckPassed -and $script:hwRAMCheckPassed -and $script:diskStorageCheckPassed -and $script:diskTypeCheckPassed) 
            {
                exit 0
            }
            else
            {
                exit 1
            }
        }
        
        # Check that all tests passed for operating system prerequisite check and exit with result code
        elseif ($menuSelection -eq 2 -and $testCode -eq 2)
        {
            if ($script:OSCheckPassed -and $script:IISOffCheckPassed -and $script:hyperVEnabled -and $script:containersFeatureEnabled) 
            {
                exit 0
            }
            else
            {
                exit 1
            }
        }

        # Check that all tests passed for software prerequisite check and exit with result code
        elseif ($menuSelection -eq 3 -and $testCode -eq 3)
        {
            if ($script:dockerInstalled -and $script:dockerRunning) 
            {
                if ($SuppressDockerDNSRequirement) {
                    exit 0
                }
                elseif ($script:dockerDNSSuccess) {
                    exit 0
                }
                else {
                    exit 1
                }
            }
            else
            {
                exit 1
            }
        }

        # Check that all tests passed for network port availability check and exit with result code
        elseif ($menuSelection -eq 4 -and $testCode -eq 4)
        {
            if ($script:tcpPortsAvailable) 
            {
                exit 0
            }
            else
            {
                exit 1
            }
        }
    }
}

function Set-Menu {
    if (-not $Unattended)
    {
        $menuOptions = @('Scan All Prerequisites', 'Scan Hardware Prerequisites', 'Scan Operating System & Features', 'Scan Software Prerequisites', 'Scan Network Port Availability', 'Install Chocolatey', "Install Docker Desktop", 'Install mkcert', 'Install SitecoreDockerTools PowerShell Module', "Enable 'Containers' Windows Feature", "Enable 'Hyper-V' Windows Features", 'Access 10.x.x Developer Installation Guide (Web)', 'Download 10.x.x Sitecore Container Package (ZIP)', 'Open Sitecore Container Docs', 'Remove Sitecore License in Persisted User Environment Variable', "Open 'sitecore-container-prerequisites' GitHub repository", 'Exit')

        $menuSelection = Invoke-Menu -MenuTitle "**********************************************`nPrerequisite Validator for Sitecore Containers`n**********************************************" -MenuOptions $menuOptions
    }

    if ($menuSelection -eq 0) {
        Write-Host "`nFull Prerequisite Check" -ForegroundColor Magenta
        Invoke-FullPrerequisiteCheck
        Invoke-Pause
        Complete-Test $menuSelection
    }
    elseif ($menuSelection -eq 1) {
        Write-Host "`nHardware Prerequisite Check" -ForegroundColor Magenta
        Invoke-HardwareCheck
        Invoke-Pause
        Complete-Test $menuSelection
    }
    elseif ($menuSelection -eq 2) {
        Write-Host "`nOperating System & Features Check" -ForegroundColor Magenta
        Invoke-OperatingSystemCheck
        Invoke-Pause
        Complete-Test $menuSelection
    }
    elseif ($menuSelection -eq 3) {
        Write-Host "`nSoftware Prerequisite Check" -ForegroundColor Magenta
        Invoke-SoftwareCheck
        Invoke-Pause
        Complete-Test $menuSelection
    }
    elseif ($menuSelection -eq 4) {
        Write-Host "`nNetwork Port Check" -ForegroundColor Magenta
        Invoke-NetworkPortCheck
        Invoke-Pause
        Complete-Test $menuSelection
    }
    elseif ($menuSelection -eq 5) {
        Write-Host "`nInstalling Chocolatey" -ForegroundColor Magenta
        Install-Chocolatey
        Invoke-Pause
    }
    elseif ($menuSelection -eq 6) {
        Write-Host "`nInstalling Docker Desktop" -ForegroundColor Magenta
        Install-DockerDesktop

        Invoke-Pause
    }
    elseif ($menuSelection -eq 7) {
        Write-Host "`nInstalling mkcert" -ForegroundColor Magenta
        Install-Mkcert
        Invoke-Pause
    }
    elseif ($menuSelection -eq 8) {
        Write-Host "`nInstalling SitecoreDockerTools" -ForegroundColor Magenta
        Install-SitecoreDockerTools
        Write-SitecoreDockerWelcome
        Invoke-Pause
    }
    elseif ($menuSelection -eq 9) {
        Write-Host "`nEnabling 'Containers' Windows Feature" -ForegroundColor Magenta
        Enable-ContainersFeature
        Invoke-Pause
    }
    elseif ($menuSelection -eq 10) {
        Write-Host "`nEnabling 'Hyper-V' Windows Feature" -ForegroundColor Magenta
        Enable-HyperVFeature
        Invoke-Pause
    }
    elseif ($menuSelection -eq 11) {
        $innerMenuOptions = @('10.0.0', '10.0.1', '10.0.2', '10.1.0', '10.1.1', '10.1.2', '10.2.0', '10.3.2', '10.4.0', 'Exit')
        $innerMenuSelection = Invoke-Menu -MenuTitle "**********************************************`nPrerequisite Validator for Sitecore Containers`n**********************************************" -MenuOptions $innerMenuOptions
        if ($innerMenuSelection -eq 0) {
            Write-Host "`nOpening Sitecore 10.0.0 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.0.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 1) {
            Write-Host "`nOpening Sitecore 10.0.1 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.0.1"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 2) {
            Write-Host "`nOpening Sitecore 10.0.2 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.0.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 3) {
            Write-Host "`nOpening Sitecore 10.1.0 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.1.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 4) {
            Write-Host "`nOpening Sitecore 10.1.1 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.1.1"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 5) {
            Write-Host "`nOpening Sitecore 10.1.2 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.1.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 6) {
            Write-Host "`nOpening Sitecore 10.2.0 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.2.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 7) {
            Write-Host "`nOpening Sitecore 10.3.2 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.3.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 8) {
            Write-Host "`nOpening Sitecore 10.4.0 Release Page" -ForegroundColor Magenta
            Invoke-SitecoreContainerGuideDownload -Version "10.4.0"
            Invoke-Pause
        }
    }
    elseif ($menuSelection -eq 12) {
        $innerMenuOptions = @('10.0.0', '10.0.1', '10.0.2', '10.1.0', '10.1.1', '10.1.2', '10.2.0', '10.3.2', '10.4.0', 'Exit')
        $innerMenuSelection = Invoke-Menu -MenuTitle "**********************************************`nPrerequisite Validator for Sitecore Containers`n**********************************************" -MenuOptions $innerMenuOptions

        if ($innerMenuSelection -eq 0) {
            Write-Host "`nDownloading 10.0.0 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.0.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 1) {
            Write-Host "`nDownloading 10.0.1 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.0.1"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 2) {
            Write-Host "`nDownloading 10.0.2 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.0.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 3) {
            Write-Host "`nDownloading 10.1.0 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.1.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 4) {
            Write-Host "`nDownloading 10.1.1 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.1.1"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 5) {
            Write-Host "`nDownloading 10.1.2 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.1.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 6) {
            Write-Host "`nDownloading 10.2.0 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.2.0"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 7) {
            Write-Host "`nDownloading 10.3.2 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.3.2"
            Invoke-Pause
        }elseif ($innerMenuSelection -eq 8) {
            Write-Host "`nDownloading 10.4.0 Container Deployment Package" -ForegroundColor Magenta
            Invoke-SitecoreContainerPackageDownload -Version "10.4.0"
            Invoke-Pause
        }
    }
    elseif ($menuSelection -eq 13) {
        Write-Host "`nOpen 10.4.0 Container Docs" -ForegroundColor Magenta
        Invoke-OpenContainerDocs
    }
    elseif ($menuSelection -eq 14) {
        Write-Host "`nRemove Sitecore License in Persisted User Environment Variable" -ForegroundColor Magenta
        Remove-SitecoreLicenseUserVariable
    }
    elseif ($menuSelection -eq 15) {
        Write-Host "`nOpening 'sitecore-container-prerequisites' GitHub Repository" -ForegroundColor Magenta
        Invoke-SCPGithubRepo
    }
    elseif ($menuSelection -eq 16) {
        Write-Host "`nBye!" -ForegroundColor Magenta
        exit
    }
}

# This function is used to override the Write-Host function
# Use Microsoft.PowerShell.Utility\Write-Host anywhere you want to suppress this override, such as in basic checks (admin, ISE, etc.)
function global:Write-Host() {
    # Suppress output when the -Quiet switch is used
    if ($Quiet) {
        return
    }
    else {
        # Call the original Write-Host function, passing all arguments        
        $arguments = @($args)
        Microsoft.PowerShell.Utility\Write-Host @arguments
    }
}

$script:HwCoresCheckPassed = $false
$script:hwRAMCheckPassed = $false
$script:diskStorageCheckPassed = $false
$script:OSCheckPassed = $true
$script:IISOffCheckPassed = $false
$script:hyperVEnabled = $false
$script:containersFeatureEnabled = $false
$script:dockerInstalled = $false
$script:dockerRunning = $false
$script:dockerDNSSuccess = $false
$script:tcpPortsAvailable = $false
$script:psModuleScDockerTools = $false

# Require Unattended mode for Quiet mode
if ($Quiet -and !$Unattended) {
    Microsoft.PowerShell.Utility\Write-Host "The -Quiet switch can only be used with the -Unattended switch." -ForegroundColor Red
    exit
}

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Microsoft.PowerShell.Utility\Write-Host "Please open a PowerShell terminal as an administrator, then try again." -ForegroundColor Red
    exit
}

if ($host.name -eq "Windows PowerShell ISE Host") {
    Microsoft.PowerShell.Utility\Write-Host "PowerShell ISE is not supported.  Please open a PowerShell terminal as an administrator, then try again." -ForegroundColor Red
    exit
}

Set-Menu
