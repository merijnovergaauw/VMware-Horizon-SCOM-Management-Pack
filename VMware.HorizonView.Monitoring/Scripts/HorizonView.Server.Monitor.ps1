## Author: Merijn Overgaauw, GripLogix Consulting

param($domainName, $userName, $password)
$params = "DomainName: $domainName, UserName: $userName"

# Constants
$debug = $true

# Constants used for event logging
$SCRIPT_NAME			= 'HorizonView.Server.Monitor.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED			= 4101
$PROPERTYBAG_CREATED	= 4102
$ERROR_GENERATED        = 4103
$INFO_GENERATED         = 4104
$SCRIPT_ENDED			= 4105

#==================================================================================
# Sub:		LogDebugEvent
# Purpose:	Logs an informational event to the Operations Manager event log
#			only if Debug argument is true
#==================================================================================
function Log-DebugEvent
	{
		param($eventNo, $eventLevel, $message)

		$message = "`n" + $message
		if ($debug)
		{
			$api.LogScriptEvent($SCRIPT_NAME,$eventNo,$eventLevel,$message)
		}
	}
#==================================================================================

# Start script by setting up API object
$api = New-Object -comObject 'MOM.ScriptAPI'

$message = "$SCRIPT_NAME script started. Parameters:`n$params"
Log-DebugEvent $SCRIPT_STARTED $EVENT_LEVEL_INFO $message

# Load PowerCli module.
Try {
    Import-Module VMware.VimAutomation.HorizonView -ErrorAction Stop
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    }
Catch {message = "Import-Module. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
  
# Create credential
$secPassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential (("$domainName\$userName"), $secPassword)

# Get data
Try {$hvServer = Connect-HVServer -server localhost -credential $cred -ErrorAction Stop}
Catch {$message = "Connect-HVServer failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}

$horizonViewServerName = $env:computername
$horizonViewServerFQDN = ([System.Net.Dns]::GetHostByName(($env:computerName))).HostName
 
$hvServer.extensiondata.virtualcenterhealth.virtualcenterhealth_list().hostdata | % {
	$hostName = $_.Name
	$hostStatus = $_.Status

	$bag = $api.CreatePropertyBag()
	$bag.AddValue('HypervisorHostName',$hostName)
	$bag.AddValue('HypervisorHostConnectionState',$hostStatus)
	$bag

	$message = "Property bag created.
	Hypervisor Host Name: $hostName
	Hypervisor Host Status: $hostStatus"

	Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message
}

$hvServer.extensiondata.ConnectionServerHealth.ConnectionServerHealth_List() | ? {$_.Name -eq $horizonViewServerName} | % {
	$horizonViewServerName = $_.Name
	$horizonViewStatus = $_.Status

	$bag = $api.CreatePropertyBag()
	$bag.AddValue('HorizonViewServerName',$horizonViewServerName)
	$bag.AddValue('HorizonViewServerStatus',$horizonViewStatus)
	$bag

	$message = "Property bag created.
	Horizon View Server Name: $horizonViewServerName
	Horizon View Server Status: $horizonViewStatus"

	Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message
}

$message = "$SCRIPT_NAME script ended. Parameters:`n$params"
Log-DebugEvent $SCRIPT_ENDED $EVENT_LEVEL_INFO $message
