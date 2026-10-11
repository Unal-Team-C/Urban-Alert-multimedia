---
description: Crear o actualizar los principios no negociables del proyecto (.sdd/constitution.md)
argument-hint: "[principios o cambios, opcional]"
---

Objetivo: definir o actualizar `.sdd/constitution.md`, las reglas que todo plan e implementación deben respetar. Sigue `.sdd/PROTOCOL.md`.

Entrada del usuario: $ARGUMENTS

1. Lee `.sdd/STATE.md` y `.sdd/constitution.md` (si sigue en versión 0.0.0 es la plantilla: trátala como vacía).
2. Si el proyecto ya tiene código, inspecciona manifiestos, configuración, tests y CI para inferir el stack y las convenciones reales. No inventes.
3. Redacta principios **concretos y verificables** (máx. ~10). Evita «código de calidad»; prefiere «toda lógica de dominio tiene tests unitarios; `npm test` pasa antes de cada commit». Cubre: stack y versiones, pruebas y comandos, calidad/estilo, seguridad, límites de rendimiento si aplican, lo prohibido. Cada principio con su **Por qué**.
4. Lo importante que no puedas inferir → pregúntalo (máx. 5 preguntas, cada una con opción recomendada). Persiste cada respuesta en el archivo en cuanto la recibas. Lo que quede sin resolver, márcalo `[NEEDS CLARIFICATION]`.
5. Sube la versión (semver: mayor = principio eliminado o redefinido; menor = añadido; parche = redacción) y añade una línea al Historial.
6. Si hay `plan.md` existentes, indica cuáles podrían incumplir los principios nuevos.
7. Persistencia: entrada en `.sdd/journal.md`; actualiza `.sdd/STATE.md` (si `fase` era `constitution`, deja como siguiente paso `/sdd-new <descripción>`).
8. Resume al usuario los principios en ≤10 líneas.
