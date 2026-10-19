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
    $Single = $false
    $OpenInCode = $false
    $CleanArgs = @()

    foreach ($arg in $args) {
        if ($arg -eq '-1') {
            $Single = $true
        }
        elseif ($arg -eq '-c') {
            $OpenInCode = $true
        }
        elseif ($arg -eq '-1c' -or $arg -eq '-c1') {
            $Single = $true
            $OpenInCode = $true
        }
        else {
            $CleanArgs += $arg
        }
    }

    $SearchTerm = $CleanArgs -join ' '

    if (-not $SearchTerm) {
        Write-Host "Please provide a search term." -ForegroundColor Red
        return
    }

    # Gather matching filenames and explicitly sort them alphabetically
    $matches = @(rg --files | rg -i -- $SearchTerm | Sort-Object)

    if ($matches.Count -eq 0) {
        Write-Host "No files found matching '$SearchTerm'." -ForegroundColor Yellow
        return
    }

    # Decide workflow based on the -1 (Single) flag
    if ($Single) {
        if ($matches.Count -eq 1) {
            $selection = $matches
        }
        else {
            # Multiple files -> interactive fzf picker
            $selection = $matches | fzf --header="Multiple files found. Select one:" --preview="bat --style=numbers --color=always {}"
        }

        # Apply action based on the -c flag
        if ($selection) {
            if ($OpenInCode) {
                # Launch code instantly without waiting
                Start-Process code -ArgumentList "`"$selection`"" -WindowStyle Hidden
            } else {
                return $selection
            }
        }
    }
    else {
        # Standard behaviour without -1 flag
        if ($OpenInCode) {
            # Batch all paths into a single call and open in background immediately
            $quotedMatches = $matches | ForEach-Object { "`"$_`"" }
            Start-Process code -ArgumentList $quotedMatches -WindowStyle Hidden
        } else {
            # Print the colorized, highlighted filenames to the console
            rg --files | rg -i --color=always -- $SearchTerm | Sort-Object
        }
    }
}

Set-Alias ff Find-File -Force


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
    $currentBranch = git branch --show-current
    
    # 1. Isolate master or main
    $mainBranch = git branch --format="%(refname:short)" | Where-Object { $_ -eq "master" -or $_ -eq "main" } | Select-Object -First 1
    
    # 2. Get other branches (excluding main AND the active current branch)
    $otherLocal = git branch --format="%(refname:short)" | Where-Object { $_ -ne $mainBranch -and $_ -ne $currentBranch }
    
    # 3. Format the active branch with the prefix
    $decoratedCurrent = "› $currentBranch"
    
    # Assemble array structure
    $selection = @(
        if ($currentBranch -ne $mainBranch) { $mainBranch }
        $decoratedCurrent
        $otherLocal
        "+ Create New Branch"
    ) | Where-Object { $_ } | fzf --header="Switch Local Branch"
    
    if ($selection) {
        if ($selection -eq "+ Create New Branch") {
            $rawBranchInput = Read-Host "Enter description or commit text for new branch"
            if ($rawBranchInput) {
                # Format the branch name cleanly using the gen-branch function rules
                $newBranch = New-GitBranchName -InputText $rawBranchInput
                git checkout -b $newBranch
            }
        }
        # Safely exit if they selected the branch they are already standing on
        elseif ($selection -eq $decoratedCurrent -or $selection.Trim() -eq $currentBranch) {
            Write-Host "Already on '$currentBranch'" -ForegroundColor Cyan
            return
        }
        else {
            # Strip layout prefix using a wildcard match to bypass encoding quirks
            $cleanBranch = ($selection -replace "^.*?\s+", "").Trim()
            
            git switch $cleanBranch
            
            # Check if git switch failed (e.g., due to unstaged changes)
            if ($LASTEXITCODE -ne 0) {
                $confirmation = Read-Host "Switch failed. Force switch? (Discard unstaged changes) [y/N]"
                if ($confirmation -match '^[yY](es)?$') {
                    git switch -f $cleanBranch
                } else {
                    Write-Host "Switch aborted." -ForegroundColor Yellow
                }
            }
        }
    }
}
New-Alias sb Invoke-GitBranchSwitchLocal -Force

