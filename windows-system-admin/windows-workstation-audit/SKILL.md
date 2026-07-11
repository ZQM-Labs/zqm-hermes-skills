---
name: windows-workstation-audit
description: >
  Audit a Windows workstation (hardware, BIOS/firmware, Secure Boot, TPM,
  BitLocker, disks/SMART, RAM XMP/DOCP, Intel VT-x virtualization) and generate
  prompt-gated, syntax-validated PowerShell remediation scripts. Includes scripts
  to read everything via WMI/CIM (no install needed) and to enable XMP or
  virtualization from a single BIOS reboot. Use when auditing a Dell/Windows PC,
  enabling XMP/DOCP memory profile, checking or enabling VT-x / Hyper-V / WSL2 /
  Docker support, or when `wmic` fails and you must fall back to PowerShell CIM.
triggers:
  - audit a Windows workstation / Dell XPS / this PC
  - enable XMP / DOCP / memory profile / RAM running below rated speed
  - check or enable Intel VT-x / virtualization / Hyper-V / WSL2 / Docker
  - wmic not recognized / exit 127 on Windows
  - BitLocker protection off / resume BitLocker / back up recovery keys
  - Secure Boot / TPM status read denied (non-admin)
  - "crypto or wallet or blockchain storage discovery on this machine -> hand off to crypto-asset-forensics"
---

# Windows Workstation Audit + Remediation

A reusable flow for fully auditing a Windows box and fixing the two most common
BIOS-level oversights (XMP off, VT-x off) with one reboot, plus safe BitLocker
handling. All scripts are read-only or strictly prompt-gated (Y/N before any
mutation). They run from an ELEVATED PowerShell (`Run as Administrator`).

## CRITICAL PITFALLS (learned the hard way — follow these)

1. **`wmic` is broken on this host** (exit 127 "not recognized"). Use PowerShell
   CIM instead: `Get-CimInstance Win32_Processor`, `Win32_ComputerSystem`,
   `Win32_PhysicalMemory`, `Win32_BIOS`, `Get-PhysicalDisk`, `Get-Tpm`,
   `Confirm-SecureBootUEFI`.

2. **Bash (MSYS2) MANGLES PowerShell.** The agent's terminal is `bash`, not
   PowerShell. Piping PowerShell through bash corrupts:
   - `$_.Size`, `$_.Name`, `$_`, `$null` → eaten/garbled
   - em-dashes `—` → break the PowerShell parser
   - `2>nul` → `nul` gets split
   **RULE: never run multi-line or `$_`-heavy PowerShell inline in a terminal
   command. ALWAYS write the `.ps1` to a file with `write_file`, then run it with
   `powershell -NoProfile -ExecutionPolicy Bypass -File C:/tmp/x.ps1`.**

3. **Non-admin shell blocks privileged reads.** `Confirm-SecureBootUEFI`,
   `Get-Tpm` detail, and raw SMART reliability counters return "Access denied" /
   blank unless elevated. The scripts self-check elevation and exit cleanly.

4. **XMP CANNOT be enabled without a reboot.** The DRAM is trained by the memory
   controller at POST; Windows cannot re-clock live memory. Any "enable XMP" flow
   ends in exactly one reboot. No software-only shortcut exists.

5. **XMP rated speed ≠ SPD Speed field.** `Win32_PhysicalMemory.Speed` reports the
   DIMM's BASE jedec profile (e.g. 4800), NOT its XMP rating. The real rated speed
   is in the PART NUMBER — `F5-5200...` → 5200 MT/s. So "Configured 4800 vs SPD
   4800" does NOT mean XMP is on. Compare ConfiguredClockSpeed against the part
   number's embedded speed. (See `eval-workstation.ps1` XMP logic.)

6. **Dell `cctk` cannot be auto-downloaded.** The driver page returns "no longer
   available" and `dl.dell.com` + the drivers API return 403 to non-browser
   clients. scoop has NO `dell-command-configure` manifest. winget/choco absent.
   The user must install Command | Configure manually from a real browser. After
   that, `enable-xmp.ps1` auto-detects the manual install.

