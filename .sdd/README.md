# Arnés SDD con persistencia para Claude Code

Arnés de uso general para **desarrollo guiado por especificaciones** (Spec-Driven Development) diseñado para que el trabajo **sobreviva a cualquier interrupción**: cierre de la app, crash, corte de red o compactación del contexto.

Requisitos: Windows con PowerShell 5.1+ (incluido en Windows). Git es opcional pero recomendado.

## Cómo funciona la persistencia

Tres capas, de más a menos automática:

| Capa | Mecanismo | Qué protege |
|---|---|---|
| **Hooks** (automático) | `PostToolUse` registra cada edición en `.sdd/activity.log`; `PreCompact` marca compactaciones; `SessionStart` reinyecta estado, tareas, ediciones sin registrar, journal y git al abrir/reanudar/compactar | Rastro de lo que se tocó aunque Claude no llegara a anotarlo |
| **Protocolo** (Claude) | *Write-ahead*: se anota en `STATE.md` y se marca `[~]` **antes** de trabajar; se cierra con `[x]` + journal + `STATE.md` **justo al terminar** | Saber qué se estaba haciendo y qué falta |
| **Git** (opcional) | Commit local por tarea completada (`autoCommitPerTask`) | Poder comparar y recuperar código |

El hook `Stop` impide terminar un turno con ediciones sin checkpoint mientras haya una feature activa (una sola vez por turno, sin bucles).

## Flujo

```
/sdd-constitution → /sdd-new → /sdd-clarify → /sdd-plan → /sdd-tasks → /sdd-implement → /sdd-verify
```

Tras una interrupción: abre la sesión y escribe `/sdd-resume continuar` (o simplemente «continúa»; el contexto ya se inyecta solo).
Otros: `/sdd-status`, `/sdd-checkpoint [nota]`, `/sdd-switch <feature>`.

Detalle completo del protocolo: [PROTOCOL.md](PROTOCOL.md).

## Estructura

```
CLAUDE.md                     importa .sdd/PROTOCOL.md
.claude/
  settings.json               hooks + permisos
  hooks/                      lib.ps1, session-start.ps1, post-edit.ps1, pre-compact.ps1, stop.ps1
  commands/sdd-*.md           comandos slash
.sdd/
  PROTOCOL.md                 reglas (las lee Claude)
  config.json                 configuración
  STATE.md                    puntero de reanudación        (estado del proyecto)
  journal.md                  bitácora append-only          (estado del proyecto)
  constitution.md             principios del proyecto       (estado del proyecto)
  activity.log                rastro automático de hooks    (ignorado por git)
  templates/                  plantillas
  install.ps1                 instalador
specs/NNN-slug/               spec.md, plan.md, tasks.md, verify.md, notes.md
```

## Configuración (`.sdd/config.json`)

| Clave | Por defecto | Efecto |
|---|---|---|
| `enforceCheckpointOnStop` | `true` | El hook Stop exige actualizar STATE.md si hubo ediciones |
| `requireApprovalGates` | `true` | Spec, plan y tareas requieren aprobación explícita antes de avanzar |
| `autoCommitPerTask` | `true` | Commit local tras cada tarea verificada (si hay repo git) |
| `journalTailLines` | `20` | Líneas del journal inyectadas al iniciar sesión |
| `maxEditsShown` | `25` | Máximo de ediciones sin checkpoint mostradas |
| `gitStatusLines` | `25` | Máximo de líneas de `git status` mostradas |

## Instalar en otro proyecto

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".sdd\install.ps1" -Target "D:\ruta\al\proyecto"
```

- Copia hooks, comandos, protocolo y plantillas; crea `STATE.md`, `journal.md`, `constitution.md`, `config.json` y `specs/` solo si no existen.
- Si el destino ya tiene `.claude/settings.json`, fusiona hooks y permisos (con copia de seguridad).
- Si ya tiene `CLAUDE.md`, le añade la sección que importa el protocolo.
- `-Force` actualiza los archivos del arnés (no toca el estado del proyecto).

## Solución de problemas

- **Los hooks no se ejecutan**: se cargan al iniciar la sesión; abre una sesión nueva. Revisa que aparezca el bloque «SDD HARNESS» al principio. En un terminal `claude` interactivo, `/hooks` muestra los registrados.
- **Probar un hook a mano**:
  ```bash
  echo '{"source":"startup"}' | powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/session-start.ps1
  ```
- **Desactivar temporalmente el bloqueo en Stop**: `"enforceCheckpointOnStop": false` en `.sdd/config.json`.
- **Los scripts `.ps1` deben ser solo ASCII** (PowerShell 5.1 los lee como ANSI si no tienen BOM).
