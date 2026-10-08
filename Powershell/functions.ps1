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

function Get-PyPiExpiry {
    <#
    .SYNOPSIS
        Extracts and displays the expiration date from the ELANPYPI_URL environment variable.
    .DESCRIPTION
        Parses the VssSessionToken timestamp inside $env:ELANPYPI_URL, converts it to a 
        readable date, and calculates the remaining validity time.
    #>
    [CmdletBinding()]
    param()

    process {
        # 1. Check if the environment variable exists
        if (-not $env:ELANPYPI_URL) {
            Write-Error "Environment variable $env:ELANPYPI_URL is not set."
            return
        }

        # 2. Use RegEx to isolate the timestamp matching YYYY-MM-DD followed by the time
        if ($env:ELANPYPI_URL -match 'VssSessionToken_(?<Date>\d{4}-\d{2}-\d{2})T(?<Time>\d{4})') {
            $DateStr = $Matches['Date']
            $TimeStr = $Matches['Time']

            # Reformat to a standard string that PowerShell can parse (e.g., "2026-10-01 13:07")
            $FormattedTimestamp = "{0} {1}:{2}" -f $DateStr, $TimeStr.Substring(0,2), $TimeStr.Substring(2,2)
            
            # Convert to a real DateTime object
            $ExpiryDate = [DateTime]::ParseExact($FormattedTimestamp, "yyyy-MM-dd HH:mm", $null)
            $TimeRemaining = $ExpiryDate - (Get-Date)

            # 3. Output a clean summary
            Write-Host "--- PyPi Token Status ---" -ForegroundColor Cyan
            Write-Host "Expiry Date: " -NoNewline
            Write-Host $ExpiryDate.ToString("F") -ForegroundColor Yellow
            
            if ($TimeRemaining.Ticks -lt 0) {
                Write-Host "Status:      EXPIRED" -ForegroundColor Red
            } else {
                Write-Host "Time Left:   " -NoNewline
                Write-Host ("{0} days, {1} hours, {2} minutes" -f $TimeRemaining.Days, $TimeRemaining.Hours, $TimeRemaining.Minutes) -ForegroundColor Green
            }
        } else {
            Write-Error "Could not find a valid 'VssSessionToken_YYYY-MM-DDTHHmm' timestamp inside the URL."
        }
    }
}


function Install-FirewallCertificates {
    <#
    .SYNOPSIS
        Runs the elanpy script to install firewall certificates.
    #>
    [CmdletBinding()]
    param()

    process {
        Write-Host "Installing firewall certificates..." -ForegroundColor Cyan
        python -c "from elanpy.misc.install_firewall_certificates import install_firewall_certificates; install_firewall_certificates()"
    }
}

function Update-Requirements {
    <#
    .SYNOPSIS
        Refreshes the environment variables and installs pip requirements using the secure PyPi URL.
    #>
    [CmdletBinding()]
    param()

    process {
        # 1. Run the environment update function
        Update-Environment

        # 2. Verify the PyPi URL variable is present before installing
        if (-not $env:ELANPYPI_URL) {
            Write-Error "Cannot install requirements: $env:ELANPYPI_URL is not set."
            return
        }

        # 3. Check for the requirements file in the current directory
        if (-not (Test-Path "requirements.txt")) {
            Write-Error "requirements.txt not found in the current directory: $(Get-Location)"
            return
        }

        Write-Host "Installing Python packages from requirements.txt..." -ForegroundColor Cyan
        pip install -r requirements.txt --extra-index-url $env:ELANPYPI_URL
    }
}

function Find-File {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$SearchTerm
    )
    rg --files | rg -i $SearchTerm
}
Set-Alias ff Find-File

function touch {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string[]]$Paths
    )

    process {
        foreach ($Path in $Paths) {
            # Resolve the path to handle relative paths accurately
            $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            
            if (Test-Path -LiteralPath $ResolvedPath) {
                # File exists: update both Last Write and Last Access timestamps to right now
                (Get-Item -LiteralPath $ResolvedPath).LastWriteTime = [DateTime]::Now
                (Get-Item -LiteralPath $ResolvedPath).LastAccessTime = [DateTime]::Now
            } else {
                # File does not exist: create a new empty file
                New-Item -ItemType File -Path $ResolvedPath -Force | Out-Null
            }
        }
    }
}
