<#
  check-syntax.ps1  -  validates a PowerShell script with the language parser.
  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File check-syntax.ps1
  Then edit the $target line below, or call with the path as an argument.
#>
param([string]$target = '')
if (-not $target) {
    # default: validate the whole skills script folder
    $dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $files = Get-ChildItem -Path $dir -Filter *.ps1 -ErrorAction SilentlyContinue
} else {
    $files = @([System.IO.Path]::Combine('C:\tmp', $target))
}
foreach ($f in $files) {
    $path = if ($f -is [string]) { $f } else { $f.FullName }
    if (-not (Test-Path $path)) { Write-Host ("SKIP (not found): " + $path); continue }
    $errs = $null; $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    if ($errs) {
        Write-Host ("PARSE ERRORS in " + $path + " :")
        $errs | ForEach-Object { Write-Host ("  " + $_.Message) }
    } else {
        Write-Host ("SYNTAX OK: " + $path)
    }
}
