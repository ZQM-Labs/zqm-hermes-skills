# fix_authorized_keys_acl.ps1 — grant the interactive user (by BOTH the profile-folder name AND the
# rename-aware account name) + SYSTEM + BUILTIN\Administrators FullControl on authorized_keys.
# Handles the zqmco/AlexZ account-rename mismatch where $env:USERNAME resolves to a DIFFERENT
# principal than the folder name. Elevated, self-logging.
$log = Join-Path $PSScriptRoot "fix_authorized_keys_acl.log"
function out($s){ Add-Content -Path $log -Value $s }
out ("=== fix_authorized_keys_acl started " + (Get-Date) + " ===")
$ak = "C:\Users\zqmco\.ssh\authorized_keys"
if (-not (Test-Path $ak)) { out "  authorized_keys ABSENT - nothing to fix"; exit }
try {
    $acl = Get-Acl $ak
    $acl.SetAccessRuleProtection($true, $false)
    $cands = @($env:USERNAME, "ZQM-NODE-1\AlexZ", "SYSTEM", "BUILTIN\Administrators")
    foreach ($id in $cands) {
        try {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($id, "FullControl", "Allow")
            $acl.AddAccessRule($rule)
            out ("  granted $id")
        } catch {
            out ("  skip $id (unresolved): " + $_.Exception.Message)
        }
    }
    Set-Acl $ak $acl
    out "  Set-Acl done"
    (Get-Acl $ak).Access | For-Each-Object { out ("  ACE: $($_.IdentityReference) = $($_.FileSystemRights)") }
} catch {
    out ("  FAILED: " + $_.Exception.Message)
}
out ("=== finished " + (Get-Date) + " ===")
