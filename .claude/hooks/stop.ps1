# Stop hook: if files were edited since the last checkpoint while a feature is
# active, block the end of the turn once and ask Claude to persist the state.
# Loop-safe: never blocks when stop_hook_active is true.
# ASCII-only file (see lib.ps1).

. (Join-Path $PSScriptRoot 'lib.ps1')

try {
    $in = Read-HookInput
    if ($in -and $in.stop_hook_active) { exit 0 }

    $root = Get-ProjectRoot
    $cfg = Get-Config $root
    if (-not $cfg.enforceCheckpointOnStop) { exit 0 }

    $statePath = Join-Path $root '.sdd\STATE.md'
    if (-not (Test-Path -LiteralPath $statePath)) { exit 0 }
    $feature = Get-StateField (Read-Lines $statePath) 'feature_activa'
    if (Test-NoFeature $feature) { exit 0 }

    $act = Get-ActivitySinceCheckpoint $root
    if ($act.Edits.Count -eq 0) { exit 0 }

    $list = ($act.Edits | Select-Object -First 8) -join ', '
    if ($act.Edits.Count -gt 8) { $list += ', ...' }
    $reason = ("[sdd-harness] Checkpoint pendiente: {0} archivo(s) editados desde el ultimo checkpoint ({1}). " +
        "Antes de terminar el turno: (1) actualiza specs/{2}/tasks.md si cambio el estado de alguna tarea; " +
        "(2) anade una entrada a .sdd/journal.md si hubo avances o decisiones; " +
        "(3) actualiza .sdd/STATE.md (fase, tarea_actual, estado_tarea, Siguiente paso, Contexto de trabajo). " +
        "Editar STATE.md registra el checkpoint.") -f $act.Edits.Count, $list, $feature

    $payload = @{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress
    [Console]::Out.Write($payload)
} catch {}
exit 0
