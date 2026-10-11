# PreCompact hook: marks the compaction in .sdd/activity.log. After compaction,
# SessionStart (source=compact) re-injects the persisted state.
# ASCII-only file (see lib.ps1).

. (Join-Path $PSScriptRoot 'lib.ps1')

try {
    $in = Read-HookInput
    $trigger = 'unknown'
    if ($in -and $in.trigger) { $trigger = [string]$in.trigger }
    Write-Activity (Get-ProjectRoot) 'COMPACT' $trigger
} catch {}
exit 0
