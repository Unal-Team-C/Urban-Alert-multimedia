# Especificación: Despliegue del Servicio Multimedia en AWS

- **ID**: 002-despliegue-aws
- **Estado**: aprobada <!-- borrador | aclarada | aprobada | implementada -->
- **Creada**: 2026-10-11
- **Entrada original**: "El repositorio de urban-alert-plataforma tiene las especificaciones de arquitectura de la plataforma. El de multimedia tiene una implementación que se hizo en local simulando un servicio lambda, un s3 para fotos y una base mongodb para metadatos. Ahora debemos llevar esto a AWS, pero debemos establecer dos flujos de github actions para ello: uno de aprovisionamiento al aprobar un pull request en main y otro para desaprovisionar, pero este bajo demanda, es decir ejecutando la action directamente; ambos scripts deben usar terraform. Ya hay una variable AWS_REGION y un secret AWS_ROLE_ARN." + "Tanto el s3 como mongodb deben ser servicios nativos de la nube." + decisión en la conversación: metadatos en Amazon DocumentDB (compatible con MongoDB), flujo SDD completo.

## 1. Resumen

Llevar el Servicio Multimedia, que hoy solo se ejecuta en contenedores locales (función emulada, MinIO y MongoDB), a AWS con servicios gestionados: el mismo código como función sin servidor (paquete de código, sin imagen de contenedor), las imágenes en el almacenamiento de objetos nativo de AWS y los metadatos en la base de documentos compatible con MongoDB de AWS. El servicio se publica **solo** a través del API Gateway de la plataforma compartida de UrbanAlert y usa su red privada. Toda la infraestructura se describe como código y la gestionan dos flujos de GitHub Actions: uno de aprovisionamiento, que se ejecuta al integrar cambios en `main`, y otro de desaprovisionamiento, que solo se lanza a mano. El contrato de la API no cambia.

## 2. Problema y contexto

- El servicio solo funciona en la máquina de cada integrante (`compose.yaml`): Reportes y el frontend no tienen una instancia compartida a la que subir evidencias, y las URL de imagen que devuelve (`http://localhost:9000/...`) no sirven fuera de esa máquina.
- Crear la infraestructura a mano en la consola no es repetible ni revisable, y no permite reconstruir el entorno si se borra.
- La plataforma compartida (`Unal-Team-C/urban-alert-plataforma`) ya ofrece la red privada (subredes privadas con salida a internet por NAT y acceso privado al almacenamiento de objetos) y el API Gateway por el que se exponen todos los microservicios. Publica su contrato en SSM Parameter Store (`/urban-alert/plataforma/`).
- Ya existen en la cuenta (348364742283, us-east-2): el proveedor OIDC de GitHub, el rol compartido que asumen los workflows (secreto `AWS_ROLE_ARN`, variable `AWS_REGION` en este repo) y el bucket del estado de Terraform `urban-alert-tfstate-348364742283`. El rol tiene hoy permisos pensados para servicios en contenedores (ECS); le faltan, entre otros, los de funciones sin servidor y de CDN.
- El README del servicio ya anticipa el despliegue: imagen de contenedor para la función (512 MB, 15 s), bucket privado servido por CDN, regla de ciclo de vida (QAS-08) hacia una clase de almacenamiento que siga permitiendo lectura directa, pool de conexiones bajo y concurrencia limitada, y un proceso de inicialización por despliegue.

## 3. Usuarios y actores

- **Equipo de desarrollo**: publicar cambios del servicio y de la infraestructura integrando un pull request en `main`, sin pasos en la consola, y eliminar el entorno cuando no se usa.
- **Cliente (frontend/app)**: subir evidencias y consultar sus metadatos por la URL del API Gateway, y ver las imágenes por su URL definitiva.
- **Servicio de Reportes**: guardar tal cual el `imageUrl` devuelto y validar que empieza por la URL base pública de Multimedia.
- **Revisor / docente**: entender desde el repositorio qué infraestructura existe, cómo se despliega y qué hay que configurar.

