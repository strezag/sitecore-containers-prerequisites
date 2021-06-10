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

    Download latest 10.1.0 
        - Container Package ZIP
        - Local Development Installation Guide PDF

    Open Container Docs

    .AUTHOR
     @GabeStreza
#>

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

    $OSVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName)
    $OSProductName = $OSVersion.ProductName
    if ($OSProductName -match "Enterprise|Professional|Education|Pro") {
        switch ([System.Environment]::OSVersion.Version.Build) {
            18362 { 
                Write-Host "+ $OSProductName 1903 detected." -ForegroundColor Green
            }
            18363 { 
                Write-Host "+ $OSProductName 1909 detected." -ForegroundColor Green
            }
            19041 { 
                Write-Host "+ $OSProductName 2004 detected." -ForegroundColor Green
            }
            19042 { 
                Write-Host "+ $OSProductName 20H2 detected." -ForegroundColor Green
            }
            Default { 
                $script:OSCheckPassed = $false 
            }
        }
    }
    else {
        Write-Host "X $OSProductName detected.`n`  > Virtualization cannot be enabled on this OS. (Windows 10 Enterprise, Professional, or Education required." -ForegroundColor Red
        $script:OSCheckPassed = $false 
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
        } else {
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
                    if (($dnsSetting | Measure-Object).Count -gt 0) {
                        if ($dnsSetting -match "8.8.8.8") {
                            Write-Host "+ Docker DNS is set to Google's public DNS server:  $dnsSetting"  -ForegroundColor Green
                        }
                        else {
                            Write-Host "- Docker's '$($drive.DeviceID)\ProgramData\Docker\config\daemon.json' configuration is not set to Google's public DNS server: 8.8.8.8.`nCurrent setting:  $dnsSetting" -ForegroundColor Yellow
                        }
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

        $dockerNetworkSuccess = (& docker run mcr.microsoft.com/powershell:lts-nanoserver-1809 pwsh.exe -Command Test-Connection -TcpPort 80 -TargetName nuget.org)
        if ($dockerNetworkSuccess -eq "True") {
            Write-Host "+ Docker Desktop can successfully reach the internet." -ForegroundColor Green
        }
        else {
            Write-Host "X Docker Desktop cannot reach the internet. Check Docker network configuration and the InterfaceMetric values on your network adapter." -ForegroundColor Red
            Write-Host "https://github.com/docker/for-win/issues/2760#issuecomment-430889666" -ForegroundColor Red
        }
    }

    ########## Check for SitecoreDockerTools PSModule install status  */
    Write-Host "`n`nVERIFYING 'SitecoreDockerTools' POWERSHELL MODULE IS INSTALLED..." -ForegroundColor Cyan
    Invoke-SitecoreDockerToolsCheck
}

function Invoke-NetworkPortCheck {

    ########## Checking required TCP port availability  */
    Write-Host "`n`nCHECKING REQUIRED TCP PORT AVAILABILITY..." -ForegroundColor Cyan

    $tcpPortAvailableCount = 0
    if ((Get-NetTCPConnection | Where-Object Localport -eq 443).Count -eq 0) {
        Write-Host "+ TCP port 443 (required for Traefik HTTPS proxy) is available." -ForegroundColor Green
        $tcpPortAvailableCount++
    }
    else {
        Write-Host "X TCP port 443 (required for Traefik HTTPS proxy) is not available." -ForegroundColor Red
    }

    if ((Get-NetTCPConnection | Where-Object Localport -eq 8079).Count -eq 0) {
        Write-Host "+ TCP port 8079 (required for Traefik dashboard) is available." -ForegroundColor Green
        $tcpPortAvailableCount++
    }
    else {
        Write-Host "X TCP port 8079 (required for Traefik dashboard) is not available." -ForegroundColor Red
    }

    if ((Get-NetTCPConnection | Where-Object Localport -eq 8081).Count -eq 0) {
        $tcpPortAvailableCount++
        Write-Host "+ TCP port 8081 (required for xConnect) is available." -ForegroundColor Green
    }
    else {
        Write-Host "X TCP port 8081 (required for xConnect) is not available." -ForegroundColor Red
    }

    if ((Get-NetTCPConnection | Where-Object Localport -eq 8984).Count -eq 0) {
        $tcpPortAvailableCount++
        Write-Host "+ TCP port 8984 (required for Solr API and dashboard) is available." -ForegroundColor Green
    }
    else {
        Write-Host "X TCP port 8984 (required for Solr API and dashboard) is not available." -ForegroundColor Red
    }

    if ((Get-NetTCPConnection | Where-Object Localport -eq 14330).Count -eq 0) {
        $tcpPortAvailableCount++
        Write-Host "+ TCP port 14330 (required for SQL Server) is available." -ForegroundColor Green
    }
    else {
        Write-Host "X TCP port 14330 (required for SQL Server) is not available." -ForegroundColor Red
    }

    if ($tcpPortAvailableCount -eq 5) {
        $script:tcpPortsAvailable = $true
    }
}

