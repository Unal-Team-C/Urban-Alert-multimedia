# Inventario de recursos de AWS

Cuenta `348364742283`, región `us-east-2`. Spec 002 (RF-009, RF-015, RF-017). Ningún recurso de este servicio se creó a mano antes del código: no hay importaciones.

## 1. Recursos creados por Terraform

| Stack | Estado | Recursos | Deprovision |
|---|---|---|---|
| `almacen` | `multimedia/almacen.tfstate` | Bucket `urban-alert-multimedia-images-348364742283` (Block Public Access, propietario, SSE-S3, ciclo de vida Intelligent-Tiering día 0 y limpieza de multipart a 7 días, política solo para CloudFront + TLS); Origin Access Control `urban-alert-multimedia-images-348364742283`; distribución de CloudFront (`PriceClass_100`) | **Se conserva** (`prevent_destroy`) |
| `base` | `multimedia/base.tfstate` | En la VPC compartida: SG `urban-alert-multimedia-lambda` y `urban-alert-multimedia-docdb`, subnet group y grupo de parámetros `urban-alert-multimedia-docdb`, clúster DocumentDB `urban-alert-multimedia-docdb` + instancia `urban-alert-multimedia-docdb-1`; secreto `urban-alert-multimedia-docdb`; roles `urban-alert-multimedia-api` y `urban-alert-multimedia-init` (políticas en línea `*-runtime`); grupos de logs `/aws/lambda/urban-alert-multimedia` y `/aws/lambda/urban-alert-multimedia-init` | Se elimina; queda la copia `urban-alert-multimedia-final-<run_id>` |
| `servicio` | `multimedia/servicio.tfstate` | Funciones Lambda `urban-alert-multimedia` (API) y `urban-alert-multimedia-init` (y las interfaces de red que Lambda crea en las subredes privadas) | Se elimina |
| `rutas` | `multimedia/rutas.tfstate` | En el API Gateway compartido: 1 integración `AWS_PROXY` y las rutas `POST /api/v1/multimedia/images` y `GET /api/v1/multimedia/images/{imageId}/metadata`; permiso `AllowSharedGatewayMultimediaRoutes` en la función | Se elimina |

Para borrar de verdad el bucket o la distribución habría que quitar `prevent_destroy` en un commit y añadir a un workflow un paso que destruya el stack `almacen` (nunca a mano, P1). No está previsto: las `imageUrl` guardadas por Reportes dejarían de funcionar.

## 2. Recursos externos de arranque (no gestionados por Terraform)

Terraform los necesita para ejecutarse; los workflows no los tocan. Cómo crearlos: [bootstrap/README.md](bootstrap/README.md).

| Recurso | ID en AWS | Notas |
|---|---|---|
| Proveedor OIDC de GitHub | `arn:aws:iam::348364742283:oidc-provider/token.actions.githubusercontent.com` | Compartido; documentado en `urban-alert-geoespacial/infra/bootstrap` |
| Rol de los workflows | ARN en el secreto `AWS_ROLE_ARN` de GitHub (`github-actions-…`) | Compartido; confía en `repo:Unal-Team-C@335834608/*:ref:refs/heads/main` |
| Política `github-actions-urban-alertPolicy` | `arn:aws:iam::348364742283:policy/github-actions-urban-alertPolicy` | S3, DocumentDB (`rds:*`), secretos, grupos de seguridad |
| Política `github-actions-urban-alert-terraform` | `arn:aws:iam::348364742283:policy/github-actions-urban-alert-terraform` | Roles `urban-alert-*`, KMS vía RDS y Secrets Manager |
| Política `github-actions-urban-alert-platform` | `arn:aws:iam::348364742283:policy/github-actions-urban-alert-platform` | API Gateway, SSM `/urban-alert/*` |
| Política `github-actions-urban-alert-multimedia` | `arn:aws:iam::348364742283:policy/github-actions-urban-alert-multimedia` | **De este repo**: [bootstrap/github-multimedia-policy.json](bootstrap/github-multimedia-policy.json) (Lambda, CloudFront, PassRole a Lambda, logs `/aws/lambda/urban-alert-*`) |
| Bucket del estado | `urban-alert-tfstate-348364742283` | Claves `multimedia/{almacen,base,servicio,rutas}.tfstate` |

## 3. Plataforma compartida (otro repo, no gestionada aquí)

`Unal-Team-C/urban-alert-plataforma`: VPC, subredes privadas, NAT, endpoint de gateway S3, API Gateway y VPC Link. Este repo solo lee su contrato en SSM (`/urban-alert/plataforma/`) y registra rutas en su gateway; Deprovision elimina esas rutas y nunca toca la plataforma.