## 4. Historias de usuario

### HU-1: Aprovisionar y desplegar al integrar en `main` (Prioridad: P1)

Como integrante del equipo quiero que al integrar un pull request en `main` se aprovisione la infraestructura y quede desplegada la versión de ese commit, para no depender de pasos manuales.

**Criterios de aceptación**
1. Dado un pull request integrado en `main`, cuando termina el flujo de aprovisionamiento, entonces el servicio responde con la versión de ese commit a través de la URL del API Gateway.
2. Dado un commit en `main` que hace fallar las pruebas o las comprobaciones estáticas, cuando se ejecuta el flujo, entonces no se modifica la infraestructura ni se despliega nada, y el flujo queda en rojo.
3. Dado un commit en `main` sin cambios de infraestructura ni de código, cuando se ejecuta el flujo, entonces no se modifica ningún recurso salvo la referencia al commit desplegado, y el servicio sigue respondiendo.
4. Dados dos commits seguidos en `main`, cuando sus flujos coinciden en el tiempo, entonces se ejecutan uno detrás de otro, nunca a la vez.
5. Dado un pull request abierto o aprobado pero no integrado, cuando se revisa, entonces no se aprovisiona nada.

### HU-2: Desaprovisionar el entorno a mano (Prioridad: P1)

Como integrante del equipo quiero lanzar a mano un flujo que elimine el entorno, para no generar costes cuando no se usa y poder recrearlo después integrando en `main`.

**Criterios de aceptación**
1. Dado el repositorio en GitHub, cuando un integrante lanza el flujo de desaprovisionamiento y confirma la operación, entonces se eliminan los recursos del servicio gestionados como código y el resultado queda en el resumen de la ejecución.
2. Dado que se lanza el flujo sin la confirmación exacta, cuando se ejecuta, entonces no elimina nada e indica que falta la confirmación.
3. Dada la base de metadatos con datos, cuando se desaprovisiona, entonces antes de eliminarla queda una copia final restaurable, cuyo nombre aparece en el resumen.
8. Dadas imágenes subidas antes de desaprovisionar, cuando se desaprovisiona y se vuelve a aprovisionar, entonces sus `imageUrl` siguen descargando la imagen.
4. Dado el entorno desaprovisionado, cuando se integra un nuevo cambio en `main` (o se relanza el aprovisionamiento), entonces se recrea el entorno completo y el servicio vuelve a responder.
5. Dado el entorno ya eliminado, cuando se vuelve a lanzar el desaprovisionamiento, entonces termina sin error indicando que no había nada que eliminar.
6. El flujo nunca se ejecuta por un commit ni por un pull request; solo bajo demanda.
7. Dado el desaprovisionamiento terminado, cuando se revisa la plataforma compartida, entonces sigue intacta y ya no tiene rutas ni recursos del servicio que impidan desaprovisionarla.

### HU-3: Subir y consultar evidencias en la nube (Prioridad: P1)

Como cliente quiero subir una foto y consultar sus metadatos por el API Gateway, con el mismo contrato que en local, para integrar Multimedia sin cambios.

**Criterios de aceptación**
1. Dado el servicio desplegado, cuando un cliente envía `POST <gateway>/api/v1/multimedia/images` con un JPEG o PNG válido de hasta 3 670 016 bytes, entonces recibe `201` con `imageId`, `imageUrl` y el resto del cuerpo definido en `docs/openapi.json`.
2. Dado un `imageId` devuelto, cuando el cliente llama a `GET <gateway>/api/v1/multimedia/images/{imageId}/metadata`, entonces recibe `200` con el mismo cuerpo; con un id inexistente, `404`.
3. Dado un `imageUrl` devuelto, cuando se abre en un navegador, entonces se descarga la imagen ya sin metadatos incrustados, por HTTPS y sin pasar por la función.
4. Dado un formato no admitido, un archivo de más de 3 670 016 bytes o datos de captura inválidos, cuando se sube, entonces se responde `415`, `413` o `400` como en local.
5. Dada una ruta del gateway bajo `/api/v1/multimedia/` distinta de las dos publicadas (p. ej. `/docs`, `DELETE .../images/{id}`), cuando se llama, entonces el gateway responde `404`.

