# Windows Local Network Inventory (single host, run from Node-1)

Verified recipe used 2026-07-10 for the `ZQM-NODE-1` inventory. Run from the bash
terminal tool. KEY LESSON: do NOT inline PowerShell that uses `$_`/`$env:` through
bash — bash expands those. Instead write a `.ps1` (file contents are untouched) and
run it with `-File`. See SKILL.md pitfall #20.

## Why a script file (not inline)
Inline `powershell -Command "...Where-Object { $_.InterfaceAlias }..."` from bash
yields `CommandNotFoundException` with token `/c/WINDOWS/system32.InterfaceAlias`
(bash expanded `$_`). Fix = `.ps1` + `-File`.

## Inventory script (write to C:\Users\zqmco\net_inv.ps1, run -File, then delete)

```powershell
Write-Output "=== HOSTNAME ==="
$env:COMPUTERNAME

Write-Output "`n=== IP ADDRESSES (v4/v6, non-loopback) ==="
Get-NetIPAddress | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
    Select-Object InterfaceAlias, AddressFamily, IPAddress, PrefixLength |
    Format-Table -AutoSize | Out-String -Width 220

Write-Output "=== ADAPTERS (MAC + link speed) ==="
Get-NetAdapter | Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed, Status |
    Format-Table -AutoSize | Out-String -Width 200

Write-Output "=== DEFAULT GATEWAY ==="
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object NextHop, InterfaceAlias |
    Format-Table -AutoSize | Out-String -Width 200

Write-Output "=== DNS ==="
Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, ServerAddresses |
    Format-Table -AutoSize | Out-String -Width 200

Write-Output "=== TCP STATE COUNTS ==="
Get-NetTCPConnection | Group-Object State | Select-Object Name, Count |
    Sort-Object Count -Descending | Format-Table -AutoSize | Out-String -Width 200

Write-Output "=== LISTENING TCP PORTS ==="
Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess |
    Sort-Object LocalPort | Format-Table -AutoSize | Out-String -Width 220

Write-Output "=== LISTENING UDP ==="
Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort | Sort-Object LocalPort |
    Format-Table -AutoSize | Out-String -Width 220

Write-Output "=== WI-FI SSID / link ==="
netsh wlan show interfaces | Select-String 'SSID|State|Signal|Radio|Channel|Receive rate|Transmit rate|Authentication'
```

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:/Users/zqmco/net_inv.ps1"`
(forward slashes dodge the bash backslash-strip from pitfall #6). Clean up after.

## Homelab subnet verdict (the user's standing question)
The host is "on 192.168.1.0/24" iff its operational IPv4 (Wi-Fi/Ethernet) AND default
gateway are both inside 192.168.1.0/24. This session: Wi-Fi=`192.168.1.218/24`,
gateway=`192.168.1.1` → YES on the homelab subnet. The only other routable IP was the
Hyper-V NAT `172.19.160.1/20` (internal vSwitch, not LAN). APIPA `169.254.x.x` =
interface down / no DHCP (ignore for subnet logic).

## Public IP probe (egress)
`curl -s -m 6 https://api.ipify.org` returned UNREACHABLE from the sandbox — WAN egress
is blocked from this inside-LAN vantage (consistent with SKILL.md "WAN side still
unreachable from the sandbox"). Don't claim a public IP; report UNREACHABLE.

## Notes
- `Get-NetTCPConnection -State Listen` already returns the rich table (LocalAddress/
  LocalPort/OwningProcess) — no need to join on `Get-Process`. Pid→service:
  `Get-Process -Id <pid> | Select-Object Name,Path`.
- TCP states seen this session: Listen 32, Bound 102, TimeWait 46, Established 40,
  CloseWait 2. (`Bound` = ephemeral socket bound to a port, normal on a busy host.)
- Notable LAN-exposed services on .218: 22 (SSH), 135/139/445 (RPC/NetBIOS/SMB),
  2179 (RDP-virt), 5985/5986 (WinRM), 11434 (Ollama, unauthenticated — see
  references/ollama-security-audit.md).
