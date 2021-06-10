# Sitecore Containers Prerequisites

Checks the machine for Sitecore Container compatibility.

Quickly verify Sitecore Container:
- Hardware requirements (CPU, RAM, DISK STORAGE and TYPES)
- Operating system compatibility (OS Build Version, Hyper-V/Containers Feature Check, IIS Running State)
- Software requirements (Docker Desktop, Docker engine OS type Linux vs Windows Containers, Sitecore Docker Tools, Sitecore License persistence in user environment variable)
- Network Port Check (443, 8079, 8984, 14330)

Download and install software:
- Chocolatey
- Docker Desktop
- mkcert

Enable required Windows Features
- Containers
- Hyper-V

Download latest 10.1.0 
- Container Package ZIP
- Local Development Installation Guide PDF

Miscellaneous
- Remove Sitecore license persisted in user environment variable (can be problematic as it overrides session variables in modern Docker solutions)


## Full Scan Demo

![](./img/full-scan-demo.gif)

## Demo of Docker Container Type Identification

![](./img/switch-containers-demo.gif)