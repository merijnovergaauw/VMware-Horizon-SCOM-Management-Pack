## Author: Merijn Overgaauw, GripLogix Consulting

param($sourceId, $managedEntityId, $domainName, $userName, $password)
$params = "$sourceId, $managedEntityId"
$debug = $true
 
# Constants used for event logging
$SCRIPT_NAME            = 'HorizonView.Discovery.ps1'
$EVENT_LEVEL_ERROR      = 1
$EVENT_LEVEL_WARNING    = 2
$EVENT_LEVEL_INFO       = 4
 
$SCRIPT_STARTED         = 9101
$PROPERTYBAG_CREATED    = 9102
$ERROR_GENERATED        = 9103
$INFO_GENERATED         = 9104
$SCRIPT_ENDED           = 9105

#==================================================================================
# Sub:        LogDebugEvent
# Purpose:    Logs an informational event to the Operations Manager event log
#            only if Debug argument is true
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

# Start script.
$api = New-Object -comObject 'MOM.ScriptAPI'
$discoveryData = $api.CreateDiscoveryData(0, $SourceId, $ManagedEntityId)

$message = "$SCRIPT_NAME script started. `nParameters:`n$params"
Log-DebugEvent $SCRIPT_STARTED $EVENT_LEVEL_INFO $message

# Load PowerCli module.
Try {
    Import-Module VMware.VimAutomation.HorizonView -ErrorAction Stop
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    Import-Module VMware.Hv.Helper -ErrorAction Stop
    }
Catch {message = "Import-Module. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}

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
  
Try {$horizonViewServers = Get-SCOMClass -Name "GripLogix.VMware.HorizonView.Server" -ErrorAction Stop | Get-SCOMClassInstance | ? {$_.IsAvailable -eq $true}}
Catch {$message = "Get-SCOMClass -Name GripLogix.VMware.HorizonView.Server failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}

# Create credential
$secPassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential (("$domainName\$userName"), $secPassword)
 
Foreach ($horizonViewServer in $horizonViewServers) 
    {
    $horizonViewServerName = $horizonViewServer.DisplayName
		
	$message = "Starting discovery on server: $horizonViewServerName"
	Log-DebugEvent $PROPERTYBAG_CREATED $EVENT_LEVEL_INFO $message

    Try {$hvServer = Connect-HVServer -server $horizonViewServerName -credential $cred -ErrorAction Stop;$hvServerDiscoverySucceeded = $true}
    Catch {$hvServerDiscoverySucceeded = $false; $message = "Connect-HVServer to $horizonViewServerName failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
  
    $viewAPI = $hvServer.ExtensionData
    $dataCenter = $viewAPI.Pod.Pod_List() | ? {$_.LocalPod -eq $true}
	$dataCenterName = $dataCenter.DisplayName

    Try {$globalEntitlements = Get-HVGlobalEntitlement -HvServer $hvServer -ErrorAction Stop}
    Catch {$message = "Get-HVGlobalEntitlement failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}
 
    Try {
        Get-HVPool -HvServer $hvServer -ErrorAction Stop | ? {$_ -ne $null} | % {
            $poolName = $_.Base.DisplayName
			$poolGlobalEntitlementId = $_.GlobalEntitlementData.GlobalEntitlement.Id
			$poolGlobalEntitlementDisplayName = $globalEntitlements | ? {$_.Id.Id -eq $poolGlobalEntitlementId} | % {$_.Base.DisplayName}

			If ($poolGlobalEntitlementId -and $datacenterName -and $dataCenterName -ne "")
				{
				$GrandParentInstance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']$")
				$GrandParentInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Id$", "$poolGlobalEntitlementId")
				$GrandParentInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Name$", $poolGlobalEntitlementDisplayName)
				$GrandParentInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $poolGlobalEntitlementDisplayName)
				$discoveryData.AddInstance($GrandParentInstance)

				$ParentInstance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.Datacenter']$")
				$ParentInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Id$", "$poolGlobalEntitlementId")
				$ParentInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Datacenter']/Name$", $dataCenterName)
				$ParentInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $dataCenterName)
				$discoveryData.AddInstance($ParentInstance)

				$Instance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.PoolContainer']$")
				$Instance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Id$", "$poolGlobalEntitlementId")
				$Instance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Datacenter']/Name$", $dataCenterName)
				$Instance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "Pools")
				$discoveryData.AddInstance($Instance)

				$ChildInstance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.Pool']$")
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Id$", "$poolGlobalEntitlementId")
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Datacenter']/Name$", $dataCenterName)
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Pool']/Name$", $poolName)
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Pool']/GlobalEntitlementId$", "$poolGlobalEntitlementId")
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Pool']/GlobalEntitlementName$", $poolGlobalEntitlementDisplayName)
				$ChildInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $poolName)
				$discoveryData.AddInstance($ChildInstance)

				$Instance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.ServerContainer']$")
				$Instance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.GlobalEntitlement']/Id$", "$poolGlobalEntitlementId")
				$Instance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Datacenter']/Name$", $dataCenterName)
				$Instance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "Servers")
				$discoveryData.AddInstance($Instance)
		
				$ChildInstance = $discoveryData.CreateClassInstance("$MPElement[Name='GripLogix.VMware.HorizonView.Server']$")
				$ChildInstance.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $horizonViewServerName)
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Server']/Name$", $horizonViewServerName)
				$ChildInstance.AddProperty("$MPElement[Name='GripLogix.VMware.HorizonView.Server']/Datacenter$", $dataCenterName)
				$ChildInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $horizonViewServerName)
				$discoveryData.AddInstance($ChildInstance)

				$RelationshipInstance = $discoveryData.CreateRelationshipInstance("$MPElement[Name='GripLogix.VMware.HorizonView.ServerContainer.contains.Server']$")
				$RelationshipInstance.Source = $Instance
				$RelationshipInstance.Target = $ChildInstance
				$discoveryData.AddInstance($RelationshipInstance)
				}
            }
        }
    Catch {message = "Get-HVPool failed. Error: $_."; Log-DebugEvent $ERROR_GENERATED $EVENT_LEVEL_ERROR $message}

	$hvServer = $null
    $horizonViewServerName = $null
    $viewAPI = $null
	$dataCenter = $null
	$dataCenterName = $null
    $globalEntitlements = $null
	$poolName = $null
	$poolGlobalEntitlementId = $null
	$poolGlobalEntitlementDisplayName = $null
    }
 
$discoveryData
$message = "$SCRIPT_NAME script ended. Parameters:`n$params"
Log-DebugEvent $SCRIPT_ENDED $EVENT_LEVEL_INFO $message
  
 

