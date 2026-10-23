# LockdownWin
Automated workflow that disables main telemetry services that are shipped with Windows 11 PCs. Remove any kernel level unnecessary interventions. Firewall rules to ensure hardened network security. Implemented on multiple layers of anti-revision persistence to ensure service(s) can't be used. 

## Features
- Disables main telemetry services
- Disable **wlidsvc** (Which is a system service that manages Microsoft Account services on your Local PC) *Disabling this will not affect you if you have Local Account and don't use Microsoft Account integrations within your laptop*
> Important to note that this will break the Xbox Game Bar, Microsoft Store, and PC Game Pass.
- Disable Ports Legacy Protocols 
- Disable AI Features like CoPilot and Recall
- Implements multiple layers of persistence


## Automated Security Checks

- Syntax Checking via PSScriptAnalyzer

## Disclaimer
You are responsible for anything that happens to your PC when choosing to use this repo and any contents it contains.