7. **Validate syntax before handing a script to the user.** Write a check `.ps1`
   that calls `[System.Management.Automation.Language.Parser]::ParseFile($f,
   [ref]$tokens, [ref]$errs)` and reports errors. Use `[System.IO.Path]::Combine`
   to build the path inside the check script — an unquoted `C:` in a string
   triggers a "Variable reference is not valid" parser error in the check itself.

8. **BitLocker "FullyEncrypted" + "Protection=Off"** means the volume is encrypted
   but the key protector is suspended → opens without the key. Fix: back up
   recovery keys FIRST, then `manage-bde -protectors -enable <drv>`. Use
   `manage-bde.exe` (always present), NOT the BitLocker PS module (often missing).

9. **`VirtualizationFirmwareEnabled=False` is a FALSE NEGATIVE on Windows 11 24H2
   when VBS/HVCI (Memory Integrity) is running.** VBS loads a hypervisor at boot
   and consumes the VMX bit, so `Win32_Processor.VirtualizationFirmwareEnabled`
   reads False even though VT-x is ON in firmware. PROOF that VT-x is really on:
   DeviceGuard `SecurityServicesRunning=2` (VBS running) + HVCI
   `HKLM:\...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity Enabled=1`
   (Memory Integrity ON). VBS/HVCI CANNOT run without VT-x+SLAT. So before
   concluding "VT-x off → reboot to F2," check VBS state. If VBS is Running OR
   `systeminfo` shows "A hypervisor has been detected," VT-x is ON and the eval
   flag is lying. Do NOT hand the user a BIOS-enable step in that case. (Seen on
   ZQM-NODE-4: fresh 24H2 install, VBS+Memory Integrity on by default, eval
   reported VirtualizationFirmwareEnabled=False → corrected.)
   no Windows tool can flip them.

   10. **netsh `show rule name=` matches DISPLAY NAME, not the rule Name/InstanceID.**
       `Get-NetFirewallRule` returns the rule *Name* (e.g. `OpenSSH-Server-In-TCP`),
       but `netsh advfirewall firewall show rule name="OpenSSH-Server-In-TCP"` returns
       "No rules match" because netsh keys on the *display* name (`OpenSSH SSH Server
       (sshd)`). A "no match" from netsh is a NAME-MISMATCH ARTIFACT, NOT proof the rule
       is absent. SECOND-PATH RULE: when Get-NetFirewallRule says a rule exists, confirm
       with netsh using the CORRECT display name (pull DisplayName from
       `Get-NetFirewallRule -Name <name> | Select DisplayName`). On ZQM-NODE-4 this exact
       mistake briefly made me wrongly doubt a confirmed firewall-Any finding; the
       third-path netsh check with the right display name re-confirmed it.

   11. **Security-log retention is often ~1 day on busy nodes** — a "last 7d" query may
       only span 1 day. Do NOT compute a "growth rate / day" from a 1-day span; report
       actual per-day buckets and flag the retention limit. For a real multi-week curve,
       pull a peer node that retains longer or stand up the sysintel 30m cron. (Seen on
       ZQM-NODE-4: 27,396 records, oldest 7/10 newest 7/11 -> 136 fails were really
       122 build-day + 14 next-day, decaying, not a steady 19.4/day.)

   12. **Most "admin-gated" data is actually reachable NON-ELEVATED — don't punt
      to the user too early.** A non-admin shell blocks SOME cmdlets
      (`Confirm-SecureBootUEFI`, `Get-Tpm`, `manage-bde -status`,
      `Get-StorageReliabilityCounter`/SMART, `bcdedit`) but a different path gets
      the same facts without elevation:
        - Secure Boot : `HKLM:\...\Control\SecureBoot\State` `UEFISecureBootEnabled` (reg)
        - TPM 2.0 health/spec/PCR7 : `tpmtool getdeviceinformation` (full output, non-elev)
        - VBS/HVCI : `HKLM:\...\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity` `Enabled`
        - OS-disk proof : `Get-Partition` -> `IsBoot=True` on a disk = C: lives there (no bcdedit)
        - Open ports + owner : `Get-NetTCPConnection -State Listen`
        - GPU / pending updates : `Win32_VideoController` / Microsoft.Update.Session COM
      See `references/non-elevated-probes.md` for copy-paste snippets. Only TRUE
      admin-gates (SMART wear, BitLocker keys, bcdedit text) need an elevated re-run.

   10. **ESP is OFTEN ALREADY MOUNTED at X: on Win11 24H2** (and `boot-forensics.ps1`'s
      old `Set-Partition -NewDriveLetter X` will FAIL because X: is taken). Detect the
      ESP by GPT type `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` and reuse its existing
      drive letter if already mounted; only assign a fresh letter (Y:/Z:/W:) if none.
      On ZQM-NODE-4 the ESP was already X: and the naive script needed this fix.
   reboots, would be suspicious -> escalate.

   13. **When a privileged read is DENIED, find the UNPRIVILEGED event that proves the same
   fact — don't stop at "blocked."** This is the blindspot discipline from the
   zqm-attestation-toolkit: a denied `Get-Tpm` / CIM `Win32_Tpm` (CimException Access
   denied) does NOT mean "can't verify" — the TPM-WMI provider logs attestation to the
   System event log READABLE unelevated. Event 1041 (HealthStatus=Attestable) proves the
   TPM is present & attesting; Event 519 (TPM clear) is a notable event that must be
   characterized (S-1-5-18 + "SRK Pub not present" at a build timestamp = benign
   auto-reprovision, NOT an incident). On ZQM-NODE-4 this pattern closed finding [4]
   ("TPM blocked non-admin") to "TPM CONFIRMED present & attestable via Event 1041."
   Always wrap privileged checks in an exception-typing `Probe` wrapper so the denial
   class is recorded exactly. See `references/non-elevated-probes.md` (TPM event section)
   and `scripts/tpm-blindspot.ps1`.
   ## SCRIPTS (in scripts/)

