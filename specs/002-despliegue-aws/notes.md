# Notas: 002-despliegue-aws

## Indicaciones técnicas para /sdd-plan

Tecnologías impuestas por el usuario: Terraform, GitHub Actions, S3, DocumentDB, la función Lambda actual. Patrón de referencia: `Unal-Team-C/urban-alert-geoespacial` (spec 002) y `urban-alert-plataforma` (spec 001, docs/integracion.md).

- Stacks (como Geoespacial): `infra/base` (ECR, S3 + CloudFront OAC + ciclo de vida, DocumentDB + SG + subnet group, secreto, roles, logs) → build/push de la imagen (`--provenance=false`, Lambda rechaza índices OCI con atestaciones) → `infra/servicio` (Lambda en VPC + función init + integración AWS_PROXY payload 2.0 + rutas + `aws_lambda_permission`). Estado `multimedia/base.tfstate`, `multimedia/servicio.tfstate`.
- Contrato de la plataforma: SSM `/urban-alert/plataforma/{vpc-id,subredes-privadas,api-id,api-execution-arn,api-endpoint}`. La plataforma ya tiene NAT (Secrets Manager) y endpoint de gateway S3.
- DocumentDB: TLS obligatorio → `global-bundle.pem` de `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem` en la imagen; URI con `tls=true&tlsCAFile=...&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false`. Clase mínima db.t4g.medium (~0,07–0,08 USD/h). Deletion protection solo se quita en Deprovision; copia final con sufijo `run_id` (como Geoespacial).
- Secreto: Geoespacial usa `random_password` en el estado (cifrado) y `aws_secretsmanager_secret` con `recovery_window_in_days = 0`. Evitar `manage_master_user_password`: rota cada 7 días y la función cachea el cliente.
- Cambio de código mínimo: si existe `MONGODB_URI_SECRET_ARN`, la URI se lee de Secrets Manager (cacheada por proceso); local sigue con `MONGODB_URI`. `init_resources` necesita un handler Lambda que solo cree índices (bucket y política los gestiona Terraform).
- Permisos que faltan en el rol compartido (políticas actuales: `github-actions-urban-alertPolicy`, `-terraform`, `-platform`): `lambda:*` sobre `function:urban-alert-*`, `cloudfront:*` (distribución + OAC), `iam:PassRole` a `lambda.amazonaws.com`, logs `/aws/lambda/urban-alert-*`, `iam:AttachRolePolicy` (o usar política en línea para ENI de VPC). S3 `urban-alert-*`, `rds:*`, secretos `urban-alert-*`, ECR `urban-alert-*`, SG ya están cubiertos.
- Concurrencia reservada: la cuenta puede tener límite 10 (no se puede reservar). Variable con defecto sin reserva; documentar el presupuesto de conexiones.
- Validación local con Podman, igual que la plataforma (fmt, validate, test con mock_provider, actionlint, shellcheck).

## Validación local (T017, 2026-10-11)

| Comprobación | Resultado |
|---|---|
| `pytest tests/unit` (python:3.13) | 57 pasan |
| `terraform init -lockfile=readonly` + `validate` + `test` | almacen 5/5, base 10/10, servicio 6/6, rutas 3/3 |
| `terraform fmt -check -recursive infra` | ok |
| actionlint 1.7.7, shellcheck v0.10.0 | sin avisos |
| `scripts/build-lambda-zip.sh` dos veces | idéntico (sha256 `ad71e946…`), 21,3 MB; importa en python:3.13 amd64 |

## Comprobaciones en AWS para /sdd-verify

Requisito previo: política `github-actions-urban-alert-multimedia` adjunta al rol (infra/bootstrap/README.md) y plataforma aprovisionada.

1. **HU-1 #1, RF-010, MS-001**: integrar en `main` → Provision en verde. Los pasos van en el orden de plan §4.3; el resumen muestra la URL del gateway, la URL del bucket de imágenes y el commit. Anotar la duración del primer Provision (< 30 min).
2. **HU-3 #1–#3, RNF-004**: `curl -F image=@foto-3.5MB.jpg <gateway>/api/v1/multimedia/images` → `201` en < 15 s (también en frío). El `imageUrl` se abre en un navegador por HTTPS. `exiftool` sobre la descarga: sin GPS ni EXIF salvo la orientación.
3. **HU-3 #2, #4, #5**: `GET …/images/{imageId}/metadata` → `200`; con un UUID inexistente → `404`; HEIC → `415`; > 3 670 016 bytes → `413`; `lat` sin `lon` → `400`; `GET …/docs` → `404`.
4. **HU-4 #1, RNF-001** (D-015): `https://<bucket>.s3.us-east-2.amazonaws.com/` (listado) → `403`; una clave inexistente → `403`; `http://` → denegado; `curl -X PUT` anónimo → `403`.
5. **HU-4 #2–#3**: en la consola o con la CLI, DocumentDB sin acceso público, SG de entrada solo desde `urban-alert-multimedia-lambda`, parámetro `tls=enabled`. Variables de la Lambda sin `MONGODB_URI` ni la contraseña.
6. **HU-1 #3, RNF-003, RNF-005**: relanzar Provision sobre el mismo commit (Re-run all jobs) → los cuatro stacks dicen `No changes` y el job termina en < 15 min.
7. **HU-1 #4, RF-014**: lanzar Deprovision mientras corre Provision → queda en cola.
8. **HU-2 #2**: Deprovision con una confirmación incorrecta → falla sin borrar nada.
9. **HU-2 #1, #3, #7, #8, RF-011, RF-017, MS-002**: subir una imagen y guardar su `imageUrl` → Deprovision → resumen con la copia `urban-alert-multimedia-final-<run_id>` → el `imageUrl` sigue abriendo → `GET …/metadata` → `404` del gateway (ruta eliminada). Sin funciones, clúster ni secreto de Multimedia en la cuenta.
10. **HU-2 #4, #5**: Deprovision otra vez → "vacío" en los tres stacks, sin error. Push a `main` → el servicio vuelve; el `imageUrl` antiguo sigue funcionando (sus metadatos, solo tras restaurar la copia: README).
