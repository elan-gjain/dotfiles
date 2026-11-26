if (Get-Command posh -ErrorAction SilentlyContinue) {
    posh init pwsh --config "$HOME\Documents\GitHub\dotfiles\Powershell\omp\hul10.yaml" | Invoke-Expression
}
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$HOME\Documents\GitHub\dotfiles\Powershell\omp\hul10.yaml" | Invoke-Expression
}

# Removes '--height' restriction to enforce a modern, fullscreen view
$env:FZF_DEFAULT_OPTS = "--layout=reverse --no-height --ansi --border"
# Syntax-highlighted side preview window for files (triggered by Ctrl + T)
$env:FZF_CTRL_T_OPTS = "--preview 'bat --style=numbers --color=always --line-range :500 {}'"
# Visual folder tree layout preview for directory navigation (triggered by Alt + C)
$env:FZF_ALT_C_OPTS = "--preview 'dir /a /o:gn {}'"

Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

if (Get-Module -ListAvailable PSReadLine) {
    Set-PSReadLineKeyHandler -Key 'Ctrl+l' -Function ClearScreen
}

$env:ARTIFACTS_CREDENTIALPROVIDER_FEED_PROVIDER_CHOICE = "AzCli"
$env:AZURE_TOKEN_CREDENTIALS="dev"

# Custom Profile Path Mappings
$env:PROFILE_IMPORTS        = "$HOME\Documents\GitHub\dotfiles\PowerShell\imports.ps1"
$env:PROFILE_CUSTOMISATIONS = "$HOME\Documents\GitHub\dotfiles\PowerShell\customisations.ps1"
$env:PROFILE_FUNCTIONS      = "$HOME\Documents\GitHub\dotfiles\PowerShell\functions.ps1"
$env:PROFILE_ALIASES        = "$HOME\Documents\GitHub\dotfiles\PowerShell\aliases.ps1"
