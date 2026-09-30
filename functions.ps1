function Update-Environment {
    <#
    .SYNOPSIS
        Refreshes environment variables from the Windows Registry into the current session.
    .DESCRIPTION
        This function pulls fresh Machine and User environment variables from the registry,
        rebuilds the $env:PATH variable, and updates all other environment variables.
    #>
    [CmdletBinding()]
    param()

    process {
        Write-Host "Refreshing environment variables from Registry..." -ForegroundColor Cyan
        
        # 1. Grab fresh copies of Machine and User variables directly from the OS
        $MachineVars = [System.Environment]::GetEnvironmentVariables("Machine")
        $UserVars    = [System.Environment]::GetEnvironmentVariables("User")
        
        # 2. Rebuild the PATH variable safely
        # Combine System PATH and User PATH exactly how Windows constructs it natively
        $NewPathEntries = @()
        if ($MachineVars.ContainsKey("Path")) { $NewPathEntries += $MachineVars["Path"] -split ';' }
        if ($UserVars.ContainsKey("Path"))    { $NewPathEntries += $UserVars["Path"] -split ';' }
        
        # Filter out empty paths and remove duplicates while maintaining order
        $UniquePaths = $NewPathEntries | Where-Object { $_ } | Select-Object -Unique
        $env:Path = $UniquePaths -join ';'
        
        # 3. Refresh all other individual environment variables
        # Process Machine variables first, then User variables (so User overrides Machine)
        foreach ($Key in $MachineVars.Keys) {
            if ($Key -ne "Path") { 
                Set-Item -Path "env:$Key" -Value $MachineVars[$Key] 
            }
        }
        foreach ($Key in $UserVars.Keys) {
            if ($Key -ne "Path") { 
                Set-Item -Path "env:$Key" -Value $UserVars[$Key] 
            }
        }
        
        Write-Host "Environment successfully refreshed!" -ForegroundColor Green
    }
}


function Kill-All {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ProcessName,

        [Parameter()]
        [switch]$Restart
    )

    process {
        # Get all running instances of the process
        $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

        if (-not $Processes) {
            Write-Warning "No running processes found named '$ProcessName'."
            return
        }

        # Track the file path if a restart is requested
        $Path = $null
        if ($Restart) {
            # Grab the path from the first instance before killing it
            $Path = $Processes[0].Path
            
            # Fallback for system processes like 'explorer' that don't always expose .Path easily
            if (-not $Path -and $ProcessName -eq "explorer") {
                $Path = "$env:windir\explorer.exe"
            }
        }

        # Kill all instances
        Write-Host "Stopping all instances of '$ProcessName'..." -ForegroundColor Cyan
        $Processes | Stop-Process -Force

        # Restart the process if the switch was provided
        if ($Restart) {
            if ($Path) {
                Write-Host "Restarting '$ProcessName'..." -ForegroundColor Green
                Start-Process -FilePath $Path
            } else {
                Write-Warning "Could not determine the file path to restart '$ProcessName'. Trying by name..."
                Start-Process -FilePath $ProcessName
            }
        }
    }
}

