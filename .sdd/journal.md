# Journal SDD

<!-- Bitácora append-only: añade entradas AL FINAL, no reescribas las anteriores.
     Formato:
     ## AAAA-MM-DD · <feature o "general"> · <evento>
     - detalle (qué, por qué, archivos, verificación)
     Las horas exactas de cada edición/checkpoint quedan en .sdd/activity.log. -->

## 2026-09-24 · general · Arnés SDD instalado
- Hooks (SessionStart, PostToolUse, PreCompact, Stop), 11 comandos /sdd-*, protocolo, plantillas e instalador.
- Probado: rastreo de ediciones, bloqueo en Stop, checkpoint vía STATE.md, reinyección de contexto, instalación/fusión en otro proyecto.

## 2026-10-11 · 002-despliegue-aws · Creada spec
- Desde la descripción del usuario: desplegar Multimedia en AWS (Lambda de imagen en la red de urban-alert-plataforma, rutas en su gateway, S3 + CloudFront, DocumentDB), Terraform, workflows Provision (push a main) y Deprovision (manual con confirmación).
- Decisiones del usuario: DocumentDB para metadatos (servicios nativos de AWS); flujo SDD completo.
- "Al aprobar un PR" se interpreta como al integrarlo (push a main): el rol OIDC solo confía en refs/heads/main.
- 2 clarificaciones abiertas: conservación de imágenes al desaprovisionar; ciclo de vida QAS-08.

## 2026-10-11 · 002-despliegue-aws · Clarificación 1
- Imágenes al desaprovisionar: se conservan (opción b). Se conserva también CloudFront para que las imageUrl no cambien (RF-017). Restaurar la copia de DocumentDB queda manual y documentado.

## 2026-10-11 · 002-despliegue-aws · Clarificación 2 · spec aclarada
- QAS-08: S3 Intelligent-Tiering desde el día 0, sin niveles de archivo opcionales (comparado con Glacier IR: sin cargo por lectura ni mínimo de 90 días). RF-008.
- Spec en estado "aclarada", sin marcadores pendientes; falta la aprobación del usuario.

## 2026-10-11 · 002-despliegue-aws · Spec aprobada
- Aprobada por el usuario. Indicación para el plan: actualizar las rutas/configuración del servicio para usar los servicios de la nube (S3, CloudFront, DocumentDB, gateway) y decidir el orden en que se levantan los servicios.

## 2026-10-11 · 002-despliegue-aws · Plan redactado (borrador)
- 4 stacks: almacen (S3+CloudFront, persistente, prevent_destroy) → base (ECR, DocumentDB db.t4g.medium, secreto con URI, SG, roles, logs) → imagen (SHA, --provenance=false) → servicio (Lambda API + Lambda init) → init (aws lambda invoke) → rutas (AWS_PROXY 2.0) → humo. Deprovision: rutas → servicio → base (allow_destroy + copia final); almacen intacto.
- Código: MONGODB_URI_SECRET_ARN + resolve_uri (Secrets Manager), handler de init, CA de DocumentDB en la imagen. Sin AWS_ENDPOINT_URL_S3; PUBLIC_IMAGE_BASE_URL = CloudFront.
- D-008: concurrencia reservada 10 × pool 2 (≤ 40 conexiones); exige límite de cuenta ≥ 20. D-011: nueva política de bootstrap github-actions-urban-alert-multimedia (Lambda, CloudFront, PassRole a Lambda, logs /aws/lambda).
- Coste encendido ~56–57 USD/mes (DocumentDB); desaprovisionado, céntimos. Investigación en research.md.

## 2026-10-11 · 002-despliegue-aws · Revisión 2: .zip, sin entorno local
- El usuario prefiere subir el código a Lambda como .zip (sin ECR) y declara que el entorno local ya no es necesario.
- Spec: RF-001 cambiado (runtime python3.13 + .zip), RF-016 eliminado (los archivos locales se quedan, sin mantenimiento), RF-009/RF-010/RNF-008/HU-1 #3 ajustados.
- Plan revisado: sin ECR; scripts/build-lambda-zip.sh determinista (medido: 44 MB / 20 MB); job package con artefacto; D-010 reescrita, D-014 nueva (solo pruebas unitarias en CI). Orden: tests → zip → plataforma → almacen → base → servicio → init → rutas → humo.

