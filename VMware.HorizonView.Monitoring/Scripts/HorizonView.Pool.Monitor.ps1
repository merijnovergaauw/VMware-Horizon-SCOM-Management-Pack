## Author: Merijn Overgaauw, GripLogix Consulting

param($domainName, $userName, $password)
$params = "DomainName: $domainName, UserName: $userName"

# Constants
$DEBUG = $true

# Constants used for event logging
$SCRIPT_NAME			= 'HorizonView.Pool.Monitor.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED			= 3101
$PROPERTYBAG_CREATED	= 3102
$ERROR_GENERATED        = 3103
$INFO_GENERATED         = 3104
$SCRIPT_ENDED			= 3105

#==================================================================================
# Sub:		LogDebugEvent
# Purpose:	Logs an informational event to the Operations Manager event log
#			only if Debug argument is true
#==================================================================================
function Log-DebugEvent
	{
		param($eventNo, $eventLevel, $message)

		$message = "`n" + $message
		if ($DEBUG)
		{
			$api.LogScriptEvent($SCRIPT_NAME,$eventNo,$eventLevel,$message)
		}
	}
#==================================================================================

# Start script by setting up API object
$api = New-Object -comObject 'MOM.ScriptAPI'

$message = "$SCRIPT_NAME script started. Parameters:`n$params"
Log-DebugEvent $SCRIPT_STARTED $EVENT_LEVEL_INFO $message

