# bootstrap.ps1 — run ON a TARGET node (Node-2/3/4), Admin PowerShell.
# One-shot: enable WinRM remoting, set adapter Private, create a local admin
# for LAN management, and (optionally) open the indexer port to the subnet.
# Use the SAME `zqmlocal` password on every node so the fleet script can use
# one `.\zqmlocal` credential for all three.

$LocalUser = "zqmlocal"
$LocalPass = Read-Host -Prompt "Set password for local admin '$LocalUser' (use a NEW password, NOT your Microsoft/email password)" -AsSecureString

# 1. Enable PowerShell Remoting + WinRM listeners + firewall exception
Enable-PSRemoting -Force

# 2. Classify the active LAN adapter as Private (required for Private-scoped rules)
Set-NetConnectionProfile -NetworkCategory Private

# 3. Create / reset the local admin account used for remoting
$acct = Get-LocalUser -Name $LocalUser -ErrorAction SilentlyContinue
if (-not $acct) {
    New-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true -AccountNeverExpires
    Write-Host "Created local user $LocalUser"
} else {
    Set-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true
    Write-Host "Reset password for existing $LocalUser"
}
Add-LocalGroupMember -Group "Administrators" -Member $LocalUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member $LocalUser -ErrorAction SilentlyContinue

# 4. (optional) Open the indexer service port to the LAN subnet only
New-NetFirewallRule -DisplayName "ZQM-Indexer-In-5000" -Direction Inbound -Protocol TCP `
    -LocalPort 5000 -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue

Write-Host ("Bootstrap complete on {0} ({1})" -f $env:COMPUTERNAME, `
    ((Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -notmatch Loopback).IPAddress -join ", "))