### HU-4: Almacenamiento privado y nativo de la nube (Prioridad: P1)

Como equipo queremos que imágenes y metadatos vivan en servicios gestionados de AWS, accesibles solo por donde corresponde, para no administrar servidores ni exponer datos.

**Criterios de aceptación**
1. Dado el entorno aprovisionado, cuando alguien intenta listar el contenido del almacenamiento de imágenes, escribir en él o leer un objeto directamente sin pasar por la CDN, entonces se le deniega.
2. Dado el entorno aprovisionado, cuando se intenta conectar a la base de metadatos desde internet o desde otro servicio de la VPC, entonces no es posible; solo la función de Multimedia (y su proceso de inicialización) llegan a ella.
3. Dado el servicio desplegado, cuando se conecta a la base de metadatos, entonces la conexión va cifrada y la credencial se lee del almacén de secretos en tiempo de ejecución.
4. Dada una imagen que lleva meses sin leerse (nivel de acceso poco frecuente), cuando se abre su `imageUrl`, entonces se sigue descargando con un GET directo.

### HU-5: Entender y reproducir el despliegue (Prioridad: P2)

Como revisor o nuevo integrante quiero encontrar en el repositorio cómo se despliega el servicio, qué recursos de arranque y permisos necesita y cuánto cuesta, para reproducir el entorno desde cero.

**Criterios de aceptación**
1. Dada la cuenta con solo los recursos de arranque y la plataforma aprovisionada, cuando se siguen los pasos documentados (incluidos los permisos que hay que añadir a mano al rol) y se integra en `main`, entonces se obtiene el entorno completo funcionando.
2. Dado el README, cuando se buscan las variables y secretos de GitHub, los workflows, las rutas publicadas y el coste mensual estimado, entonces aparecen con su propósito y sin valores secretos.

### Casos borde

- La plataforma compartida no está aprovisionada → el aprovisionamiento falla antes de cambiar nada, indicando que falta la plataforma (`ParameterNotFound` sobre `/urban-alert/plataforma/...`).
- El aprovisionamiento falla a mitad (permisos, cuotas, la base tarda en estar disponible) → el siguiente aprovisionamiento retoma desde el estado registrado sin duplicar recursos.
- El paquete de código supera el límite de subida directa de la función → la construcción falla indicando el tamaño, antes de tocar la infraestructura.
- La base de metadatos no responde tras el despliegue → la comprobación final del flujo falla (la consulta de metadatos responde `503`).
- Las colecciones e índices de la base no existen tras recrearla → el proceso de inicialización los crea en cada aprovisionamiento, sin error si ya existen.
- Un pico de subidas → el total de conexiones a la base no supera el límite fijado (RNF-002).
- Alguien cambia a mano un recurso gestionado como código → el siguiente aprovisionamiento lo devuelve a lo definido en el repositorio.
- Un cambio en `main` intentaría eliminar o reemplazar la base de metadatos o el almacenamiento de imágenes → el aprovisionamiento falla en lugar de borrarlos (solo el desaprovisionamiento puede).
- Otra feature ya registró una ruta con la misma clave en el gateway → el aprovisionamiento falla con conflicto y la ruta existente no cambia.
- Se lanza el desaprovisionamiento mientras corre un aprovisionamiento → espera a que termine.
- El flujo se lanza desde una rama distinta de `main` o desde un fork → no obtiene credenciales de AWS.
- Tras desaprovisionar y volver a aprovisionar, la base de metadatos nueva está vacía aunque las imágenes sigan en el bucket → las `imageUrl` siguen funcionando, pero `GET .../metadata` responde `404` hasta que se restaure a mano la copia final (procedimiento documentado).
- El rol de los workflows no tiene un permiso necesario → el flujo falla con `AccessDenied` indicando la acción, y la documentación de arranque dice qué política añadir.

