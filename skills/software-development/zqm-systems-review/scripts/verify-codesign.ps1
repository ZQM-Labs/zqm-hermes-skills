param(
    [string]$Path,
    [string]$ExpectedThumbprint = 'D9C7C50808FD1FEB074D635DCC71111FB712F733',
    [string]$SubjectContains = 'Alex Zelenski'
)
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "VERIFICATION_FAILED"
    Write-Host "Missing: $Path"
    exit 1
}
$sig = Get-AuthenticodeSignature -LiteralPath $Path
$c = $sig.SignerCertificate
$ok = ($sig.Status -eq 'Valid') -and ($null -ne $c) -and ($c.Thumbprint -eq $ExpectedThumbprint) -and ($c.Subject.Contains($SubjectContains))
if (-not $ok) {
    Write-Host "VERIFICATION_FAILED"
    Write-Host "Status: $($sig.Status)"
    Write-Host "Thumbprint: $($c.Thumbprint)"
    Write-Host "Subject: $($c.Subject)"
    exit 1
}
Write-Host 'VERIFIED_OK'
Write-Host "Status: $($sig.Status)"
Write-Host "Thumbprint: $($c.Thumbprint)"
Write-Host "Subject: $($c.Subject)"
Write-Host "File: $Path"
