# Semaphore UI

<!-- Describe aquí el proyecto: objetivo, stack y comandos de build/test. -->

Este proyecto se desarrolla con **desarrollo guiado por especificaciones (SDD)** usando Claude Code y un arnés con persistencia en disco: si la sesión se corta en cualquier momento (cierre de la app, crash, compactación del contexto), el trabajo se retoma exactamente donde quedó.

> Referencia técnica del arnés (hooks, configuración, instalación en otros proyectos): [.sdd/README.md](../.sdd/README.md)
> Reglas que sigue Claude: [.sdd/PROTOCOL.md](../.sdd/PROTOCOL.md)

---

## Primeros pasos

### 1. Abre una sesión nueva

Los hooks se cargan al iniciar la sesión. Abre una sesión de Claude Code en la carpeta del proyecto y comprueba que al principio del contexto aparece el bloque **«SDD HARNESS»** con el estado actual.

### 2. Describe el proyecto (recomendado)

En [CLAUDE.md](../CLAUDE.md), por encima de la sección SDD, añade en pocas líneas qué es el proyecto, qué tecnologías usa y los comandos de compilación y tests. Claude lo lee en cada sesión.

### 3. Define los principios del proyecto (opcional)

```
/sdd-constitution
```

Si no hay código todavía, Claude te preguntará por tecnologías, forma de probar, reglas de seguridad, etc. También puedes darle pistas directamente:

```
/sdd-constitution Frontend en Vue 3 + TypeScript, tests con Vitest, sin dependencias nuevas sin justificar
```

Los principios quedan en `.sdd/constitution.md` y todo plan técnico se contrasta con ellos. Si te saltas este paso, los planes no se validarán contra ningún principio.

### 4. Crea tu primera funcionalidad

```
/sdd-new Pantalla de login con usuario y contraseña, bloqueo tras 5 intentos fallidos
```

Crea `specs/001-<nombre>/spec.md` con **qué** se construye y **por qué**, sin entrar en el cómo.

**Desde un archivo**: si ya tienes los requisitos escritos, pasa la ruta en lugar de la descripción:

```
/sdd-new docs/requisitos-login.md
/sdd-new docs/requisitos.pdf docs/mockup.png solo la parte de administración
```

- Acepta Markdown/texto, PDF, imágenes y carpetas (y Word/Excel si la skill correspondiente está disponible). El texto que acompañe a las rutas se toma como indicaciones.
- El original se copia sin tocar en `specs/NNN-<nombre>/fuentes/` y cada requisito de la spec indica de qué parte de la fuente sale.
- Claude respeta el contenido del archivo (no inventa ni descarta requisitos); lo contradictorio o incompleto queda marcado para `/sdd-clarify`.
- Los detalles técnicos que traiga el archivo no van a la spec: se guardan en `notes.md` y los usa `/sdd-plan`.
- Si el archivo contiene varias funcionalidades independientes, Claude propone dividirlas en varias specs.

### 5. Recorre las fases aprobando cada una

| Paso | Comando | Tu papel |
|---|---|---|
| Aclarar dudas | `/sdd-clarify` | Responder las preguntas (llegan de una en una, con una opción recomendada) |
| Aprobar la spec | escribe «apruebo la spec» | Claude la marca como `aprobada` |
| Plan técnico | `/sdd-plan` | Revisar las decisiones y escribir «apruebo el plan» |
| Tareas | `/sdd-tasks` | Revisar la lista y escribir «apruebo las tareas» |
| Implementar | `/sdd-implement` (una tarea) o `/sdd-implement todas` | Revisar el resultado; se hace un commit por cada tarea verificada |
| Verificar | `/sdd-verify` | Leer `verify.md`; si algo falla, se crean tareas de corrección |

Si prefieres avanzar sin aprobar cada paso, pon `"requireApprovalGates": false` en [.sdd/config.json](../.sdd/config.json).

```
constitution → specify → clarify → plan → tasks → implement → verify → done
```

---

## Si la sesión se corta

Abre una sesión nueva y escribe:

```
/sdd-resume continuar
```

El estado ya se carga solo al abrir la sesión. Este comando además comprueba en el código qué quedó a medias, pone al día las tareas y el estado, y continúa desde ahí.

Qué garantiza que no se pierda nada:

- Antes de empezar cada tarea, Claude la marca `[~]` y anota en `.sdd/STATE.md` qué va a hacer.
- Al terminarla: la marca `[x]`, escribe en `.sdd/journal.md`, actualiza `STATE.md` y hace un commit local.
- Cada edición de archivo queda registrada automáticamente en `.sdd/activity.log`, aunque Claude no llegue a anotarla.
- Claude no puede terminar un turno con ediciones sin guardar el estado.

---

## Comandos

| Comando | Para qué |
|---|---|
| `/sdd-constitution [cambios]` | Crear o actualizar los principios del proyecto |
| `/sdd-new <descripción \| ruta>` | Nueva funcionalidad y su especificación, desde texto o desde archivos |
| `/sdd-clarify [foco]` | Resolver ambigüedades de la spec con preguntas |
| `/sdd-plan [preferencias]` | Plan técnico |
| `/sdd-tasks` | Lista de tareas ejecutables |
| `/sdd-implement [T00X\|siguiente\|todas]` | Implementar tareas con checkpoint tras cada una |
| `/sdd-verify` | Verificar la implementación contra la spec |
| `/sdd-status` | Ver dónde estás y qué toca después (no modifica nada) |
| `/sdd-resume [continuar]` | Retomar tras una interrupción |
| `/sdd-checkpoint [nota]` | Guardar todo el contexto ya mismo (antes de cerrar o de un cambio arriesgado) |
| `/sdd-switch <NNN\|nombre>` | Cambiar de funcionalidad sin perder el contexto de la actual |

**Cambios pequeños** (typos, ajustes de configuración) se piden directamente, sin spec. Si pides algo que en realidad es una funcionalidad nueva, Claude te propondrá pasar primero por `/sdd-new`.

---

## Dónde está cada cosa

```
CLAUDE.md                  instrucciones permanentes para Claude (importa el protocolo)
specs/NNN-nombre/          spec.md · plan.md · tasks.md · verify.md de cada funcionalidad
.sdd/STATE.md              dónde estamos y cuál es el siguiente paso
.sdd/journal.md            bitácora de avances y decisiones
.sdd/constitution.md       principios del proyecto
.sdd/config.json           configuración del arnés
.claude/                   hooks y comandos de Claude Code
```

## Configuración rápida (`.sdd/config.json`)

| Clave | Por defecto | Efecto |
|---|---|---|
| `requireApprovalGates` | `true` | Spec, plan y tareas requieren tu aprobación antes de avanzar |
| `autoCommitPerTask` | `true` | Commit local tras cada tarea verificada (nunca hace `push`) |
| `enforceCheckpointOnStop` | `true` | Obliga a guardar el estado al final de cada turno con ediciones |
