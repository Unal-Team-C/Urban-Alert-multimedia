# UrbanAlert — Servicio Multimedia

Microservicio de UrbanAlert que guarda las evidencias fotográficas de los reportes y devuelve, por cada imagen, una **URL definitiva** que Reportes guarda tal cual. Es una **función AWS Lambda en Python 3.13 + FastAPI**, empaquetada como imagen de contenedor; [Mangum](https://mangum.fastapiexpert.com/) traduce los eventos de API Gateway a FastAPI. Las imágenes van a un almacenamiento de objetos S3 (**MinIO** en local) y sus metadatos a **MongoDB**. Esta versión se ejecuta en local con contenedores, sin gateway ni cola de mensajes.

- Especificación, plan y tareas (desarrollado con SDD): [specs/001-servicio-multimedia/](specs/001-servicio-multimedia/) — [spec](specs/001-servicio-multimedia/spec.md) · [plan](specs/001-servicio-multimedia/plan.md) · [tareas](specs/001-servicio-multimedia/tasks.md)
- Contrato de la API (OpenAPI, archivo estático): [docs/openapi.json](docs/openapi.json). Se puede abrir en [Swagger Editor](https://editor.swagger.io/) o en Scalar.
- Cómo se trabaja con el arnés SDD: [docs/SDD.md](docs/SDD.md)

## Cómo funciona

```
Subir:  Cliente ──POST imagen (multipart)──▶ Lambda ──▶ S3/MinIO (objeto) + MongoDB (metadatos)
                ◀── 201 { imageId, imageUrl, … }
Ver:    Cliente ──GET imageUrl────────────────────────▶ S3/MinIO (o CDN en la nube), sin Lambda
```

- **Formatos:** solo **JPEG y PNG**, detectados por el contenido del archivo y no por el nombre ni el tipo declarado. HEIC, WebP, PDF y el resto responden `415`. El cliente convierte HEIC a JPEG.
- **Tamaño:** **3 670 016 bytes (3,5 MB) como máximo**, límite incluido. El cliente comprime antes de enviar: el evento síncrono de Lambda no admite más de 6 MB.
- **Privacidad:** se quitan del archivo los metadatos incrustados (EXIF con GPS, fecha, modelo del dispositivo y autor; XMP; IPTC; comentarios; imágenes secundarias tras el fin del archivo). Solo se conserva la orientación. Los datos de captura viajan como campos del formulario y se guardan en MongoDB.
- **Lectura:** `imageUrl` no caduca ni lleva firma. El bucket solo permite leer objetos sueltos por su clave (UUID v4): no se puede listar ni escribir sin credenciales.

## Requisitos

Un runtime de contenedores con Compose. En este equipo se usa **Podman** + `docker-compose`:

```bash
podman machine start       # tras cada reinicio del equipo
brew install docker-compose
```

> **Si `docker-compose` falla con `docker-credential-desktop: executable file not found`**: `~/.docker/config.json` todavía apunta a un Docker Desktop desinstalado (`"credsStore": "desktop"`). Quita esa línea o usa una configuración vacía solo para este proyecto:
>
> ```bash
> mkdir -p ~/.docker-podman && echo '{}' > ~/.docker-podman/config.json
> export DOCKER_CONFIG=~/.docker-podman
> ```

En los ejemplos, `docker compose`, `docker-compose` y `podman compose` son equivalentes.

## Arranque

```bash
cp .env.example .env              # valores locales; .env no se versiona
podman compose up -d --build
```

| Servicio | Puerto en el host | Descripción |
|---|---|---|
| `minio` | 9000 (API S3) · 9001 (consola) | Almacenamiento de imágenes. Imagen `cgr.dev/chainguard/minio`: MinIO retiró sus imágenes oficiales (plan D-004) |
| `mongo` | 27017 | MongoDB 8: base `multimedia`, colección `images` |
| `init` | — | Proceso de una sola ejecución: crea el bucket, su política (solo lectura de objetos) y los índices. Termina con `Exited (0)` |
| `multimedia` | 9010 | La función, en la imagen oficial de Lambda con el *Runtime Interface Emulator*. Arranca cuando `init` termina bien |

Para empezar de cero (borra imágenes y metadatos):

```bash
podman compose down -v && podman compose up -d --build
```

Para reaplicar el bucket, la política y los índices: `podman compose run --rm init`.

## Invocar la función en local

El emulador no es un API Gateway: recibe el **evento** que API Gateway (HTTP API, payload 2.0) le entregaría a Lambda, con el multipart en base64. El script lo construye:

```bash
scripts/invoke-upload.sh foto.jpg                                              # sin datos de captura
scripts/invoke-upload.sh foto.jpg 2026-10-06T16:12:05-05:00 4.6097 -74.0817   # con fecha y coordenadas
```

La respuesta es la de Lambda: `{"statusCode": 201, "headers": {…}, "body": "<JSON>"}`. El `imageUrl` del cuerpo (`http://localhost:9000/urbanalert-images/<uuid>.jpg`) se abre directamente en el navegador.

## Contrato

JSON en camelCase y nombres en inglés, con las mismas convenciones que Geoespacial. Todos los errores tienen la forma `{"code": <int>, "message": <str>, "details"?: [{"field", "reason"}]}`.

### UploadImage — `POST /api/v1/multimedia/images`

`multipart/form-data`:

| Parte | Obligatoria | Regla |
|---|---|---|
| `image` | sí | JPEG o PNG, de 1 a 3 670 016 bytes |
| `capturedAt` | no | ISO 8601 **con** zona horaria (`-05:00` o `Z`), no posterior al momento de la carga |
| `lat`, `lon` | no | Van juntas. −90..90 y −180..180; no se limitan a Bogotá (la ubicación oficial del reporte la valida Geoespacial) |

Respuesta `201` (cabecera `Location: /api/v1/multimedia/images/{imageId}/metadata`):

```json
{
  "imageId": "7f3c2a9e-1b4d-4c6e-9a8f-2d1e0b5c7a31",
  "imageUrl": "http://localhost:9000/urbanalert-images/7f3c2a9e-1b4d-4c6e-9a8f-2d1e0b5c7a31.jpg",
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
| `503 Service unavailable` | MinIO o MongoDB no responden. Si falla MongoDB, el objeto ya subido se borra |

### GetImageMetadata — `GET /api/v1/multimedia/images/{imageId}/metadata`

`200` con el mismo cuerpo de la subida; `404 Image not found` si no existe o el id no es un UUID; `503` si MongoDB no responde.

### Ver la imagen — `GET {imageUrl}`

La sirve el almacenamiento directamente, sin pasar por la función. Una URL inexistente no devuelve imagen (MinIO responde `404`).

**Para el servicio de Reportes:** recibe `imageUrl` del cliente y la guarda tal cual (mide menos de 2000 caracteres). Conviene validar que empiece por la URL base pública de Multimedia, para no aceptar imágenes externas.

**Para el cliente:** comprimir o redimensionar a 3,5 MB o menos, convertir HEIC a JPEG (Safari lo hace al subir; en Chrome, Edge y Firefox de escritorio hace falta una librería como `heic2any`) y enviar la fecha y las coordenadas de captura como campos, porque al recomprimir se pierde el EXIF.

## Configuración

Las variables se toman de `.env` (ver [.env.example](.env.example)). Si una variable no existe, se usa el valor por defecto de [compose.yaml](compose.yaml).

| Variable | Defecto local | Uso |
|---|---|---|
| `AWS_ENDPOINT_URL_S3` | `http://minio:9000` | Endpoint S3, leído por boto3. **En AWS no se define** |
| `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | credenciales de MinIO | En Lambda las pone el rol IAM |
| `S3_BUCKET` / `S3_ADDRESSING_STYLE` | `urbanalert-images` / `path` | Bucket y estilo de direcciones (`auto` en AWS) |
| `PUBLIC_IMAGE_BASE_URL` | `http://localhost:9000/urbanalert-images` | Prefijo de `imageUrl`, accesible desde el host. En la nube, el dominio del CDN |
| `MONGODB_URI` / `MONGODB_DATABASE` | `mongodb://…@mongo:27017/?authSource=admin` / `multimedia` | Metadatos |
| `MONGODB_TIMEOUT_MS` / `MONGODB_MAX_POOL_SIZE` | `3000` / `5` | Tiempo de espera y conexiones por instancia de Lambda |
| `MAX_IMAGE_BYTES` / `MULTIPART_OVERHEAD_BYTES` | `3670016` / `65536` | Tamaño máximo y margen para el rechazo temprano por `Content-Length` |
| `STORAGE_CONNECT_TIMEOUT_S` / `STORAGE_READ_TIMEOUT_S` / `STORAGE_MAX_ATTEMPTS` | `2` / `5` / `3` | Tiempos de espera y reintentos de S3 |
| `ENABLE_DOCS` | `false` | Rutas `/docs` y `/openapi.json`. Apagadas: la documentación es `docs/openapi.json` |
| `LOG_LEVEL` | `INFO` | Logs JSON a stdout con `correlationId` (cabecera `X-Correlation-Id`) y `awsRequestId` |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`, `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` | valores locales | Credenciales de los contenedores (solo para uso local) |

## Pruebas

Corren dentro de un contenedor con un bucket (`urbanalert-images-test`) y una base (`multimedia_test`) propios, que se vacían antes de cada prueba de integración.

```bash
podman compose --profile test run --rm --build tests                       # unitarias + integración + e2e
podman compose --profile test run --rm --build tests pytest tests/unit     # solo unitarias (sin servicios)
podman compose --profile test run --rm --build tests pytest tests/e2e      # contra el emulador de Lambda
```

| Nivel | Qué cubre |
|---|---|
| `tests/unit` | Detección de formato, reglas de captura, limpieza de metadatos, handler de Lambda con eventos de API Gateway, configuración y logs |
| `tests/integration` | Subida, metadatos, descarga anónima, política del bucket, fallos de MinIO/MongoDB con compensación, contrato OpenAPI |
| `tests/e2e` | Eventos de API Gateway contra el RIE: subida, consulta, imagen máxima (evento de 4,9 MB, < 15 s) y evento de más de 6 MB (el RIE lo trunca) |

Tras cambiar rutas o modelos, regenerar el contrato (la prueba `test_openapi` falla si no coincide):

```bash
podman compose --profile test build tests
podman run --rm -v "$PWD/docs:/out" --entrypoint python urbanalert-multimedia-tests -m app.export_openapi /out/openapi.json
```

## Despliegue en AWS (fuera del alcance local)

La misma imagen se sube a ECR y se despliega como Lambda de imagen de contenedor (512 MB, timeout 15 s) detrás de un API Gateway HTTP API, sin definir `AWS_ENDPOINT_URL_S3`. Puntos a tener en cuenta (detalle en el [plan](specs/001-servicio-multimedia/plan.md) §10):

- Bucket privado detrás de CloudFront con *Origin Access Control*. `PUBLIC_IMAGE_BASE_URL` pasa a ser el dominio del CDN.
- La regla de ciclo de vida (QAS-08) debe mover las imágenes a **S3 Glacier Instant Retrieval** o Intelligent-Tiering: Glacier Flexible o Deep Archive no se pueden leer con un GET directo.
- `MONGODB_MAX_POOL_SIZE` bajo y concurrencia reservada en Lambda, para no agotar las conexiones de MongoDB en un pico.
- El proceso `init` se ejecuta una vez por despliegue, con credenciales de administración que la función no tiene.

## Estructura

```text
app/              función: main.py (FastAPI + Mangum), service.py, config.py, logging_setup.py
  api/            rutas, esquemas y errores
  domain/         formato de imagen, reglas de captura, limpieza de metadatos (sin dependencias)
  storage/        S3/MinIO (boto3) y MongoDB (pymongo)
  admin/          init_resources.py (bucket, política, índices)
docs/             openapi.json (contrato) y SDD.md (guía del arnés)
scripts/          invoke-upload.sh
tests/            unit/, integration/, e2e/, samples.py (imágenes de prueba), events.py (eventos de API Gateway)
specs/            especificación, plan y tareas (SDD)
compose.yaml      minio, mongo, init, multimedia y tests (perfil "test")
Dockerfile        stages runtime (imagen Lambda) y test
```
