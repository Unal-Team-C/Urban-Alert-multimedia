# Plan técnico: Despliegue del Servicio Multimedia en AWS

- **Spec**: ./spec.md
- **Estado**: aprobado <!-- borrador | aprobado -->
- **Fecha**: 2026-10-11 (revisión 2: paquete .zip en vez de imagen de contenedor; sin entorno local)

## 1. Resumen técnico

Cuatro stacks de Terraform con estado en `s3://urban-alert-tfstate-348364742283/multimedia/`, aplicados solo desde GitHub Actions:

- **`almacen`** (persistente, nunca se destruye): S3 de imágenes con Intelligent-Tiering y CloudFront con OAC.
- **`base`**: DocumentDB, secreto con la URI, grupos de seguridad, roles de las funciones y logs.
- **`servicio`**: Lambda del API y Lambda de inicialización. Ambas usan el runtime gestionado `python3.13` y el mismo paquete .zip, y van en la VPC de la plataforma.
- **`rutas`**: integración y dos rutas en el API Gateway compartido, más el permiso de invocación.

El workflow construye el .zip de forma determinista con un script: dependencias como wheels `manylinux2014_x86_64` para CPython 3.13, el código de `app/` y la CA de DocumentDB.

Cambios en el código para usar la nube:

- La URI de MongoDB se lee de Secrets Manager si existe `MONGODB_URI_SECRET_ARN`.
- `init_resources` gana un handler de Lambda.

Sin `AWS_ENDPOINT_URL_S3`, boto3 usa S3 nativo; `PUBLIC_IMAGE_BASE_URL` pasa a ser el dominio de CloudFront. Orden de levantamiento en §4.3; el desmontaje es el inverso, sin tocar `almacen`. No hay ECR ni imagen de contenedor.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje / versión | Python 3.13 (runtime gestionado `python3.13` de Lambda, x86_64), FastAPI + Mangum; Terraform `>= 1.10, < 2.0` (CI y local con `hashicorp/terraform:1.16.5`) |
| Dependencias principales | Las de `requirements.txt` sin cambios (boto3 ya incluye Secrets Manager). Proveedores `hashicorp/aws ~> 6.0` y `hashicorp/random ~> 3.6` |
| Paquete | `build/multimedia.zip`: medido el 2026-10-11 con las dependencias actuales, **44 MB descomprimido / 20 MB comprimido** (límites de Lambda: 250 MB / 50 MB por subida directa). botocore ocupa 25 MB |
| Almacenamiento | S3 (bucket `urban-alert-multimedia-images-348364742283`) + CloudFront; DocumentDB 5.0 (`urban-alert-multimedia-docdb`, 1 × db.t4g.medium), base `multimedia`, colección `images` |
| Pruebas | pytest unitarias (`tests/unit`) en el runner con Python 3.13; `terraform test` con `mock_provider`; actionlint 1.7.7; shellcheck v0.10.0; prueba de humo contra AWS |
| Plataforma objetivo | AWS 348364742283, us-east-2; Lambda (512 MB, 15 s) en las subredes privadas de `urban-alert-plataforma` |
| Restricciones | Rol OIDC compartido que solo confía en `refs/heads/main`; permisos del rol limitados al prefijo `urban-alert-*`; evento síncrono de Lambda ≤ 6 MB; integración del gateway ≤ 30 s |

Validación local (Podman, sin instalar nada), desde la raíz del repo:

```bash
TF='podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5'
for s in almacen base servicio rutas; do eval "$TF -chdir=infra/$s init -backend=false" && eval "$TF -chdir=infra/$s validate" && eval "$TF -chdir=infra/$s test"; done
eval "$TF fmt -check -recursive infra"
podman run --rm -v "$PWD":/w -w /w docker.io/library/python:3.13-slim sh -c "pip install -q -r requirements-dev.txt && pytest tests/unit"
podman run --rm -v "$PWD":/w -w /w docker.io/library/python:3.13-slim sh -c "apt-get -qq update && apt-get -qq install -y zip curl >/dev/null && scripts/build-lambda-zip.sh"
podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7
podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:v0.10.0 scripts/*.sh
```

## 3. Verificación contra la constitución

La constitución de este repo es la plantilla vacía (versión 0.0.0). Se verifica contra los principios de `urban-alert-plataforma` (P1–P10), que Geoespacial también sigue, para que los tres repos sean coherentes. Se recomienda adoptarlos después con `/sdd-constitution`.

