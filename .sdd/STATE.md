# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-despliegue-aws
fase: implement
tarea_actual: T002
estado_tarea: hecha

## Siguiente paso

T002: añadir build/ y .terraform/ a .gitignore; verificar con git check-ignore build/x infra/base/.terraform.

## Contexto de trabajo

- Numerada 002 porque el README cita specs/001-servicio-multimedia (no está versionada en el repo).

## Bloqueos / preguntas abiertas

- ninguno
