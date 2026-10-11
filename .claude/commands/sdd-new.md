---
description: Iniciar una nueva feature SDD y redactar su especificación (spec.md), desde una descripción o desde archivos
argument-hint: "<descripción> | <ruta/al/archivo> [más archivos o indicaciones]"
---

Entrada: $ARGUMENTS

Si la entrada está vacía, pide al usuario una descripción o la ruta de un archivo y detente. Sigue `.sdd/PROTOCOL.md`.

## 0. Determinar el origen

- **Archivos**: cada fragmento de la entrada que sea una ruta existente (relativa al proyecto o absoluta, con o sin `@` delante) es un archivo fuente. Si es una carpeta, sus archivos legibles lo son. El resto del texto son indicaciones adicionales.
  - Formatos: texto/Markdown, PDF, imágenes (se leen directamente); `.docx`/`.xlsx`/`.pptx` con la skill correspondiente si está disponible; si no se puede leer, dilo y pide otro formato.
  - Una ruta que no existe → avisa y pregunta; no la trates como descripción.
- **Descripción**: si no hay archivos, la entrada es la descripción de la funcionalidad.

Un archivo puede contener **una** funcionalidad o **varias**. Si claramente contiene varias independientes (secciones o épicas separadas), propón al usuario dividirlas en varias features (una carpeta cada una) y confirma antes de crearlas.

## 1. Estado previo

Lee `.sdd/STATE.md`. Si hay una feature activa no terminada (fase distinta de `done`), avisa y confirma con el usuario antes de cambiar. Si confirma, aparca su contexto como en `/sdd-switch` (copia `Contexto de trabajo` y `Bloqueos` al final de `specs/<anterior>/notes.md`).

## 2. Carpeta

Siguiente número `NNN` (3 dígitos) según las carpetas existentes en `specs/`; slug kebab-case ASCII de 2-4 palabras → `specs/NNN-slug/`.

## 3. Write-ahead

ANTES de redactar, actualiza `STATE.md`: `feature_activa: NNN-slug`, `fase: specify`, `tarea_actual: -`, `estado_tarea: -`, siguiente paso «Redactar spec.md de NNN-slug a partir de: <descripción resumida o rutas de los archivos>». Limpia `Contexto de trabajo` y `Bloqueos`.

## 4. Conservar las fuentes (solo si hay archivos)

Copia cada archivo fuente a `specs/NNN-slug/fuentes/` sin modificarlo (trazabilidad: la spec debe poder contrastarse siempre con el original). En archivos binarios grandes (> ~10 MB) no copies: anota su ruta en `fuentes/ORIGEN.md`.

## 5. Redactar `specs/NNN-slug/spec.md`

Desde `.sdd/templates/spec.md`, escribiendo primero el esqueleto y rellenando por secciones:

- **Qué y por qué, nunca cómo**: sin lenguajes, frameworks, APIs ni estructura de código.
- Requisitos numerados (`RF-001`, `RNF-001`), cada uno testeable y sin ambigüedad.
- Historias de usuario priorizadas con criterios Dado/Cuando/Entonces y casos borde.
- Supón lo razonable y documéntalo en *Supuestos*. Solo lo que cambie alcance, seguridad o UX de forma relevante y no pueda suponerse → `[NEEDS CLARIFICATION: pregunta]` (máx. 3).
- Respeta `.sdd/constitution.md`.

Si el origen son archivos (**modo importación**):

- **Fidelidad**: conserva el contenido y la intención del original; no inventes requisitos ni descartes ninguno. Reorganiza en las secciones de la plantilla y reformula solo para hacer cada requisito testeable.
- `Entrada original:` → rutas de las fuentes (en `fuentes/`) más las indicaciones del usuario.
- Cada requisito indica su procedencia: `- **RF-003**: … _(fuente: requisitos.pdf §2.1)_`.
- Si el archivo ya trae detalles de implementación (tecnologías, diseño), no los metas en la spec: resúmelos en `notes.md` bajo `## Indicaciones técnicas de la fuente` para usarlos en `/sdd-plan`.
- Contradicciones o huecos del original → `[NEEDS CLARIFICATION]` (aquí el límite de 3 no aplica si el original tiene más; priorízalos).
- Si el archivo ya sigue la estructura de la plantilla, respétala y limítate a normalizar y completar.

## 6. Autorrevisión

Checklist del final de la spec; corrige lo que falle y marca las casillas. En modo importación, comprueba además que cada requisito del original tiene su RF/RNF o está en *Fuera de alcance* con motivo.

## 7. Persistencia

Journal («Creada spec NNN-slug desde <descripción | archivos>: resumen»); `STATE.md` con `fase: clarify` si hay marcadores o `fase: specify` si no, y siguiente paso.

## 8. Informar

Ruta, resumen en 3-5 líneas, preguntas abiertas y, si hubo importación, qué se reinterpretó o quedó fuera. Siguiente: `/sdd-clarify` si hay dudas; si no, que revise y apruebe la spec para `/sdd-plan`.
