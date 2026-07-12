# ZQM LAN Topology (verified 2026-07-10 via live ICMP + TCP probe)

## Windows nodes
| Name    | IP             | DNS               | State (2026-07-10)                          |
|---------|----------------|-------------------|---------------------------------------------|
| Node-1  | 192.168.1.218  | ZQM-Node-1.lan    | Hermes agent host; 445/5000/5985 OPEN       |
| Node-2  | 192.168.1.21   | ZQM-Node-2.lan    | 445/5985 OPEN; 5000 CLOSED; remoting OK     |
| Node-3  | 192.168.1.46   | ZQM-Node-3.lan    | 445 OPEN; 5985 CLOSED (bootstrap pending)   |
| Node-4  | 192.168.1.215  | ZQM-Node-4.lan    | 445 OPEN; 5985 CLOSED (bootstrap pending)   |

NOTE: IPs are NON-sequential. Do not guess .21/.22/.23/.24 — resolve `<name>.lan` and probe.

## ZQM-Gardens (Synology NAS)
| Name      | IP(s)                  | DSM (5000/5001) | SMB write from Node-1        |
|-----------|------------------------|-----------------|-------------------------------|
| Garden-01 | 192.168.1.173          | OPEN            | denied (no cached cred)       |
| Garden-02 | 192.168.1.40           | OPEN            | WRITE-OK (cached SMB session)|
| Garden-03 | 192.168.1.64           | OPEN            | denied                        |
| Garden-04 | 192.168.1.144 / .147   | CLOSED          | denied                        |

All Gardens: SSH(22)/HTTP(80)/HTTPS(443)/NFS(111,2049) OPEN; SNMP(161) CLOSED on all.
Garden-02 `web` share is the reliable drop point for scripts shared across the LAN.