# sbo -> Interactive Local + Remote Branch Switcher (with separator)
function Invoke-GitBranchSwitchAll {
    $currentBranch = git branch --show-current
    
    # 1. Isolate master or main
    $mainBranch = git branch --format="%(refname:short)" | Where-Object { $_ -eq "master" -or $_ -eq "main" } | Select-Object -First 1
    
    # 2. Get remaining local branches
    $otherLocal = git branch --format="%(refname:short)" | Where-Object { $_ -ne $mainBranch -and $_ -ne $currentBranch }
    
    # 3. Fetch remote branches cleanly
    $remoteBranches = git branch -r --format="%(refname:short)" | Where-Object { $_ -notmatch '->' }
    
    # 4. Format active branch with prefix
    $decoratedCurrent = "› $currentBranch"
    
    # Assemble full structure
    $selection = @(
        if ($currentBranch -ne $mainBranch) { $mainBranch }
        $decoratedCurrent
        $otherLocal
        "+ Create New Branch"
        "--- REMOTE BRANCHES ---"
        $remoteBranches
    ) | Where-Object { $_ } | fzf --header="Switch Branch (Local or Remote)" --preview-window=hidden
    
    if ($selection -and $selection -ne "--- REMOTE BRANCHES ---") {
        if ($selection -eq "+ Create New Branch") {
            $rawBranchInput = Read-Host "Enter description or commit text for new branch"
            if ($rawBranchInput) {
                # Format the branch name cleanly using the gen-branch function rules
                $newBranch = New-GitBranchName -InputText $rawBranchInput
                git checkout -b $newBranch
            }
        }
        # Safely exit if they selected the branch they are already standing on
        elseif ($selection -eq $decoratedCurrent -or $selection.Trim() -eq $currentBranch) {
            Write-Host "Already on '$currentBranch'" -ForegroundColor Cyan
            return
        }
        else {
            # Strip layout prefix using a wildcard match to bypass encoding quirks
            $cleanBranch = $selection -replace "^.*?\s+", ""
            $cleanBranch = $cleanBranch.Trim()
            if ($cleanBranch -like "origin/*") {
                $cleanBranch = $cleanBranch -replace "^origin/", ""
            }
            
            git switch $cleanBranch
            
            # Check if git switch failed (e.g., due to unstaged changes)
            if ($LASTEXITCODE -ne 0) {
                $confirmation = Read-Host "Switch failed. Force switch? (Discard unstaged changes) [y/N]"
                if ($confirmation -match '^[yY](es)?$') {
                    git switch -f $cleanBranch
                } else {
                    Write-Host "Switch aborted." -ForegroundColor Yellow
                }
            }
        }
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

# pr -> Interactive Open PR Selector
function Invoke-GitListOpenPRs {
    # 1. Ensure we are in a Git repository
    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Write-Error "Not a git repository."
        return
    }

    # 2. Check if GitHub CLI is installed
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI ('gh') is required to list PRs. Please install it."
        return
    }

    # 3. Fetch open PRs as raw JSON fields (number, title, headRefName)
    Write-Host "Fetching open pull requests..." -ForegroundColor Cyan
    $prJson = gh pr list --state open --limit 50 --json number,title,headRefName 2>$null | ConvertFrom-Json

    if (-not $prJson) {
        Write-Warning "No open pull requests found for this repository."
        return
    }

    # 4. Format lines with structured column padding for fzf
    $fzfLines = foreach ($pr in $prJson) {
        # Format: "#1234  [branch-name]  PR Title Text"
        "#$($pr.number.ToString().PadRight(6)) [$($pr.headRefName.PadRight(20))]  $($pr.title)"
    }

    # 5. Pipe formatted list to fzf
    $selected = $fzfLines | fzf --header="Select an open PR to view in browser" --height=40% --reverse

    # 6. Extract the numeric ID from the selected line and open via gh pr view --web
    if ($selected -match "^#(?<num>\d+)") {
        $prNumber = $Matches.num
        Write-Host "Opening PR #$prNumber in browser..." -ForegroundColor Green
        gh pr view $prNumber --web
    }
}
New-Alias pr Invoke-GitListOpenPRs -Force


