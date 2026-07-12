# robust_probe.py — reusable live-probe helpers for the hash-claims recreation tier.
# Copy into any claim-verification script. Bytes-consistent (no bytes/str crash);
# distinguishes service-down from node-off. Fixes the bug that crashed fleet
# diagnostics.py at the first closed port (N2:6379), so it never scanned N2/N4.
import socket, time

def tcp_probe(ip, port, to=2.5, payload=None):
    """Return (status, resp_bytes). resp is ALWAYS bytes — never a str."""
    s = socket.socket(); s.settimeout(to)
    try:
        s.connect((ip, port))
        if payload:
            s.sendall(payload); time.sleep(0.3)
            return ("OPEN", s.recv(256))
        return ("OPEN", b"OPEN")
    except Exception as e:
        return ("closed", b"ERR:" + str(e).encode())   # bytes on BOTH branches
    finally:
        try: s.close()
        except Exception: pass

def node_is_up(ip, mgmt_ports=(22, 445, 5985), to=2.5):
    """Distinguish 'service stopped' from 'whole node powered off'.
    Probe other management ports; if ALL closed -> node likely OFF."""
    open_ports = [p for p in mgmt_ports if tcp_probe(ip, p, to)[0] == "OPEN"]
    return open_ports   # non-empty => host reachable; service port is a real change

# Example claim probes (one authoritative method each)
def ollama_up(ip):
    st, r = tcp_probe(ip, 11434, payload=b"GET /api/tags HTTP/1.0\r\n\r\n")
    return st == "OPEN" and (b"models" in r or b"200" in r)

def redis_state(ip):
    st, r = tcp_probe(ip, 6379, payload=b"PING\r\n")
    if r.startswith(b"+PONG"):   return "UNAUTH"
    if r.startswith(b"-NOAUTH"): return "AUTH_REQ"
    return "DOWN" if st == "closed" else "UNEXPECTED"

def litellm_up(ip, port=4001):
    st, r = tcp_probe(ip, port, payload=b"GET /v1/models HTTP/1.0\r\n\r\n")
    return st == "OPEN" and b'"id"' in r

if __name__ == "__main__":
    # quick self-test of the pattern
    for ip in ["192.168.1.218", "192.168.1.21"]:
        print(ip, "node_up_ports=", node_is_up(ip),
              "ollama=", ollama_up(ip), "redis=", redis_state(ip))
