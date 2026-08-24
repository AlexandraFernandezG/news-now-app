# NewsNow

MVP de un periódico digital sobre AWS, 100% serverless. **Fase 1**:
infraestructura como código y la API de artículos. **Fase 2**: capa de IA
sobre Amazon Bedrock, resumen automático por artículo y digest diario.

---

## Estructura del repositorio

```
news-now-app/
├── terraform/
│   ├── bootstrap/                 # state bucket + lock table (+ rol OIDC), se aplica primero y aparte
│   ├── modules/
│   │   ├── lambda-function/       # Lambda + rol IAM propio + log group
│   │   └── static-site/           # S3 privado + OAC + CloudFront con fallback SPA
│   ├── ai/                        # Fase 2 — stack independiente (estado propio)
│   │   ├── bedrock_iam.tf         # policies IAM de summarize_article y daily_digest
│   │   ├── dynamodb_digests.tf    # tabla digests
│   │   ├── summarize_article.tf   # Lambda + DLQ (SQS) + event source mapping del stream
│   │   ├── daily_digest.tf        # Lambda + rol + EventBridge Scheduler (cron diario)
│   │   ├── alarms.tf              # alarma de errores de summarize_article
│   │   ├── main.tf                # providers, data source de la tabla articles, locals
│   │   ├── backend.tf             # backend S3 (key propia, mismo bucket que la Fase 1)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── main.tf                    # providers, locals, instanciación de módulos
│   ├── backend.tf                 # backend S3 → recursos del bootstrap
│   ├── api_gateway.tf             # HTTP API, JWT authorizer, rutas, stage
│   ├── api_cache_cloudfront.tf    # CloudFront delante del API (cachea GET /articles)
│   ├── waf.tf                     # Web ACL de la app pública (us-east-1)
│   ├── dynamodb.tf                # tabla articles + Streams + GSI
│   ├── cognito.tf                 # User Pool, dominio y App Client
│   ├── iam.tf                     # políticas mínimas de cada Lambda
│   ├── variables.tf
│   └── outputs.tf
├── src/
│   ├── articles/                  # los 4 handlers del CRUD
│   └── common/                    # db.py (DynamoDB) · responses.py (HTTP)
├── tests/                         # unit tests de los 4 handlers, DynamoDB mockeada
├── ai-summarizer/                 # Fase 2 — handlers de la capa de IA
│   ├── summarize_article.py       # consumidor del stream, Bedrock Haiku
│   ├── daily_digest.py            # disparado por EventBridge Scheduler, Bedrock Sonnet
│   └── tests/                     # moto (DynamoDB) + mocks de la respuesta de Bedrock
├── docs/ai-usage/                 # prompts y evidencia de uso de IA
├── .github/workflows/deploy.yml   # CI/CD con OIDC
├── requirements-test.txt          # deps solo para tests (pytest, boto3, moto)
├── pytest.ini
└── CLAUDE.md
```

---

## Despliegue

Requisitos: Terraform ≥ 1.5 y credenciales AWS con permisos de administración
para el paso 1.

### 1. Bootstrap (una sola vez)

Crea el bucket del state y la tabla de locks. Va aparte porque el backend
remoto no puede existir antes que el bucket que lo aloja.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Para habilitar además el rol de CI/CD:

```bash
terraform apply -var='github_repository=mi-org/news-now-app'
```

> Los nombres de bucket S3 son globales. Si `news-now-terraform-state` está
> ocupado, cambia `state_bucket_name` aquí y el `bucket` de
> `terraform/backend.tf` (o pasa `-backend-config="bucket=…"` en el init).

### 2. Stack de aplicación

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Salidas relevantes: `public_app_url`, `admin_app_url`, `api_url`,
`cognito_user_pool_id`, `cognito_user_pool_client_id`, `public_app_bucket`,
`admin_app_bucket`.

Para validar el HCL sin credenciales ni backend remoto:

```bash
terraform init -backend=false && terraform validate
```

### 3. Alta del primer redactor

El User Pool tiene el registro abierto deshabilitado: las cuentas las crea un
administrador.

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$(terraform output -raw cognito_user_pool_id)" \
  --username redactor@ejemplo.com \
  --user-attributes Name=email,Value=redactor@ejemplo.com Name=email_verified,Value=true
```

---

## API

Base: el output `api_url` (CloudFront). El endpoint directo del API Gateway
(`api_endpoint`) existe para depurar, sin caché.

| Método | Ruta | Auth | Respuesta |
|---|---|---|---|
| `GET` | `/articles` | — | `200` `{ items, count, next }` |
| `POST` | `/articles` | JWT | `201` artículo creado |
| `PUT` | `/articles/{id}` | JWT | `200` artículo actualizado |
| `DELETE` | `/articles/{id}` | JWT | `204` sin cuerpo |

**Parámetros de `GET /articles`**

| Parámetro | Descripción |
|---|---|
| `publish_date` | `YYYY-MM-DD`. Consulta el GSI en lugar de recorrer la tabla |
| `limit` | 1–100 (20 por defecto) |
| `next` | Cursor de paginación devuelto por la llamada anterior |

**Cuerpo de `POST` / `PUT`**

```json
{
  "title": "Titular",
  "content": "Cuerpo del artículo",
  "image_url": "https://…",
  "tags": ["politica"],
  "status": "published",
  "publish_date": "2026-08-22"
}
```

`title` y `content` son obligatorios en `POST`; en `PUT` todos los campos son
opcionales pero debe llegar al menos uno. `author`, `id`, `created_at` y
`updated_at` los fija el servidor — la autoría sale del JWT, nunca del cuerpo.
Cualquier campo no reconocido produce `400`.

**Errores**: `400` validación · `401` token ausente o inválido (lo emite API
Gateway) · `404` artículo inexistente · `409` colisión al crear · `500`
inesperado. El cuerpo es siempre `{ "message": "...", "details": {...} }`.

---

## Fase 2 — capa de IA

Stack independiente en `terraform/ai/` (estado propio, mismo bucket de
backend que la Fase 1), que añade la generación de resúmenes sobre la
infraestructura ya desplegada sin tocarla — referencia la tabla `articles`
por nombre en lugar de gestionarla.

Para desplegarlo (tras el stack de la Fase 1):

```bash
cd terraform/ai
terraform init
terraform plan
terraform apply
```

Para validar el HCL sin credenciales ni backend remoto:

```bash
terraform init -backend=false && terraform validate
```
