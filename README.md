# Sitecore Containers Prerequisites

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/strezag/sitecore-containers-prerequisites?style=social)](https://github.com/strezag/sitecore-containers-prerequisites)

## Overview

This PowerShell script checks that your Windows machine is fully set up to run **Sitecore Containers**, performing:

- ✅ **Hardware checks** (CPU, RAM, disk)
- 🛠 **OS & Windows Feature validation** (Edition, build, Containers, Hyper‑V, IIS status)
- 📦 **Software checks** (Docker Desktop, container mode, DNS config, SitecoreDockerTools)
- 🌐 **Network port availability**
- ⚙️ Misc. checks (CBFSConnect driver, `SITECORE_LICENSE` variable)

You can run it in either **interactive** or **unattended** mode—perfect for local setup or CI pipelines.

---

### ✅ tl;dr Usage

Run this script from an **admin-elevated PowerShell session**:

```powershell
Start-BitsTransfer -Source "https://raw.githubusercontent.com/strezag/sitecore-containers-prerequisites/main/sitecore-containers-prerequisites.ps1"
.\sitecore-containers-prerequisites.ps1
```

**Run unattended & quiet, with pass/fail message:**

```powershell
Start-BitsTransfer -Source "https://raw.githubusercontent.com/strezag/sitecore-containers-prerequisites/main/sitecore-containers-prerequisites.ps1"
.\sitecore-containers-prerequisites.ps1 -Unattended -Quiet
Write-Host "Exit code is $LastExitCode which means you $($LastExitCode -eq 0 ? 'passed' : 'failed')"
```

**Run unattended, full output:**

```powershell
Start-BitsTransfer -Source "https://raw.githubusercontent.com/strezag/sitecore-containers-prerequisites/main/sitecore-containers-prerequisites.ps1"
.\sitecore-containers-prerequisites.ps1 -Unattended
```


---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Usage](#usage)
4. [Parameters](#parameters)
5. [Checks Performed](#checks-performed)
6. [Menu Options](#menu-options)
7. [Examples](#examples)
8. [Exit Codes](#exit-codes)
9. [Screenshots](#screenshots)
10. [Contributing](#contributing)
11. [License](#license)
12. [Links](#links)

---

## Prerequisites

- **Windows 10/11** Pro, Enterprise, or Education (build 1903+ recommended)
- **PowerShell 5.1+** (run in **Windows PowerShell** as Administrator; ISE not supported)
- **Internet access** for downloads and DNS checks
- **Admin rights** required to run and install components

---

## Installation

### Option 1: One-liner (download & run)

```powershell
Start-BitsTransfer -Source "https://raw.githubusercontent.com/strezag/sitecore-containers-prerequisites/main/sitecore-containers-prerequisites.ps1"
.\sitecore-containers-prerequisites.ps1
```

### Option 2: Clone the repo

```bash
git clone https://github.com/strezag/sitecore-containers-prerequisites.git
cd sitecore-containers-prerequisites
.\sitecore-containers-prerequisites.ps1
```

---

## Usage

### Interactive Mode

Use the arrow keys to select a check or action:

```powershell
.\sitecore-containers-prerequisites.ps1
```

### Unattended Mode

Run a scan with no prompts:

```powershell
.\sitecore-containers-prerequisites.ps1 -Unattended
```

Target a specific check with `-MenuSelection`, and suppress output with `-Quiet`.

```powershell
.\sitecore-containers-prerequisites.ps1 -Unattended -MenuSelection 1 -Quiet
```

---

## Parameters

| Parameter                        | Description                                                        |
|----------------------------------|--------------------------------------------------------------------|
| `-Unattended`                    | Runs the script without interactive prompts                        |
| `-MenuSelection <0–16>`         | Executes a specific check or action by index (default: 0 = Full)   |
| `-Quiet`                         | Suppresses non-critical output                                     |
| `-SuppressDockerDNSRequirement` | Skips DNS connectivity test for Docker in unattended mode          |

---

## Checks Performed

### 1. **Hardware**
- ≥ 4 CPU cores  
- ≥ 16 GB RAM (32 GB recommended)  
- ≥ 25 GB free disk space (SSD recommended)

### 2. **Operating System & Features**
- Windows 10/11 Pro/Ent/Edu, build 1903+
- Containers & Hyper‑V Windows features enabled
- IIS service is stopped
- CBFSConnect2017 driver compatibility

### 3. **Software**
- Docker Desktop installed & running (Windows containers mode)
- `com.docker.service` + Docker daemon active
- DNS config (8.8.8.8 or 1.1.1.1 optional)
- SitecoreDockerTools PowerShell module
- `SITECORE_LICENSE` user environment variable set

### 4. **Network Ports**
- TCP 443, 8079, 8081, 8984, 14330 available

---

## Menu Options

| Index | Action                                                       |
|-------|--------------------------------------------------------------|
| 0     | Full Prerequisite Check                                      |
| 1     | Hardware Prerequisite Check                                  |
| 2     | Operating System & Features Check                            |
| 3     | Software Prerequisite Check                                  |
| 4     | Network Port Availability Check                              |
| 5     | Install Chocolatey                                           |
| 6     | Install Docker Desktop                                       |    
| 7     | Install mkcert (TLS cert tool)                               |
| 8     | Install SitecoreDockerTools PowerShell module                |
| 9     | Enable Containers Windows feature                            |
| 10    | Enable Hyper‑V Windows feature                               |
| 11    | Open Sitecore 10.x Dev Guide                                 |
| 12    | Download Sitecore Container Deployment Package               |
| 13    | Open Sitecore Container Docs                                 |
| 14    | Remove SITECORE_LICENSE env var                              |
| 15    | Open this GitHub repo                                        |
| 16    | Exit script                                                  |

---

## Examples

```powershell
# Run full check interactively
.\sitecore-containers-prerequisites.ps1

# Run full check silently for CI
.\sitecore-containers-prerequisites.ps1 -Unattended -Quiet

# Run hardware check only
.\sitecore-containers-prerequisites.ps1 -Unattended -MenuSelection 1
```

---

## Screenshots

**Full Scan Demo**  
![](./img/full-scan-demo.gif)

**Switch to Windows Containers Demo**  
![](./img/switch-containers-demo.gif)

---

## Contributing

Bug reports, feature ideas, and pull requests are welcome!

---

## License

GNU GENERAL PUBLIC LICENSE – see [LICENSE](LICENSE) for details.

---