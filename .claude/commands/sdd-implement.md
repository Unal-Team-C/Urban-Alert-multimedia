---
description: Implementar tareas de la feature activa con checkpoint tras cada una
argument-hint: "[T00X | siguiente | todas]  (por defecto: siguiente)"
---

Alcance: $ARGUMENTS (vacío o `siguiente` = una tarea; `todas` = hasta terminar o bloquearse; `T00X` = esa tarea)

Sigue `.sdd/PROTOCOL.md`. Las reglas de persistencia de este comando no son opcionales.

## Antes de empezar

1. Lee `.sdd/STATE.md`, `.sdd/config.json`, la constitución y `tasks.md` + `plan.md` de la feature activa (y `spec.md` cuando necesites criterios de aceptación).
2. Si hay alguna tarea `[~]` o el contexto de sesión muestra ediciones sin checkpoint, aplica primero el procedimiento de `/sdd-resume` a esa tarea. No empieces otra.
3. **Gate**: si `requireApprovalGates` y `tasks.md` no está `aprobado`, pide aprobación.

## Bucle por tarea

A. **Elegir**: la tarea indicada, o la primera `[ ]` cuyas dependencias estén `[x]`.

B. **Write-ahead** (antes de tocar código):
   - marca la tarea `[~]` en `tasks.md`;
   - `STATE.md` → `fase: implement`, `tarea_actual: T00X`, `estado_tarea: en_progreso`, siguiente paso = qué vas a hacer exactamente (archivos, enfoque).

C. **Implementar** lo mínimo que cumple la tarea, respetando plan y constitución. En el momento en que ocurra:
   - un hallazgo útil (gotcha, comando, hipótesis) → `STATE.md §Contexto de trabajo`;
   - una decisión o desviación del plan → `plan.md §Decisiones` + journal.
   En tareas largas, actualiza `STATE.md` con el progreso parcial («hecho X e Y, falta Z») cada vez que completes un sub-paso significativo.

D. **Verificar** con el criterio `verifica:` de la tarea (tests, build, lint, typecheck). No marques `[x]` sin verificar. Si no es posible verificar, déjalo escrito en el journal.

E. **Cerrar**:
   - `[x]` en `tasks.md`;
   - journal: `## AAAA-MM-DD · <feature> · T00X hecha` + resumen, archivos y resultado de la verificación;
   - `STATE.md` → `estado_tarea: hecha`, `tarea_actual` = siguiente tarea, siguiente paso concreto; limpia del Contexto lo que ya no aplique;
   - si `autoCommitPerTask` es `true` y hay repo git: `git add -A` y `git commit -m "<feature> T00X: <descripción>"`. Solo commit local; nunca `push`.

F. **Bloqueo**: `[!] … — bloqueo: <motivo>`, anótalo en `STATE.md §Bloqueos`; continúa con otra tarea independiente o detente y pregunta.

G. **Tarea más grande de lo previsto**: detente, divídela en `tasks.md` (`T00Xa`, `T00Xb`…), checkpoint, y sigue.

## Reglas

- No adelantes trabajo de otras tareas «de paso».
- Si la spec o el plan resultan erróneos, para y propón el cambio al usuario; no lo cambies en silencio.
- Tras cada tarea el proyecto queda consistente (compila y los tests existentes pasan).

## Al terminar

Si todas las tareas están `[x]` o `[-]`: `STATE.md` → `fase: verify`, siguiente paso `/sdd-verify`. Resume al usuario lo hecho, lo pendiente y los bloqueos.
