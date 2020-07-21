# Global Variables
$global:ltposhURL = 'https://raw.githubusercontent.com/LabtechConsulting/LabTech-Powershell-Module/master/LabTech.psm1'
$global:RfaAutomateServer='https://automate.rfa.com'

# Load other modules
$web = New-Object Net.WebClient
$OtherModules = @(
    $ltposhURL
    'https://raw.githubusercontent.com/tonypags/PsWinAdmin/master/Get-RegistryValueData.ps1'
    'https://raw.githubusercontent.com/RFAInc/RfaAgentRepair/master/RfaAgentRepair.psm1'
)
Foreach ($uri in $OtherModules) {
    $web.DownloadString($uri) | Invoke-Expression
}
$web.Dispose | Out-Null


function Get-AdEnabledComputers {

    <#
    .SYNOPSIS
    Returns a list of computernames found in AD and not disabled.
    .DESCRIPTION
    Returns a list of computernames found in AD and not disabled.
    #>

    # Check and load module
    $ModuleLoaded = Get-Module -Name ActiveDiretory
    $Module = Get-Module -ListAvailable -Name ActiveDiretory
    if ($Module) {
        if ($ModuleLoaded) {} else {
            Import-Module ActiveDiretory
        }
    } else {
        Write-Error "Rerun this script on a DC or a device with RSAT installed."
    }

    # Pull list of enabled computers and return to pipeline
    Get-AdComputer -Filter * | Where-Object {$_.Enabled} | Select-Object -ExpandProperty Name

}

function Confirm-RequiresAdmin {

    <#
    .SYNOPSIS
    Confirms environment has local admin privilages.
    .DESCRIPTION
    Older versions of PowerShell do not support the #Requires -RunAsAdministrator feature. This function fills the gap.
    .EXAMPLE
    Confirm-RequiresAdmin
    Call this function at the top of your script. An error will be thrown in the same manner as the modern feature.
    .NOTES
    https://github.com/OfficeDev/Office-IT-Pro-Deployment-Scripts
    #>

    param()


    If (-NOT 
        ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole(
                [Security.Principal.WindowsBuiltInRole] "Administrator"
            )
        )
    {
        throw "Administrator rights are required to run this script!"
    }

}


function Test-LtInstall {
    <#
    .SYNOPSIS
    Tests the local machine for installation and functionality.
    #>
    param (
        # Set the "pass" conditions
        $ServerShouldBeLike = '*automate.rfa.com*',
        $LocationShouldBe = $LocationID,
        $LastContactShouldBeGreaterThan = (Get-Date).AddMinutes(-5),
        [switch]$Generic,
        [switch]$Quiet
    )
    
    # Check for existing install
    $TestPass = $true
    $LTServiceInfo = Get-LTServiceInfo -ErrorAction SilentlyContinue
    
    if ($Generic) {

        if (-not $LTServiceInfo) {$TestPass = $false}
    
    } else {
    
        $ServerIs = $LTServiceInfo.'Server Address'
        $LocationIs = $LTServiceInfo.LocationID
        $LastContactIs = $LTServiceInfo.LastSuccessStatus -as [datetime]
        
        # Test the info vs the conditions
        
        if (-not ($ServerIs -like $ServerShouldBeLike)) {$TestPass = $false}
        if (-not ($LocationIs -eq $LocationShouldBe)) {$TestPass = $false}
        if (-not ($LastContactIs -ge $LastContactShouldBeGreaterThan)) {$TestPass = $false}
    
    }
    
    if ($Quiet -or $Generic) {
        Write-Output $TestPass
    } else {
        [PSCustomObject]@{
            ServerAddress = $ServerIs
            LocationID = $LocationIs
            LastSuccessStatus = $LastContactIs
        }
    }

}



