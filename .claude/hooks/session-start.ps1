# SessionStart hook: re-injects the persisted SDD state into the context on
# startup / resume / clear / compact, so work survives any interruption.
# ASCII-only file (see lib.ps1).

. (Join-Path $PSScriptRoot 'lib.ps1')

$out = New-Object System.Collections.Generic.List[string]
try {
    $in = Read-HookInput
    $source = 'unknown'
    if ($in -and $in.source) { $source = [string]$in.source }

    $root = Get-ProjectRoot
    $cfg = Get-Config $root
    $statePath = Join-Path $root '.sdd\STATE.md'
    $needsResume = $false

    $out.Add("=== SDD HARNESS: contexto recuperado automaticamente (origen: $source) ===")
    $out.Add('Protocolo: .sdd/PROTOCOL.md | Fuente de verdad: .sdd/STATE.md + specs/<feature>/tasks.md')
    $out.Add(('Config: gates={0} autoCommitPerTask={1} enforceCheckpointOnStop={2}' -f `
        $cfg.requireApprovalGates, $cfg.autoCommitPerTask, $cfg.enforceCheckpointOnStop))

    if (-not (Test-Path -LiteralPath $statePath)) {
        $out.Add('')
        $out.Add('AVISO: no existe .sdd/STATE.md. El arnes no esta inicializado: ejecuta .sdd/install.ps1 -Target . o crea STATE.md desde .sdd/templates/state.md.')
    } else {
        $state = Read-Lines $statePath
        $out.Add('')
        $out.Add('--- .sdd/STATE.md ---')
        $prevBlank = $false
        foreach ($l in (Remove-HtmlComments $state)) {
            $blank = -not $l.Trim()
            if (-not ($blank -and $prevBlank)) { $out.Add($l) }
            $prevBlank = $blank
        }

        $feature = Get-StateField $state 'feature_activa'
        $estado = Get-StateField $state 'estado_tarea'
        if ($estado -match 'en_progreso') { $needsResume = $true }

        if (-not (Test-NoFeature $feature)) {
            $featureDir = Join-Path $root ('specs\' + $feature)
            $out.Add('')
            if (-not (Test-Path -LiteralPath $featureDir)) {
                $out.Add("--- AVISO: la feature activa '$feature' no existe en specs/ ---")
            } else {
                $docs = @('spec.md', 'plan.md', 'tasks.md', 'verify.md', 'notes.md') |
                    Where-Object { Test-Path -LiteralPath (Join-Path $featureDir $_) }
                $out.Add("--- Feature activa: specs/$feature (archivos: $($docs -join ', ')) ---")
                $ti = Get-TaskInfo (Join-Path $featureDir 'tasks.md')
                if ($ti.Exists -and $ti.Total -gt 0) {
                    $out.Add(('Tareas: {0}/{1} hechas | {2} en progreso | {3} bloqueadas | {4} pendientes | {5} descartadas' -f `
                        $ti.Done, $ti.Total, $ti.InProgress, $ti.Blocked, $ti.Pending, $ti.Discarded))
                    foreach ($t in $ti.InProgressLines) { $out.Add('  [~] ' + (Limit-Text $t)) }
                    foreach ($t in $ti.BlockedLines) { $out.Add('  [!] ' + (Limit-Text $t)) }
                    foreach ($t in $ti.NextLines) { $out.Add('  [ ] ' + (Limit-Text $t)) }
                    if ($ti.InProgress -gt 0) { $needsResume = $true }
                }
            }
        }
    }

    $act = Get-ActivitySinceCheckpoint $root
    $out.Add('')
    $lastCp = '(nunca)'
    if ($act.LastCheckpoint) { $lastCp = $act.LastCheckpoint }
    if ($act.Edits.Count -gt 0) {
        $needsResume = $true
        $out.Add("--- Archivos editados DESPUES del ultimo checkpoint ($lastCp): posible trabajo sin registrar ---")
        $max = [int]$cfg.maxEditsShown
        foreach ($f in ($act.Edits | Select-Object -First $max)) { $out.Add("  - $f") }
        if ($act.Edits.Count -gt $max) { $out.Add("  ... y $($act.Edits.Count - $max) mas (ver .sdd/activity.log)") }
    } else {
        $out.Add("--- Ultimo checkpoint: $lastCp (sin ediciones posteriores) ---")
    }
    if ($act.Compactions -gt 0) {
        $out.Add("  (hubo $($act.Compactions) compactacion(es) de contexto desde ese checkpoint)")
    }

    $journal = @(Remove-HtmlComments (Read-Lines (Join-Path $root '.sdd\journal.md')) | Where-Object { $_ -notmatch '^\s*$' })
    if ($journal.Count -gt 0) {
        $n = [int]$cfg.journalTailLines
        $out.Add('')
        $out.Add("--- .sdd/journal.md (ultimas $n lineas) ---")
        foreach ($l in ($journal | Select-Object -Last $n)) { $out.Add($l) }
    }

    if ((Test-Path -LiteralPath (Join-Path $root '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $ErrorActionPreference = 'Continue'
        $out.Add('')
        $branch = (& git -C $root rev-parse --abbrev-ref HEAD 2>$null)
        $out.Add("--- Git (rama: $branch) ---")
        $status = @(& git -C $root status --short 2>$null)
        if ($status.Count -eq 0) { $out.Add('  arbol de trabajo limpio') }
        else {
            $max = [int]$cfg.gitStatusLines
            foreach ($s in ($status | Select-Object -First $max)) { $out.Add("  $s") }
            if ($status.Count -gt $max) { $out.Add("  ... y $($status.Count - $max) mas") }
        }
        $log = @(& git -C $root log --oneline -5 2>$null)
        foreach ($c in $log) { $out.Add("  $c") }
        $ErrorActionPreference = 'Stop'
    }

    $out.Add('')
    $out.Add('--- Instrucciones del arnes ---')
    if ($needsResume) {
        $out.Add('* HAY TRABAJO POSIBLEMENTE INTERRUMPIDO (tarea en progreso o ediciones sin checkpoint). Antes de empezar trabajo nuevo aplica el procedimiento de /sdd-resume: verifica el estado real del codigo, reconcilia tasks.md y STATE.md, y luego continua.')
    }
    $out.Add('* Regla write-ahead: registra en STATE.md (y [~] en tasks.md) ANTES de trabajar; cierra cada tarea con [x] + journal + STATE.md (+ commit si autoCommitPerTask).')
    $out.Add('* Editar .sdd/STATE.md registra un checkpoint. Mantenlo al dia al final de cada turno con ediciones.')

    Write-Activity $root 'SESSION_START' $source
} catch {
    $out.Add("[sdd-harness] error en session-start: $($_.Exception.Message)")
}

[Console]::Out.Write(($out -join "`n") + "`n")
exit 0
