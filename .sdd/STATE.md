# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-despliegue-aws
fase: implement
tarea_actual: T014
estado_tarea: -

## Siguiente paso

T014: escribir .github/workflows/provision.yml (push a main; jobs test → package → provision en el orden de plan §4.3; concurrencia urban-alert-multimedia-aws; OIDC).

## Contexto de trabajo

- Terraform: wrapper `$SCRATCHPAD/tf` (podman hashicorp/terraform:1.16.5 + caché de proveedores en el volumen tf-plugin-cache). Lockfile: `init -backend=false` + `providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64`.
- Tests de stacks con `prevent_destroy`: solo `command = plan` + `mock_provider { override_during = plan }` (las runs apply se destruyen al final y prevent_destroy lo impide).
- Pruebas unitarias rápidas: imagen local `mm-unit` (python:3.13-slim + requirements-dev + zip/unzip/curl). `podman run --rm -v "$PWD":/w -w /w mm-unit pytest -q tests/unit`. Reconstruir si cambian los requirements.
- Numerada 002 porque el README cita specs/001-servicio-multimedia (no está versionada en el repo).

## Bloqueos / preguntas abiertas

- ninguno
