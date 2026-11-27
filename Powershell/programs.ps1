$programsDirectory = "$HOME\Documents\GitHub\dotfiles\Powershell\Programs"

foreach ($programFile in (Get-ChildItem -LiteralPath $programsDirectory -Filter '*.ps1' -File | Sort-Object -Property Name)) {
    . $programFile.FullName
}
