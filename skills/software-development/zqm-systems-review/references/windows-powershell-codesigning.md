# Windows PowerShell Code Signing Reference

## Identity used on this host

- CN: `Alex Zelenski, GISP`
- Email: `zqmcomputing@gmail.com`
- Certificate thumbprint: `D9C7C50808FD1FEB074D635DCC71111FB712F733`
- EKU: Code Signing
- Store path: `Cert:\CurrentUser\My`
- Trust stores: `TrustedPublisher`, `Root`
- Algorithm preferred on PowerShell: `SHA256`

## Signing a script or artifact

```powershell
Set-AuthenticodeSignature `
  -FilePath 'C:\Users\zqmco\wiki\entities\zqm-prime-research.ps1' `
  -Certificate (Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq 'D9C7C50808FD1FEB074D635DCC71111FB712F733' }) `
  -HashAlgorithm SHA256
```

## Immediate verification

```powershell
$sig = Get-AuthenticodeSignature -FilePath 'C:\Users\zqmco\wiki\entities\zqm-prime-research.ps1'
$sig.Status
$sig.SignerCertificate.Thumbprint
$sig.SignerCertificate.Subject
$sig.SignatureAlgorithm.FriendlyName
```

Pass criteria:
- `Status` is `Valid`
- `Thumbprint` matches `D9C7C50808FD1FEB074D635DCC71111FB712F733`
- `Subject` is `CN="Alex Zelenski\," GISP, E=zqmcomputing@gmail.com`

## Failure modes to report explicitly

- Certificate missing from `CurrentUser\My`
- Certificate expired
- `Set-AuthenticodeSignature` returns `UnknownError`, `NotSigned`, or `Deny`
- Verification returns a different thumbprint or `Invalid` status

## Re-signing policy on this host

- Do not re-sign a file that already verifies correctly.
- When signing multiple files, verify each file immediately after signing before moving to the next.
- Treat signing as a write+verify atomic pair; report blockers explicitly.

## Ad-hoc verification script pattern for edited files

Create a temp script with `tempfile.mkstemp(prefix='hermes-verify-', suffix='.ps1')`, run it via `powershell -NoProfile -ExecutionPolicy Bypass -File <temp>`, capture stdout, then delete the temp file. Do not leave permanent duplicate verify wrappers in the tree.