function Invoke-GitStashInteractive {
    # 1. Fetch the stash list
    $stashList = git stash list

    if (-not $stashList) {
        Write-Host "No stashes found." -ForegroundColor Yellow
        return
    }

    # 2. Add an option to create a new stash at the top of the list
    $options = @("+ Create New Stash") + $stashList

    # 3. Simple list picker
    $selection = $options | fzf --header="Git Stash Manager (Enter: Select | Esc: Cancel)"

    if (-not $selection) {
        return
    }

    # Handle creation of a new stash
    if ($selection -eq "+ Create New Stash") {
        $message = Read-Host "Enter stash message (Optional)"
        if ($message.Trim()) {
            git stash push -m $message.Trim()
        } else {
            git stash push
        }
        return
    }

    # Extract the exact stash identifier (e.g., stash@{2}) using explicit array access [0]
    if ($selection -match 'stash@\{[0-9]+\}') {
        $targetStash = $matches[0]
    } else {
        Write-Host "Could not parse stash selection." -ForegroundColor Red
        return
    }

    # 4. Standard sequential workflow options via Read-Host
    Write-Host "`nSelected: $selection" -ForegroundColor Cyan
    Write-Host "Choose an action:"
    Write-Host "  [a] Apply (Keep in stash list)"
    Write-Host "  [p] Pop   (Apply and remove from list)"
    Write-Host "  [d] Drop  (Delete from list)"
    Write-Host "  [v] View full diff"
    Write-Host "  [c] Cancel"
    
    $action = Read-Host "Action"

    switch ($action.ToLower().Trim()) {
        "a" { git stash apply $targetStash }
        "p" { git stash pop $targetStash }
        "d" { 
            $confirm = Read-Host "Are you sure you want to drop $targetStash? [y/N]"
            if ($confirm -match '^[yY](es)?$') {
                git stash drop $targetStash
            } else {
                Write-Host "Dropped aborted." -ForegroundColor Yellow
            }
        }
        "v" { git stash show -p $targetStash }
        default { Write-Host "Action cancelled." -ForegroundColor Yellow }
    }
}

# Clear out pre-existing conflicts for 'gs'
if (Get-Alias gs -ErrorAction SilentlyContinue) { Remove-Item alias:gs -Force }

# Establish alias
New-Alias gs Invoke-GitStashInteractive -Force


function New-GitBranchName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$InputText
    )

    # 1. Handle the 'TECH-####' exception by preserving it while lowercasing everything else
    # We find 'TECH-\d+' and lowercase everything except matches found by regex
    $processedText = [regex]::Replace($InputText, '(?i)\btech-\d+\b|.+?', {
        param($match)
        if ($match.Value -match '(?i)^tech-\d+$') {
            # Keep TECH- capitalized, but ensure the word 'TECH' itself is uppercase
            return $match.Value.ToUpper()
        }
        # Lowercase everything else
        return $match.Value.ToLower()
    })

    # 2. Clean up characters: Remove special characters, keep only alphanumerics, spaces, and hyphens
    $cleanedText = $processedText -replace '[^a-z0-9\s\-]', ''

    # 3. Replace all spaces (and multiple spaces/hyphens) with a single hyphen
    $branchName = $cleanedText -replace '[\s\-]+', '-'

    # Trim trailing or leading hyphens
    return $branchName.Trim('-')
}

# Set the requested alias
Set-Alias -Name gen-branch -Value New-GitBranchName

