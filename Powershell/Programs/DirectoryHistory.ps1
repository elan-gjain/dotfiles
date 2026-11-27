if (-not $script:DirectoryHistoryInitialized) {
    $script:DirectoryHistory = [System.Collections.Generic.List[string]]::new()
    $script:DirectoryHistory.Add($PWD.Path)
    $script:DirectoryHistoryCurrentIndex = 0
    $script:DirectoryHistoryLastObservedPath = $PWD.Path
    $script:DirectoryHistoryNavigationInProgress = $false
    $script:DirectoryHistoryOriginalPrompt = $function:prompt
    $script:DirectoryHistoryInitialized = $true

    function prompt {
        if (-not $script:DirectoryHistoryNavigationInProgress) {
            $currentPath = $PWD.Path

            if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals(
                    $currentPath,
                    $script:DirectoryHistoryLastObservedPath
                )) {
                $forwardEntryCount = $script:DirectoryHistory.Count - $script:DirectoryHistoryCurrentIndex - 1
                if ($forwardEntryCount -gt 0) {
                    $script:DirectoryHistory.RemoveRange(
                        $script:DirectoryHistoryCurrentIndex + 1,
                        $forwardEntryCount
                    )
                }

                $script:DirectoryHistory.Add($currentPath)
                $script:DirectoryHistoryCurrentIndex = $script:DirectoryHistory.Count - 1
                $script:DirectoryHistoryLastObservedPath = $currentPath
            }
        }

        & $script:DirectoryHistoryOriginalPrompt
    }
}

function Set-DirectoryHistoryLocation {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Index
    )

    $targetPath = $script:DirectoryHistory[$Index]

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Write-Error "Directory does not exist: $targetPath"
        return
    }

    $script:DirectoryHistoryNavigationInProgress = $true
    try {
        Set-Location -LiteralPath $targetPath -ErrorAction Stop
        $script:DirectoryHistoryCurrentIndex = $Index
        $script:DirectoryHistoryLastObservedPath = $PWD.Path
    }
    catch {
        Write-Error "Could not change to '$targetPath': $($_.Exception.Message)"
    }
    finally {
        $script:DirectoryHistoryNavigationInProgress = $false
    }
}

function Move-DirectoryHistory {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(-1, 1)]
        [int]$Direction,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Steps
    )

    $targetIndex = $script:DirectoryHistoryCurrentIndex + ($Direction * $Steps)
    if ($targetIndex -lt 0) {
        $targetIndex = 0
    }
    elseif ($targetIndex -ge $script:DirectoryHistory.Count) {
        $targetIndex = $script:DirectoryHistory.Count - 1
    }

    if ($targetIndex -eq $script:DirectoryHistoryCurrentIndex) {
        return
    }

    while ($true) {
        $targetPath = $script:DirectoryHistory[$targetIndex]
        if (Test-Path -LiteralPath $targetPath -PathType Container) {
            break
        }

        $directionName = if ($Direction -lt 0) { 'back' } else { 'forward' }
        $response = Read-Host "This dir '$targetPath' doesn't exist anymore. Go $directionName 1 more? [y/N]"
        if ($response -notmatch '^(?i:y|yes)$') {
            return
        }

        $nextIndex = $targetIndex + $Direction
        if ($nextIndex -lt 0 -or $nextIndex -ge $script:DirectoryHistory.Count) {
            Write-Warning "No more directory history entries in that direction."
            return
        }

        $targetIndex = $nextIndex
    }

    Set-DirectoryHistoryLocation -Index $targetIndex
}

function back {
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Steps = 1
    )

    Move-DirectoryHistory -Direction -1 -Steps $Steps
}

function fwd {
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Steps = 1
    )

    Move-DirectoryHistory -Direction 1 -Steps $Steps
}

function pcd {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Error 'fzf is required for directory history navigation.'
        return
    }

    $fzfEntries = for ($index = 0; $index -lt $script:DirectoryHistory.Count; $index++) {
        $marker = if ($index -eq $script:DirectoryHistoryCurrentIndex) { '> ' } else { '  ' }
        "{0}`t{1}{2}" -f $index, $marker, $script:DirectoryHistory[$index]
    }

    $selection = $fzfEntries | fzf --reverse --no-height --ansi --border --delimiter "`t" --with-nth '2..' --header 'Select a directory from session history'
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return
    }

    $selectionFields = $selection -split "`t", 2
    $selectedIndex = 0
    if ($selectionFields.Count -lt 2 -or
        -not [int]::TryParse($selectionFields[0], [ref]$selectedIndex) -or
        $selectedIndex -lt 0 -or
        $selectedIndex -ge $script:DirectoryHistory.Count) {
        Write-Error 'Could not determine the selected directory history entry.'
        return
    }

    Set-DirectoryHistoryLocation -Index $selectedIndex
}
