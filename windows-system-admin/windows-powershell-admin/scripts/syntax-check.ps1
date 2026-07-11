<#
  syntax-check.ps1 - validate a .ps1 before handing it to the user.
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/syntax-check.ps1 -Path C:/tmp/target.ps1
  Prints "PARSE ERRORS:" + messages, or "SYNTAX OK".
#>
param([string]$Path)
$errs = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
if ($errs) {
    "PARSE ERRORS:"
    $errs | ForEach-Object { $_.Message }
} else {
    "SYNTAX OK"
}
