---
description: Guardar ahora en disco todo el contexto necesario para continuar si la sesión se corta
argument-hint: "[nota]"
---

Nota: $ARGUMENTS

Deja el estado como si la sesión fuera a cortarse inmediatamente después:

1. `tasks.md` de la feature activa refleja el estado real de cada tarea (`[~]` en la que está en curso).
2. `.sdd/STATE.md` al día: `feature_activa`, `fase`, `tarea_actual`, `estado_tarea`; **Siguiente paso** accionable por alguien sin contexto; **Contexto de trabajo** con todo lo que solo está en la conversación (hipótesis, qué se probó y resultado, comandos útiles, archivos a mirar, lo que ibas a hacer); **Bloqueos**.
3. Decisiones tomadas en la conversación y aún no escritas → `plan.md §Decisiones` o journal.
4. `.sdd/journal.md`: entrada `## AAAA-MM-DD · <feature> · Checkpoint` con la nota.
5. Commit solo si la nota lo pide (p. ej. «commit»): `git add -A` + `git commit -m "wip(<feature>): checkpoint <nota>"`.

Responde en 2-3 líneas: qué quedó guardado y cuál es el siguiente paso.