| Principio | ¿Cumple? | Nota |
|---|---|---|
| P1 IaC solo desde Actions | Sí | En local solo `init -backend=false`, `validate`, `test`, `fmt` |
| P2 Arranque fuera de Terraform | Sí | La nueva política del rol se versiona en `infra/bootstrap/` y se aplica a mano (D-011) |
| P3 Sin secretos | Sí | OIDC. La URI vive en Secrets Manager y la función solo recibe su ARN (D-006). Las salidas no incluyen la contraseña. La contraseña queda en el estado cifrado, como en Geoespacial |
| P4 Destructivo solo explícito | Sí | DocumentDB con `deletion_protection` (solo la quita Deprovision); bucket y CloudFront con `prevent_destroy` (D-003) |
| P5 Coste mínimo documentado | Sí | Clases mínimas; sin ECR; tabla de costes (§4.6) |
| P6 Validación antes de commit y apply | Sí | Primer job de Provision; comandos en §2 |
| P7 Pruebas de lo que protege | Sí | Un `.tftest.hcl` por stack (§9) |
| P8 Versiones fijadas | Sí | Terraform, proveedores, lockfiles con 3 plataformas, actions, herramientas y dependencias de Python con versión exacta |
| P9 Contrato estable | Sí | Solo consume `/urban-alert/plataforma/*`; prefijo `urban-alert-multimedia`; etiquetas por defecto (`Project`, `Service`, `ManagedBy`, `Stack`) |
| P10 Serializado e idempotente | Sí | Grupo `urban-alert-multimedia-aws` sin cancelación. Con el .zip determinista (D-010), relanzar el mismo commit no cambia nada |

## 4. Arquitectura y componentes

### 4.1 Vista general

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

### 4.2 Stacks y recursos

| Stack | Estado | Recursos | ¿Lo destruye Deprovision? |
|---|---|---|---|
| `almacen` | `multimedia/almacen.tfstate` | Bucket con Block Public Access, propiedad del propietario (sin ACL), SSE-S3, política (solo CloudFront por `AWS:SourceArn`; deniega sin TLS), ciclo de vida (Intelligent-Tiering día 0; abortar multipart a 7 días); OAC; distribución (`redirect-to-https`, `CachingOptimized`, `PriceClass_100`) | **Nunca** (`prevent_destroy`) |
| `base` | `multimedia/base.tfstate` | SG `-lambda` (salida 443 a todo y 27017 al SG de la base); SG `-docdb` (entrada 27017 solo desde el SG `-lambda`); subnet group y grupo de parámetros `docdb5.0` con `tls=enabled`; clúster DocumentDB (cifrado, 7 días de copias, `deletion_protection = !allow_destroy`, copia final) + 1 instancia; `random_password`; secreto `urban-alert-multimedia-docdb` con la URI; roles `urban-alert-multimedia-api` y `urban-alert-multimedia-init` con políticas en línea; grupos de logs `/aws/lambda/urban-alert-multimedia{,-init}` (30 días) | Sí, en 2 pasos (como Geoespacial) |
| `servicio` | `multimedia/servicio.tfstate` | `aws_lambda_function` del API (`runtime = "python3.13"`, `handler = "app.main.handler"`, `filename = var.paquete_zip`, `source_code_hash = filebase64sha256(...)`, 512 MB, 15 s, VPC, variables §7.2, concurrencia según D-008, etiqueta `Commit`) e `-init` (mismo .zip, `handler = "app.admin.init_resources.handler"`, 60 s) | Sí |
| `rutas` | `multimedia/rutas.tfstate` | Una integración `AWS_PROXY` (payload `2.0`, función del API), 2 rutas `NONE` y `aws_lambda_permission` para `apigateway.amazonaws.com` limitado a `<api-execution-arn>/*/*/api/v1/multimedia/*` | Sí, el primero |

Dependencias entre stacks: `base` lee `almacen` (bucket ARN), `servicio` lee `almacen` y `base`, y `rutas` lee `servicio`, todas con `terraform_remote_state` sobre el mismo bucket. El contrato de la plataforma se lee de SSM: `base` lee VPC y subredes; `rutas` lee `api-id` y `api-execution-arn`, más `api-endpoint` como salida.

### 4.3 Orden de levantamiento (Provision)

