# NewsNow — Fase 1: infraestructura base

MVP de un periódico digital sobre AWS, íntegramente serverless. Esta fase
entrega la infraestructura como código y la API de artículos. La capa de IA
(resúmenes) corresponde a la Fase 2 y **no** está implementada, aunque la base
de datos ya queda preparada para ella.

---

## Arquitectura

```
                        ┌──────────────────────────────┐
   Lectores  ──────────►│ CloudFront + WAF (rate limit)│──► S3 news-now-public-app (privado, OAC)
                        └──────────────────────────────┘
                        ┌──────────────────────────────┐
   Redacción ──────────►│ CloudFront                   │──► S3 news-now-admin-app  (privado, OAC)
                        └──────────────────────────────┘
                        ┌──────────────────────────────┐
   Ambas SPAs ─────────►│ CloudFront  (cachea GET      │──► API Gateway HTTP API
                        │  /articles, TTL 60s)         │      │  JWT Authorizer (Cognito)
                        └──────────────────────────────┘      │
                                                              ├─ get_articles     (público)
                                                              ├─ create_article   (JWT)
                                                              ├─ update_article   (JWT)
                                                              └─ delete_article   (JWT)
                                                                      │
                                                              DynamoDB `articles`
                                                              on-demand · Streams ON
                                                              GSI publish_date-index
```

Nada se aprovisiona por capacidad: S3, CloudFront, Lambda, API Gateway HTTP API
y DynamoDB on-demand escalan solos ante los picos de tráfico impredecibles.

### Piezas y por qué están

| Requisito | Implementación |
|---|---|
| Dos SPAs sin exponer S3 | Buckets privados + un OAC por distribución; el bucket policy solo acepta a *su* distribución (`AWS:SourceArn`) |
| React Router | `custom_error_response` 403 y 404 → `/index.html` con código **200** |
| Protección de la app pública | Web ACL WAFv2, `scope = CLOUDFRONT` en us-east-1, regla `rate_based_statement`: **2000 req/IP cada 300 s**, acción `block` |
| Caché del listado | Behavior `/articles` con cache policy propia (TTL variable, 60 s por defecto) y `cached_methods = [GET, HEAD]`; el behavior por defecto usa `CachingDisabled` |
| Autenticación | Cognito User Pool + App Client (SPA, sin secreto, code + PKCE) y JWT Authorizer nativo del HTTP API |
| Menor privilegio | Un rol por Lambda con una política inline que contiene solo sus acciones DynamoDB. Sin `AWSLambdaBasicExecutionRole` |
| Observabilidad | Un Log Group explícito por Lambda + logs de acceso del API, todos a **14 días** |
| Preparado para Fase 2 | Streams `NEW_AND_OLD_IMAGES` y GSI `publish_date-index` creados ya: añadirlos después obligaría a recrear la tabla |

### Detalles que merecen explicación

**`POST /articles` comparte ruta con el listado cacheado.** Los
`ordered_cache_behavior` de CloudFront seleccionan por patrón de ruta, no por
método. El behavior de `/articles` permite todos los métodos pero solo cachea
`GET`/`HEAD`, de modo que las escrituras siempre llegan al origen sin que un
POST reciba un 405.

**`Authorization` se reenvía al origen pero no entra en la clave de caché.**
`GET /articles` es público e idéntico para todos: incluir la cabecera
fragmentaría la caché por usuario sin ninguna ganancia.

**El GSI es `publish_date` (hash) + `created_at` (range).** Con `publish_date`
en formato `YYYY-MM-DD`, el resumen diario de la Fase 2 es una única Query
sobre una sola partición, y `created_at` ordena dentro del día.

---

## Estructura del repositorio

```
news-now-app/
├── terraform/
│   ├── bootstrap/                 # state bucket + lock table (+ rol OIDC), se aplica primero y aparte
│   ├── modules/
│   │   ├── lambda-function/       # Lambda + rol IAM propio + log group
│   │   └── static-site/           # S3 privado + OAC + CloudFront con fallback SPA
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
├── ai-summarizer/                 # Fase 2 — stubs, sin implementar
├── docs/ai-usage/                 # prompts y evidencia de uso de IA
├── .github/workflows/deploy.yml   # CI/CD con OIDC
├── requirements-test.txt          # deps solo para tests (pytest, boto3)
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
  "excerpt": "Entradilla",
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

## Tests

Unit tests de los 4 handlers en `tests/`, con la tabla DynamoDB mockeada
(`unittest.mock`, sin `moto` ni AWS real) — verifican validación, construcción
de las llamadas a DynamoDB y traducción de errores a códigos HTTP.

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements-test.txt   # solo pytest + boto3
.venv/Scripts/pytest -v
```

