---
description: Resumen de solo lectura del estado SDD (features, fases, progreso, bloqueos)
---

Muestra el estado del proyecto **sin modificar ningún archivo**.

1. Lee `.sdd/STATE.md`, las últimas ~15 líneas de `.sdd/journal.md` y las entradas de `.sdd/activity.log` posteriores al último `CHECKPOINT`.
2. Para cada carpeta de `specs/`: estado de la spec, existencia/estado de plan, tareas (hechas/total, en progreso, bloqueadas) y resultado de `verify.md` si existe.
3. Responde con:
   - una tabla `Feature | Fase | Tareas | Estado`, marcando la activa;
   - de la feature activa: tarea actual, siguiente paso, bloqueos;
   - avisos: tareas `[~]`, ediciones sin checkpoint, gates pendientes de aprobación, `[NEEDS CLARIFICATION]` abiertos;
   - el comando recomendado a continuación.
