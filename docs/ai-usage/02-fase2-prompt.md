# Fase 2 — Prompt de la capa de IA

**Herramienta:** Claude Code (modelo Sonnet 5)
**Fecha:** 2026-08-23
**Alcance:** resumen automático por artículo (`summarize_article`) y digest
diario (`daily_digest`), sobre Amazon Bedrock. Añade a la infraestructura de
la [Fase 1](01-fase1-prompt.md); no la modifica.

---

## Qué dejó listo la Fase 1

| Pieza | Dónde | Para qué sirve en Fase 2 |
|---|---|---|
| DynamoDB Streams (`NEW_AND_OLD_IMAGES`) | [dynamodb.tf](../../terraform/dynamodb.tf) | Disparar el resumen al crear/editar un artículo. |
| GSI `publish_date-index` | [dynamodb.tf](../../terraform/dynamodb.tf) | Recuperar lo publicado un día concreto con una única Query. |
| Campos `summary` y `summary_status` | [create_article.py](../../src/articles/create_article.py) | Todo artículo nace con `summary = null` y `summary_status = "PENDING"`. |
| Reinicio de `summary_status` | [update_article.py](../../src/articles/update_article.py) | Al cambiar `title` o `content` vuelve a `"PENDING"`: el resumen viejo se invalida solo. |

## Prompt enviado

> Estoy construyendo el MVP de "NewsNow", un periódico digital, como caso práctico técnico.
>
> Esta es la FASE 2: capa de IA. La Fase 1 (infraestructura base: S3, CloudFront, WAF,
> API Gateway, 4 Lambdas CRUD, DynamoDB con la tabla `articles`, Cognito) ya está
> implementada y desplegada, este prompt SOLO añade la capa de IA sobre esa base existente.
>
> La arquitectura YA ESTÁ DECIDIDA. No propongas alternativas, no sugieras otros servicios,
> no cambies ninguna decisión de diseño. Tu tarea es únicamente implementarla en Terraform
> y en los handlers Lambda.
>
> **Contexto de la funcionalidad**
>
> NewsNow quiere un asistente de IA que:
> 1. Resuma automáticamente cada artículo individual cuando se crea o edita.
> 2. Genere un resumen diario ("digest") agregando todos los artículos publicados ese día.
>
> **Servicios/recursos nuevos que se agregan en esta fase**
>
> 1. 2 Lambda functions: `summarize_article` y `daily_digest`.
> 2. 1 tabla DynamoDB nueva: `digests`.
> 3. IAM: roles y policies nuevos, uno por cada una de las 2 Lambdas nuevas.
> 4. CloudWatch: Log Groups para las 2 Lambdas nuevas + 1 Alarm sobre errores de
>    `summarize_article`.
> 5. Amazon Bedrock: Claude Haiku 4.5 (invocado por `summarize_article`) y Claude
>    Sonnet 5 (invocado por `daily_digest`).
> 6. SQS: 1 Dead-Letter Queue asociada a `summarize_article`.
> 7. EventBridge Scheduler: 1 regla de cron diario que dispara `daily_digest`.
>
> No se agrega SES, SNS, ni ningún mecanismo de envío de notificaciones/email, el digest
> diario solo se guarda en DynamoDB, no se envía por ningún canal externo en este MVP.
>
> **Arquitectura decidida (implementar tal cual, sin modificar)**
>
> - Amazon Bedrock como proveedor del modelo, vía SDK de Bedrock (boto3), nunca la API de
>   Anthropic directamente. Claude Haiku 4.5 para `summarize_article`, Claude Sonnet 5 para
>   `daily_digest`. Model ids inyectados por variable de entorno (`HAIKU_MODEL_ID`,
>   `SONNET_MODEL_ID`), nunca hardcodeados.
> - `summarize_article`: trigger DynamoDB Streams (INSERT/MODIFY) vía
>   `aws_lambda_event_source_mapping`; solo procesa `summary_status == "PENDING"`; escribe
>   `summary` + `summary_status = "DONE"`; si Bedrock falla, marca `"ERROR"` y relanza para
>   que, agotados los reintentos, el evento caiga en una DLQ de SQS.
> - `daily_digest`: trigger EventBridge Scheduler, cron `0 7 * * ? *` (07:00 UTC) como
>   variable, `aws_scheduler_schedule` con `flexible_time_window { mode = "OFF" }`; consulta
>   la GSI `publish_date-index`, filtra `summary_status == "DONE"`, agrega título+resumen,
>   pide a Bedrock un digest de 4-6 párrafos y lo guarda en `digests` (partición por fecha).
>   Sin envío por email/notificación.
> - IAM: `bedrock:InvokeModel` acotado al ARN del modelo concreto de cada Lambda (nunca
>   ambos modelos en la misma), acceso mínimo a sus tablas y a su DLQ.
> - CloudWatch: Log Groups a 14 días; alarma sobre `AWS/Lambda Errors` de
>   `summarize_article`, `Sum` ≥ umbral (variable, default 3) en 5 minutos.
> - Tests con `moto` (DynamoDB) y mocks de la respuesta de Bedrock, cubriendo
>   explícitamente: PENDING→procesado→DONE, DONE→ignorado (evita el bucle), fallo de
>   Bedrock→ERROR+relanza; y en el digest, que el filtro `DONE` excluye lo no resumido.
>
> **Esquema real de `articles`** (campos exactos, sin inventar nombres: `id`, `title`,
> `content` —no `body`—, `image_url`, `tags`, `status`, `publish_date`, `author`,
> `created_at`, `updated_at`, `summary`, `summary_status`). GSI existente:
> `publish_date-index` (hash `publish_date`, range `created_at`).
>
> **Estructura esperada:** `terraform/ai/{bedrock_iam,summarize_article,daily_digest,
> dynamodb_digests,alarms,variables}.tf`, `ai-summarizer/{summarize_article,daily_digest}.py`
> + `tests/`, README actualizado.
>
> **Instrucciones de trabajo:** primero los handlers Python, luego sus tests con moto
> (ejecutados), luego el Terraform (IAM → DynamoDB → Lambdas+triggers → alarmas), y al
> final `terraform init`/`validate` sobre `terraform/ai/` (sin `apply`, sin cuenta AWS
> conectada). Ir bloque a bloque, anunciando cada uno en 1-2 frases antes de generarlo.