## 2026-10-11 · 002-despliegue-aws · Plan aprobado
- Usuario: D-002 (usuario maestro) confirmado por ser prototipo; D-014 ok.
- D-008 cambiado: el usuario es nuevo y no puede ver la consola → se asume límite de cuenta de 10 ejecuciones concurrentes; sin concurrencia reservada (-1), pool 2 → ≤ 40 conexiones.
- D-011: verificadas las 3 políticas actuales del rol (copiadas por el usuario). Faltan Lambda, CloudFront, PassRole a lambda.amazonaws.com y logs /aws/lambda/urban-alert-*. JSON en el Anexo A del plan.
- Plan marcado "aprobado".

## 2026-10-11 · 002-despliegue-aws · tasks.md generado: 17 tareas
- Preparación 2 (política de bootstrap, .gitignore), Pruebas 2 (resolve_uri, handler init), Núcleo 8 (código 2, zip 1, stacks almacen/base×2/servicio/rutas), Integración 3 (scripts, provision.yml, deprovision.yml), Pulido 2 (README/inventario, validación completa).

## 2026-10-11 · 002-despliegue-aws · Corrección de la política (Anexo A)
- Eliminado `cloudfront:CreateDistributionWithTags`: el editor de IAM no la reconoce. Crear la distribución con etiquetas se autoriza con `cloudfront:CreateDistribution` + `cloudfront:TagResource`, que ya están en la política.

## 2026-10-11 · 002-despliegue-aws · tasks.md aprobado
- Aprobado por el usuario; empieza la implementación por T001.

## 2026-10-11 · 002-despliegue-aws · T001 hecha
- infra/bootstrap/github-multimedia-policy.json (Anexo A del plan, sin CreateDistributionWithTags) e infra/bootstrap/README.md (recursos compartidos, crear/adjuntar/actualizar la política, límite de concurrencia supuesto de 10, cómo comprobar).
- Verificado: `python3 -m json.tool` válido; JSON idéntico al Anexo A.

## 2026-10-11 · 002-despliegue-aws · T002 hecha
- .gitignore: build/, .terraform/, planes de Terraform. Verificado con git check-ignore.

## 2026-10-11 · 002-despliegue-aws · T003 hecha
- tests/unit/test_metadata_uri.py (4 pruebas: sin ARN, con ARN y caché, error no cacheado → MetadataStoreError, MetadataStore perezoso) y 2 asserts nuevos en test_config_logging.py.
- Verificado: fallan solo las nuevas (ImportError de resolve_uri; AttributeError de mongodb_uri_secret_arn); 50 existentes en verde.

## 2026-10-11 · 002-despliegue-aws · T004 hecha
- tests/unit/test_init_handler.py: el handler crea objectKey_unique sobre una colección falsa y no llama a client_for (S3).
- Verificado: falla con AttributeError (handler no existe).

## 2026-10-11 · 002-despliegue-aws · T005 hecha
- app/config.py: mongodb_uri_secret_arn. app/storage/metadata.py: secrets_client y resolve_uri (lru_cache sobre Settings congelado; fallos no cacheados → MetadataStoreError), collection_for usa resolve_uri, MetadataStore resuelve la colección en cada uso (un fallo del secreto da 503 y no 500 al construir la dependencia).
- Firma de MetadataStore(settings, uri=None) sin cambios: las pruebas de integración siguen siendo compatibles.
- Verificado: 56 unitarias en verde; solo falla test_init_handler (T006).

## 2026-10-11 · 002-despliegue-aws · T006 hecha
- app/admin/init_resources.py: handler(event, context) crea los índices (sin S3) y devuelve sus nombres; ensure_indexes devuelve la lista. main() local sin cambios.
- Verificado: 57 unitarias en verde.