function Invoke-FullPrerequisiteCheck {
    Invoke-HardwareCheck
    Invoke-OperatingSystemCheck
    Invoke-SoftwareCheck
    Invoke-NetworkPortCheck

    Write-Host "`n**********************************************`n" -ForegroundColor Cyan 

    if ($script:HwCoresCheckPassed -and $script:hwRAMCheckPassed -and $script:diskStorageCheckPassed -and $script:OSCheckPassed -and $script:IISOffCheckPassed -and $script:hyperVEnabled -and $script:containersFeatureEnabled -and $script:dockerInstalled -and $script:dockerRunning -and $script:tcpPortsAvailable -and $psModuleScDockerTools) {
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
    Write-Host "Downloading 'Installation Guide for Developer Workstation with Containers (10.1) (10.1.0.005207.309)' to $((Get-Location).Path).`n" -ForegroundColor Magenta
    Invoke-WebRequest -Uri "https://sitecoredev.azureedge.net/~/media/F53BECFEBDC64C8695EDF60D4E435AEA.ashx?date=20210224T164409" -OutFile ".\SitecoreContainerDeployment.10.1.0.005207.309.pdf"
    Invoke-Item (Get-Location).Path
    Invoke-Pause
}

function Invoke-SitecoreContainerPackageDownload {
    Write-Host "Downloading 'Initial release of SXP Sitecore Container Deployment for Sitecore 10.1 (10.1.0.005207.309).zip' to $((Get-Location).Path).`n" -ForegroundColor Magenta
    Invoke-WebRequest -Uri "https://github.com/Sitecore/container-deployment/releases/download/sxp%2F10.1.0.005207.309/SitecoreContainerDeployment.10.1.0.005207.309.zip" -OutFile ".\SitecoreContainerDeployment.10.1.0.005207.309.zip"
    Invoke-Item (Get-Location).Path
    Invoke-Pause
}

function Invoke-OpenContainerDocs {
    $Url = "https://doc.sitecore.com/developers/101/developer-tools/en/containers-in-sitecore-development.html"
    Start-Process $Url
    Invoke-Pause
}

function Invoke-Pause {
    Write-Host -NoNewLine "`n`nPress any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Set-Menu
}

function Set-Menu {
    $menuOptions = @('Scan All Prerequisites', 'Scan Hardware Prerequisites', 'Scan Operating System & Features', 'Scan Software Prerequisites', 'Scan Network Port Availability', 'Install Chocolatey', "Install Docker Desktop", "Install mkcert", "Install SitecoreDockerTools PowerShell Module", "Enable 'Containers' Windows Feature", "Enable 'Hyper-V' Windows Features", "Download 10.1.0 Developer Installation Guide (PDF)", "Download 10.1.0 Sitecore Container Package (ZIP)", "Open Sitecore Container Docs" , 'Exit')

    $menuSelection = Invoke-Menu -MenuTitle "**********************************************`nPrerequisite Validator for Sitecore Containers`n**********************************************" -MenuOptions $menuOptions
    
    if ($menuSelection -eq 0) {
        Write-Host "`nFull Prerequisite Check" -ForegroundColor Magenta
        Invoke-FullPrerequisiteCheck
        Invoke-Pause
    }
    elseif ($menuSelection -eq 1) {
        Write-Host "`nHardware Prerequisite Check" -ForegroundColor Magenta
        Invoke-HardwareCheck
        Invoke-Pause
    }
    elseif ($menuSelection -eq 2) {
        Write-Host "`nOperating System & Features Check" -ForegroundColor Magenta
        Invoke-OperatingSystemCheck
        Invoke-Pause
    }
    elseif ($menuSelection -eq 3) {
        Write-Host "`nSoftware Prerequisite Check" -ForegroundColor Magenta
        Invoke-SoftwareCheck
        Invoke-Pause
    }
    elseif ($menuSelection -eq 4) {
        Write-Host "`nNetwork Port Check" -ForegroundColor Magenta
        Invoke-NetworkPortCheck
        Invoke-Pause
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
        Write-Host "`nDownloading 10.1.0 Developer Workstation Container Installation Guide" -ForegroundColor Magenta
        Invoke-SitecoreContainerGuideDownload
    }
    elseif ($menuSelection -eq 12) {
        Write-Host "`nDownloading 10.1.0 Container Deployment Package" -ForegroundColor Magenta
        Invoke-SitecoreContainerPackageDownload
    }
    elseif ($menuSelection -eq 13) {
        Write-Host "`nOpen 10.1.0 Container Docs" -ForegroundColor Magenta
        Invoke-OpenContainerDocs
    }
    elseif ($menuSelection -eq 14) {
        Write-Host "`nBye!" -ForegroundColor Magenta
        exit
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
$script:tcpPortsAvailable = $false
$script:psModuleScDockerTools = $false

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please open a PowerShell terminal as an administrator, then try again." -ForegroundColor Red
    exit
}

if($host.name -eq "Windows PowerShell ISE Host"){
    Write-Host "PowerShell ISE is not supported.  Please open a PowerShell terminal as an administrator, then try again." -ForegroundColor Red
    exit
}

Set-Menu