## 5. Requisitos funcionales

- **RF-001**: La función de Multimedia DEBE desplegarse en AWS como función sin servidor con el runtime gestionado de Python 3.13, a partir de un paquete de código (.zip) construido en el flujo con las dependencias de `requirements.txt`, con 512 MB de memoria y 15 s de tiempo máximo. No se usa imagen de contenedor ni registro de imágenes _(cambio 2026-10-11)_.
- **RF-002**: Las imágenes DEBEN guardarse en Amazon S3, en un bucket privado: sin acceso público, sin listado y sin escritura salvo por la función. La lectura pública DEBE hacerse solo por una CDN con HTTPS, y `imageUrl` DEBE empezar por la URL base de esa CDN.
- **RF-003**: Los metadatos DEBEN guardarse en Amazon DocumentDB (compatible con MongoDB), en las subredes privadas de la plataforma, sin acceso público, con conexión cifrada obligatoria y almacenamiento cifrado.
- **RF-004**: La credencial de la base de metadatos DEBE guardarse en el almacén de secretos de AWS y la función DEBE leerla en tiempo de ejecución; no puede aparecer en el repositorio, en la imagen, en la configuración visible de la función, en las variables de GitHub ni en los logs.
- **RF-005**: El servicio DEBE registrar en el API Gateway compartido exactamente `POST /api/v1/multimedia/images` y `GET /api/v1/multimedia/images/{imageId}/metadata`, públicas (sin autenticación de clientes, como el resto de la plataforma), sin reescritura de ruta y sin registrar `$default` ni rutas fuera de su prefijo.
- **RF-006**: La función DEBE ejecutarse en las subredes privadas de la plataforma, tomando VPC, subredes, gateway y demás identificadores del contrato SSM en cada aprovisionamiento, sin copiarlos a mano. NO DEBE tener URL pública propia: solo se invoca a través del API Gateway compartido.
- **RF-007**: Cada aprovisionamiento DEBE ejecutar el proceso de inicialización de recursos (índices de la base de metadatos) dentro de la red privada, después de crear la base y antes de dar el despliegue por bueno; repetirlo no causa errores ni cambios.
- **RF-008**: La regla de ciclo de vida del almacenamiento de imágenes (QAS-08) DEBE pasar cada imagen a S3 Intelligent-Tiering desde el primer día, sin activar sus niveles de archivo opcionales (que exigen restauración): toda imagen sigue admitiendo lectura directa por GET, sin cargos por lectura _(clarificación 2026-10-11)_.
- **RF-009**: Toda la infraestructura del servicio DEBE estar definida como código con Terraform en este repositorio: función, roles y permisos, reglas de red, base de metadatos, secreto, bucket y su política, CDN, rutas en el gateway y logs. El estado DEBE guardarse en `urban-alert-tfstate-348364742283` bajo claves propias (`multimedia/...`), cifrado y con bloqueo.
- **RF-010**: El flujo de aprovisionamiento DEBE ejecutarse cuando se integran cambios en `main` y, en este orden: comprobaciones estáticas y pruebas unitarias; comprobación de que la plataforma está aprovisionada; almacenamiento de imágenes; recursos base; construcción del paquete de código; funciones; inicialización (RF-007); rutas; prueba de humo a través del gateway; resumen con la URL del gateway y la URL base de las imágenes. Cualquier paso fallido DEBE detener los siguientes.
- **RF-011**: El flujo de desaprovisionamiento DEBE ejecutarse solo a mano (bajo demanda desde GitHub), exigir que se escriba `urban-alert-multimedia` para confirmar, ejecutarse solo sobre `main`, y eliminar en orden inverso: rutas del gateway y función, y después los recursos base, dejando antes una copia final de la base de metadatos. No toca la plataforma compartida, los recursos de arranque ni el almacenamiento persistente de imágenes (RF-017).
- **RF-017**: El bucket de imágenes, con sus imágenes, y la CDN que las sirve DEBEN conservarse al desaprovisionar, fuera del alcance de ese flujo. El siguiente aprovisionamiento DEBE reutilizarlos, de modo que las `imageUrl` emitidas antes sigan funcionando. Ningún flujo puede borrar el bucket ni su contenido _(clarificación 2026-10-11)_.
- **RF-012**: La protección contra borrado de la base de metadatos solo la desactiva el flujo de desaprovisionamiento, nunca el de aprovisionamiento.
- **RF-013**: Los flujos DEBEN autenticarse en AWS con el rol de `AWS_ROLE_ARN` por OIDC (credenciales temporales) en la región de `AWS_REGION`, sin claves de larga duración.
- **RF-014**: Aprovisionamiento y desaprovisionamiento DEBEN compartir un grupo de concurrencia sin cancelación: nunca se ejecutan a la vez.
- **RF-015**: El repositorio DEBE documentar: los permisos que hay que añadir a mano al rol compartido (como JSON versionado de la política, igual que en Geoespacial y la plataforma); las variables y secretos de GitHub; cómo funciona cada flujo; las rutas publicadas; el coste mensual estimado; y cómo desplegar y desaprovisionar.
- ~~**RF-016**: El entorno local (`compose.yaml`, pruebas unitarias, de integración y e2e) DEBE seguir funcionando sin cambios en su forma de uso.~~ Eliminado (2026-10-11): el entorno local deja de ser necesario. Sus archivos no se borran en esta feature, pero no se mantienen; las pruebas unitarias siguen siendo obligatorias.

