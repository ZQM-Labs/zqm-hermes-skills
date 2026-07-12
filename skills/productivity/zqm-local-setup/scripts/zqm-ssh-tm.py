# zqm-ssh-tm.py — non-interactive SSH to TerraMaster TOS Gardens via paramiko.
# Requires: python -m pip install paramiko  (installs into ComfyUI venv)
# Credential is passed in (do NOT hardcode). Used after DPAPI decrypt of the
# stored garden-admin JSON, e.g. from a PowerShell wrapper that calls:
#   python zqm-ssh-tm.py <ip> <user> <password> [cmd]
import paramiko, sys

def ssh_run(ip, user, pw, cmd="uname -a; uptime; df -h / | tail -1"):
    try:
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(ip, 22, user, pw, timeout=10, look_for_keys=False, allow_agent=False)
        stdin, stdout, stderr = c.exec_command(cmd)
        out = stdout.read().decode().strip()
        print(f"SSH OK {ip}: {out}")
        c.close()
    except paramiko.AuthenticationException:
        print(f"SSH AUTH FAILED {ip} (wrong user/password)")
    except paramiko.SSHException as e:
        print(f"SSH ERROR {ip}: {e}")
    except Exception as e:
        print(f"OTHER FAIL {ip}: {type(e).__name__}: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("usage: python zqm-ssh-tm.py <ip> <user> <password> [cmd]")
        sys.exit(1)
    ip, user, pw = sys.argv[1], sys.argv[2], sys.argv[3]
    cmd = sys.argv[4] if len(sys.argv) > 4 else "uname -a; uptime; df -h / | tail -1"
    ssh_run(ip, user, pw, cmd)
