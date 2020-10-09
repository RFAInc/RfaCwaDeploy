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
        [string]$ServerShouldBeLike = '*automate.rfa.com*',
        [int]$LocationShouldBe = $LocationID,
        [version]$VersionShouldBe = (Get-LtServerVersion),
        #$LastContactShouldBeGreaterThan = (Get-Date).AddMinutes(-5),
        [switch]$Generic,
        [switch]$Quiet
    )
    
    # Check for existing install
    $TestPass = $true
    $LTServiceInfo = Get-LTServiceInfo -ErrorAction SilentlyContinue
    [version]$VersionIs = $LTServiceInfo.Version
    
    if ($Generic) {

        if (-not $LTServiceInfo) {$TestPass = $false}
    
    } else {
    
        $ServerIs = $LTServiceInfo.'Server Address'
        $LocationIs = $LTServiceInfo.LocationID
        $LastContactIs = $LTServiceInfo.LastSuccessStatus -as [datetime]
        $AgentIdIs = $LTServiceInfo.ID -as [int]
        
        # Test the info vs the conditions
        
        if (-not ($ServerIs -like $ServerShouldBeLike)) {$TestPass = $false}
        if (-not ($LocationIs -eq $LocationShouldBe)) {$TestPass = $false}
        if (-not ($AgentIdIs -gt 0)) {$TestPass = $false}
        if (-not ($VersionIs -eq $VersionShouldBe)) {$TestPass = $false}
        #if (-not ($LastContactIs -ge $LastContactShouldBeGreaterThan)) {$TestPass = $false}
    
    }
    
    if ($Quiet -or $Generic) {
        Write-Output $TestPass
    } else {
        [PSCustomObject]@{
            ServerAddress = $ServerIs
            LocationID = $LocationIs
            LastSuccessStatus = $LastContactIs
            Version = $VersionIs
            AgentId = $AgentIdIs
        }
    }

}

function Uninstall-RfaCwaAgent {
    param()
    $ltposhURL = $global:ltposhURL
    Uninstall-LtService -Server $RfaAutomateServer -Force
}

function strDate {
    (Get-Date).ToString('yyyy-MM-dd_HH:mm:ss:fff')
}

