# repair-broken-startup.ps1  — TEMPLATE (copy + edit the $fixes array)
# Repairs dead Startup-folder .lnk / .vbs automations by repointing them at
# the real script path, after backing up originals to .bak.
# Read-only safe: only edits the link target lines; never kills processes.
# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this script>

$startup = 'C:\Users\zqmco\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
$sh = New-Object -ComObject WScript.Shell

# Each entry: type 'lnk' or 'vbs', the link file, old path to replace, new path.
# For 'lnk' you may also give WorkDir (defaults to the new path's directory).
$fixes = @(
  @{ type='vbs'; file="$startup\Hermes_Gateway.vbs";
     old='C:\Users\zqmco\AppData\Local\hermes\gateway-service\Hermes_Gateway.vbs';
     new='C:\Users\zqmco\OneDrive\Desktop\repos\hermes-config\gateway-service\Hermes_Gateway.vbs' }
  @{ type='lnk'; file="$startup\ZQM-Node-01-Indexer.lnk";
     old='C:\Users\zqmco\OneDrive\Desktop\zqm-node-01-indexer\app.py';
     new='C:\Users\zqmco\OneDrive\Desktop\repos\zqm-node-01-indexer\app.py' }
  @{ type='lnk'; file="$startup\ZQM-Skill-Automation-Center.lnk";
     old='C:\Users\zqmco\AppData\Local\hermes\skills\skill-automation-center\scripts\serve_dashboard.py';
     new='C:\Users\zqmco\OneDrive\Desktop\repos\hermes-config\skills\skill-automation-center\scripts\serve_dashboard.py' }
)

foreach ($f in $fixes) {
  $path = $f.file
  Copy-Item $path "$path.bak" -Force          # safety backup
  if ($f.type -eq 'vbs') {
    $c = Get-Content $path -Raw
    if ($c.Contains($f.old)) {
      Set-Content $path ($c.Replace($f.old, $f.new)) -NoNewline
      "FIXED vbs: $path -> $($f.new)"
    } else { "WARN: old string not found in $path; skipped" }
    $resolved = $f.new
  } else { # lnk
    $l = $sh.CreateShortcut($path)
    $l.Arguments        = $f.new
    $l.WorkingDirectory = if ($f.WorkDir) { $f.WorkDir } else { Split-Path $f.new }
    $l.Save()
    "FIXED lnk: $path -> $($l.Arguments)"
    $resolved = $l.Arguments
  }
  # VERIFY the actual SCRIPT (Arguments for lnk, new for vbs) exists:
  $script = $resolved.Trim('"')
  "  verify script exists: $(Test-Path $script)  ($script)"
}
