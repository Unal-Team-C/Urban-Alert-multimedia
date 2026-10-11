# UrbanAlert — Servicio Multimedia

Microservicio de UrbanAlert que guarda las evidencias fotográficas de los reportes y devuelve, por cada imagen, una **URL definitiva** que Reportes guarda tal cual. Es una **función AWS Lambda en Python 3.13 + FastAPI**; [Mangum](https://mangum.fastapiexpert.com/) traduce los eventos de API Gateway a FastAPI.

En AWS:
- Las imágenes van a **Amazon S3** y se sirven por **CloudFront**.
- Los metadatos van a **Amazon DocumentDB** (compatible con MongoDB).
- El servicio se publica solo a través del **API Gateway compartido** de la [plataforma de UrbanAlert](https://github.com/Unal-Team-C/urban-alert-plataforma).

Toda la infraestructura es Terraform y la gestionan dos workflows de GitHub Actions.

- Despliegue en AWS (spec, plan y tareas, desarrollado con SDD): [specs/002-despliegue-aws/](specs/002-despliegue-aws/) — [spec](specs/002-despliegue-aws/spec.md) · [plan](specs/002-despliegue-aws/plan.md) · [tareas](specs/002-despliegue-aws/tasks.md)
- Contrato de la API (OpenAPI, archivo estático): [docs/openapi.json](docs/openapi.json). Se puede abrir en [Swagger Editor](https://editor.swagger.io/) o en Scalar.
- Cómo se trabaja con el arnés SDD: [docs/SDD.md](docs/SDD.md)

## Cómo funciona

```
Subir:  Cliente ──POST imagen (multipart)──▶ API Gateway ──▶ Lambda ──▶ S3 (objeto) + DocumentDB (metadatos)
                ◀── 201 { imageId, imageUrl, … }
Ver:    Cliente ──GET imageUrl────────────────▶ CloudFront ──▶ S3 (sin pasar por la función)
```

- **Formatos:** solo **JPEG y PNG**, detectados por el contenido del archivo y no por el nombre ni el tipo declarado. HEIC, WebP, PDF y el resto responden `415`. El cliente convierte HEIC a JPEG.
- **Tamaño:** **3 670 016 bytes (3,5 MB) como máximo**, límite incluido. El cliente comprime antes de enviar: el evento síncrono de Lambda no admite más de 6 MB.
- **Privacidad:** se quitan del archivo los metadatos incrustados (EXIF con GPS, fecha, modelo del dispositivo y autor; XMP; IPTC; comentarios; imágenes secundarias tras el fin del archivo). Solo se conserva la orientación. Los datos de captura viajan como campos del formulario y se guardan en la base de metadatos.
- **Lectura:** `imageUrl` no caduca ni lleva firma. El bucket es privado: solo CloudFront lee objetos sueltos por su clave (UUID v4). No se puede listar, ni leer sin pasar por CloudFront, ni escribir salvo la función.

## Contrato

JSON en camelCase y nombres en inglés, con las mismas convenciones que Geoespacial. Todos los errores tienen la forma `{"code": <int>, "message": <str>, "details"?: [{"field", "reason"}]}`. Las rutas se llaman con la URL del API Gateway compartido (`<gateway>`, en el resumen del workflow Provision).

### UploadImage — `POST <gateway>/api/v1/multimedia/images`

`multipart/form-data`:

| Parte | Obligatoria | Regla |
|---|---|---|
| `image` | sí | JPEG o PNG, de 1 a 3 670 016 bytes |
| `capturedAt` | no | ISO 8601 **con** zona horaria (`-05:00` o `Z`), no posterior al momento de la carga |
| `lat`, `lon` | no | Van juntas. −90..90 y −180..180; no se limitan a Bogotá (la ubicación oficial del reporte la valida Geoespacial) |

```bash
curl -F image=@foto.jpg -F capturedAt=2026-10-06T16:12:05-05:00 -F lat=4.6097 -F lon=-74.0817 "<gateway>/api/v1/multimedia/images"
```

Respuesta `201` (cabecera `Location: /api/v1/multimedia/images/{imageId}/metadata`):

```json
{
  "imageId": "7f3c2a9e-1b4d-4c6e-9a8f-2d1e0b5c7a31",
  "imageUrl": "https://d111111abcdef8.cloudfront.net/7f3c2a9e-1b4d-4c6e-9a8f-2d1e0b5c7a31.jpg",
  "contentType": "image/jpeg",
  "sizeBytes": 2457600,
  "uploadedAt": "2026-10-06T21:15:42Z",
  "capture": { "capturedAt": "2026-10-06T16:12:05-05:00", "coordinate": { "lat": 4.6097, "lon": -74.0817 } }
}
```

`sizeBytes` es el tamaño del archivo guardado, ya sin metadatos. `capture` es `null` si no se enviaron datos de captura.

| Código | Cuándo |
|---|---|
| `400 Invalid parameter` | Falta `image`, archivo vacío, `capturedAt` inválida o futura, `lat`/`lon` fuera de rango o solo una de las dos |
| `413 Image exceeds the maximum size` | Más de 3 670 016 bytes |
| `415 Unsupported image format` | No es JPEG ni PNG, o su estructura de metadatos está dañada |
| `503 Service unavailable` | S3 o DocumentDB no responden (o no se puede leer el secreto de la base). Si falla la base, el objeto ya subido se borra |

### GetImageMetadata — `GET <gateway>/api/v1/multimedia/images/{imageId}/metadata`

`200` con el mismo cuerpo de la subida; `404 Image not found` si no existe o el id no es un UUID; `503` si la base no responde.

### Ver la imagen — `GET {imageUrl}`

La sirve CloudFront directamente, sin pasar por la función. Una URL inexistente responde **`403`**, no `404`: el bucket no permite listar y S3 no revela si la clave existe.

Cualquier otra ruta bajo `/api/v1/multimedia/` (`/docs`, `/openapi.json`, `DELETE …`) responde `404` desde el gateway.

**Para el servicio de Reportes:** recibe `imageUrl` del cliente y la guarda tal cual (mide menos de 2000 caracteres). Conviene validar que empiece por la URL base de las imágenes (`https://<id>.cloudfront.net/`, en el resumen de Provision), para no aceptar imágenes externas.

**Para el cliente:** comprimir o redimensionar a 3,5 MB o menos, convertir HEIC a JPEG (Safari lo hace al subir; en Chrome, Edge y Firefox de escritorio hace falta una librería como `heic2any`) y enviar la fecha y las coordenadas de captura como campos, porque al recomprimir se pierde el EXIF.

## Despliegue en AWS

Cuenta `348364742283`, región `us-east-2`. La plataforma compartida debe estar aprovisionada antes (workflow Provision de `Unal-Team-C/urban-alert-plataforma`).

### Arquitectura

```text
 Cliente ──HTTPS──► API Gateway compartido (plataforma)
                     POST /api/v1/multimedia/images
                     GET  /api/v1/multimedia/images/{imageId}/metadata
                     │ AWS_PROXY, payload 2.0
 ┌── VPC de la plataforma ──▼─────────────────────────────────────────────────────┐
 │  subredes privadas:  Lambda urban-alert-multimedia ──TLS:27017──► DocumentDB   │
 │   (python3.13, .zip)  │  │                                       (1 instancia)│
 │                       │  └─HTTPS─► NAT ─► Secrets Manager (URI de la base)     │
 │                       └─HTTPS─► endpoint de gateway S3 ─► bucket de imágenes   │
 │  Lambda urban-alert-multimedia-init (índices; la invoca Provision)            │
 └────────────────────────────────────────────────────────────────────────────────┘
 Cliente ──HTTPS GET imageUrl──► CloudFront (OAC) ──► bucket privado (Intelligent-Tiering)
```

| Stack (`infra/`) | Recursos | Estado de Terraform | ¿Lo borra Deprovision? |
|---|---|---|---|
| [`almacen`](infra/almacen/) | Bucket S3 privado con Intelligent-Tiering desde el día 0, CloudFront con Origin Access Control | `multimedia/almacen.tfstate` | **Nunca** (`prevent_destroy`): las `imageUrl` siguen funcionando |
| [`base`](infra/base/) | DocumentDB 5.0 (1 × db.t4g.medium, cifrado, TLS obligatorio, 7 días de copias, protección contra borrado), secreto con la URI, grupos de seguridad, roles de las funciones, logs (30 días) | `multimedia/base.tfstate` | Sí, con copia final de la base |
| [`servicio`](infra/servicio/) | Lambda del API y Lambda de init (mismo .zip) en las subredes privadas | `multimedia/servicio.tfstate` | Sí |
| [`rutas`](infra/rutas/) | Integración y las dos rutas en el API Gateway compartido, permiso de invocación | `multimedia/rutas.tfstate` | Sí, la primera |

Los identificadores de la red y del gateway se leen del contrato de la plataforma en SSM (`/urban-alert/plataforma/*`), nunca se copian a mano. Inventario completo: [infra/INVENTARIO.md](infra/INVENTARIO.md).

### Workflows

| Workflow | Cuándo | Qué hace |
|---|---|---|
| [Provision](.github/workflows/provision.yml) | Cada push a `main` (al integrar un pull request) | Ver el orden abajo |
| [Deprovision](.github/workflows/deprovision.yml) | Solo a mano: Actions → Deprovision → Run workflow → escribir `urban-alert-multimedia` | `rutas` → `servicio` → `base` (quita la protección de DocumentDB y deja la copia `urban-alert-multimedia-final-<run_id>`). No toca `almacen`, la plataforma ni los recursos de arranque. Un stack ya vacío se salta |

Los dos comparten el grupo de concurrencia `urban-alert-multimedia-aws`: nunca se ejecutan a la vez. Se autentican con OIDC (`AWS_ROLE_ARN` + `AWS_REGION`), sin claves guardadas. Borrar el grupo de seguridad de las funciones puede tardar 20–40 minutos en Deprovision, mientras Lambda libera sus interfaces de red.

**Orden de levantamiento (Provision):**

| # | Paso | Por qué |
|---|---|---|
| 0 | Pruebas unitarias, `terraform fmt`/`validate`/`test` de los 4 stacks, actionlint, shellcheck | Si algo falla, no se toca AWS |
| 1 | Paquete .zip ([scripts/build-lambda-zip.sh](scripts/build-lambda-zip.sh)) | Determinista: el mismo código da el mismo hash, y relanzar un commit no cambia la función |
| 2 | Plataforma ([scripts/check-platform.sh](scripts/check-platform.sh)) | Sin la red y el gateway compartidos no se cambia nada |
| 3 | `almacen` | Su URL de CloudFront y su bucket los necesitan la función y sus permisos |
| 4 | `base` | La función necesita el rol, la red y el secreto. La primera vez, DocumentDB tarda 10–15 min |
| 5 | `servicio` | Las funciones con el .zip del commit (etiqueta `Commit`) |
| 6 | Init ([scripts/run-init.sh](scripts/run-init.sh)) | Crea los índices dentro de la VPC y prueba red, secreto y TLS antes de abrir el tráfico |
| 7 | `rutas` | El servicio se publica solo cuando ya está listo |
| 8 | Prueba de humo ([scripts/smoke-gateway-multimedia.sh](scripts/smoke-gateway-multimedia.sh)) | Metadatos de un id inexistente → `404` del servicio; `/docs` → `404`; CloudFront sin clave y S3 directo → `403`. No escribe datos |
| 9 | Resumen | URL del gateway, URL base de las imágenes, commit, paquete y plan de cada stack |

### Primera vez

1. Aplicar a mano la política [infra/bootstrap/github-multimedia-policy.json](infra/bootstrap/github-multimedia-policy.json) al rol de los workflows (pasos en [infra/bootstrap/README.md](infra/bootstrap/README.md)). Sin ella, Provision falla con `AccessDenied` sobre Lambda o CloudFront.
2. Comprobar que la plataforma está aprovisionada.
3. Integrar en `main`.

Secretos y variables de GitHub (Settings → Secrets and variables → Actions):

| Tipo | Nombre | Para qué | Ejemplo |
|---|---|---|---|
| Secreto | `AWS_ROLE_ARN` | Rol que asumen los workflows por OIDC | `arn:aws:iam::348364742283:role/github-actions-…` |
| Variable | `AWS_REGION` | Región de todo el despliegue | `us-east-2` |

No hace falta ningún otro secreto: la contraseña de DocumentDB la genera Terraform y la función la lee de Secrets Manager.

### Configuración de la función en AWS

La ponen los stacks; no se edita a mano. Los valores ajustables (memoria, tiempos, pool, concurrencia, clase de la base, retención) están en los `terraform.tfvars` de cada stack.

| Variable | Valor en AWS |
|---|---|
| `AWS_ENDPOINT_URL_S3` | **No se define**: boto3 usa S3 nativo |
| `AWS_REGION`, credenciales | Las pone Lambda (rol `urban-alert-multimedia-api`) |
| `S3_BUCKET` | `urban-alert-multimedia-images-348364742283` |
| `PUBLIC_IMAGE_BASE_URL` | `https://<id>.cloudfront.net` (prefijo de `imageUrl`) |
| `MONGODB_URI_SECRET_ARN` | ARN del secreto `urban-alert-multimedia-docdb`, que contiene la URI (TLS con la CA incluida en el paquete, `replicaSet=rs0`, `retryWrites=false`) |
| `MONGODB_URI` | **No se define** (la URI está en el secreto) |
| `MONGODB_DATABASE` / `MONGODB_MAX_POOL_SIZE` | `multimedia` / `2` |
| `ENABLE_DOCS` / `LOG_LEVEL` | `false` / `INFO` |

El resto de variables (`MAX_IMAGE_BYTES`, `MONGODB_TIMEOUT_MS`, `STORAGE_*_TIMEOUT_S`, …) usan los valores por defecto de [app/config.py](app/config.py).

**Conexiones a DocumentDB:** la cuenta tiene el límite de las cuentas nuevas, 10 ejecuciones concurrentes de Lambda en total. Con un pool de 2 más 2 conexiones de monitorización por instancia, el máximo es 40 conexiones, frente a las 500 que admite db.t4g.medium. Un pico de más de 10 peticiones simultáneas a cualquier Lambda de la cuenta se rechaza por limitación (throttling) y el gateway responde con error. Si se sube la cuota, poner `concurrencia_reservada = 10` en [infra/servicio/terraform.tfvars](infra/servicio/terraform.tfvars).

### Costes

Estimación mensual en `us-east-2` (730 h):

| Recurso | Precio | Encendido | Desaprovisionado |
|---|---|---|---|
| DocumentDB db.t4g.medium (1 instancia) | ~0,075 USD/h | ~55 USD | 0 |
| DocumentDB almacenamiento + E/S | 0,10 USD/GB-mes + 0,20 USD/millón de E/S | < 1 USD | 0 |
| Copia final de DocumentDB | ~0,021 USD/GB-mes | — | céntimos |
| Secrets Manager (1 secreto) | 0,40 USD/mes | 0,40 USD | 0 |
| Lambda (2 funciones) | 0,20 USD/millón de peticiones + GB-s (capa gratuita) | ~0 | 0 |
| S3 Intelligent-Tiering | 0,023 → 0,0125 (30 días sin acceso) → 0,004 USD/GB-mes (90 días) + 0,0025 USD/1000 objetos | céntimos | céntimos |
| CloudFront | Capa gratuita: 1 TB y 10 M de peticiones/mes | ~0 | ~0 |
| CloudWatch Logs (30 días) | 0,50 USD/GB ingerido | ~0 | 0 |
| **Total** | | **~56 USD** | **céntimos** |

No incluye la plataforma compartida (~36,6 USD/mes, en su README). Para no pagar DocumentDB cuando no se usa, desaprovisionar: las imágenes y sus URL se conservan.

### Restaurar los metadatos tras volver a aprovisionar

Un Provision después de un Deprovision crea una base de metadatos **vacía**. Las imágenes siguen en el bucket y sus `imageUrl` funcionan, pero `GET …/metadata` responde `404` hasta restaurar la copia final. Es un procedimiento excepcional y manual, fuera de los workflows:

1. Restaurar la copia en un clúster temporal: `aws docdb restore-db-cluster-from-snapshot --db-cluster-identifier urban-alert-multimedia-restore --snapshot-identifier urban-alert-multimedia-final-<run_id> --engine docdb --db-subnet-group-name urban-alert-multimedia-docdb --vpc-security-group-ids <sg de urban-alert-multimedia-docdb>`. Después, `aws docdb create-db-instance` con una instancia `db.t4g.medium` para ese clúster.
2. Desde una máquina dentro de la VPC de la plataforma (por ejemplo, una tarea efímera de ECS con `mongodump`/`mongorestore` y la CA `global-bundle.pem`), volcar la colección `images` de la base `multimedia` del clúster temporal y cargarla en `urban-alert-multimedia-docdb`. La URI del destino está en el secreto `urban-alert-multimedia-docdb`; el clúster temporal usa el mismo usuario y la misma contraseña que tenía el original.
3. Borrar el clúster temporal y su instancia.

### Validación local (sin instalar nada)

Con Podman (`podman machine start`), desde la raíz del repo:

```bash
podman run --rm -v "$PWD":/w -w /w docker.io/library/python:3.13-slim sh -c "pip install -q -r requirements-dev.txt && pytest tests/unit"
TF='podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5'
for s in almacen base servicio rutas; do eval "$TF -chdir=infra/$s init -backend=false" && eval "$TF -chdir=infra/$s validate" && eval "$TF -chdir=infra/$s test"; done
eval "$TF fmt -check -recursive infra"
podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7
podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:v0.10.0 scripts/*.sh
```

`plan`, `apply` y `destroy` contra el estado real solo se ejecutan desde los workflows. Tras cambiar un proveedor, regenerar los `.terraform.lock.hcl` con `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64` (el CI usa `-lockfile=readonly`).

## Estructura

```text
app/              función: main.py (FastAPI + Mangum), service.py, config.py, logging_setup.py
  api/            rutas, esquemas y errores
  domain/         formato de imagen, reglas de captura, limpieza de metadatos (sin dependencias)
  storage/        S3 (boto3) y MongoDB/DocumentDB (pymongo; URI desde Secrets Manager en AWS)
  admin/          init_resources.py (índices; handler de la Lambda de init)
infra/            stacks de Terraform almacen, base, servicio y rutas; bootstrap/ (política del rol); INVENTARIO.md
scripts/          build-lambda-zip.sh, check-platform.sh, run-init.sh, smoke-gateway-multimedia.sh; invoke-upload.sh (local)
.github/workflows provision.yml y deprovision.yml
docs/             openapi.json (contrato) y SDD.md (guía del arnés)
tests/            unit/ (en el CI); integration/ y e2e/ (entorno local, no mantenidos)
specs/            especificaciones, planes y tareas (SDD)
compose.yaml      entorno local (no mantenido)
Dockerfile        imagen local con el emulador de Lambda (no mantenida; en AWS se despliega un .zip)
```

## Entorno local (no mantenido)

Desde la spec 002, el servicio se despliega y prueba en AWS. El entorno local con contenedores sigue en el repositorio, pero ya no forma parte del pipeline ni se garantiza que funcione. Usa MinIO en lugar de S3, MongoDB 8 en lugar de DocumentDB y el emulador de Lambda (`compose.yaml`, `Dockerfile`, `tests/integration`, `tests/e2e`, `scripts/invoke-upload.sh`).

```bash
podman compose up -d --build                        # minio :9000/:9001, mongo :27017, init, multimedia :9010
scripts/invoke-upload.sh foto.jpg                   # invoca el emulador con un evento de API Gateway
podman compose --profile test run --rm --build tests
```

Localmente la URI de MongoDB se lee de `MONGODB_URI` (no se define `MONGODB_URI_SECRET_ARN`) y `imageUrl` empieza por `http://localhost:9000/urbanalert-images`.
