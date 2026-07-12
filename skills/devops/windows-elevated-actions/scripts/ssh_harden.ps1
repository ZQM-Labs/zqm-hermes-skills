# ssh_harden.ps1 — SELF-CONTAINED sshd PasswordAuthentication=no hardening (lockout-guarded).
# Run ELEVATED (Start-Process -Verb RunAs). Self-logs to the path below.
# Lesson P2 (2026-07-11): do NOT depend on a pre-written user-only-ACL authorized_keys being
# readable from the elevated context — this script writes the key itself with a permissive ACL.
param(
  $log = "C:\Users\zqmco\swarm\ssh_harden.log"
)
function out($s){ Add-Content -Path $log -Value $s }
out ("=== ssh_harden started " + (Get-Date) + " ===")

$sshDir  = "C:\Users\zqmco\.ssh"
$pub     = Join-Path $sshDir "id_ed25519.pub"
$ak      = Join-Path $sshDir "authorized_keys"
$dropdir = "C:\ProgramData\ssh\sshd_config.d"
$drop    = Join-Path $dropdir "99-zqm-hardening.conf"

# ---- 1. Ensure authorized_keys has the user's pubkey (self-contained) ----
try {
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Force -Path $sshDir | Out-Null }
    $keyLine = (Get-Content $pub -ErrorAction Stop) | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
    if (-not (Test-Path $ak)) {
        Set-Content -Path $ak -Value $keyLine -Encoding ASCII -ErrorAction Stop
        out ("    created authorized_keys with pubkey")
    } else {
        $existing = Get-Content $ak -ErrorAction SilentlyContinue
        if (-not ($existing -contains $keyLine)) {
            Add-Content -Path $ak -Value $keyLine -Encoding ASCII -ErrorAction Stop
            out ("    appended pubkey to authorized_keys")
        } else { out ("    authorized_keys already has pubkey") }
    }
    # Permissive ACL so the elevated read (and sshd service account) can read it.
    $acl = Get-Acl $ak
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERDOMAIN\$env:USERNAME","FullControl","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
    Set-Acl $ak $acl
    out ("    ACL set (user+SYSTEM+Admin)")
} catch {
    out ("    KEY INSTALL FAILED: " + $_.Exception.Message)
    out "    ABORT: cannot safely harden without a verified key"
    out ("=== finished " + (Get-Date) + " ==="); exit 1
}

# ---- 2. Write hardening drop-in + restart sshd ----
try {
    if (-not (Test-Path $dropdir)) { New-Item -ItemType Directory -Force -Path $dropdir | Out-Null }
    @"
# ZQM hardening $(Get-Date -Format yyyy-MM-dd)
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
"@ | Set-Content -Path $drop -Encoding ASCII
    out ("    OK: wrote " + $drop)
    Restart-Service -Name sshd -Force -ErrorAction Stop
    out "    OK: restarted sshd"
} catch {
    out ("    SSHD HARDEN FAILED: " + $_.Exception.Message)
}
out ("=== ssh_harden finished " + (Get-Date) + " ===")
