# Global Variables
$global:ltposhURL = 'https://raw.githubusercontent.com/LabtechConsulting/LabTech-Powershell-Module/master/LabTech.psm1'
$global:RfaAutomateServer='https://automate.rfa.com'

# Load external functions
Invoke-Expression ((new-object Net.WebClient).DownloadString($ltposhURL))



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
        
        if (-not $ServerIs -like $ServerShouldBeLike) {$TestPass = $false}
        if (-not $LocationIs -eq $LocationShouldBe) {$TestPass = $false}
        if (-not $LastContactIs -ge $LastContactShouldBeGreaterThan) {$TestPass = $false}
    
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
        ServerPassword='+KuQQJbctLbr7IrXfLCLcg=='
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
            exit 0
        
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

    } else {

        Write-Output ($Error.Exception.Message)
        Write-Output (Test-LtInstall | Format-List | Out-String)
        Throw "FAILURE: The Automate Agent could not be installed or is not checking in after a minute."

    }

}# END function Install-RfaCwaAgent