- `eval-workstation.ps1` — READ-ONLY full eval via WMI/CIM + bcdedit. No install.
  Covers BIOS identity, boot config, Secure Boot, TPM, virtualization, RAM XMP gap,
  disks/SMART, BitLocker, power plan, network/remote services, Windows features, OS.
- `admin-audit.ps1` — elevated read-only: Secure Boot, TPM, BitLocker, SMART, XMP.
- `enable-xmp.ps1` — prompt-gated: finds/locates cctk (or manual), auto-detects the
  memory-profile attribute name, sets XMP Profile 1, Y/N-gated single reboot.
- `fix-audit.ps1` — prompt-gated remediation: back up BL recovery keys, resume F:/D:
  protection, optional sshd/WinRM lockdown. Never changes anything without Y.
- `backup-bl-keys.ps1` — exports recovery keys via `Win32_EncryptableVolume`
  (the correct way; the `manage-bde -protectors -get -path` approach silently fails
  when no protector exists).
- `check-syntax.ps1` — validates any `.ps1` with the PowerShell parser.
- `boot-forensics.ps1` — READ-ONLY boot-chain: disk bus-type, C:→disk map, BCD
  boot device, ESP .efi inventory, VT-x/RAM result from CIM. Proves OS-on-SATA.
  NOTE: detects an ESP already mounted (e.g. at X:) instead of blindly reassigning
  X: (which fails) — see pitfall #10.