# Load OpsMgr module.
$operationsManagerCmdletsTest = (Get-Module | % {$_.Name}) -Join ' '
If (!$operationsManagerCmdletsTest.Contains('OperationsManager'))
	{
	$moduleFound = $false
	$setupKeys = @('HKLM:\Software\Microsoft\Microsoft Operations Manager\3.0\Setup',
	'HKLM:\SOFTWARE\Microsoft\System Center Operations Manager\12\Setup')
	foreach($setupKey in $setupKeys)
		{
		If ((Test-Path $setupKey) -and ($moduleFound -eq $false))
			{
			$setupKey = Get-Item -Path $setupKey
			$installDirectory = $setupKey.GetValue('InstallDirectory')
			$psmPath = $installdirectory + '\Powershell\OperationsManager\OperationsManager.psm1'
			If (Test-Path $psmPath) {$moduleFound = $true}
			}
		}
	If ($moduleFound)
		{
		Try {Import-Module $psmPath -ErrorAction Stop}
		Catch {$message = "Failed to load OpsMgr module. Error: $_"
		Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
		}
	Else
		{
		Try {Import-Module OperationsManager -ErrorAction Stop}
		Catch {$message = "Failed to load OpsMgr module. Error: $_"
		Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
		}
	}

# Load PowerCli module.
Try {
    Import-Module VMware.VimAutomation.HorizonView -ErrorAction Stop
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    Import-Module VMware.Hv.Helper -ErrorAction Stop
    }
Catch {message = "Import-Module. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
  
Try {$hvServers = Get-SCOMClass -Name "GripLogix.VMware.HorizonView.Server" -ErrorAction Stop | Get-SCOMClassInstance | ? {$_.IsAvailable -eq $true} | Sort-Object -Unique @{E={$_.'[GripLogix.VMware.HorizonView.Server].Datacenter'.Value}}}
Catch {$message = "Get-SCOMClass -Name GripLogix.VMware.HorizonView.Server failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}

# Create credential
$secPassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential (("$domainName\$userName"), $secPassword)

# Create array for GlobalEntitlement metrics
[System.Collections.ArrayList]$geArray = @()

# Get data
ForEach ($hvServer in $hvServers)
	{
    $hvServerName = $hvServer.DisplayName
 
    Try {$hvServer = Connect-HVServer -server $hvServerName -credential $cred -ErrorAction Stop}
    Catch {$message = "Connect-HVServer failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
  
	$viewAPI = $hvServer.ExtensionData
	$query_service = New-Object "Vmware.Hv.QueryServiceService"		
	$queryDesktopSummaryView = New-Object "Vmware.Hv.QueryDefinition"		
	$queryDesktopSummaryView.queryEntityType = 'DesktopSummaryView'			
	$pools = $query_service.QueryService_Query($ViewAPI,$queryDesktopSummaryView)
    $dataCenter = $viewAPI.Pod.Pod_List() | ? {$_.LocalPod -eq $true}
	$dataCenterName = $dataCenter.DisplayName

	# Pool data collection
	$pools.Results.DesktopSummaryData | ? {$_ -ne $null} | % {
		$poolName = [string]$_.DisplayName
		$poolGeId = [string]$_.GlobalEntitlement.Id
		$poolMachinesNumber = [int]$_.NumMachines
		$poolSessionsNumber = [int]$_.NumSessions
		If ($poolMachinesNumber) {$poolSessionsPercentage = [math]::Round(($poolSessionsNumber / $poolMachinesNumber) * 100)}
		Else {$poolSessionsPercentage = $null}
		$poolAvailableMachinesNumber = $poolMachinesNumber - $poolSessionsNumber

		$bag = $api.CreatePropertyBag()
		$bag.AddValue('PoolName',$poolName)
		$bag.AddValue('NumberOfMachines',$poolMachinesNumber)
		$bag.AddValue('NumberOfSessions',$poolSessionsNumber)
		If ($poolSessionsPercentage ) {$bag.AddValue('PercentageOfSessions',$poolSessionsPercentage)}
		$bag.AddValue('NumberOfAvailableMachines',$poolAvailableMachinesNumber)
		$bag

		$message = "Property bag created.
		PoolName: $poolName
		NumberOfMachines: $poolMachinesNumber
		NumberOfSessions: $poolSessionsNumber
		PercentageOfSessions: $poolSessionsPercentage
		NumberOfAvailableMachines: $poolAvailableMachinesNumber
		Data Center: $dataCenterName
		Horizon View Server: $hvServerName"

		Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message

		# Calculate GlobalEntitlement metrics and create object array
		If ($poolGeId -ne "")
			{
			If (($geArray | % {$_.geId}) -notcontains $poolGeId) 
				{
				$psObject = New-Object psObject
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geId -value $poolGeId
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geMachinesNumber -value $poolMachinesNumber
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geSessionsNumber -value $poolSessionsNumber
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geSessionsPercentage -value $poolSessionsPercentage
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geAvailableMachinesNumber -value $poolAvailableMachinesNumber
				}
			Else
				{
				$object = $geArray | ? {$_.geId -eq $poolGeId}
				$geMachinesNumber = $object.geMachinesNumber + $poolMachinesNumber
				$geSessionsNumber = $object.geSessionsNumber + $poolSessionsNumber
				If ($geMachinesNumber) {$geSessionsPercentage = [math]::Round(($geSessionsNumber / $geMachinesNumber) * 100)}
				Else {$geSessionsPercentage = $null}
				$geAvailableMachinesNumber = $object.geAvailableMachinesNumber + $poolAvailableMachinesNumber

				$geArray.Remove($object)

				$psObject = New-Object psObject
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geId -value $poolGeId
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geMachinesNumber -value $geMachinesNumber
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geSessionsNumber -value $geSessionsNumber
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geSessionsPercentage -value $geSessionsPercentage
				Add-Member -InputObject $psObject -MemberType NoteProperty -Name geAvailableMachinesNumber -value $geAvailableMachinesNumber
				}

			$geArray = $geArray += $psObject
			}
		}	
		
	# Machine data collection
	$queryMachineSummaryView = New-Object "Vmware.Hv.QueryDefinition"  
	$queryMachineSummaryView.queryEntityType = 'MachineSummaryView'   

    $query_service.QueryService_Query($ViewAPI,$queryMachineSummaryView) | % {$_.Results.Base} | % {
		$machineName = $_.Name
		$basicState = $_.BasicState

		$bag = $api.CreatePropertyBag()
		$bag.AddValue('MachineName',$machineName)
		$bag.AddValue('BasicState',$basicState)
		$bag

		$message = "Property bag created.
		MachineName: $machineName
		BasicState: $basicState"

		Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message
		}	
		
	$hvServer.extensiondata.virtualcenterhealth.virtualcenterhealth_list().datastoredata | % {
		$dataStoreName = $_.Name
		$dataStoreCapacity = $_.CapacityMB
		$dataStoreFreeSpace = $_.FreeSpaceMB
		If ($dataStoreCapacity) {$dataStoreFreeSpacePercentage = [math]::Round(($dataStoreFreeSpace/$dataStoreCapacity)*100)}
		Else {$dataStoreFreeSpacePercentage = $null}

		$bag = $api.CreatePropertyBag()
		$bag.AddValue('DataStoreName',$dataStoreName)
		$bag.AddValue('DataStoreCapacity',$dataStoreCapacity)
		$bag.AddValue('DataStoreFreeSpace',$dataStoreFreeSpace)
		If ($dataStoreFreeSpacePercentage) {$bag.AddValue('DataStoreFreeSpacePercentage',$dataStoreFreeSpacePercentage)}
		$bag

		$message = "Property bag created.
		DataStoreName: $dataStoreName
		DataStoreCapacity: $dataStoreCapacity
		DataStoreFreeSpace: $dataStoreFreeSpace
		DataStoreFreeSpacePercentage: $dataStoreFreeSpacePercentage
		Data Center: $dataCenterName
		Horizon View Server: $hvServerName"

		Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message
		}									
	}

Foreach ($geArrayItem in $geArray)
	{
	$geId = $geArrayItem.geId
	$geMachinesNumber = $geArrayItem.geMachinesNumber
	$geSessionsNumber = $geArrayItem.geSessionsNumber
	$gePoolSessionsPercentage = $geArrayItem.geSessionsPercentage
	$geAvailableMachinesNumber = $geArrayItem.geAvailableMachinesNumber

	$bag = $api.CreatePropertyBag()
	$bag.AddValue('GlobalEntitlementId',$geId)
	$bag.AddValue('NumberOfMachines',$geMachinesNumber)
	$bag.AddValue('NumberOfSessions',$geSessionsNumber)
	If ($gePoolSessionsPercentage) {$bag.AddValue('PercentageOfSessions',$gePoolSessionsPercentage)}
	$bag.AddValue('NumberOfAvailableMachines',$geAvailableMachinesNumber)
	$bag

	$message = "Property bag created.
	GlobalEntitlementId: $geId
	NumberOfMachines: $geMachinesNumber
	NumberOfSessions: $geSessionsNumber
	PercentageOfSessions: $gePoolSessionsPercentage
	NumberOfAvailableMachines: $geAvailableMachinesNumber"

	Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message
	}

$message = "$SCRIPT_NAME script ended. Parameters:`n$params"
Log-DebugEvent $SCRIPT_ENDED $EVENT_LEVEL_INFO $message
