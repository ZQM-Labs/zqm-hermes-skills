# Evidence Anchoring — "hash claims" workflow (ZQM-NODE-4, 2026-07-11)

This user wants audit/investigation output SHA256-anchored and independently
re-verified, not taken on a single script's verdict. This reference collects
the reusable pieces.

## 1. SHA256 a file (Get-FileHash is ABSENT on this host)

```powershell
$b = [System.IO.File]::ReadAllBytes('C:\tmp\verify-claims.out')
$h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($b)
($h | ForEach-Object { $_.ToString('x2') }) -join ''
```
Hash EVERY artifact you produce (probeN.out, verify*.out, baseline TSV). Print
the hex so the user has a tamper-evident anchor they can re-check later.

## 2. 2nd-path verification matrix (label each claim)

| # | Claim | 2nd independent path | Verdict |
|---|-------|----------------------|---------|
| 1 | OS boots off SLOW SATA C: | WMI C:->Partition->Disk association (not Get-Partition loop) | CONFIRMED |
| 2 | Ollama LAN-exposed, no auth | Invoke-RestMethod -> 192.168.1.215:11434 -> 45 models | CONFIRMED |
| 3 | Secure Boot ON | HKLM registry UEFISecureBootEnabled=1 | CORROBORATED (single source; Confirm-SecureBootUEFI needs Admin) |
| 4 | TPM 2.0 healthy | CIM Win32_Tpm = BLOCKED non-admin | BLOCKED (use `tpmtool getdeviceinformation` CLI non-elev instead) |
| 5 | VT-x functional (VBS masks flag) | HypervisorPresent=True + VBS/HVCI reg=1 | CORROBORATED |
| 6 | WinRM 5985 open to Any | WSMan:\localhost\Listener = BLOCKED non-admin | BLOCKED (netstat :::5985 Listen from probe stands) |
| 7 | SSH LAN-scoped /24 | sshd_config ListenAddress unset; ZQM-OpenSSH-22 /24 rule | CONFIRMED |
| 8 | WSL HUNG | bounded wsl -l -v -> no return in 6s (REGDB_E_CLASSNOTREG) | CONFIRMED |
| 9 | XMP OFF 4800 vs 5200 | Win32_PhysicalMemory ConfiguredClockSpeed=4800 | CORROBORATED (single source) |
| 10 | Remote Assistance Any/Any open | Get-NetFirewallRule 'RA Server TCP-In' Enabled=True | CONFIRMED |
| 11 | McAfee+Defender "conflict" | Defender AntivirusEnabled=False while McAfee active = EXPECTED, retracted | RETRACTED |

Honesty rule: BLOCKED = say so; don't substitute a memory note for a live 2nd
path. CORROBORATED(single-source) = name the missing 2nd path.

## 3. Growth-rate baseline (append-only TSV)

Don't invent a GB/day curve — you need 2+ samples. Snapshot into a TSV and
re-run later:

```powershell
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm'
$users = [math]::Round((Get-ChildItem $env:USERPROFILE -Recurse -File -EA 0 | Measure Length -Sum).Sum/1GB, 2)
$om = Join-Path $env:USERPROFILE '.ollama\models'
$omGB = if (Test-Path $om) { [math]::Round((Get-ChildItem $om -Recurse -File -EA 0 | Measure Length -Sum).Sum/1GB, 2) } else { $null }
$free = @{}; Get-Volume | ?{$_.DriveLetter} | %{ $free["$($_.DriveLetter)"] = [math]::Round($_.SizeRemaining/1GB,1) }
$log = 'C:\tmp\growth-baseline.tsv'
if (-not (Test-Path $log)) { "TIMESTAMP`tUsersGB`tOllamaModelsGB`tCfreeGB`tDfreeGB`tFfreeGB" | Set-Content $log -Enc UTF8 }
"$ts`t$users`t$omGB`t$($free['C'])t$($free['D'])t$($free['F'])" | Add-Content $log -Enc UTF8
```
Rate = (UsersGB@N - UsersGB@1) / days. On ZQM-NODE-4, C:\Users=426GB of which
~420GB is `~/.ollama/models` — the model library IS the disk footprint. Moving
`.ollama` to the NVMe (F:) belongs in the OS->NVMe migration plan for load speed.

## 4. Ollama firewall rule origin

`Get-NetFirewallRule -DisplayName 'ollama.exe'` -> Owner = `(none/installer)`.
It is the Ollama installer's default rule, NOT created by our scripts. After
`harden-ollama.ps1` sets OLLAMA_HOST=127.0.0.1 the listener is loopback-only so
the rule is moot — but add `Remove-NetFirewallRule -DisplayName 'ollama.exe'`
to the harden script for completeness.
