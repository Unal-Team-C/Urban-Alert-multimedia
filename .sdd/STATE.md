# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-despliegue-aws
fase: implement
tarea_actual: T003
estado_tarea: -

## Siguiente paso

T003: escribir tests/unit/test_metadata_uri.py y ampliar test_config_logging.py (MONGODB_URI_SECRET_ARN); deben fallar solo por falta de resolve_uri.

## Contexto de trabajo

- Numerada 002 porque el README cita specs/001-servicio-multimedia (no está versionada en el repo).

## Bloqueos / preguntas abiertas

- ninguno