function Install-RfaCwaAgent {

    <#
    .SYNOPSIS
    Installs the RFA Automate agent
    .DESCRIPTION
    Checks the local system for the Automate agent and verifies if the agent belongs to RFA and not some other MSP. (Re-) installs as needed. Also ensures the agent is checking in after install. 
    .PARAMETER LocationID
    Location ID as a number
    .PARAMETER LogPath
    Path to the log file for diaglosing script behavior
    .PARAMETER NoWait
    Will not pause for 90 seconds after installing (meant for users to review result)
    .PARAMETER Reinstall
    Will force an reinstall on any existing installations that are found regardless of current state
    .NOTES
    AUTHOR: Tony Pagliaro (RFA) tpagliaro@rfa.com
    Date: 2019/12/13
    #>

    [CmdletBinding()]
    param(
        # Location ID as a number
        [Parameter(Position=0)]
        [int]$LocationID=1,
        
        # Path to the log file for diaglosing script behavior
        [Parameter()]
        [string]$LogPath='C:\windows\temp\rfaltagent.log',
        
        # Will pause for after installing (meant for users to review result)
        [Parameter()]
        [switch]$Wait,
        
        # Will force an uninstall on any existing installations that are found
        [Parameter()]
        [switch]$Reinstall
    )
    
    $vMsg = "$(strDate) Testing current session to ensure we are running as admin."
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
    $vMsg = "$(strDate) Testing $($env:COMPUTERNAME) for existing install."
    Write-Verbose $vMsg
    Write-Debug $vMsg
    $vMsg | Out-File $LogPath -Append
    if (Test-LtInstall -Generic -Quiet) {

        # Test is the agent is checking into correct server/location
        $vMsg = "$(strDate) Checking if current install on $($env:COMPUTERNAME) points to $($global:RfaAutomateServer)."
        Write-Verbose $vMsg
        Write-Debug $vMsg
        $vMsg | Out-File $LogPath -Append
        if (Test-LtInstall -Quiet) {
        
            # Already installed, do nothing
        
        } else {
        
            # Show the reasons
            $Reasons = (Test-LtInstall).FailReason
            $vMsg = "$(strDate) Agent uninstall required on $($env:COMPUTERNAME)! Reasons: $($Reasons)"
            Write-Verbose $vMsg
            Write-Debug $vMsg
            $vMsg | Out-File $LogPath -Append
            
            # Further work required
            $UninstallRequired = $true
        
        }

    } else {
        
        $InstallRequired = $true

    }


    # Remove if required
    if ($UninstallRequired -or $Reinstall) {

        $ErrorLogBackupPath = "$($env:WINDIR)\Temp\lterrors.$((Get-Date).ToString('yyyyMMddHHmmss')).txt"
        $vMsg = "$(strDate) Backing up error log to ""$($ErrorLogBackupPath)"" on $($env:COMPUTERNAME)."
        Write-Verbose $vMsg
        Write-Debug $vMsg
        $vMsg | Out-File $LogPath -Append
        Backup-LtErrorsLog -Path $ErrorLogBackupPath

        $vMsg = "$(strDate) Removing install on $($env:COMPUTERNAME)."
        Write-Verbose $vMsg
        Write-Debug $vMsg
        $vMsg | Out-File $LogPath -Append
        Uninstall-LTService -Server $Server -Force
        
        $InstallRequired = $true
        Start-Sleep -Seconds 2

    }

    if ($InstallRequired) {

        Try{

            $vMsg = "$(strDate) Installing on $($env:COMPUTERNAME)."
            Write-Verbose $vMsg
            Write-Debug $vMsg
            $vMsg | Out-File $LogPath -Append
            Install-LTService @InstallSplat -ea stop

        } Catch {

            $vMsg = "$(strDate) Retrying install on $($env:COMPUTERNAME), skipping .Net validation."
            Write-Verbose $vMsg
            Write-Debug $vMsg
            $vMsg | Out-File $LogPath -Append
            Install-LTService @InstallSplat -SkipDotNet

        } Finally {
            Start-Sleep -Seconds 5
        }

    }


    # Test is the agent is checking into correct server/location
    if (Test-LtInstall -Quiet) {

        Write-Output "SUCCESS: The Automate Agent was successfully installed."
        if ( $Wait ) { Read-Host "Review Results and Press Enter to exit" }

    } else {

        Throw "FAILURE: The Automate Agent could not be installed or is not checking in yet."
        Write-Output ($Error[0].Exception.Message)
        Write-Output (Test-LtInstall | Format-List | Out-String)
        Write-Output "Please check the portal manually. See troubleshooting guide if missing: https://rfatech.atlassian.net/wiki/x/BYB8D"
        if ( $Wait ) { Read-Host "Review Results and Press Enter to exit" }

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

function Get-LtServerVersion {
    ((New-Object System.Net.WebClient).DownloadString('https://automate.rfa.com/LabTech/Agent.aspx')) -replace '\|'
}

function Get-LtServiceVersion {
    # Get version of LtAgent 
(Get-Item 'C:\Windows\LtSvc\LtSvc.exe').versioninfo |
    ForEach-Object{($_.FileMajorPart -as [string]) + '.' + ($_.FileMinorPart)}

}

function Backup-LtErrorsLog {
    <#
    .SYNOPSIS
    Copies the log file to a temp location.
    .DESCRIPTION
    Backs up the LtErrors file to the windows temp folder, by default. Destination can be changed with Path parameter.
    .PARAMETER Path
    Path to the destination file for the backup
    .EXAMPLE
    Backup-LtErrorsLog
    #>
    [CmdletBinding()]
    param (
        # Path to the destination file for the backup
        [Parameter(Position=0)]
        [string]
        $Path=("$($env:WINDIR)\Temp\lterrors.$((Get-Date).ToString('yyyyMMddHHmmss')).txt")
    )
    
    begin {
        # Log file source
        $SourceLog = "$($env:WINDIR)\LtSvc\lterrors.txt"
    }
    
    process {
        # no pipeline support
    }
    
    end {
        Copy-Item -Path $SourceLog -Destination $Path -Force -Confirm:$false
    }
}
