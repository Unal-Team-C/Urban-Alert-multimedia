---
description: Reanudar tras una interrupción reconstruyendo el estado real, y continuar
argument-hint: "[continuar]"
---

Argumentos: $ARGUMENTS

Procedimiento de reanudación. **No empieces trabajo nuevo hasta completar el paso 5.**

1. **Estado registrado**: lee `.sdd/STATE.md`, las últimas ~30 líneas de `.sdd/journal.md` y las líneas de `.sdd/activity.log` posteriores al último `CHECKPOINT` (archivos `EDIT` sin registrar, `COMPACT`, `SESSION_START`).
2. **Plan de trabajo**: lee `tasks.md` de la feature activa, y `plan.md`/`spec.md` en la medida en que lo necesites para entender la tarea actual.
3. **Estado real del código**:
   - con git: `git status`, `git diff` (y `git diff --staged`), `git log --oneline -5`;
   - sin git: revisa los archivos `EDIT` posteriores al último checkpoint.
4. **Diagnóstico de cada tarea `[~]`** (o de `tarea_actual` si `estado_tarea` es `en_progreso`): compara el código con la descripción de la tarea y **ejecuta su verificación**.
   - Hecha y verificada → ciérrala como en el paso E de `/sdd-implement`.
   - A medias → escribe en `STATE.md §Contexto de trabajo` qué está hecho y qué falta exactamente; mantén `[~]`.
   - Cambios rotos o incoherentes → descríbelos al usuario y pregunta antes de descartar nada. **Nunca** `git checkout`, `git reset`, `git clean` ni borrar archivos sin permiso explícito.
   - Si las ediciones sin checkpoint no corresponden a ninguna tarea, identifícalas y pregunta.
5. **Reconciliar**: `tasks.md` y `STATE.md` reflejan la realidad; journal: `## AAAA-MM-DD · <feature> · Reanudación` con lo encontrado y lo decidido.
6. **Informa** en ≤8 líneas: dónde estábamos, qué se encontró, siguiente paso.
   Si los argumentos contienen «continuar» o el usuario ya pidió seguir, continúa con el siguiente paso (con `/sdd-implement` si la fase es `implement`), salvo que toque un gate de aprobación: en ese caso pregunta.
