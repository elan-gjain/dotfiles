function pushit {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    
    git add .
    git commit -m $Message
    git push
}


function export {
    param (
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$Argument
    )

    # Combine everything typed into a single line
    $RawInput = $Argument -join " "

    # Look for the first '=' symbol to split the variable name from the value
    $EqualIndex = $RawInput.IndexOf('=')

    if ($EqualIndex -gt 0) {
        # Extract and clean up the variable name
        $Name = $RawInput.Substring(0, $EqualIndex).Trim()

        # Extract the value part
        $Value = $RawInput.Substring($EqualIndex + 1).Trim()

        # Strip outer single or double quotes if they exist
        if ($Value -match '^"(.*)"$|^''(.*)''$') {
            $Value = $Matches[1] ? $Matches[1] : $Matches[2]
        }

        # Save to the current process environment
        [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    } else {
        Write-Error "Invalid export syntax. Use: export NAME=value"
    }
}


function unset {
    param (
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$Variables
    )

    foreach ($Var in $Variables) {
        # Trim any accidental spaces or quotes
        $CleanVar = $Var.Trim().Replace('"', '').Replace("'", "")
        
        # Remove the variable from the current process
        [System.Environment]::SetEnvironmentVariable($CleanVar, $null, "Process")
    }
}

# Create a short, easy-to-type alias for quick use
Set-Alias -Name 'refrenv' -Value Update-Environment

if (Get-Alias -Name ls -ErrorAction SilentlyContinue) {
    Remove-Item Alias:\ls -Force
}

function ls {
    eza.exe --icons=never --group-directories-first $args
}

function ll {
    eza.exe --long --icons=never --group-directories-first --git $args
}

function l {
    eza.exe --icons=never --group-directories-first $args
}


if (Get-Alias -Name pwd -ErrorAction SilentlyContinue) {
    Remove-Item Alias:\pwd -Force
}

function pwd {
    (Get-Location).Path
}

function Edit-Aliases {
    code "C:\Users\gjain\Documents\PowerShell\aliases.ps1"
}

function Edit-Functions {
    code "C:\Users\gjain\Documents\PowerShell\functions.ps1"
}

Set-Alias python39 "C:\Users\gjain\AppData\Roaming\uv\python\cpython-3.9-windows-x86_64-none\python.exe"
Set-Alias python311 "C:\Users\gjain\AppData\Roaming\uv\python\cpython-3.11-windows-x86_64-none\python.exe"
Set-Alias python312 "C:\python\python3.12.9\python.exe"

function Invoke-Exit { exit }
Set-Alias -Name exti -Value Invoke-Exit
