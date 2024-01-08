#Requires -Version 5.1

<#
  .SYNOPSIS
  Demo script for replicating source directory to replica directory.

  .DESCRIPTION
  This script replicates source directories and files to replica directory.
  Not replicating time stamps, attributes and auditing.
  Intended only for Windows environment.
  For large file/directory structures will be probably slow as would need some parallel execution (working in a threads).
  Using .NET classes for file operations (like get folder tree, copy etc.) would do script execution much faster.
  You can turn on the verbose output using -Verbose parameter.
  
  .PARAMETER SourceDirectory
  Specifies the path to source directory. This parameter is mandatory.

  .PARAMETER ReplicaDirectory
  Specifies the path to the replica directory. This parameter is mandatory.

  .PARAMETER LogFilePath
  Specifies the path to the log file. If not specified then script defaults to script folder. Therefore this parameter is optional.

  .PARAMETER ProceedOwnerAndAcls
  Switch parameter, if specified, script proceeds with ACLs and owners.

  .PARAMETER Verbose
  Switch built-in parameter, to see verbose output (good for debugging etc.)

  .INPUTS
  None.

  .OUTPUTS
  All items operation messages are logged into the log file.

  .EXAMPLE
  PS> .\VeeamTask.ps1 -SourceDirectory "c:\temp\A_Source" -ReplicaDirectory "c:\temp\B_Destination" -LogFilePath "C:\temp\ReplicaScriptLog.txt"

#>

param (
    [parameter(Mandatory=$true)][string]$SourceDirectory,
    [parameter(Mandatory=$true)][string]$ReplicaDirectory,
    [parameter(Mandatory=$false)][string]$LogFilePath="n/a",
    [parameter(Mandatory=$false)][switch]$ProceedOwnerAndAcls=$false
)

