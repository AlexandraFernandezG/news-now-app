# Fase 1 — Prompt de infraestructura base

**Herramienta:** Claude Code (modelo Opus 5)
**Fecha:** 2026-08-22
**Alcance:** infraestructura Terraform + handlers Lambda. La capa de IA queda
explícitamente fuera y se aborda en la [Fase 2](02-fase2-prompt.md).

---

## Prompt enviado

> Estoy construyendo el MVP de "NewsNow", un periódico digital, como caso práctico técnico.
> Esta es la FASE 1: infraestructura base. La capa de IA (resúmenes de artículos) se añadirá
> en una fase posterior, así que NO la implementes todavía — pero ten en cuenta que la tabla
> de artículos debe quedar preparada para ello.
>
> La arquitectura YA ESTÁ DECIDIDA. No propongas alternativas, no sugieras otros servicios,
> no cambies ninguna decisión de diseño. Tu tarea es únicamente implementarla en Terraform y
> en los handlers Lambda.
>
> **Contexto de la aplicación**
> Periódico digital con dos frontends React estáticos: app pública (muestra artículos) y app
> de administración (CRUD de artículos, requiere login). Backend: API REST en Python.
> Se esperan picos de tráfico grandes e impredecibles (dependencia de influencers para
> promoción de contenido), por lo que todo debe ser serverless/PaaS con auto-scaling nativo.
>
> **Arquitectura decidida (implementar tal cual, sin modificar)**
>
> *Hosting de las apps (frontend)*
> - 2 buckets S3 (privados, sin acceso público directo) + 2 distribuciones CloudFront, cada
>   una con su propio Origin Access Control (OAC).
>   - App pública: bucket `news-public-app`
>   - App admin: bucket `news-admin-app`
> - Ambas configuradas como SPA: error 404/403 → redirige a `index.html` (código 200) para
>   que React Router funcione correctamente.
> - AWS WAF (Web ACL) protegiendo la distribución CloudFront de la app pública:
>   - Regla de rate limiting: máximo 2000 peticiones por IP cada 5 minutos, acción "block".
>   - `scope = CLOUDFRONT` (debe crearse en la región `us-east-1`).
> - La app de admin NO lleva WAF en esta fase (queda protegida por Cognito a nivel de API).
>
> *Backend / API*
> - Lambda "puro" en Python (sin frameworks tipo FastAPI/Chalice/Zappa) + API Gateway HTTP API
>   (no REST API).
> - Una tercera distribución CloudFront delante del API Gateway, cacheando únicamente la ruta
>   `GET /articles` (los métodos POST/PUT/DELETE no se cachean, deben pasar siempre).
>   - Origin: el endpoint del API Gateway.
>   - TTL de cache configurable vía variable, default 60 segundos.
> - 4 Lambdas para el CRUD de artículos:
>   - `get_articles` (GET /articles) — pública, sin autenticación
>   - `create_article` (POST /articles) — requiere autenticación
>   - `update_article` (PUT /articles/{id}) — requiere autenticación
>   - `delete_article` (DELETE /articles/{id}) — requiere autenticación
>
> *Base de datos*
> - DynamoDB, tabla `articles`, capacidad on-demand.
> - Debe tener DynamoDB Streams habilitado desde ya (aunque nada lo consuma todavía, para no
>   tener que recrear la tabla cuando se añada la capa de IA en la Fase 2).
> - Incluir una GSI por fecha de publicación (`publish_date`), que se usará en la Fase 2 para
>   el resumen diario.
>
> *Autenticación*
> - Amazon Cognito User Pool + App Client, con JWT Authorizer nativo de API Gateway
>   protegiendo las rutas POST/PUT/DELETE (GET queda pública).
>
> *IAM y observabilidad*
> - IAM: un rol de ejecución por Lambda con permisos mínimos necesarios (principio de menor
>   privilegio) — no uses políticas administrativas amplias.
> - CloudWatch Log Groups creados explícitamente para cada Lambda, con retención de 14 días.
>
> *Backend remoto de Terraform*
> - Bucket S3 + tabla DynamoDB para locking. Trátalo como un paso de bootstrapping SEPARADO
>   (carpeta `terraform/bootstrap/`), que se aplica una única vez antes que el resto del proyecto.
>
> **Instrucciones de trabajo**
> 1. Primero `terraform/bootstrap/` (state bucket + lock table).
> 2. Luego los módulos reutilizables (`lambda-function`, `static-site`).
> 3. Luego el resto de recursos Terraform que usan esos módulos: DynamoDB, Cognito,
>    API Gateway, las 4 Lambdas, IAM.
> 4. Luego `waf.tf` y `api_cache_cloudfront.tf`.
> 5. Luego los handlers Lambda en `src/`.
> 6. Al final, `terraform init`, `terraform validate` y `terraform plan` en ambas carpetas.
>
> Ve carpeta por carpeta en el orden indicado. Antes de cada bloque, dime en 1-2 frases qué
> vas a crear y por qué encaja con la arquitectura ya decidida — pero no propongas cambios a
> esa arquitectura.

*(El prompt incluía además el árbol de carpetas esperado, reproducido en el
[README](../../README.md#estructura-del-repositorio).)*

---

## Resultado

59 recursos en el módulo raíz + 8 en bootstrap. Detalle de qué se generó, qué
hubo que decidir y cómo se verificó: [evidencia-uso-ia.md](evidencia-uso-ia.md).
