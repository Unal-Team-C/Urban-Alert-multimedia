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