## 6. Requisitos no funcionales

- **RNF-001 (seguridad)**: Ningún secreto aparece en el repositorio, la imagen, variables de GitHub, salidas de Terraform ni logs de los flujos. El almacenamiento de imágenes y la base de metadatos no tienen acceso público. La función solo tiene los permisos que usa (escribir y borrar objetos de su bucket, leer su secreto, red en la VPC, logs).
- **RNF-002 (conexiones)**: El número máximo de conexiones simultáneas de la función a la base (instancias concurrentes × pool por instancia) está acotado y documentado, y es inferior al máximo que admite la instancia elegida.
- **RNF-003 (idempotencia)**: Dos aprovisionamientos seguidos sobre el mismo commit dan cero cambios de infraestructura en el segundo.
- **RNF-004 (latencia)**: Una subida de una imagen de 3,5 MB a través del gateway responde en menos de 15 s, incluida una invocación en frío.
- **RNF-005 (duración)**: Un aprovisionamiento sin cambios de infraestructura termina en menos de 15 minutos.
- **RNF-006 (coste)**: Se usan los tamaños mínimos adecuados para un proyecto académico (una sola instancia de base, la clase más pequeña admitida) y cada recurso con coste figura en una tabla de costes del README con su estimación mensual.
- **RNF-007 (protección de datos)**: La base de metadatos tiene copias automáticas con al menos 7 días de retención y protección contra borrado accidental.
- **RNF-008 (trazabilidad)**: La versión desplegada se puede rastrear hasta su commit (la función lleva el SHA como etiqueta y el resumen del flujo lo muestra) y los logs de la función quedan en CloudWatch con retención definida.

## 7. Entidades clave

No hay entidades de datos nuevas: el documento de metadatos de imagen (colección `images`) y el contrato de la API no cambian. Recursos del entorno relevantes:

- **Entorno de Multimedia en la nube**: funciones, bucket de imágenes, CDN, base de metadatos, secreto, reglas de red, rutas en el gateway y logs.
- **Plataforma compartida** (externa): red privada, salida a internet y API Gateway; esta feature solo la consume.
- **Recursos de arranque** (externos): proveedor OIDC, rol de los workflows con sus políticas, bucket del estado.

## 8. Fuera de alcance

