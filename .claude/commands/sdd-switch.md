---
description: Cambiar la feature activa aparcando el contexto de la actual
argument-hint: "<NNN | slug>"
---

Feature destino: $ARGUMENTS

1. Busca en `specs/` la carpeta que coincida (por número o parte del slug). Si no hay argumento o es ambiguo, lista las features con su fase y pregunta.
2. **Aparca la actual** (si hay): haz lo del `/sdd-checkpoint`; luego añade al final de `specs/<actual>/notes.md` una sección `## Aparcado AAAA-MM-DD` con fase, tarea actual, siguiente paso, Contexto de trabajo y Bloqueos de `STATE.md`. Una tarea `[~]` se queda `[~]`.
3. **Activa la destino**: deduce su fase por sus archivos (spec/plan/tasks/verify y sus `Estado:`), y su tarea actual (primera `[~]`, si no primera `[ ]`). Recupera de su `notes.md` la última sección `Aparcado` si existe.
4. Reescribe `STATE.md` con los datos de la destino (Contexto y Bloqueos recuperados). Journal: `## AAAA-MM-DD · general · Cambio de feature <actual> → <destino>`.
5. Informa: feature activa, fase, siguiente paso.
