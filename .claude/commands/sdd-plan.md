---
description: Diseñar el plan técnico (plan.md) de la feature activa
argument-hint: "[preferencias o restricciones técnicas]"
---

Preferencias del usuario: $ARGUMENTS

Sigue `.sdd/PROTOCOL.md`.

1. Lee `.sdd/STATE.md`, `.sdd/config.json`, `.sdd/constitution.md` y la `spec.md` de la feature activa. Si existen, lee también `notes.md` (en especial `## Indicaciones técnicas de la fuente`) y consulta `fuentes/` cuando necesites el detalle original: esas indicaciones son preferencias a respetar salvo que contradigan la constitución (en ese caso, justifícalo en §Decisiones).
2. **Gate**: si `requireApprovalGates` y la spec no está `aprobada`, muestra un resumen y pide aprobación explícita; si la da, márcala `aprobada` y sigue. Si quedan `[NEEDS CLARIFICATION]` que bloqueen el diseño, propón `/sdd-clarify` y detente.
3. **Write-ahead**: `STATE.md` → `fase: plan`, siguiente paso «Redactar plan.md de <feature>».
4. **Investiga** el código existente (estructura, patrones, dependencias, comandos de build/test) para que el plan encaje. Si evalúas opciones externas, documenta lo investigado en `research.md` de la feature.
5. **Redacta** `plan.md` desde `.sdd/templates/plan.md`, escribiendo primero el esqueleto y rellenando sección a sección:
   - contexto técnico concreto (versiones, comandos);
   - verificación contra cada principio de la constitución (excepción = justificación escrita);
   - arquitectura, estructura de archivos, modelo de datos, contratos/interfaces;
   - decisiones `D-00X` con alternativas y motivo;
   - estrategia de pruebas con comandos;
   - riesgos y mitigaciones;
   - trazabilidad: **todo RF/RNF** mapeado a componentes y pruebas.
   Artefactos opcionales si aportan: `data-model.md`, `contracts/`.
6. **Autorrevisión**: todo requisito cubierto; nada viola la constitución sin justificar; sin abstracciones ni dependencias que la spec no justifique.
7. **Persistencia**: journal con las decisiones clave; `STATE.md` → siguiente paso «Revisar y aprobar plan → /sdd-tasks».
8. Presenta al usuario el enfoque y las decisiones que debe validar. Cuando apruebe, pon `Estado: aprobado` en el plan y regístralo.
