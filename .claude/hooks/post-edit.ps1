# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit): records every file edit in
# .sdd/activity.log. An edit to .sdd/STATE.md is recorded as a CHECKPOINT.
# Gives a crash-recovery trail of files touched since the last checkpoint.
# ASCII-only file (see lib.ps1).

. (Join-Path $PSScriptRoot 'lib.ps1')

try {
    $in = Read-HookInput
    if (-not $in -or -not $in.tool_input) { exit 0 }
    $path = $in.tool_input.file_path
    if (-not $path) { $path = $in.tool_input.notebook_path }
    if (-not $path) { exit 0 }

    $root = Get-ProjectRoot
    $rel = Get-RelativePath $root ([string]$path)
    if (-not $rel) { exit 0 }  # outside the project (e.g. user memory files)

    if ($rel -ieq '.sdd/STATE.md') {
        Write-Activity $root 'CHECKPOINT' ([string]$in.tool_name)
    } elseif ($rel -ieq '.sdd/journal.md' -or $rel -ieq '.sdd/activity.log') {
        # bookkeeping files: not work in progress
    } else {
        Write-Activity $root 'EDIT' $rel
    }
} catch {}
exit 0