function goto {
    param (
        [Parameter(Position = 0)]
        [string]$Target
    )

    # 1. Configuration Path
    $MappingFile = "$HOME/documents/github/dotfiles/PowerShell/mappings.json"
    if (-not (Test-Path $MappingFile)) {
        Write-Error "Mapping file not found at $MappingFile"
        return
    }

    # 2. Parse JSON & resolve paths upfront
    $Mappings = Get-Content -Raw $MappingFile | ConvertFrom-Json
    $ResolvedList = foreach ($Prop in $Mappings.PSObject.Properties) {
        $RawPath = $Prop.Value
        $Expanded = [Environment]::ExpandEnvironmentVariables($RawPath).Replace('$HOME', $HOME).Replace('/', '\')
        
        # Safe acronym generation using native methods (e.g., "data-portal" -> "dp")
        $SplitWords = $Prop.Name -split '[-_\s]'
        $Initials = ($SplitWords.ForEach({ $_[0] }) -join '').ToLower()

        [PSCustomObject]@{
            Key      = $Prop.Name
            Path     = $Expanded
            Initials = $Initials
        }
    }

    $FinalMatch = $null

    # 3. Scenario A: No argument provided -> Open full fzf menu
    if ([string]::IsNullOrWhiteSpace($Target)) {
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-Error "fzf is required for interactive mode."
            return
        }

        # Build visual list and append the edit option at the very bottom
        $FzfInput = [System.Collections.Generic.List[string]]::new()
        foreach ($Item in $ResolvedList) {
            $FzfInput.Add(("{0,-15} -> {1}" -f $Item.Key, $Item.Path))
        }
        $FzfInput.Add("[Edit Mappings File]")

        $Selection = $FzfInput | fzf --height 40% --reverse --header="Select a directory shortcut:"
        if ([string]::IsNullOrWhiteSpace($Selection)) { return }
        
        # Check if the user selected the edit option
        if ($Selection -eq "[Edit Mappings File]") {
            code $MappingFile
            return
        }

        # CRITICAL FIX: Extract ONLY the first string (index 0) from the fzf selection row
        $SelectedKey = ($Selection -split '\s+')[0]
        $FinalMatch = $ResolvedList | Where-Object { $_.Key -eq $SelectedKey } | Select-Object -First 1
    }
    else {
        # 4. Scenario B: Explicit argument passed -> Deep Fuzzy & Abbreviation Match
        $CleanTarget = $Target.Replace('-', '').Replace('_', '').ToLower()
        
        # Generate a regex pattern for fuzzy typing (e.g., "dapi" becomes "d.*a.*p.*i")
        $FuzzyChars = [char[]]$CleanTarget | ForEach-Object { [regex]::Escape($_) }
        $FuzzyPattern = $FuzzyChars -join '.*'

        $Matches = $ResolvedList | Where-Object {
            $CleanKey = $_.Key.Replace('-', '').Replace('_', '').ToLower()
            
            # Match checks: exact, substring, acronym initials, or deep fuzzy sequence
            $_.Key.ToLower() -eq $Target.ToLower() -or 
            $CleanKey.Contains($CleanTarget) -or
            $_.Initials -eq $Target.ToLower() -or
            $CleanKey -match $FuzzyPattern
        }

        # 5. Handle Matches intelligently
        if ($Matches.Count -eq 0) {
            Write-Error "go: No mapping found matching '$Target'"
            return
        } 
        elseif ($Matches.Count -eq 1) {
            $FinalMatch = $Matches
        } 
        else {
            # Multiple matches found -> Pipe conflicts into fzf
            if (Get-Command fzf -ErrorAction SilentlyContinue) {
                $FzfInput = $Matches | ForEach-Object { "{0,-15} -> {1}" -f $_.Key, $_.Path }
                $Selection = $FzfInput | fzf --height 40% --reverse --header="Multiple matches found for '$Target'. Pick one:"
                
                if ([string]::IsNullOrWhiteSpace($Selection)) { return }
                
                # CRITICAL FIX: Extract index 0 here too
                $SelectedKey = ($Selection -split '\s+')[0]
                $FinalMatch = $Matches | Where-Object { $_.Key -eq $SelectedKey } | Select-Object -First 1
            } else {
                $FinalMatch = $Matches[0]
            }
        }
    }

    # 6. Execute CD
    if ($FinalMatch) {
        if (Test-Path $FinalMatch.Path) {
            Set-Location $FinalMatch.Path
        } else {
            Write-Error "Directory does not exist: $($FinalMatch.Path)"
        }
    }
}

New-Alias go goto 

