# zqm-bootstrap.ps1
# Run on a Windows workstation (Node-2 / Node-3 / Node-4) in ADMIN PowerShell.
# Enables PowerShell Remoting, sets the LAN adapter to Private, creates a
# local management admin account, and (optionally) opens the indexer port.
# After this runs, Node-1 can manage the box via:
#   $cred = Get-Credential   # .\zqmlocal + the password you set below
#   $s = New-PSSession -ComputerName <IP> -Port 5985 -Credential $cred

param(
    [string]$LocalUser = "zqmlocal",
    [int]$IndexerPort = 5000
)

$LocalPass = Read-Host -Prompt "Set password for local admin '$LocalUser' (use a NEW password, not your Gmail one)" -AsSecureString

# 1. Enable PowerShell Remoting + WinRM listeners + firewall exception
Enable-PSRemoting -Force

# 2. Classify the active LAN adapter as Private (so Private-scoped rules take effect)
Set-NetConnectionProfile -NetworkCategory Private

# 3. Create / reset the local management account and make it an admin
if (-not (Get-LocalUser -Name $LocalUser -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true -AccountNeverExpires
    Write-Host "Created local user $LocalUser"
} else {
    Set-LocalUser -Name $LocalUser -Password $LocalPass -PasswordNeverExpires:$true
    Write-Host "Reset password for existing $LocalUser"
}
Add-LocalGroupMember -Group "Administrators"          -Member $LocalUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Management Users" -Member $LocalUser -ErrorAction SilentlyContinue

# 4. (optional) Open the indexer port to the LAN subnet, Private profile only
New-NetFirewallRule -DisplayName "ZQM-Indexer-In-$IndexerPort" `
    -Direction Inbound -Protocol TCP -LocalPort $IndexerPort `
    -Action Allow -Profile Private -RemoteAddress 192.168.1.0/24 -ErrorAction SilentlyContinue

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' }).IPAddress -join ', '
Write-Host "Bootstrap complete on $env:COMPUTERNAME ($ip)"
