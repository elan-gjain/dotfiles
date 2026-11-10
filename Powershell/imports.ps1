$env:PATH += ";$HOME\bin"
$env:PATH += ";$HOME\.local\bin"

Import-Module posh-git -ErrorAction SilentlyContinue
Import-Module PSFzf -ErrorAction SilentlyContinue