`boto3` y `pytest` son dependencias de test únicamente: nunca viajan en el zip
de una Lambda (el empaquetado en `terraform/main.tf` lista los ficheros de
`src/` explícitamente, ver [CLAUDE.md](CLAUDE.md)), y en producción `boto3` lo
aporta el propio runtime de Lambda.

| Fichero | Qué cubre |
|---|---|
| `tests/conftest.py` | Fixtures: `mock_table` (mockea `common.db.get_table`), `event_factory` (eventos de API Gateway HTTP API) |
| `tests/test_get_articles.py` | Scan vs. Query al GSI, paginación, validación de `limit`/`publish_date`/cursor |
| `tests/test_create_article.py` | Alta, valores por defecto, autoría desde el JWT (nunca desde el body), validaciones, `409` en duplicado |
| `tests/test_update_article.py` | Actualización parcial, reinicio de `summary_status` al tocar `title`/`content`, `404` en inexistente |
| `tests/test_delete_article.py` | Borrado condicional, `404` en inexistente |

57 tests, 100% de cobertura de líneas en los 4 handlers (`pytest --cov=articles`).

---

## CI/CD

`.github/workflows/deploy.yml`, autenticación por OIDC (sin claves estáticas).
Requiere el secreto `AWS_DEPLOY_ROLE_ARN` con el output
`github_actions_role_arn` del bootstrap.

| Job | Cuándo | Qué hace |
|---|---|---|
| `validate` | siempre | `compileall` de `src/`, `terraform fmt -check`, `init -backend=false`, `validate` |
| `plan` | pull request | `terraform plan` y comentario con el resultado en la PR |
| `apply` | push a `main` | `terraform apply` y exportación de outputs |
| `frontends` | push a `main` | build y `s3 sync` de cada SPA + invalidación de CloudFront |

`frontends` se salta solo mientras no existan `apps/public/` y `apps/admin/`,
que no forman parte de la Fase 1.

---

## Fase 2 — qué queda preparado

| Pieza | Output de Terraform |
|---|---|
| Stream de la tabla, para disparar el resumen por artículo | `articles_table_stream_arn` |
| GSI por fecha, para el resumen diario | `articles_publish_date_index` |

Además, todo artículo se escribe con `summary: null` y
`summary_status: "PENDING"`, y `update_article` vuelve a marcarlo como
`PENDING` cuando cambia `title` o `content`. Detalle en
[docs/ai-usage/02-fase2-prompt.md](docs/ai-usage/02-fase2-prompt.md).

---

## Verificación de esta entrega

Ejecutado con Terraform 1.15.9 y provider AWS 6.61.0. **No se ha hecho
`apply`**: no existe ningún recurso en AWS.

```
terraform validate (bootstrap)   → Success
terraform plan     (bootstrap)   → 8 to add, 0 to change, 0 to destroy
terraform validate (raíz)        → Success
terraform plan     (raíz)        → 59 to add, 0 to change, 0 to destroy
terraform fmt -check -recursive  → OK
python -m compileall src         → OK
```

El plan de la raíz se ejecutó con un override temporal a backend local, ya que
el bucket de state solo existe tras aplicar el bootstrap.

Avisos conocidos: el provider AWS 6.x marca `hash_key` como obsoleto en favor
de `key_schema`. Se mantiene `hash_key` a propósito, porque `key_schema` no
existe en el provider 5.x y el rango declarado (`>= 5.40.0, < 7.0.0`) admite
ambas versiones mayores.

## Antes de producción

- `cors_allow_origins` está en `["*"]`; restringirlo a los dos dominios
  CloudFront reales.
- Revisar que los nombres de bucket globales (`news-now-public-app`,
  `news-now-admin-app`, `news-now-terraform-state`) estén libres.
- `GET /articles` sin filtro hace `Scan` paginado. Es adecuado para el volumen
  de un MVP y va amortiguado por la caché, pero cuando crezca el archivo la
  portada deberá pedir un `publish_date` concreto y pasar por el GSI.
