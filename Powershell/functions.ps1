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


# sb -> Interactive Local Branch Switcher
function Invoke-GitBranchSwitchLocal {
    # Get clean list of local branches and pipe to fzf
    $branch = git branch --format="%(refname:short)" | fzf --header="Switch Local Branch"
    
    if ($branch) {
        git switch $branch.Trim()
    }
}
New-Alias sb Invoke-GitBranchSwitchLocal -Force

# sbo -> Interactive Local + Remote Branch Switcher (with separator)
function Invoke-GitBranchSwitchAll {
    # 1. Fetch clean local branches
    $localBranches = git branch --format="%(refname:short)"
    
    # 2. Fetch remote branches, removing the 'origin/' prefix to make switching clean
    $remoteBranches = git branch -r --format="%(refname:short)" | Where-Object { $_ -notmatch '->' }
    
    # 3. Combine them using fzf's header lines or build an inline header separator
    # We pipe local branches first, a custom visual separator line, then remote branches
    $selection = @(
        $localBranches
        "--- REMOTE BRANCHES ---"
        $remoteBranches
    ) | fzf --header="Switch Branch (Local or Remote)" --preview-window=hidden
    
    # 4. Process selection (ignore if they click the separator label)
    if ($selection -and $selection -ne "--- REMOTE BRANCHES ---") {
        $cleanBranch = $selection.Trim()
        
        # If it's a remote branch (starts with origin/), strip it so git switch tracks it locally
        if ($cleanBranch -like "origin/*") {
            $cleanBranch = $cleanBranch -replace "^origin/", ""
        }
        
        git switch $cleanBranch
    }
}
New-Alias sbo Invoke-GitBranchSwitchAll -Force

# db -> Interactive Branch Deletion with Safeguards
function Invoke-GitBranchDelete {
    # 1. Get clean list of local branches (excluding the current active one)
    $branch = git branch --format="%(refname:short)" | fzf --header="SELECT BRANCH TO DELETE (Cannot delete main/master)"
    
    if (-not $branch) {
        Write-Host "Deletion cancelled. No branch selected." -ForegroundColor Yellow
        return
    }

    $branch = $branch.Trim()

    # 2. Strict protection for production/default branches
    if ($branch -eq "master" -or $branch -eq "main") {
        Write-Host "Action Denied: You cannot delete the '$branch' branch using this tool." -ForegroundColor Red
        return
    }

    # 3. Request a clean console confirmation prompt
    Write-Host ""
    Write-Host "WARNING: You are about to delete local branch: " -NoNewline -ForegroundColor Yellow
    Write-Host $branch -ForegroundColor Cyan
    $confirmation = Read-Host "Do you really want to delete this branch? (y/n)"

    # 4. Process deletion if explicitly confirmed
    if ($confirmation -match "^[yY](es)?$") {
        # Tries soft delete (-d) first, if not merged it will tell you, but you can swap to -D if you prefer forced
        git branch -d $branch
    } else {
        Write-Host "Aborted. Branch '$branch' was not deleted." -ForegroundColor Yellow
    }
}
New-Alias db Invoke-GitBranchDelete -Force


function gor {
    # Check if the current directory is a git repository
    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Write-Error "Not a git repository (or any of the parent directories)"
        return
    }

    # Fetch the remote origin URL
    $remoteUrl = git remote get-url origin 2>$null

    if (-not $remoteUrl) {
        Write-Error "No remote 'origin' configured for this repository."
        return
    }

    # Get the current branch name
    $branch = git branch --show-current 2>$null

    # Clean up SSH or HTTPS URL formatting into a browser-ready link
    $webUrl = $remoteUrl -replace '^git@', 'https://' `
                         -replace '(?<=https://[^/]+):', '/' `
                         -replace '\.git$', ''

    # Append branch path unless on main or master
    if ($branch -and $branch -ne "main" -and $branch -ne "master") {
        $webUrl = "$webUrl/tree/$branch"
    }

    Write-Host "Opening remote: $webUrl" -ForegroundColor Cyan
    
    # Open the URL in the default browser
    Start-Process $webUrl
}


function pr {
    # 1. Ensure we are in a Git repository
    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Write-Error "Not a git repository (or any of the parent directories)"
        return
    }

    # 2. Check if GitHub CLI is installed
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warning "GitHub CLI ('gh') is not installed. Falling back to URL construction..."
        
        # Fallback method: Manually build the URL from the remote origin
        $repoUrl = git config --get remote.origin.url
        if ($repoUrl -match "github.com[:/](.+?)/(.+?)(\.git)?$") {
            $owner = $Matches[1]
            $repo = $Matches[2]
            $branch = git branch --show-current
            $url = "https://github.com"
            Start-Process $url
        } else {
            Write-Error "Could not parse GitHub remote URL."
        }
        return
    }

    # 3. Use GitHub CLI to find and open the open PR for the current branch
    $currentBranch = git branch --show-current
    Write-Host "Looking up open PR for branch: $currentBranch..." -ForegroundColor Cyan
    
    # Executing 'gh pr view --web' opens the current branch's PR in the browser
    gh pr view --web 2>$null

    # 4. If no open PR exists, ask if the user wants to create one
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "No open pull request found for '$currentBranch'."
        $choice = Read-Host "Would you like to create a new PR? (y/n)"
        if ($choice -eq 'y') {
            gh pr create --web
        }
    }
}