function Install-RfaCwaAgent {

    <#
    .SYNOPSIS
    Installs the RFA Automate agent
    .DESCRIPTION
    Checks the local system for the Automate agent and verifies if the agent belongs to RFA and not some other MSP. (Re-) installs as needed. Also ensures the agent is checking in after install. 
    .PARAMETER LocationID
    Location ID as a number
    .PARAMETER NoWait
    Will not pause for 90 seconds after installing (meant for users to review result)
    .NOTES
    AUTHOR: Tony Pagliaro (RFA) tpagliaro@rfa.com
    Date: 2019/12/13
    #>

    [CmdletBinding()]
    param(
        # Location ID as a number
        [Parameter(Position=0)]
        [int]$LocationID=1,
        
        # Will not pause for 90 seconds after installing (meant for users to review result)
        [switch]$NoWait
    )
    
    $vMsg = "Testing current session to ensure we are running as admin."
    Write-Verbose $vMsg
    Write-Debug $vMsg
    Confirm-RequiresAdmin

    $ltposhURL = $global:ltposhURL
    $RfaAutomateServer = $global:RfaAutomateServer
    $UninstallRequired = $false
    $InstallRequired = $false
    $InstallSplat = @{

        Server=$RfaAutomateServer
        ServerPassword='y[K9knLJc2]QcExf'
        Hide=$true
        LocationID=$LocationID

    }


    # Check for existing install
    $vMsg = "Testing $($env:COMPUTERNAME) for existing install."
    Write-Verbose $vMsg
    Write-Debug $vMsg
    if (Test-LtInstall -Generic -Quiet) {

        # Test is the agent is checking into correct server/location
        $vMsg = "Checking if current install on $($env:COMPUTERNAME) points to $($global:RfaAutomateServer)."
        Write-Verbose $vMsg
        Write-Debug $vMsg
        if (Test-LtInstall -Quiet) {
        
            # Already installed, exit no issues
            Write-Output "PASSED: The Automate Agent is already installed."
            if ( -not $NoWait ) { Start-Sleep 15 }
        
        } else {
        
            # Further work required
            $UninstallRequired = $true
        
        }

    } else {
        
        $InstallRequired = $true

    }


    # Remove if required
    if ($UninstallRequired) {

        $vMsg = "Removing install on $($env:COMPUTERNAME)."
        Write-Verbose $vMsg
        Write-Debug $vMsg
        Uninstall-LTService -Server $Server -Force
        Start-Sleep 60
        
        $InstallRequired = $true

    }

    if ($InstallRequired) {

        Try{

            $vMsg = "Installing on $($env:COMPUTERNAME)."
            Write-Verbose $vMsg
            Write-Debug $vMsg
            Install-LTService @InstallSplat -ea stop

        } Catch {

            $vMsg = "Retrying install on $($env:COMPUTERNAME), skipping .Net validation."
            Write-Verbose $vMsg
            Write-Debug $vMsg
            Install-LTService @InstallSplat -SkipDotNet

        } Finally {
            
            if ( -not $NoWait ) { Start-Sleep 90 }

        }

    }


    # Test is the agent is checking into correct server/location
    if (Test-LtInstall -Quiet) {

        Write-Output "SUCCESS: The Automate Agent was successfully installed."
        if ( -not $NoWait ) { Start-Sleep 5 }

    } else {

        Write-Output ($Error.Exception.Message)
        Write-Output (Test-LtInstall | Format-List | Out-String)
        if ( -not $NoWait ) { Start-Sleep 5 }
        Throw "FAILURE: The Automate Agent could not be installed or is not checking in after a minute."

    }

}# END function Install-RfaCwaAgent

function Test-LtRemoteRegistry {
    <#
    .SYNOPSIS
    Checks the remote computer for existing config.
    .DESCRIPTION
    Does not test as deeply as Test-LtInstall, meant for pre-check after a Test-Connection passes. Useful if WinRM is disabled.
    .INPUTS
    This function consumes ComputerName property from the pipeline.
    .OUTPUTS
    This function outputs a custom object to the pipeline with the computername, MAC, ClientID, LastContact, and ServerAddress.
    #>
    [CmdletBinding()]
    Param(
        # The name of the remote computer
        [Parameter(Mandatory=$true)]
        [string[]]
        $ComputerName
    )

    Begin {
        $KeyPath = 'SOFTWARE\LabTech\Service'
        $Values = @(
            'Server Address'
            'LastSuccessStatus'
            'MAC'
            'ClientID'
        )
    }

    Process {

        Foreach ($Computer in $ComputerName) {

            $RegSplat = @{
                ComputerName = $Computer
                RegistryHive = 'LocalMachine'
                RegistryKeyPath = $KeyPath
                Value = $null
                ErrorAction = 'Stop'
            }

            if (Test-Connection -ComputerName $Computer -Count 2 -Quiet) {

                Foreach ($Value in $Values) {
                    $RegSplat.Set_Item('Value',$Value)
                    Try {
                        Get-RegistryValueData @RegSplat | New-Variable -Name ($Value.Replace(' ','')) -Force
                    } Catch {
                        $null | New-Variable -Name ($Value.Replace(' ','')) -Force
                    }
                }#END Foreach ($Value in $Values)

                [pscustomobject]@{
                    ComputerName = $Computer
                    ServerAddress = $ServerAddress.RegistryValueData
                    LastContact = $LastSuccessStatus.RegistryValueData
                    MAC = $MAC.RegistryValueData
                    ClientID = $ClientID.RegistryValueData
                }

            } else {
                Write-Warning "$($Computer) is not responding."
            }#END if (Test-Connection -ComputerName $Computer -Count 2 -Quiet)

        }#END Foreach ($Computer in $ComputerName)

    }#END Process
}
