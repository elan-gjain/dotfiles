Import-Module posh-git -ErrorAction SilentlyContinue
Import-Module PSFzf -ErrorAction SilentlyContinue
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config 'C:\Users\gjain\Documents\WindowsPowerShell\OhMyPosh\janededobbleer-edited.json' | Invoke-Expression
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
