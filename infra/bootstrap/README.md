# Recursos de arranque de Multimedia

Terraform no gestiona estos recursos: los necesita para poder ejecutarse, y el workflow de desaprovisionamiento no debe borrarlos (spec 002, RF-013 y RF-015).

Cuenta `348364742283`, región `us-east-2`. El JSON de esta carpeta es la copia versionada de lo configurado en AWS: si se cambia la política en la consola, hay que actualizar aquí el JSON, y al revés.

## Lo que ya existe (compartido con los demás repos)

| Recurso | Dónde está documentado |
|---|---|
| Proveedor OIDC de GitHub | [urban-alert-geoespacial/infra/bootstrap](https://github.com/Unal-Team-C/urban-alert-geoespacial/tree/main/infra/bootstrap) |
| Rol de los workflows (`github-actions-…`) y su confianza `repo:Unal-Team-C@335834608/*:ref:refs/heads/main` | ídem; cubre también este repo |
| Políticas `github-actions-urban-alertPolicy` y `github-actions-urban-alert-terraform` | ídem: S3 `urban-alert-*`, DocumentDB (`rds:*`), secretos `urban-alert-*`, roles `urban-alert-*`, grupos de seguridad |
| Política `github-actions-urban-alert-platform` | [urban-alert-plataforma/infra/bootstrap](https://github.com/Unal-Team-C/urban-alert-plataforma/tree/main/infra/bootstrap): API Gateway, SSM `/urban-alert/*` |
| Bucket del estado `urban-alert-tfstate-348364742283` | ídem Geoespacial. Este repo usa las claves `multimedia/*.tfstate` |
| Secreto `AWS_ROLE_ARN` y variable `AWS_REGION` (`us-east-2`) de GitHub | Settings → Secrets and variables → Actions de este repo (ya configurados) |

## Pasos manuales (una sola vez, antes del primer Provision)

### 1. Política de Multimedia en el rol de GitHub

Las políticas actuales no permiten crear funciones Lambda ni distribuciones de CloudFront, solo pasan roles a ECS y solo crean logs en `/ecs/*` y `/aws/apigateway/*`. Lo que falta está en [github-multimedia-policy.json](github-multimedia-policy.json) (plan D-011).

Con un usuario con permisos de IAM, sustituyendo `<rol-de-github>` por el nombre del rol de `AWS_ROLE_ARN` (lo que va después de `role/`):

```bash
aws iam create-policy --policy-name github-actions-urban-alert-multimedia \
  --policy-document file://infra/bootstrap/github-multimedia-policy.json
aws iam attach-role-policy --role-name <rol-de-github> \
  --policy-arn arn:aws:iam::348364742283:policy/github-actions-urban-alert-multimedia
```

Para actualizarla tras un cambio del JSON (se conservan hasta 5 versiones; borra la más antigua si hace falta):

```bash
aws iam create-policy-version --set-as-default \
  --policy-arn arn:aws:iam::348364742283:policy/github-actions-urban-alert-multimedia \
  --policy-document file://infra/bootstrap/github-multimedia-policy.json
```

| Bloque | Para qué |
|---|---|
| `LambdaProjectFunctions` | Crear, actualizar y borrar las funciones `urban-alert-multimedia` y `-init`, concederle al gateway permiso de invocación e invocar la de inicialización desde el workflow |
| `PassRolesToLambda` | Asignar los roles `urban-alert-multimedia-*` a las funciones (las políticas actuales solo pasan roles a ECS) |
| `LambdaLogGroups` | Grupos de logs `/aws/lambda/urban-alert-*` con su retención |
| `CloudFrontImages` | **Sin uso** desde el plan D-015: la cuenta no está verificada para CloudFront y las imágenes se sirven desde S3. Se conserva porque el JSON refleja lo aplicado en AWS; se puede quitar con una versión nueva de la política. Era para la distribución y el Origin Access Control del bucket de imágenes. CloudFront es global y sus acciones de creación no admiten restringir el recurso por nombre. `cloudfront:CreateDistributionWithTags` no existe como acción de IAM: crear con etiquetas lo cubren `CreateDistribution` + `TagResource` |

### 2. Límite de concurrencia de Lambda

Se supone que la cuenta tiene el límite de las cuentas nuevas: 10 ejecuciones concurrentes en total (plan D-008). Por eso la función no reserva concurrencia (`concurrencia_reservada = -1` en `infra/servicio/terraform.tfvars`). Lambda exige dejar 10 sin reservar, y con un límite de 10 no se puede reservar nada.

Con un usuario que pueda consultarlo:

```bash
aws lambda get-account-settings --query 'AccountLimit.ConcurrentExecutions'
```

Si el límite es de 20 o más, se puede poner `concurrencia_reservada = 10` para fijar el tope de conexiones a DocumentDB (10 × 4 = 40). Para subirlo: Service Quotas → AWS Lambda → *Concurrent executions*.

### 3. Comprobar

Lanzar Provision con un push a `main`, con la plataforma ya aprovisionada.

- Si falla en `configure-aws-credentials`, el problema es la confianza OIDC del rol o el secreto o la variable de GitHub.
- Si falla con `AccessDenied` sobre `lambda:`, `iam:PassRole` o `logs:` de `/aws/lambda/`, falta el paso 1. El siguiente push retoma desde el estado.
- Si falla `PutBucketPolicy` con `AccessDenied` y un mensaje sobre *public policies* / *BlockPublicPolicy*, la cuenta tiene activado Block Public Access a nivel de cuenta: un administrador debe desactivar en la cuenta las opciones de políticas públicas (S3 → Block Public Access settings for this account), porque el bucket de imágenes es de lectura pública (plan D-015).