- `tpm-blindspot.ps1` — non-elevated TPM verification: when Get-Tpm/CIM Win32_Tpm
  are denied, proves TPM presence via unprivileged TPM-WMI Event 1041, and
  characterizes any 519 (clear) event. READ-ONLY (pitfall #13).
- `repair-wsl.ps1` — ELEVATED, Y/N-gated: regsvr32 msi.dll (fixes REGDB_E_CLASSNOTREG), optional DISM.
- `plan-os-migration.ps1` — READ-ONLY OS→NVMe migration assessment + safe steps (no clone).

## REFERENCES (in references/)
- `vbs-vtx-false-negative.md` — why `VirtualizationFirmwareEnabled=False` lies on
  VBS/HVCI boxes, the proof recipe (DeviceGuard SecurityServicesRunning=2, HVCI
  Enabled=1, systeminfo hypervisor), and how the eval now self-corrects.
- `non-elevated-probes.md` — copy-paste snippets for every non-Admin CIM/registry/CLI
  read (Secure Boot, TPM via tpmtool, VBS, OS-disk partition map, listening ports,
  GPU, pending updates) + the curl exposure-proof recipes. Use these BEFORE asking
  the user to elevate.
- `evidence-anchoring.md` — the "hash claims" deliverable: SHA256-anchor every
  artifact (Get-FileHash is ABSENT here -> use .NET SHA256), the 2nd-path
  verification matrix (CONFIRMED/CORROBORATED/BLOCKED), and the growth-rate
  append-only TSV baseline. Use on every audit the user wants proved.

## TYPICAL FLOW

1. For privileged reads (Secure Boot / TPM / BitLocker / SMART / BCD / HVCI), PREFER the
   **windows-sysintel** elevated broker over keeping an elevated shell open: the
   pre-registered `sysintel-priv` scheduled task pulls all of it into
   `sysintel/out/{priv,deeper,forensic,perftune}.json` via `bash pull_priv.sh` (no manual
   Admin re-run, no UAC prompt). `eval-workstation.ps1` still works but requires you to
   hold an elevated PowerShell the whole session. If `pull_priv.sh` hangs, the broker task
   is wedged on an elevated orphan — see the sysintel-toolkit "ELEVATED-ORPHAN refinement"
   (schtasks /end, not taskkill).
2. Findings usually: XMP off (RAM below rated), VT-x off (VirtualizationFirmwareEnabled=False),
   sshd/WinRM running, OS on reused/slow disk.
3. To fix XMP + virtualization: one reboot → F2 → Performance → Memory → XMP Profile 1,
   AND Performance/Virtualization → enable Intel VT-x (+ VT-d) → F10.
4. After reboot verify (CAUTION: on VBS/HVCI-enabled boxes
   `VirtualizationFirmwareEnabled` reads False even when VT-x is ON in firmware —
   see pitfall #9. Do NOT trust that flag alone; confirm with the DeviceGuard
   truth-check instead):
   # VBS running (2) proves VT-x+SLAT are on:
   `(Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard).SecurityServicesRunning` → expect 2
   `(Get-CimInstance Win32_PhysicalMemory|Select -First 1).ConfiguredClockSpeed` → expect 5200
5. For BitLocker: run `fix-audit.ps1` (backs up keys, resumes protection, Y/N per step).

## CRYPTO / WALLET DISCOVERY (sub-branch of "learn more about this workstation")
If an audit surfaces blockchain dirs (Chia/XMR/ZMR/custom), wallet keystores, or
plot/chain storage (e.g. F:\CHIA_FARM, F:\XMRBlockStorage, F:\ZMRStash), DO NOT
treat them as a hardware finding — hand off to the **crypto-wallet-forensics** skill (security/crypto-wallet-forensics).
That skill covers: read-only discovery, structurally probing a keystore format WITHOUT
a password (M1–M10), exposure rating (file ACL + volume auto-unlock + LAN + session
leak), the recovery-by-sweep runbook, and hunting a forgotten AI-generated passphrase.
Key safety rules it enforces (do not violate here): never decrypt a keystore ON the
exposed box, never accept the passphrase into the agent session, and never value crypto
from storage artifacts (plots/chain-copies are $0; only a real balance × price counts).

## NOTE ON VIRTUALIZATION
VT-x off kills Hyper-V / WSL2 / Docker / Android Emulator / any VM. Enable it.
Caveat: VirtualBox (Type-2) conflicts with Hyper-V — if the user wants VirtualBox,
they need Hyper-V OFF / "Windows Hypervisor Platform" instead. For WSL2/Docker/
Hyper-V, leave VT-x ON.

## BE ACTIVE — PROVE IT, DON'T JUST CITE IT
The audit's value is a real, evidence-backed picture — not a printed script verdict
plus a "please run this elevated" handoff. Before asking the user to elevate:
1. **Run every non-elevated probe you can** (pitfall #11) — CIM/registry/CLI.
2. **Empirically verify exposure with `curl` from bash** — citing a listening port
   is weaker than exercising the service. On ZQM-NODE-4:
     - `curl -s http://127.0.0.1:11434/api/tags` returned the Ollama model list WITH
       NO AUTH -> proves LAN-exposed, unauthenticated inference (not just "port open").
     - `curl -s -i http://127.0.0.1:5985/wsman` -> `HTTP/1.1 405` -> proves WinRM live
       and reachable.
3. **Drive the desktop** with `computer_use` (capture/som) to confirm GUI state
   (Task Manager, running apps). Use it for genuinely visual state; CIM already gives
   more precise process/port data, so don't waste a desktop probe where CIM suffices.
4. **Only THEN** hand the user a Y/N-gated elevated script for the truly admin-gated
   fields (SMART wear, BitLocker keys, bcdedit). This is the "utilize your tools
   better" correction: be active, not passive.

## BOOT-CHAIN FORENSICS (esp. "is the OS on the slow disk?" / binary inspection)
When the user asks to "investigate the binaries" or confirm where Windows boots
from, do this read-only chain (elevated PowerShell):

1. **Disk/bus topology** — `Get-Disk` + `Get-Partition` shows `BusType` (SATA vs
   NVMe) and which partition holds C:. If `IsBoot=True` on a SATA disk while a fast
   NVMe sits idle, the OS is on the slow disk. (On ZQM-NODE-4: Disk0=SATA 870 QVO
   holds C:; Disk1=9100 PRO NVMe is data-only F:.)
2. **ESP .efi inventory** — find the ESP by GPT type `c12a7328-f81f-11d2-ba4b-
   00a0c93ec93b` (NOT by assuming Disk0/part1, and NEVER blindly `Set-Partition
   -NewDriveLetter X` — on 24H2 the ESP is often ALREADY mounted at X:, which makes
   that fail). Reuse the existing letter; only assign a fresh one (Y:/Z:/W:) if none.
   Then list `*.efi`. Expect:
   `EFI\Boot\bootx64.efi` (fallback), `EFI\Microsoft\Boot\bootmgfw.efi` (Windows
   Boot Manager), `bootmgr.efi`, `BCD` (49 KB store), `memtest.efi`.
   **Dell adds its own layers:** `EFI\dell\SOS\*` (Support OS / Safe OS recovery
   with its own bootmgfw + BCD) and `EFI\PEBoot\*` (Dell preboot PE for firmware
   updates). These are normal, not malware.
3. **BCD boot device** — `bcdedit /enum '{current}'` shows `device=partition=C:`
   and `osdevice=partition=C:`. That is the definitive proof of which disk/volume
   Windows actually loads from. `bcdedit /enum firmware` lists the fwbootmgr
   order (Windows Boot Manager first, then NIC PXE/HTTP entries).
4. **XMP/VT-x decision bytes are UNREADABLE from Windows.** They live in the Dell
   `Setup` UEFI NVRAM variable (SPI flash). All three read attempts fail from
   userland: cctk absent (Dell CDN 403), WMI `root\dcim\sysman\biosattributes`
   empty, kernel32 `GetFirmwareEnvironmentVariable(Ex)` returns 0 (needs
   SeSystemEnvironmentPrivilege / ring-0). **Conclusion: the settings are only
   changeable via F2 BIOS Setup or cctk — not by any Windows tool.** Inspection
   can only confirm the *result* (VT-x=False via CIM, RAM 4800 via CIM), never
   the raw NVRAM bytes. Do not claim a Windows tool can flip them.
5. **WSL corruption** — `wsl --status` / `wsl -l -v` returning
   `REGDB_E_CLASSNOTREG` (Wsl/CallMsi/Install) means WSL's MSI COM class is
   unregistered; any `bash`/`.sh` relying on WSL fails. Repair (user to run, not
   auto): `regsvr32 /s msi.dll` first (re-registers the class), or
   `dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux
   /all /norestart`, or `wsl --install`. This blocked the sysintel `monitor.sh`.

## EVIDENCE ANCHORING (the "hash claims" deliverable)

This user explicitly asks to "hash claims" — they want every investigation's
evidence SHA256-anchored and independently re-verified, not taken on the
report's word. Make it a standard deliverable:

1. **Hash the artifacts.** After producing probe/script `.out` files, emit
   SHA256 of each. NOTE: `Get-FileHash` is ABSENT on this host's PS 5.1 build
   (CommandNotFoundException) — use the .NET recipe (see `windows-powershell-admin`
   pitfall, and `references/evidence-anchoring.md`):
   ```powershell
   $b=[System.IO.File]::ReadAllBytes($f); $h=[System.Security.Cryptography.SHA256]::Create().ComputeHash($b)
   ($h|ForEach-Object{$_.ToString('x2')})-join''
   ```
2. **2nd-path verification matrix.** For each material claim, run an INDEPENDENT
   method and label CONFIRMED / CORROBORATED(single-source) / BLOCKED(admin).
   Be honest about admin-gated blind spots: TPM CIM (`Win32_Tpm`) and WinRM
   WSMan (`WSMan:\localhost\Listener`) are GENUINELY non-admin BLOCKED on this
   host — the netstat/curl proof still stands, so cite that instead of claiming
   "verified via CIM."
3. **Growth-rate baselines.** When the user asks about disk "growth rates", don't
   invent a curve. Snapshot sizes into an APPEND-ONLY TSV
   (`growth-baseline.tsv`: TIMESTAMP, UsersGB, OllamaModelsGB, C/D/FfreeGB) and
   tell them to re-run in 1–4 weeks for a real GB/day slope. The dominant
   consumer on ZQM-NODE-4 is `~/.ollama/models` (420 GB = 98.6% of C:\Users) —
   that IS the disk footprint; logs/pagefile/hiberfil are essentially fixed.

## OLLAMA FIREWALL RULE — KNOWN ORIGIN (don't self-blame)

The loose `ollama.exe / Port=Any / Remote=Any` inbound rule is the **Ollama
installer's default** (Get-NetFirewallRule Owner = `(none/installer)`), NOT
created by any of our scripts (grep: no `New-NetFirewallRule` in C:\tmp). When
you run `harden-ollama.ps1`, setting `OLLAMA_HOST=127.0.0.1` makes the listener
loopback-only so the rule becomes moot — BUT the rule is still sloppy. Add a
step that removes it (`Remove-NetFirewallRule -DisplayName 'ollama.exe'`) so the
hardening is complete. (Flagged 2026-07-11, not yet patched into harden-ollama.ps1.)

## ACTION PACKAGE (user says "proceed" — all gated, none auto-run from agent)
The agent cannot execute these (non-admin shell / firmware / disk-clone risk), so
prepare elevated, Y/N-gated scripts and hand them over:
- **WSL repair** — `repair-wsl.ps1` (regsvr32 msi.dll, optional DISM).
- **Ollama LAN** — `harden-ollama.ps1` (see ollama-local-models skill).
- **XMP + VT-x** — F2 only (no script): reboot → F2 → Performance → Memory → XMP
  Profile 1, AND Performance/Virtualization → Intel VT-x (+VT-d) → F10.
- **OS→NVMe migration** — `plan-os-migration.ps1` (READ-ONLY plan; do NOT auto-
  clone a live boot disk). Real clone needs a bootable USB tool (Macrium/Hasleo/
  AOMEI): back up → free space on NVMe → clone ESP+MSR+C: → set NVMe boot → verify.
  The BCD on the NVMe ESP gets recreated during clone.
