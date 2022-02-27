# VMware Horizon SCOM Mangement Pack
VMware Horizon SCOM Management Pack 👓

This VMware Horizon SCOM Management Pack contains some essential infrastructure and capacity usage monitoring for VMware Horizon View VDI platforms. Among others, it makes use of a Resource Pool to run several workflows. It can be used as a framework to add more monitoring workflows to.

Make sure you configure a Run As Account using the Run As Profile from the Management Pack when implementing it. Use this blog as a reference to install the VMware PowerCLI PowerShell cmdlets and to configure the SCOM Run As Account with VMware PowerCLI permissions: https://blogs.vmware.com/euc/2020/01/vmware-horizon-7-powercli.html You need to install the VMware PowerCLI PowerShell cmdlets on the SCOM Resource Pool members which are your SCOM MS servers by default. VMware Horizon Servers should have them installed already.

![image](https://user-images.githubusercontent.com/76749035/154802989-481c4e6d-012d-4b43-a27c-ccbbf539e4d7.png)

Currently contains the following monitoring:

Monitors:
* VMware Horizon Windows Service Monitor
* VMware Horizon % Sessions (Global Entitlement)
* VMware Horizon % Sessions (Pool)
* VMware Horizon Hypervisor Connection Status
* VMware Horizon Horizon Server Status

Rules:
* VMware Horizon Global Entitlement Percentage of Sessions Performance Collection Rule
* VMware Horizon Global Entitlement Number of Machines Performance Collection Rule
* VMware Horizon Global Entitlement Number of Available Machines Performance Collection Rule
* VMware Horizon Global Entitlement Number of Sessions Performance Collection Rule
* VMware Horizon Pool Number of Available Machines Performance Collection Rule
* VMware Horizon Pool Number of Machines Performance Collection Rule
* VMware Horizon Pool Percentage of Sessions Performance Collection Rule
* VMware Horizon Pool Number of Sessions Performance Collection Rule
* VMware Horizon Data Store Free Space % Performance Collection Rule
* VMware Horizon Data Store Free Space Performance Collection Rule
* VMware Horizon Data Store Free Space Percentage Alerting
* VMware Horizon Machine State Alerting
* VMware Horizon Hypervisor Connection State Alerting
