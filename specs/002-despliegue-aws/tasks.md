# Tareas: Despliegue del Servicio Multimedia en AWS

- **Plan**: ./plan.md
- **Estado**: aprobado <!-- borrador | aprobado -->

Leyenda: `[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada · `[-]` descartada · `[P]` paralelizable

Formato de cada tarea (una línea):
`- [ ] T001 [P] Descripción imperativa — archivos: ruta/a, ruta/b — cubre: RF-001 — verifica: <comando o criterio observable>`

Dependencias: cada fase depende de la anterior; dentro de una fase se ejecuta en orden salvo `[P]`.
Dependencias explícitas: añadir `— depende: T00X`.

Atajos de verificación (Podman, desde la raíz del repo; ver plan §2):
- `PYTEST` = `podman run --rm -v "$PWD":/w -w /w docker.io/library/python:3.13-slim sh -c "pip install -q -r requirements-dev.txt && pytest tests/unit"`
- `TF <stack>` = `hashicorp/terraform:1.16.5` con `-chdir=infra/<stack>`: `init -backend=false` + `validate` + `test`, y `fmt -check -recursive infra`
- `LINT` = actionlint 1.7.7 sobre el repo + shellcheck v0.10.0 sobre `scripts/*.sh`

## Fase 1: Preparación

- [x] T001 Versionar la política de bootstrap y documentar los pasos manuales (crear la política, adjuntarla al rol, límite de concurrencia supuesto de 10) — archivos: infra/bootstrap/github-multimedia-policy.json, infra/bootstrap/README.md — cubre: RF-013, RF-015 — verifica: `python3 -m json.tool infra/bootstrap/github-multimedia-policy.json` sin errores y contenido idéntico al Anexo A del plan
- [x] T002 [P] Ignorar `build/` y `.terraform/` en git — archivos: .gitignore — cubre: RF-009 — verifica: `git check-ignore build/x infra/base/.terraform` imprime ambas rutas

## Fase 2: Pruebas (antes del código)

- [x] T003 Escribir pruebas unitarias de `MONGODB_URI_SECRET_ARN` y `resolve_uri` (sin ARN usa `MONGODB_URI`; con ARN lee el secreto con un cliente simulado y lo cachea; un error del cliente lanza `MetadataStoreError`) — archivos: tests/unit/test_metadata_uri.py, tests/unit/test_config_logging.py — cubre: RF-004 — verifica: `PYTEST` falla solo en las pruebas nuevas (ImportError/AttributeError de `resolve_uri`)
- [x] T004 [P] Escribir prueba unitaria del handler de init (crea `objectKey_unique` sobre una colección falsa, no crea cliente S3, devuelve los índices) — archivos: tests/unit/test_init_handler.py — cubre: RF-007 — verifica: `PYTEST` falla solo en esa prueba (`handler` no existe)

## Fase 3: Núcleo

### Código

- [x] T005 Implementar `mongodb_uri_secret_arn` y `resolve_uri` (Secrets Manager con `lru_cache`, error → `MetadataStoreError`) y usarlo en `collection_for` — archivos: app/config.py, app/storage/metadata.py — cubre: RF-004 — depende: T003 — verifica: `PYTEST` en verde
- [x] T006 Implementar `handler(event, context)` de init (solo índices; `main()` sin cambios) — archivos: app/admin/init_resources.py — cubre: RF-007 — depende: T004 — verifica: `PYTEST` en verde
- [x] T007 Escribir el script del paquete .zip determinista (wheels manylinux2014_x86_64/cp313, `--no-compile`, `app/` sin `__pycache__`, CA de DocumentDB en `certs/`, fechas fijas, orden estable, falla si > 50 MB, imprime tamaño y sha256) — archivos: scripts/build-lambda-zip.sh — cubre: RF-001, RNF-003 — depende: T005, T006 — verifica: dos ejecuciones seguidas en `python:3.13-slim` dan el mismo sha256; tamaño < 50 MB; `unzip -l` contiene `app/main.py`, `certs/global-bundle.pem`, `pydantic_core/`

### Terraform (cada stack con sus pruebas `mock_provider`; lockfile para linux_amd64, linux_arm64 y darwin_arm64)

- [x] T008 Crear el stack `almacen`: bucket privado (Block Public Access ×4, propietario, SSE-S3, `prevent_destroy`), política (solo la distribución por `AWS:SourceArn` + denegar sin TLS), ciclo de vida (Intelligent-Tiering día 0, abortar multipart a 7 días), OAC, CloudFront (`redirect-to-https`, `CachingOptimized`, `PriceClass_100`, `prevent_destroy`), salidas `bucket_name`, `bucket_arn`, `cdn_url` — archivos: infra/almacen/* — cubre: RF-002, RF-008, RF-009, RF-017, RNF-001 — verifica: `TF almacen` en verde con los runs de §9 del plan
- [x] T009 Crear el stack `base`, parte de red y datos: SSM de la plataforma, SG `-lambda` y `-docdb`, subnet group, grupo de parámetros `docdb5.0` con `tls=enabled`, clúster (cifrado, 7 días, `deletion_protection = !allow_destroy`, copia final `-final-<suffix>`) + 1 instancia db.t4g.medium, `random_password`, secreto con la URI (TLS, CA, `replicaSet=rs0`, `retryWrites=false`, `recovery_window_in_days = 0`) — archivos: infra/base/{backend,versions,providers,variables,network,docdb,secrets,outputs}.tf, infra/base/terraform.tfvars, infra/base/tests/base.tftest.hcl — cubre: RF-003, RF-004, RF-006, RF-012, RNF-001, RNF-007 — verifica: `TF base` en verde (runs de protección, red, TLS, secreto, `allow_destroy`)
- [x] T010 Completar `base` con roles e IAM en línea (API: `s3:PutObject`/`DeleteObject` en su bucket, `GetSecretValue` del secreto, ENI, logs de su grupo; init: igual sin S3) y grupos de logs de 30 días; leer `almacen` con `terraform_remote_state` — archivos: infra/base/{iam,logs}.tf, infra/base/tests/base.tftest.hcl — cubre: RNF-001, RNF-008 — depende: T008, T009 — verifica: `TF base` en verde con los runs de mínimo privilegio (init sin S3; API sin `s3:*`)
- [ ] T011 Crear el stack `servicio`: Lambda del API y de init (`python3.13`, x86_64, `filename`/`source_code_hash` desde `var.paquete_zip`, 512 MB/15 s y 60 s, VPC, variables de §7.2 del plan, `MONGODB_MAX_POOL_SIZE = 2`, `concurrencia_reservada = -1`, etiqueta `Commit`), con salidas de nombres y ARN — archivos: infra/servicio/* — cubre: RF-001, RF-002, RF-004, RF-006, RNF-002, RNF-004, RNF-008 — depende: T010 — verifica: `TF servicio` en verde (sin `AWS_ENDPOINT_URL_S3` ni `MONGODB_URI`; handlers; subredes y SG de `base`; `PUBLIC_IMAGE_BASE_URL` = CloudFront)
- [ ] T012 Crear el stack `rutas`: integración `AWS_PROXY` 2.0, las 2 rutas `NONE`, `aws_lambda_permission` limitado a `/*/*/api/v1/multimedia/*`, salida `gateway_url` desde SSM — archivos: infra/rutas/* — cubre: RF-005, RF-006 — depende: T011 — verifica: `TF rutas` en verde (exactamente 2 rutas, sin `$default`, `source_arn` acotado)

## Fase 4: Integración

- [ ] T013 [P] Copiar `check-platform.sh` de Geoespacial y escribir `run-init.sh` (invoke con `--log-type Tail`, falla con `FunctionError` mostrando el log) y `smoke-gateway-multimedia.sh` (metadata de UUID aleatorio → 404, `/docs` → 404, CloudFront `/` → 403, URL directa de S3 → 403) — archivos: scripts/check-platform.sh, scripts/run-init.sh, scripts/smoke-gateway-multimedia.sh — cubre: RF-007, RF-010, RF-005 — verifica: `LINT` sin avisos en los scripts; `bash -n` de cada uno
- [ ] T014 Escribir `provision.yml` (push a `main`; jobs `test` → `package` (artefacto) → `provision`: plataforma → almacen → base → servicio (`-var paquete_zip`, `-var commit`) → init → rutas → humo → resumen; concurrencia `urban-alert-multimedia-aws`; OIDC con `AWS_ROLE_ARN`/`AWS_REGION`) — archivos: .github/workflows/provision.yml — cubre: RF-010, RF-013, RF-014, RNF-005, RNF-008 — depende: T007, T012, T013 — verifica: `LINT` sin avisos; los pasos siguen el orden de §4.3 del plan
- [ ] T015 Escribir `deprovision.yml` (`workflow_dispatch` con `confirm` = `urban-alert-multimedia` y comprobación de `main`; rutas → servicio (zip vacío) → base (`allow_destroy` + `final_snapshot_suffix=run_id`, después destroy); nunca `almacen`; stacks vacíos → aviso; resumen con la copia final y el aviso de que S3/CloudFront siguen) — archivos: .github/workflows/deprovision.yml — cubre: RF-011, RF-012, RF-013, RF-014, RF-017 — depende: T014 — verifica: `LINT` sin avisos; `grep -c almacen` solo en el resumen

## Fase 5: Pulido

- [ ] T016 Actualizar el README (despliegue en AWS: arquitectura, orden de levantamiento y desmontaje, workflows, rutas publicadas, configuración en la nube, tabla de costes, restauración de la copia de DocumentDB, diferencia 403/404; lo local se marca como no mantenido) y crear `infra/INVENTARIO.md` — archivos: README.md, infra/INVENTARIO.md — cubre: RF-015, RNF-006 — verifica: cada sección de RF-015 presente; sin valores secretos (`grep -iE "password|secret_string"` solo en textos explicativos)
- [ ] T017 Validación completa local antes de entregar (`PYTEST`, `TF` de los 4 stacks, `fmt`, `LINT`, doble build del .zip) y lista de comprobaciones en AWS para `/sdd-verify` — archivos: specs/002-despliegue-aws/notes.md — cubre: RNF-003, RNF-004, RNF-005 — verifica: todos los comandos en verde; la lista cubre HU-1…HU-4 y el ciclo Deprovision → Provision (HU-2 #8)

## Correcciones de verificación

<!-- /sdd-verify añade aquí tareas si detecta fallos -->

## Cobertura

| Requisito | Tareas |
|---|---|
| RF-001 | T007, T011 |
| RF-002 | T008, T011 |
| RF-003 | T009 |
| RF-004 | T003, T005, T009, T011 |
| RF-005 | T012, T013 |
| RF-006 | T009, T011, T012 |
| RF-007 | T004, T006, T013 |
| RF-008 | T008 |
| RF-009 | T002, T008–T012 |
| RF-010 | T013, T014 |
| RF-011 | T015 |
| RF-012 | T009, T015 |
| RF-013 | T001, T014, T015 |
| RF-014 | T014, T015 |
| RF-015 | T001, T016 |
| RF-016 | Eliminado |
| RF-017 | T008, T015 |
| RNF-001 | T008, T009, T010 |
| RNF-002 | T011 |
| RNF-003 | T007, T017 |
| RNF-004 | T011, T017 |
| RNF-005 | T014, T017 |
| RNF-006 | T016 |
| RNF-007 | T009 |
| RNF-008 | T010, T011, T014 |