| # | Paso | Por qué en este orden |
|---|---|---|
| 0 | **Pruebas y comprobaciones** (job `test`): `pytest tests/unit` (Python 3.13 en el runner); `fmt`, `validate` y `test` de los 4 stacks; actionlint; shellcheck | Nada se toca en AWS si algo falla (HU-1 #2) |
| 1 | **Paquete** (`scripts/build-lambda-zip.sh` → `build/multimedia.zip`): falla si supera 50 MB comprimido | Se construye antes de tener credenciales: si falla, no se ha tocado nada. Se sube como artefacto del job para el siguiente |
| 2 | **Plataforma** (`scripts/check-platform.sh`) | La VPC, las subredes, el NAT, el endpoint S3 y el gateway son de la plataforma; si falta, falla antes de cambiar nada |
| 3 | **`almacen`**: S3 + CloudFront | No depende de nada. Su dominio de CloudFront es la `PUBLIC_IMAGE_BASE_URL` que necesita la función, y su bucket ARN, los permisos del rol |
| 4 | **`base`**: red, DocumentDB, secreto, roles, logs | La función necesita el rol, los SG y el secreto. DocumentDB tarda unos 10–15 min solo la primera vez |
| 5 | **`servicio`**: las dos Lambda con el .zip | Necesitan todo lo de `almacen` y `base` |
| 6 | **Init** (`scripts/run-init.sh`): `aws lambda invoke` de `-init` → índice `objectKey_unique`; falla si hay `FunctionError` | Índices antes de abrir el tráfico (RF-007); además prueba de punta a punta la red, el secreto y TLS hacia DocumentDB |
| 7 | **`rutas`**: integración, rutas y permiso | Se publica el servicio solo cuando la función y la base están listas |
| 8 | **Humo** (`scripts/smoke-gateway-multimedia.sh`): por el gateway, `GET .../images/<uuid aleatorio>/metadata` → `404` (gateway → Lambda → Secrets Manager → DocumentDB) y `GET .../docs` → `404`; por CloudFront, `GET /` → `403` (sin listado); la URL directa del bucket → `403` | Comprueba la cadena completa sin escribir datos en el bucket persistente |
| 9 | **Resumen**: URL del gateway, URL base de imágenes, SHA, tamaño del paquete, plan de cada stack | Trazabilidad (RNF-008) |

### 4.4 Orden de desmontaje (Deprovision)

Se ejecuta solo en `refs/heads/main` y exige escribir `urban-alert-multimedia` como confirmación. Cada stack ya vacío se informa y se salta.

1. **`rutas`** → destroy. El gateway deja de enrutar a Multimedia (404), y la plataforma ya no ve rutas ni integraciones de este servicio.
2. **`servicio`** → destroy, con un .zip vacío como valor de `paquete_zip` (destruir no lo usa). Las ENI de Lambda empiezan a liberarse.
3. **`base`** → `apply -var allow_destroy=true -var final_snapshot_suffix=<run_id>` (quita la protección) y después `destroy`, que deja la copia final `urban-alert-multimedia-final-<run_id>`. Esperar a que se borre el SG de la función puede tardar 20–40 min (R-6).
4. **`almacen`**: no se toca (RF-017). El resumen indica que el bucket y CloudFront siguen activos y cómo restaurar la copia (§4.5).

### 4.5 Restaurar los metadatos tras reaprovisionar (manual, documentado)

Se restaura `urban-alert-multimedia-final-<run_id>` con `aws docdb restore-db-cluster-from-snapshot` en un clúster temporal. Después se vuelca y carga la colección `images` hacia el clúster nuevo con `mongodump`/`mongorestore`, desde una máquina dentro de la VPC. Queda en el README como procedimiento excepcional, fuera de los workflows (spec §8).

### 4.6 Costes (estimación mensual, us-east-2, 730 h)

| Recurso | Precio | Encendido | Desaprovisionado |
|---|---|---|---|
| DocumentDB db.t4g.medium (1 instancia) | ~0,075 USD/h | ~55 USD | 0 |
| DocumentDB almacenamiento + E/S | 0,10 USD/GB-mes + 0,20 USD/millón de E/S | < 1 USD | 0 |
| Copia final de DocumentDB | ~0,021 USD/GB-mes | — | céntimos |
| Secrets Manager (1 secreto) | 0,40 USD/mes | 0,40 USD | 0 |
| Lambda (2 funciones; el .zip lo guarda Lambda sin coste) | 0,20 USD/millón de peticiones + GB-s (capa gratuita) | ~0 | 0 |
| S3 Intelligent-Tiering | 0,023 → 0,004 USD/GB-mes + 0,0025 USD/1000 objetos | céntimos | céntimos |
| CloudFront | Capa gratuita: 1 TB y 10 M de peticiones/mes | ~0 | ~0 |
| CloudWatch Logs (30 días) | 0,50 USD/GB ingerido | ~0 | 0 |
| **Total** | | **~56 USD** | **céntimos** |

No incluye la plataforma compartida (~36,6 USD/mes, en su README). El tráfico hacia Secrets Manager pasa por su NAT, pero son unos pocos KB por arranque en frío.

## 5. Estructura de archivos

```text
app/
  config.py                    + mongodb_uri_secret_arn
  storage/metadata.py          + resolve_uri(): URI desde Secrets Manager si hay ARN (cacheada por proceso)
  admin/init_resources.py      + handler(event, context): solo índices (bucket y política son de Terraform)
tests/unit/
  test_config_logging.py       + MONGODB_URI_SECRET_ARN
  test_metadata_uri.py         nuevo: URI local vs. Secrets Manager (cliente simulado)
  test_init_handler.py         nuevo: el handler crea el índice y no toca S3
infra/
  bootstrap/
    README.md                  pasos manuales: política nueva en el rol, comprobación de la concurrencia
    github-multimedia-policy.json
  almacen/  {backend,versions,providers,variables,main,outputs}.tf  terraform.tfvars  .terraform.lock.hcl  tests/almacen.tftest.hcl
  base/     {backend,versions,providers,variables,network,docdb,secrets,iam,logs,outputs}.tf  terraform.tfvars  .terraform.lock.hcl  tests/base.tftest.hcl
  servicio/ {backend,versions,providers,variables,main,outputs}.tf  terraform.tfvars  .terraform.lock.hcl  tests/servicio.tftest.hcl
  rutas/    {backend,versions,providers,variables,main,outputs}.tf  .terraform.lock.hcl  tests/rutas.tftest.hcl
  INVENTARIO.md                recursos por stack, persistentes y de arranque
scripts/
  build-lambda-zip.sh          .zip determinista: wheels x86_64/cp313, app/, CA de DocumentDB; falla si > 50 MB
  check-platform.sh            copia del de Geoespacial (contrato SSM completo)
  run-init.sh                  invoca la Lambda de init y falla si devuelve FunctionError
  smoke-gateway-multimedia.sh  comprobaciones del paso 8
.github/workflows/
  provision.yml                push a main (§4.3)
  deprovision.yml              workflow_dispatch con confirmación (§4.4)
.gitignore                     + build/
README.md                      sección AWS: arquitectura, orden, workflows, rutas, configuración en la nube, costes, restauración; lo local se marca como no mantenido
```

No se borran ni se modifican `Dockerfile`, `compose.yaml`, `scripts/invoke-upload.sh`, `tests/integration`, `tests/e2e` ni `docs/openapi.json`: ya no se mantienen (RF-016 eliminado), pero borrarlos queda fuera de esta feature.

## 6. Modelo de datos

Sin cambios: documento `images` (`_id` = UUID, `objectKey`, `contentType`, `sizeBytes`, `uploadedAt`, `capture`) e índice único `objectKey_unique`. DocumentDB admite los tipos y el índice que se usan. Las claves de objeto (`<uuid>.<ext>`) no cambian. La clase de almacenamiento la cambia la regla de ciclo de vida, no el código.

## 7. Contratos / interfaces

### 7.1 API (sin cambios)

`docs/openapi.json`. Publicadas en el gateway, sin reescritura de ruta porque el servicio ya usa el prefijo `/api/v1/multimedia`:

| Ruta del gateway | Autorización | Destino |
|---|---|---|
| `POST /api/v1/multimedia/images` | `NONE` | Lambda `urban-alert-multimedia` (payload 2.0, Mangum) |
| `GET /api/v1/multimedia/images/{imageId}/metadata` | `NONE` | ídem |

Una `imageUrl` inexistente responde `403` en CloudFront: S3 no revela si existe sin `ListBucket`. Se documenta.

### 7.2 Configuración de la función del API

| Variable | Valor en AWS | Antes (local) |
|---|---|---|
| `AWS_ENDPOINT_URL_S3` | **no se define** → S3 nativo | `http://minio:9000` |
| `AWS_REGION`, credenciales | Las pone Lambda (rol `urban-alert-multimedia-api`) | Credenciales de MinIO |
| `S3_BUCKET` | `urban-alert-multimedia-images-348364742283` | `urbanalert-images` |
| `S3_ADDRESSING_STYLE` | `auto` (defecto) | `path` |
| `PUBLIC_IMAGE_BASE_URL` | `https://<id>.cloudfront.net` | `http://localhost:9000/urbanalert-images` |
| `MONGODB_URI` | no se define | `mongodb://…@mongo:27017/?authSource=admin` |
| `MONGODB_URI_SECRET_ARN` | ARN de `urban-alert-multimedia-docdb` | — |
| `MONGODB_DATABASE` | `multimedia` | `multimedia` |
| `MONGODB_MAX_POOL_SIZE` | `2` (D-008) | `5` |
| `ENABLE_DOCS` / `LOG_LEVEL` | `false` / `INFO` | `false` / `INFO` |

La función de init recibe solo `MONGODB_URI_SECRET_ARN`, `MONGODB_DATABASE` y `LOG_LEVEL`.

URI guardada en el secreto (cadena simple):
`mongodb://multimedia:<password>@<cluster-endpoint>:27017/?tls=true&tlsCAFile=/var/task/certs/global-bundle.pem&replicaSet=rs0&retryWrites=false`. Lambda descomprime el .zip en `/var/task`, de modo que la CA va en `certs/` dentro del paquete. Se lee de la primaria (defecto), así que lo recién subido se puede consultar enseguida.

### 7.3 Nuevas interfaces de código

- `Settings.mongodb_uri_secret_arn: str = ""`.
- `app.storage.metadata.resolve_uri(settings) -> str`: si no hay ARN, devuelve `settings.mongodb_uri`. Si lo hay, devuelve `secretsmanager.get_secret_value(SecretId=arn)["SecretString"]`, cacheado con `lru_cache`. Un fallo lanza `MetadataStoreError`, que se traduce en `503` (igual que con la base caída).
- `app.admin.init_resources.handler(event, context) -> {"indexes": [...]}`: llama a `ensure_indexes(collection_for(settings))`. `main()` no cambia.

### 7.4 Paquete .zip (`scripts/build-lambda-zip.sh`)

1. `pip install --no-compile --target build/pkg --platform manylinux2014_x86_64 --implementation cp --python-version 3.13 --only-binary=:all: -r requirements.txt`.
2. Copia `app/` (sin `__pycache__`) y descarga `https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem` en `build/pkg/certs/`.
3. Fija la fecha de todos los archivos (`touch -t 198001010000`) y comprime en orden (`find | sort | zip -X -D -@`). Mismo contenido → mismo hash (D-010).
4. Falla si el resultado supera 50 MB (52 428 800 bytes) e imprime el tamaño.

### 7.5 Workflows

- `provision.yml` (`on: push: branches: [main]`), tres jobs:
  - `test`: Python 3.13 (`actions/setup-python@v5`) + Terraform + linters.
  - `package`: construye el .zip y lo sube con `actions/upload-artifact@v4`.
  - `provision`: `id-token: write`, `actions/download-artifact@v4`, pasos 2–9.
- `deprovision.yml` (`on: workflow_dispatch`, input `confirm`).
- Ambos: `concurrency: urban-alert-multimedia-aws` sin cancelación, `aws-actions/configure-aws-credentials@v4` con `secrets.AWS_ROLE_ARN` / `vars.AWS_REGION`, `hashicorp/setup-terraform@v3` (sin wrapper), `TF_VERSION=1.16.5`.

## 8. Decisiones

### D-001: Cuatro stacks (`almacen`, `base`, `servicio`, `rutas`)
- **Decisión**: separar por ciclo de vida y por orden de levantamiento.
- **Alternativas**: un solo stack con `-target` (desaconsejado para uso rutinario y no permite conservar el bucket en Deprovision); `base` + `servicio` juntos (la función se actualiza en cada commit y la base casi nunca, y el desmontaje de la base requiere el `apply` previo con `allow_destroy`).
- **Motivo**: el init debe ejecutarse entre las funciones y las rutas (§4.3); `almacen` sobrevive al desaprovisionamiento (RF-017); el desmontaje en 2 pasos de `base` es el de Geoespacial.

### D-002: DocumentDB de una instancia db.t4g.medium, usuario maestro
- **Decisión** (confirmada por el usuario: prototipo): clúster 5.0 con una instancia de la clase más pequeña con Graviton; la función usa el usuario maestro `multimedia`.
- **Alternativas**: un usuario de aplicación con permisos de lectura y escritura sobre `multimedia` (requiere crearlo desde la VPC con el maestro); clústeres elásticos (mínimo 2 vCPU por shard, más caro).
- **Motivo**: la spec no exige un usuario de mínimo privilegio en la base; el aislamiento lo dan la red (SG) y el secreto. Si se quiere, el handler de init puede crearlo en una feature posterior.

### D-003: Persistencia con `prevent_destroy` en un stack que Deprovision no toca
- **Decisión**: `lifecycle { prevent_destroy = true }` en el bucket y la distribución; Deprovision nunca ejecuta `almacen`.
- **Alternativas**: dejar el bucket fuera de Terraform (rompe P1); `force_destroy = false` solamente (un bucket vacío sí se borraría).
- **Motivo**: RF-017. Las `imageUrl` siguen siendo válidas porque el dominio de CloudFront no cambia. Borrarlos exige un commit que quite `prevent_destroy`.

### D-004: CloudFront con OAC delante de un bucket privado
- **Decisión**: ver R-3. Sin ACL, Block Public Access completo y política solo para la distribución.
- **Motivo**: RF-002 y HU-4 #1; sin coste por hora.

### D-005: Intelligent-Tiering por regla de ciclo de vida desde el día 0
- **Decisión**: regla `transition { days = 0, storage_class = "INTELLIGENT_TIERING" }`, sin `aws_s3_bucket_intelligent_tiering_configuration` (los niveles de archivo quedan desactivados).
- **Alternativa**: subir con `StorageClass=INTELLIGENT_TIERING` desde el código (cambio de código).
- **Motivo**: RF-008 sin tocar el código. La transición se ejecuta en el ciclo diario: las imágenes pasan como mucho un día en Standard.

### D-006: URI de la base en Secrets Manager, leída por la función
- **Decisión**: `random_password` (32 caracteres, sin especiales) y un secreto con la URI completa. La función recibe solo el ARN.
- **Alternativas**: URI en una variable de entorno de la Lambda (visible en la consola y en `GetFunctionConfiguration`; viola RF-004); contraseña gestionada por DocumentDB (rotación, R-4); endpoint de interfaz (coste, R-4).
- **Motivo**: RF-004 con un cambio de código pequeño y probado; mismo patrón de estado que Geoespacial.

### D-007: Lambda de inicialización invocada por el workflow
- **Decisión**: segunda función con el mismo .zip y otro `handler`, con un rol sin acceso a S3. Provision la invoca con `aws lambda invoke` entre `servicio` y `rutas`.
- **Alternativas**: crear los índices al arrancar la función del API (latencia en frío y un `createIndex` por instancia); ejecutarlo desde el runner (no llega a la VPC).
- **Motivo**: RF-007, sin coste por hora; también sirve de comprobación de red, secreto y TLS antes de publicar las rutas.

### D-008: Presupuesto de conexiones acotado por el límite de concurrencia de la cuenta
- **Decisión**: no se reserva concurrencia (`concurrencia_reservada = -1` en `terraform.tfvars`). Se asume que la cuenta tiene el límite de las cuentas nuevas, **10 ejecuciones concurrentes** en total. Lambda exige dejar 10 sin reservar, así que con ese límite no se puede reservar nada. `MONGODB_MAX_POOL_SIZE = 2` → ≤ 10 × (2 + 2 de monitorización) = **40 conexiones**, frente a las 500 de db.t4g.medium (RNF-002).
- **Alternativa**: reservar 10 (revisión anterior). Fallaría con un límite de cuenta de 10, y el usuario no puede comprobarlo.
- **Motivo**: indicación del usuario (2026-10-11). Si AWS sube el límite, se pone `concurrencia_reservada = 10` en tfvars para mantener el tope. Limitación conocida: con 10 ejecuciones en toda la cuenta, un pico de más de 10 subidas simultáneas recibe `429`/`503` del gateway; la función de init también consume una mientras se ejecuta.

### D-009: Integración Lambda directa (`AWS_PROXY`, payload 2.0) sin VPC Link
- **Decisión**: el gateway invoca la función directamente; el VPC Link de la plataforma es para los ALB de ECS Express.
- **Motivo**: es el modelo de Lambda + HTTP API. La función no tiene URL pública (RF-006) y solo la puede invocar el gateway, con `source_arn` limitado al prefijo de Multimedia.

### D-010: Paquete .zip determinista, construido sin Docker
- **Decisión**: wheels binarios `manylinux2014_x86_64`/`cp313` con `pip --platform --only-binary=:all: --no-compile`, fechas fijas y orden estable; Terraform lo sube directamente (`filename` + `source_code_hash`). La función se etiqueta con `Commit = <sha>`.
- **Alternativas**:
  - Imagen de contenedor en ECR: era la revisión 1; el usuario la descartó porque el entorno local ya no es necesario.
  - Extraer `/var/task` de la imagen de Lambda: exige Docker en el pipeline sin aportar paridad con un entorno local que ya no se usa.
  - Subir el .zip a un bucket de artefactos: hace falta solo por encima de 50 MB, y mide 20 MB.
  - Excluir boto3 y usar el del runtime: ahorraría ~26 MB, pero la versión dejaría de estar fijada (P8).
- **Motivo**: menos infraestructura (sin ECR ni su coste) y un pipeline más corto. El hash estable hace que relanzar un commit no cambie la función (RNF-003); el SHA en la etiqueta da trazabilidad (RNF-008).

### D-011: Política de bootstrap propia `github-actions-urban-alert-multimedia`
- **Decisión**: nuevo JSON versionado en `infra/bootstrap/github-multimedia-policy.json` (contenido en el Anexo A), aplicado a mano al rol compartido por alguien con permisos de IAM.
- **Verificación** contra las tres políticas actuales del rol (copiadas por el usuario el 2026-10-11):

| Necesidad | `-urban-alertPolicy` | `-terraform` | `-platform` | ¿Falta? |
|---|---|---|---|---|
| Bucket S3 de imágenes y estado | `s3:*` en `urban-alert-*` | — | — | No |
| DocumentDB (clúster, instancia, subnet group, parámetros, copia) | `rds:*` | KMS vía `rds` | — | No |
| Rol vinculado de RDS (lo usa DocumentDB) | `rds.amazonaws.com` | — | — | No |
| Secreto `urban-alert-*` (crear, leer, actualizar, borrar) | Create/Put/Describe/GetValue/Tag | Update/Delete/GetResourcePolicy/ListVersionIds/Untag | — | No |
| Roles `urban-alert-*` con políticas en línea | — | Create/Delete/PutRolePolicy/… | — | No |
| Grupos de seguridad | Create/Delete/Authorize/Revoke | DeleteTags | `ec2:*` de red | No |
| SSM `/urban-alert/*`, API Gateway `/apis/*` | — | — | Sí | No |
| **Funciones Lambda** (crear, actualizar, permisos, invocar init) | — | — | — | **Sí** |
| **CloudFront** (distribución, OAC) | — | — | — | **Sí** |
| **`iam:PassRole` a `lambda.amazonaws.com`** | Solo `ecs`/`ecs-tasks` | — | — | **Sí** |
| **Logs `/aws/lambda/urban-alert-*`** | — | Solo `/ecs/urban-alert-*` | Solo `/aws/apigateway/…` | **Sí** |

- **Alternativa**: ampliar las políticas de Geoespacial (mezcla responsabilidades de otro repo).
- **Motivo**: P2; solo se añade lo que falta.

### D-012: Roles con políticas en línea
- **Decisión**: los permisos de ENI de VPC y de logs van en línea, en lugar de adjuntar `AWSLambdaVPCAccessExecutionRole`.
- **Motivo**: el rol de GitHub solo puede adjuntar dos políticas gestionadas de ECS (`IamAttachOnlyEcsManagedPolicies`). En línea, además, los logs se limitan al grupo de cada función.

### D-013: La plataforma y el pipeline de Geoespacial como modelo
- **Decisión**: mismos nombres de jobs, confirmación, `check-platform.sh`, resumen, variables (`name`, `allow_destroy`, `final_snapshot_suffix`) y estructura de pruebas que Geoespacial.
- **Motivo**: quien conoce un repo entiende el otro.

### D-014: Solo pruebas unitarias en el pipeline
- **Decisión**: el job `test` ejecuta `pytest tests/unit` en el runner. Las pruebas de integración y e2e (MinIO, MongoDB, RIE) salen del pipeline y la prueba de humo cubre la cadena real en AWS.
- **Alternativa**: seguir ejecutando `compose --profile test` en CI (mantener el entorno local que el usuario descartó).
- **Motivo**: RF-016 eliminado.

## 9. Estrategia de pruebas

| Nivel | Qué | Comando |
|---|---|---|
| Unitarias (nuevas) | `resolve_uri` con y sin ARN (cliente de Secrets Manager simulado con `monkeypatch`; caché; error → `MetadataStoreError`); el `handler` de init crea `objectKey_unique` sobre una colección falsa y no llama a S3; `Settings` lee `MONGODB_URI_SECRET_ARN` | `pytest tests/unit` |
| Unitarias existentes | Formato, captura, limpieza de metadatos, handler con eventos de API Gateway, configuración y logs: siguen pasando | `pytest tests/unit` |
| Paquete | El script falla si supera 50 MB; dos construcciones seguidas dan el mismo `sha256` | `scripts/build-lambda-zip.sh` dos veces + `sha256sum` (manual en la tarea y en CI vía resumen) |
| Terraform `almacen` | Bucket privado (Block Public Access ×4, sin ACL), política solo para la distribución + denegar sin TLS, regla Intelligent-Tiering día 0 sin niveles de archivo, `redirect-to-https`, OAC firmado, prefijo de nombre | `terraform test` |
| Terraform `base` | Protección por defecto (`deletion_protection`, sin `skip_final_snapshot`); con `allow_destroy` se levanta y la copia se llama `…-final-<suffix>`; DocumentDB cifrado, 7 días de copias y TLS por parámetro; SG de la base solo desde el SG de la función y solo 27017; red de la plataforma desde SSM; la URI contiene `tls=true`, la ruta de la CA y `retryWrites=false`; secreto recreable (`recovery_window_in_days = 0`); el rol del API solo tiene `PutObject`/`DeleteObject` sobre su bucket y el de init no tiene S3; prefijo `urban-alert-` | `terraform test` |
| Terraform `servicio` | `python3.13`, x86_64, handlers correctos; las dos en las subredes y el SG de `base`; 512 MB / 15 s; sin `AWS_ENDPOINT_URL_S3` ni `MONGODB_URI` y con `MONGODB_URI_SECRET_ARN`; `PUBLIC_IMAGE_BASE_URL` = CloudFront; `MONGODB_MAX_POOL_SIZE = 2`; sin concurrencia reservada por defecto; etiqueta `Commit` | `terraform test` |
| Terraform `rutas` | Exactamente las 2 rutas, `NONE`, `AWS_PROXY` 2.0 hacia la función, sin `$default`; `source_arn` limitado a `/api/v1/multimedia/*`; gateway leído de SSM | `terraform test` |
| Workflows y scripts | actionlint, shellcheck | §2 |
| En AWS (tras el primer Provision) | HU-1 #1 y #3 (segundo Provision del mismo commit: 0 cambios, RNF-003); HU-3 con una subida real de 3,5 MB (RNF-004) y el `imageUrl` en un navegador; HU-4 #1 (S3 directo → 403); HU-2 completo con un ciclo Deprovision → Provision comprobando que una `imageUrl` anterior sigue abriendo (HU-2 #8) | Lista en `verify.md` |

## 10. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| La política nueva no está aplicada al rol | El primer Provision falla con `AccessDenied` | Pasos en `infra/bootstrap/README.md`; el error indica la acción; el siguiente push retoma desde el estado |
| Límite de concurrencia de la cuenta = 10 (cuenta nueva) | Más de 10 peticiones simultáneas a cualquier Lambda de la cuenta → `429` | Prototipo: aceptado (D-008); para producción, pedir el aumento de la cuota *Concurrent executions* en Service Quotas |
| Una dependencia futura sin wheel `manylinux` para cp313 | El build falla (`--only-binary=:all:`) | Falla pronto y con mensaje claro; las actuales se comprobaron el 2026-10-11 |
| El paquete crece por encima de 50 MB | El build falla | Comprobación en el script; si pasa, subir el .zip a S3 (cambio acotado a `servicio`) |
| El .zip no es determinista (metadatos de pip) | La función se actualiza en cada relanzamiento (incumple RNF-003) | `--no-compile`, fechas fijas, orden estable; se comprueba con dos builds seguidos |
| Las ENI de Lambda tardan en liberarse | Deprovision de `base` tarda 20–40 min | Documentado; el timeout por defecto del job (6 h) basta |
| Primera creación de DocumentDB lenta | Primer Provision de ~20–30 min | Esperado (MS-001); los siguientes no la recrean |
| La CA de DocumentDB cambia | TLS falla al conectar | El bundle global incluye todas las CA vigentes y se descarga en cada build (un cambio del bundle cambia el hash y redespliega, lo que es correcto) |
| Un cambio en `main` reemplazaría el clúster | Pérdida de metadatos | `deletion_protection` hace fallar el `apply`; solo Deprovision la quita (RF-012) |
| Arranque en frío lento (secreto + TLS) | Subidas cerca de 15 s | La URI y el cliente se cachean por proceso; se mide en verify (RNF-004) |

## 11. Trazabilidad

| Requisito | Componentes | Pruebas |
|---|---|---|
| RF-001 | `servicio` (función del API), `build-lambda-zip.sh` | tftest `servicio`; paquete; humo |
| RF-002 | `almacen` (bucket, OAC, CloudFront); `PUBLIC_IMAGE_BASE_URL` | tftest `almacen`, `servicio`; humo (S3 directo → 403) |
| RF-003 | `base` (DocumentDB, SG, parámetros TLS), CA en el paquete | tftest `base`; init (paso 6) |
| RF-004 | `base` (secreto), `resolve_uri`, `MONGODB_URI_SECRET_ARN` | unitaria `test_metadata_uri`; tftest `servicio` (sin `MONGODB_URI`) |
| RF-005 | `rutas` | tftest `rutas`; humo |
| RF-006 | `base` (SSM, SG), `servicio` (vpc_config, sin URL de función), `rutas` (permiso) | tftest `base`, `servicio`, `rutas` |
| RF-007 | `init_resources.handler`, función `-init`, `run-init.sh` | unitaria `test_init_handler`; paso 6 |
| RF-008 | `almacen` (ciclo de vida) | tftest `almacen` |
| RF-009 | `infra/*`, `backend.tf` | `validate`/`test` de los 4 stacks |
| RF-010 | `provision.yml`, scripts | actionlint; ejecución real |
| RF-011 | `deprovision.yml` | actionlint; ejecución real (HU-2) |
| RF-012 | `base` (`allow_destroy`) | tftest `base` |
| RF-013 | workflows (OIDC) | actionlint; revisión |
| RF-014 | workflows (`concurrency`) | revisión |
| RF-015 | README, `infra/bootstrap/`, `INVENTARIO.md` | revisión en verify (MS-003) |
| RF-016 | Eliminado (2026-10-11) | — |
| RF-017 | `almacen` (`prevent_destroy`), Deprovision sin `almacen` | tftest `almacen`; ciclo real (HU-2 #8) |
| RNF-001 | SG, políticas IAM, secreto, Block Public Access | tftest `almacen`, `base` |
| RNF-002 | D-008 (límite de la cuenta + pool) | tftest `servicio` |
| RNF-003 | .zip determinista; stacks sin `timestamp()`; `random_password` estable | doble build; segundo Provision en verify |
| RNF-004 | 512 MB, caché de clientes | medición en verify |
| RNF-005 | Stacks sin cambios; paquete pequeño | tiempos del segundo Provision |
| RNF-006 | Clases mínimas, sin ECR; tabla §4.6 en el README | revisión |
| RNF-007 | `backup_retention_period = 7`, `deletion_protection` | tftest `base` |
| RNF-008 | Etiqueta `Commit`, resumen del workflow, grupos de logs con retención | tftest `servicio`; resumen |

## Anexo A. `infra/bootstrap/github-multimedia-policy.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaProjectFunctions",
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": [
        "arn:aws:lambda:us-east-2:348364742283:function:urban-alert-*",
        "arn:aws:lambda:us-east-2:348364742283:function:urban-alert-*:*"
      ]
    },
    {
      "Sid": "PassRolesToLambda",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::348364742283:role/urban-alert-*",
      "Condition": {
        "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" }
      }
    },
    {
      "Sid": "LambdaLogGroups",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:TagResource",
        "logs:UntagResource",
        "logs:ListTagsForResource"
      ],
      "Resource": [
        "arn:aws:logs:us-east-2:348364742283:log-group:/aws/lambda/urban-alert-*",
        "arn:aws:logs:us-east-2:348364742283:log-group:/aws/lambda/urban-alert-*:*"
      ]
    },
    {
      "Sid": "CloudFrontImages",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:GetDistributionConfig",
        "cloudfront:UpdateDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:TagResource",
        "cloudfront:UntagResource",
        "cloudfront:ListTagsForResource",
        "cloudfront:CreateOriginAccessControl",
        "cloudfront:GetOriginAccessControl",
        "cloudfront:GetOriginAccessControlConfig",
        "cloudfront:UpdateOriginAccessControl",
        "cloudfront:DeleteOriginAccessControl",
        "cloudfront:ListOriginAccessControls",
        "cloudfront:GetCachePolicy",
        "cloudfront:ListCachePolicies"
      ],
      "Resource": "*"
    }
  ]
}
```

Las acciones de CloudFront van sobre `*`: CloudFront es global y sus acciones de creación no admiten restringir el recurso por nombre. `DeleteDistribution`/`DeleteOriginAccessControl` solo se usarían si se quitara `prevent_destroy` en un commit (D-003).

Aplicarla (una vez, con un usuario con permisos de IAM; `<rol-de-github>` es el nombre del rol de `AWS_ROLE_ARN`):

```bash
aws iam create-policy --policy-name github-actions-urban-alert-multimedia --policy-document file://infra/bootstrap/github-multimedia-policy.json
aws iam attach-role-policy --role-name <rol-de-github> --policy-arn arn:aws:iam::348364742283:policy/github-actions-urban-alert-multimedia
```