- Dominio propio para el gateway o para la CDN (se usan los dominios que asigna AWS).
- Autenticación de clientes en el gateway (la plataforma no la tiene, RF-017 de su spec 001).
- Entornos múltiples (solo uno, el de la cuenta 348364742283).
- Limpieza diferida de objetos huérfanos (HU-6 de la spec del servicio) y migración de datos desde el entorno local.
- Cambios en el contrato de la API o en el comportamiento funcional del servicio.
- Restaurar automáticamente la copia final de la base de metadatos al volver a aprovisionar (se documenta el procedimiento manual).
- Crear o modificar los recursos de arranque desde los workflows (los permisos nuevos se añaden a mano, documentados).
- Mantener el entorno local (`compose.yaml`, `Dockerfile`, pruebas de integración y e2e contra MinIO/MongoDB/RIE).

## 9. Supuestos

- "Al aprobar un pull request en main" se interpreta como **al integrarlo** (evento `push` a `main`): el rol de AWS solo confía en la rama `main` (`ref:refs/heads/main`), y desplegar código aprobado pero no integrado dejaría `main` y AWS desalineados. Es el mismo criterio que la plataforma y Geoespacial. Como el repo es privado en un plan sin protección de ramas, un push directo a `main` también dispara el aprovisionamiento.
- La plataforma compartida está aprovisionada antes del primer aprovisionamiento, y su NAT da a la función salida hacia el almacén de secretos; S3 se alcanza por el endpoint de gateway que ya tiene la plataforma.
- Una persona con permisos de administración añade a mano al rol compartido los permisos que falten (funciones sin servidor, CDN, paso de rol a la función, logs de la función), siguiendo el JSON versionado en este repo.
- La URL base de la CDN que asigna AWS se acepta como URL definitiva mientras el entorno exista.
- Las rutas de subida y consulta son públicas, igual que en local; el límite de tasa y CORS los pone el gateway compartido.
- Un despliegue en una sola zona para la base de metadatos (una instancia) es suficiente para un proyecto académico.

## 10. Métricas de éxito

- **MS-001**: Tras integrar en `main`, en menos de 30 minutos (primer aprovisionamiento, con la creación de la base) una subida por el gateway devuelve `201` y su `imageUrl` se abre en un navegador.
- **MS-002**: El desaprovisionamiento deja cero recursos del servicio con coste por hora en la cuenta (quedan la copia final de la base, el bucket de imágenes y la CDN, que solo cobran por almacenamiento y uso) y la plataforma puede desaprovisionarse después sin encontrar dependientes de Multimedia.
- **MS-003**: Un integrante sin contexto reproduce el entorno siguiendo solo la documentación.

## 11. Clarificaciones

### Sesión 2026-10-11
- P: Al desaprovisionar, ¿qué pasa con las imágenes? → R: (b) el bucket y sus imágenes se conservan fuera del desaprovisionamiento. Se conserva también la CDN (sin coste por hora) para que las `imageUrl` emitidas no cambien → RF-017, HU-2 #8.

- Cambio del usuario: despliegue como .zip en vez de imagen de contenedor; "el entorno local ya no es necesario" → RF-001 cambiado, RF-016 eliminado, sin registro de imágenes.
- P: Regla de ciclo de vida QAS-08: ¿tras cuántos días y a qué clase? → R: Intelligent-Tiering desde el primer día, sin niveles de archivo opcionales (sin cargos por lectura ni mínimo de 90 días; baja sola a 0,0125 y 0,004 USD/GB-mes) → RF-008, HU-4 #4.

---

### Checklist de calidad (autorrevisión antes de entregar)

- [x] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código)
- [x] Cada requisito es testeable y no ambiguo
- [x] Criterios de aceptación con resultado observable
- [x] Casos borde identificados
- [x] Alcance acotado (fuera de alcance explícito)
- [x] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes
- [x] Coherente con `.sdd/constitution.md` (plantilla vacía; se siguen los principios de la plataforma: IaC solo desde Actions, OIDC, sin secretos, destructivo solo explícito, coste documentado)
