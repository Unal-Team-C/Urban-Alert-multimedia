# Investigación: 002-despliegue-aws

Fecha: 2026-10-11. Precios de referencia de us-east-2 (iguales a us-east-1 en estos servicios); verificar en la calculadora de AWS antes de presentar costes cerrados.

## R-1. Base de metadatos nativa de AWS

| Opción | Cambios en el código | Coste encendido | Notas |
|---|---|---|---|
| **Amazon DocumentDB** (instancia db.t4g.medium) | Mínimos: TLS con el bundle de AWS y `retryWrites=false` | ~0,075 USD/h ≈ 55 USD/mes + 0,10 USD/GB-mes + 0,20 USD/millón de E/S | Compatible con la API de MongoDB 5.0 que usa pymongo (`insert_one`, `find_one`, `create_index`). Solo accesible dentro de la VPC |
| DynamoDB | Reescribir `app/storage/metadata.py`, pruebas y entorno local | ~0 | Descartada por el usuario: deja de ser MongoDB |
| MongoDB Atlas | Ninguno | Desde 0 (M0) | No es un servicio nativo de AWS (requisito del usuario) |

DocumentDB: TLS activado por defecto (parámetro de clúster `tls = enabled`), conexión con `replicaSet=rs0`, sin escrituras reintentables (`retryWrites=false`), CA en `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`. Una db.t4g.medium admite hasta 500 conexiones.

## R-2. Clase de almacenamiento (QAS-08)

Comparativa completa en la conversación del 2026-10-11 (resumen en spec §11). Elegido Intelligent-Tiering desde el día 0: niveles automáticos de 0,023 → 0,0125 (30 días sin acceso) → 0,004 USD/GB-mes (90 días), sin cargo por lectura ni mínimo de permanencia; 0,0025 USD por 1000 objetos/mes de monitorización. Los niveles de archivo opcionales (Archive / Deep Archive Access) **no** se activan: exigen restaurar antes de leer. Los objetos de menos de 128 KB no se transicionan (las reglas de ciclo de vida los omiten por defecto) y se quedan en Standard.

## R-3. Lectura pública de imágenes

- **CloudFront + Origin Access Control (OAC)** sobre un bucket privado con Block Public Access: la política del bucket solo concede `s3:GetObject` al principal `cloudfront.amazonaws.com` con `AWS:SourceArn` = la distribución. Sin `s3:ListBucket`, una clave inexistente responde `403` (no `404`).
- Coste: sin cargo por hora; 1 TB/mes y 10 M de peticiones incluidos en la capa gratuita permanente. `PriceClass_100` (Norteamérica y Europa) es la más barata.
- Alternativa descartada: bucket con lectura pública (como MinIO en local). Block Public Access lo impide por defecto y la spec exige bucket privado (RF-002).

## R-4. Secreto de la base

- Patrón de Geoespacial: `random_password` en el estado (bucket cifrado y privado) + `aws_secretsmanager_secret` con `recovery_window_in_days = 0` (se puede recrear tras desaprovisionar).
- `manage_master_user_password` (secreto gestionado por RDS/DocumentDB): descartado, rota cada 7 días y la función cachea el cliente de MongoDB durante la vida del contenedor.
- Acceso desde la función: por el NAT de la plataforma. Un endpoint de interfaz de Secrets Manager costaría ~7,3 USD/mes por zona (~14,6 USD con 2 zonas) para ahorrar una llamada por arranque en frío: descartado.

## R-5. Paquete de la función (revisión 2: .zip en vez de imagen)

- Límites de Lambda: 50 MB comprimido por subida directa, 250 MB descomprimido.
- Medido el 2026-10-11 con `requirements.txt` actual (wheels `manylinux2014_x86_64`, cp313, `--only-binary=:all:`): **44 MB descomprimido, 20 MB comprimido**. botocore 25 MB, pydantic_core 4,9 MB, boto3 1,1 MB. Todas las dependencias tienen wheel binaria para cp313 x86_64.
- El runtime `python3.13` trae su propio boto3, pero en una versión que no controlamos; se empaqueta la fijada en `requirements.txt` (P8).
- Determinismo: `pip --no-compile` (sin `.pyc` con marcas de tiempo), `touch -t` a fecha fija y `zip -X -D` con la lista de archivos ordenada → mismo `source_code_hash` para el mismo contenido.
- Revisión 1 (descartada): imagen de contenedor en ECR, que exigía `--provenance=false` (Lambda rechaza índices OCI con atestaciones) y `ecr:GetDownloadUrlForLayer` para quien crea la función.

## R-6. Lambda en VPC

- Necesita `ec2:CreateNetworkInterface`, `DescribeNetworkInterfaces`, `DeleteNetworkInterface`, `AssignPrivateIpAddresses`, `UnassignPrivateIpAddresses` en su rol (lo que da `AWSLambdaVPCAccessExecutionRole`). Se definen en línea porque el rol de GitHub solo puede adjuntar dos políticas gestionadas de ECS.
- Al borrar la función, las ENI de Hyperplane tardan en liberarse (hasta ~20–40 min). El grupo de seguridad de la función no se puede borrar hasta entonces; el proveedor de Terraform espera.
- S3 se alcanza por el endpoint de gateway de la plataforma (asociado a las tablas de rutas privadas); Secrets Manager por el NAT.

## R-7. Concurrencia y conexiones

- pymongo abre por cliente `maxPoolSize` conexiones de aplicación + 2 de monitorización por servidor. Con `MONGODB_MAX_POOL_SIZE=2` → ≤ 4 conexiones por instancia de la función.
- Concurrencia reservada: Lambda exige que queden al menos 10 ejecuciones sin reservar en la cuenta. Con el límite por defecto de 1000 no hay problema; las cuentas nuevas pueden tener 10, y entonces no se puede reservar nada (`aws lambda get-account-settings` → `AccountLimit.ConcurrentExecutions`).
