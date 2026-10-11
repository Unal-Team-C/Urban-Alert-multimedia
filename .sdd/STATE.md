# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-despliegue-aws
fase: implement
tarea_actual: T004
estado_tarea: -

## Siguiente paso

T004: escribir tests/unit/test_init_handler.py (handler crea objectKey_unique en colección falsa, no usa S3).

## Contexto de trabajo

- Pruebas unitarias rápidas: imagen local `mm-unit` (python:3.13-slim + requirements-dev + zip/unzip/curl). `podman run --rm -v "$PWD":/w -w /w mm-unit pytest -q tests/unit`. Reconstruir si cambian los requirements.
- Numerada 002 porque el README cita specs/001-servicio-multimedia (no está versionada en el repo).

## Bloqueos / preguntas abiertas

- ninguno