function WriteMessage ($Type,$Message,$LogFile) {

    # Function for writing messages to the stdout and to the log file
    switch ( $Type ) {
        "Verbose" {
            Write-Verbose -Message $Message
            if ( $null -ne $LogFile ) {
                #Add-Content -Value ( (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ";$Type;$Message" ) -Path $LogFile
            }
        } # End of "Debug" type

        "Error" {
            Write-Host $Message -ForegroundColor Red
            if ( $null -ne $LogFile ) {
                Add-Content -Value ( (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ";$Type;$Message" ) -Path $LogFile
            }
        } # End of "Error" type

        "Warning" {
            Write-Host $Message -ForegroundColor Magenta
            if ( $null -ne $LogFile ) {
                Add-Content -Value ( (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ";$Type;$Message" ) -Path $LogFile
            }
        } # End of "Warning" type

        "Info" {
            Write-Host $Message -ForegroundColor Cyan
            if ( $null -ne $LogFile ) {
                Add-Content -Value ( (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ";$Type;$Message" ) -Path $LogFile
            }
        } # End of "Info" type

        default {
            if ( $null -ne $LogFile ) {
                Add-Content -Value ( (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ";$Type;$Message" ) -Path $LogFile
            }
        } # End of "default" type        
    } # End of switch

} # End of function

function InitializeLogFile {
    # Checking if logfilepath parameter provided, if not set default
    WriteMessage -Type "Verbose" -Message "Checking if LogFilePath parameter has been provided, if not default to script name instead"
    if ( $LogFilePath -ne "n/a" ) {
        $Config.LogFilePath = $LogFilePath
    }

    # Checking if log directory exists, if not create it
    WriteMessage -Type "Verbose" -Message "Checking if log file directory exists"
    if ( -not ( Test-Path -Path ( Split-Path -Parent $Config.LogFilePath ) ) ) {
        try {
            WriteMessage -Type "Verbose" -Message "Creating directory for log file"
            New-Item -Path ( Split-Path -Parent $Config.LogFilePath ) -ItemType Directory -ErrorAction Stop | Out-Null
        } catch {
            WriteMessage -Type "Verbose" -Message "Directory for log file cannot be created, defaulting to script folder"
            $Config.LogFilePath = $Config.ScriptDirectory + $Config.ScriptName + ".log"
        }
    }

    # Checking if log file exists, if not create empty file
    WriteMessage -Type "Verbose" -Message "Checking if log file exists"
    if ( -not ( Test-Path -Path $Config.LogFilePath ) ) {
        WriteMessage -Type "Verbose" -Message "Creating new log file"
        New-Item -Path $Config.LogFilePath -ItemType File | Out-Null
    }

} # End of function

function InitializeScript {
    # Checking if script executed as admin
    if ( $Config.ProceedOwnerAndAcls -and -not ( [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544") ) ) {
        WriteMessage -Type "Warning" -Message "Script not executed in elevated (Run as administrator) mode, therefore cannot set owner and ACLs. Option disabled." -LogFile $Config.LogFilePath
        $Config.ProceedOwnerAndAcls = $false
    }

    # Checking if source directory exists
    WriteMessage -Type "Verbose" -Message "Checking if source directory exists" -LogFile $Config.LogFilePath
    if ( -not ( Test-Path -Path $Config.SourceDirectory ) ) {
        WriteMessage -Type "Error" -Message "Source directory does not exist! Terminating" -LogFile $Config.LogFilePath
        throw "Source directory does not exist! Terminating"
    }

    # Checking if replica directory exists, if not create it
    WriteMessage -Type "Verbose" -Message "Checking if replica directory exists" -LogFile $Config.LogFilePath
    if ( -not ( Test-Path -Path $Config.ReplicaDirectory ) ) {
        try {
            WriteMessage -Type "Verbose" -Message "Creating replica directory" -LogFile $Config.LogFilePath
            New-Item -Path $Config.ReplicaDirectory -ItemType Directory -ErrorAction Stop | Out-Null
        } catch {
            WriteMessage -Type "Error" -Message "Replica directory cannot be created! Check access rights. Terminating" -LogFile $Config.LogFilePath
            throw "Replica directory cannot be created! Check access rights. Terminating"
        }
    }
} # End of function

function ReplicateDirectoryContent {
    # Load all files/directories to variable with recurse parameter and with force to see hidden and system files as well
    $AllItems = Get-ChildItem -Path $Config.SourceDirectory -Recurse -Force
    
    # Call function to create directory tree
    CreateDirectoryTree -Directories ( $AllItems | Where-Object { $_.PsIsContainer -eq $true } )

    # Call function to migrate files to the destination directories
    MigrateFiles -Files ( $AllItems | Where-Object { $_.PsIsContainer -eq $false } )
} # End of function

function CreateDirectoryTree ($Directories) {
    
    WriteMessage -Type "Verbose" -Message "Creating replica directory tree" -LogFile $Config.LogFilePath
    # Loop for each folder
    foreach ( $Directory in $Directories ) {
        # Convert '\' in the path to '\\' as -replace expects regexp (so this char must be escaped)
        $ReplicaDirectory = ( $Directory.FullName -replace "$($Config.SourceDirectory -replace "\\",'\\')","$($Config.ReplicaDirectory)" )
        
        # Check if replica directory exists, if not create it and set ACLs + owner if option enabled in config
        if ( -not ( Test-Path -Path $ReplicaDirectory ) ) {
            WriteMessage -Type "Info" -Message "New directory '$ReplicaDirectory' created" -LogFile $Config.LogFilePath
            New-Item -Path $ReplicaDirectory -ItemType Directory | Out-Null
            
            if ( $Config.ProceedOwnerAndAcls ) {
               CompareAcls -SourcePath $Directory.FullName -DestinationPath $ReplicaDirectory
            }

        } else {
            WriteMessage -Type "Verbose" -Message "Directory already exists '$ReplicaDirectory'" -LogFile $Config.LogFilePath

            if ( $Config.ProceedOwnerAndAcls ) {
               CompareAcls -SourcePath $Directory.FullName -DestinationPath $ReplicaDirectory
            }
        }
    }
} # End of function

function MigrateFiles ($Files) {

    WriteMessage -Type "Verbose" -Message "Migrating the files to the replica directory" -LogFile $Config.LogFilePath
    # Loop for each file
    foreach ( $File in $Files ) {
        $ReplicaFile = ( $File.FullName -replace "$($Config.SourceDirectory -replace "\\",'\\')","$($Config.ReplicaDirectory)" )
        
        # Main conditions for copy the file
        if ( -not ( Test-Path -Path $ReplicaFile ) ) {
            # Call function to create new copy of the file as it doesn't exist in the replica directory
            CopyFile -SourcePath $File.FullName -DestinationPath $ReplicaFile -Message "New file"

            if ( $Config.ProceedOwnerAndAcls ) {
               CompareAcls -SourcePath $File.FullName -DestinationPath $ReplicaFile
            }

        } elseif ( -not ( $File.Length -eq ( (Get-Item -Path $ReplicaFile).Length ) ) ) {
            # Call function to create new copy of the file as they are different in length
            CopyFile -SourcePath $File.FullName -DestinationPath $ReplicaFile -Message "Changed file"

            if ( $Config.ProceedOwnerAndAcls ) {
               CompareAcls -SourcePath $File.FullName -DestinationPath $ReplicaFile
            }

        } else {
            WriteMessage -Type "Verbose" -Message "File '$ReplicaFile' already exists and is same size" -LogFile $Config.LogFilePath

            if ( $Config.ProceedOwnerAndAcls ) {
               CompareAcls -SourcePath $File.FullName -DestinationPath $ReplicaFile
            }
        }

    }
} # End of function

function CopyFile ($SourcePath,$DestinationPath,$Message) {
    
    switch ( $Message ) {
            "New file" { $Message = "New file '$DestinationPath' created" }
        "Changed file" { $Message = "Updated file '$DestinationPath' as it was changed" }
               default { $Message = "New file '$DestinationPath' created" }
    }
    
    try {
        Copy-Item -Path $SourcePath -Destination $DestinationPath -ErrorAction Stop
        WriteMessage -Type "Info" -Message $Message -LogFile $Config.LogFilePath
    } catch {
        WriteMessage -Type "Error" -Message "Cannot copy the file '$DestinationPath'. Failed with '$_.Exception.Message'" -LogFile $Config.LogFilePath
    }
}

function CompareAcls ($SourcePath,$DestinationPath) {
    # Get source and destination ACLs and its access property (as ACLs are stored there)
    $AclsOfSource = (Get-Acl -Path $SourcePath).Access
    $AclsOfDestination = (Get-Acl -Path $DestinationPath).Access

    # Compare both ACL arrays and if they do not match, then call function to adjust ACLs
    if ( Compare-Object -ReferenceObject $AclsOfSource -DifferenceObject $AclsOfDestination ) {
        WriteMessage -Type "Verbose" -Message "ACLs of '$SourcePath' does not match replica" -LogFile $Config.LogFilePath
        AdjustAcls -SourcePath $SourcePath -DestinationPath $DestinationPath
    } else {
        WriteMessage -Type "Verbose" -Message "ACLs of '$SourcePath' match replica" -LogFile $Config.LogFilePath
    }
} # End of function

function AdjustAcls ($SourcePath,$DestinationPath) {
    # Try to set ACLs from source to destination
    try {
        WriteMessage -Type "Verbose" -Message "Settings ACLs for '$DestinationPath'" -LogFile $Config.LogFilePath
        Get-Acl -Path $SourcePath -ErrorAction Stop | Set-Acl -Path $DestinationPath -ErrorAction Stop
    } catch {
        WriteMessage -Type "Error" -Message "Cannot set ACLs on '$DestinationPath'. Failed with '$($_.Exception.Message)'" -LogFile $Config.LogFilePath
    }
} # End of function

function CleanReplicaForInvalidItems {
    # Function for cleaning directory tree for directories/files, which are not longer in source
    # Did not use here the 'Test-Path' but used another possible approach using 'Compare-Object'

    # Deffining new property, which have the FullName cut by the SourceDirectory and ReplicaDirectory, to be able to compare later
    $PropertyDistinguishedPath = @{
        Name = "DistinguishedPath"
        Expression = {
            $NewName = $_.FullName -replace "$($Config.SourceDirectory -replace "\\",'\\')",''
            $NewName = $NewName -replace "$($Config.ReplicaDirectory -replace "\\",'\\')",''
            $NewName
        }
    }
    
    # Gathering items from both directories (source and replica) to be able to compare further
    $AllItemsInSource = Get-ChildItem -Path $Config.SourceDirectory -Recurse -Force | Select-Object $PropertyDistinguishedPath | Select-Object -ExpandProperty DistinguishedPath
    $AllItemsInDestination = Get-ChildItem -Path $Config.ReplicaDirectory -Recurse -Force | Select-Object $PropertyDistinguishedPath | Select-Object -ExpandProperty DistinguishedPath

    # Exitting from function if there are no items in the replica folder (destination) - which means nothing to compare
    if ( $null -eq $AllItemsInDestination ) { return }

    # Copmare both directories
    $DirectoriesDifferencies = Compare-Object -ReferenceObject $AllItemsInDestination -DifferenceObject $AllItemsInSource
    
    # Loop for each object in the compared array
    foreach ( $Object in $DirectoriesDifferencies ) {
        if ( $Object.SideIndicator -eq "<=" ) {
            try {
                Remove-Item -Path ($Config.ReplicaDirectory + $Object.InputObject) -Force -Confirm:$false -ErrorAction Stop
                WriteMessage -Type "Info" -Message "Old item '$($Config.ReplicaDirectory + $Object.InputObject)' deleted" -LogFile $Config.LogFilePath
            } catch {
                WriteMessage -Type "Error" -Message "Cannot delete item '$($Config.ReplicaDirectory + $Object.InputObject)'. Failed with '$($_.Exception.Message)'" -LogFile $Config.LogFilePath
            }
        }
    }
} # End of function

$Config = [PSCustomObject]@{
    ScriptName          = Split-Path -Leaf $MyInvocation.MyCommand.Path.Replace(".ps1","")
    ScriptDirectory     = (Split-Path -Parent $MyInvocation.MyCommand.Definition) + "\"
    LogFilePath         = (Split-Path -Parent $MyInvocation.MyCommand.Definition) + "\" + (Split-Path -Leaf $MyInvocation.MyCommand.Path.Replace(".ps1","")) + ".log"

    SourceDirectory     = $SourceDirectory
    ReplicaDirectory    = $ReplicaDirectory

    ProceedOwnerAndAcls = $ProceedOwnerAndAcls.IsPresent
}

InitializeLogFile
InitializeScript
ReplicateDirectoryContent
CleanReplicaForInvalidItems