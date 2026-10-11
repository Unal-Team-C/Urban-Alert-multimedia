---
description: Descomponer el plan de la feature activa en tareas ejecutables (tasks.md)
argument-hint: "[indicaciones opcionales]"
---

Indicaciones: $ARGUMENTS

Sigue `.sdd/PROTOCOL.md`.

1. Lee `.sdd/STATE.md`, `.sdd/config.json`, la constitución, y `spec.md` + `plan.md` (+ `data-model.md`, `contracts/` si existen) de la feature activa.
2. **Gate**: si `requireApprovalGates` y el plan no está `aprobado`, pide aprobación explícita; si la da, márcalo y sigue.
3. **Write-ahead**: `STATE.md` → `fase: tasks`, siguiente paso «Generar tasks.md de <feature>».
4. **Genera** `tasks.md` desde `.sdd/templates/tasks.md`:
   - IDs `T001…` en orden ejecutable, agrupadas por fases (Preparación, Pruebas, Núcleo, Integración, Pulido). Elimina fases vacías.
   - Una línea por tarea: `- [ ] T001 [P] Descripción imperativa — archivos: … — cubre: RF-00x — verifica: <comando o criterio observable>`.
   - `[P]` solo si no comparte archivos con otra tarea pendiente ni depende de ella. Dependencias no obvias: `— depende: T00X`.
   - **Tamaño**: cada tarea cabe en un commit y en una sesión corta. Si no, divídela.
   - **Verificación obligatoria** en cada tarea: es lo que permite saber, tras un corte, si está hecha.
   - Si la constitución lo pide, tests antes que implementación.
   - Tabla de cobertura: todo RF/RNF con al menos una tarea.
5. **Autorrevisión**: sin requisitos huérfanos, sin tareas sin requisito (salvo preparación/pulido), orden coherente con dependencias.
6. **Persistencia**: journal («tasks.md generado: N tareas»); `STATE.md` → `tarea_actual` = primera tarea, siguiente paso «Aprobar tasks → /sdd-implement».
7. Presenta al usuario el número de tareas por fase y pide aprobación. Cuando apruebe, pon `Estado: aprobado` en `tasks.md` y regístralo.
