# Protocolo SDD con persistencia

> Este archivo se importa desde `CLAUDE.md`. Es obligatorio en cada sesión.

## 0. Principio rector: los archivos son la memoria

La sesión puede cortarse en cualquier momento (cierre de la app, crash, corte de red, compactación de contexto).
**Todo lo necesario para continuar debe estar en disco en el momento en que ocurre, no al final.**
Si no está escrito, no existe.

## 1. Mapa de archivos

| Archivo | Propósito | Quién escribe |
|---|---|---|
| `.sdd/STATE.md` | Puntero de reanudación: feature activa, fase, tarea, siguiente paso, contexto vivo | Claude, en cada transición |
| `.sdd/journal.md` | Bitácora *append-only* de avances y decisiones | Claude |
| `.sdd/activity.log` | Registro automático: ediciones, checkpoints, compactaciones, inicios de sesión | Hooks (no editar) |
| `.sdd/constitution.md` | Principios no negociables del proyecto | Claude + usuario |
| `.sdd/config.json` | Configuración del arnés | Usuario |
| `specs/NNN-slug/spec.md` | **Qué** y **por qué** (sin cómo) | `/sdd-new`, `/sdd-clarify` |
| `specs/NNN-slug/plan.md` | **Cómo**: arquitectura, decisiones, pruebas | `/sdd-plan` |
| `specs/NNN-slug/tasks.md` | Lista ejecutable de tareas con estado | `/sdd-tasks`, `/sdd-implement` |
| `specs/NNN-slug/verify.md` | Informe de verificación | `/sdd-verify` |
| `specs/NNN-slug/notes.md` | Contexto aparcado al cambiar de feature; indicaciones técnicas de las fuentes | `/sdd-switch`, `/sdd-new` |
| `specs/NNN-slug/fuentes/` | Copia intacta de los archivos de requisitos originales | `/sdd-new` |

## 2. Flujo y fases

```
constitution → specify → clarify → plan → tasks → implement → verify → done
 /sdd-constitution  /sdd-new  /sdd-clarify  /sdd-plan  /sdd-tasks  /sdd-implement  /sdd-verify
```

`fase` en STATE.md toma uno de esos valores.

**Gates de aprobación** (si `requireApprovalGates` es `true` en `.sdd/config.json`):
- No se pasa a `plan` sin `Estado: aprobada` en la cabecera de `spec.md`.
- No se pasa a `implement` sin `Estado: aprobado` en `plan.md` y `tasks.md`.
- La aprobación la da el usuario explícitamente; Claude la registra editando la cabecera. Si el comando se invoca sin aprobación previa, muestra un resumen y pide confirmación.

## 3. Reglas de persistencia (obligatorias)

1. **Write-ahead**: antes de empezar cualquier unidad de trabajo (tarea, redacción de spec/plan), registra en `STATE.md` qué vas a hacer; en implementación, marca además la tarea `[~]` en `tasks.md`. Solo después, trabaja.
2. **Cierre inmediato**: al terminar una tarea → verificar → `[x]` → entrada en journal → `STATE.md` al día. Si `autoCommitPerTask` es `true` y hay repo git: commit local (nunca `push` sin que el usuario lo pida).
3. **Decisiones en el momento**: toda decisión no trivial va a `plan.md §Decisiones` o al journal cuando se toma.
4. **Descubrimientos** (gotchas, comandos que funcionan, hipótesis en curso, archivos clave) → `STATE.md §Contexto de trabajo`.
5. **Siguiente paso accionable** por alguien sin contexto. Bien: «Implementar T005: endpoint POST /login en src/api/auth.ts; falta validar email y test de 401». Mal: «seguir».
6. **Tareas pequeñas**: cada una cabe en un commit. Si crece, divídela en `tasks.md` antes de seguir.
7. **Documentos largos por partes**: escribe primero el esqueleto del archivo y ve rellenando secciones, para que lo parcial quede en disco.
8. **Fin de turno**: si editaste archivos, `STATE.md` debe quedar actualizado antes de terminar (el hook `Stop` lo exige).
9. **No borrar historia**: el journal es append-only; tareas descartadas se marcan `[-]` con motivo, no se borran.
10. **STATE.md corto** (< ~60 líneas): es un puntero, no un informe. El detalle va a specs/ y journal.

### Estados de tarea (`tasks.md`)

`[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada (con motivo) · `[-]` descartada (con motivo)

## 4. Reanudación tras interrupción

Al iniciar, reanudar, limpiar o compactar la sesión, el hook `SessionStart` inyecta automáticamente:
STATE.md, resumen de tareas de la feature activa, archivos editados desde el último checkpoint, cola del journal y estado de git.

Si ese contexto muestra una tarea `[~]` o **archivos editados sin checkpoint**, antes de cualquier trabajo nuevo aplica el procedimiento de `/sdd-resume`: comprobar el estado real del código, reconciliar `tasks.md` y `STATE.md`, y solo entonces continuar.
Nunca asumas que una tarea `[~]` está hecha ni la rehagas a ciegas: verifica.

## 5. Comandos

| Comando | Qué hace |
|---|---|
| `/sdd-constitution [cambios]` | Crea/actualiza los principios del proyecto |
| `/sdd-new <descripción \| ruta(s)>` | Nueva feature: carpeta + `spec.md`; con archivos, los copia a `fuentes/` e importa su contenido |
| `/sdd-clarify [foco]` | Preguntas para eliminar ambigüedad de la spec (persistiendo cada respuesta) |
| `/sdd-plan [preferencias]` | `plan.md` técnico verificado contra la constitución |
| `/sdd-tasks` | `tasks.md` con IDs, dependencias, cobertura y verificación por tarea |
| `/sdd-implement [T00X\|siguiente\|todas]` | Ejecuta tareas con checkpoint tras cada una |
| `/sdd-verify` | Verifica requisitos contra implementación → `verify.md` |
| `/sdd-status` | Resumen de solo lectura de todas las features |
| `/sdd-resume [continuar]` | Reconstruye el estado real tras un corte y continúa |
| `/sdd-checkpoint [nota]` | Guarda ahora todo el contexto en disco |
| `/sdd-switch <NNN\|slug>` | Cambia de feature activa aparcando el contexto de la actual |

## 6. Trabajo fuera del flujo

Cambios pequeños sin feature (typos, ajustes de config) no requieren spec. Si hay una feature activa, anota igualmente el cambio en el journal y actualiza STATE.md si afecta al siguiente paso.
Si una petición del usuario es en realidad una funcionalidad nueva, propón `/sdd-new` antes de programar.
