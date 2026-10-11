---
description: Verificar la implementación de la feature activa contra su spec y la constitución (verify.md)
argument-hint: "[foco opcional]"
---

Foco: $ARGUMENTS

Sigue `.sdd/PROTOCOL.md`.

1. Lee la constitución y `spec.md`, `plan.md`, `tasks.md` de la feature activa.
2. **Write-ahead**: `STATE.md` → `fase: verify`, siguiente paso «Verificar <feature>».
3. Ejecuta la suite completa definida en el plan/constitución (tests, build, lint, typecheck). Registra comandos y resultados.
4. Crea `verify.md` en la carpeta de la feature (esqueleto primero) con:
   - fecha, resultado global (✅ / ⚠️ / ❌) y resultado de cada comando;
   - **matriz de requisitos**: cada RF, RNF y criterio de aceptación → evidencia (test, `archivo:línea`, comando) → ✅ / ⚠️ / ❌;
   - cumplimiento de cada principio de la constitución;
   - hallazgos: tareas `[x]` sin evidencia, TODOs, código muerto, secretos, desviaciones del plan no documentadas.
5. Si hay fallos: añade tareas de corrección en `tasks.md §Correcciones de verificación` (formato normal, con `verifica:`), `STATE.md` → `fase: implement` y siguiente paso con la primera corrección.
6. Si todo está ✅: `Estado: implementada` en la spec, `STATE.md` → `fase: done`, siguiente paso «Feature cerrada; /sdd-new para la siguiente».
7. **Persistencia**: journal con el resultado. Informa al usuario del resultado global y de lo que falle.
