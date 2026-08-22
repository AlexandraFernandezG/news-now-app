# Fase 2 — Capa de IA (pendiente)

> **Estado: no iniciada.** Este documento se rellenará con el prompt de la
> Fase 2 cuando se aborde. Aquí queda registrado únicamente el contrato que la
> Fase 1 ha dejado preparado, para que la Fase 2 no tenga que recrear recursos.

---

## Qué dejó listo la Fase 1

| Pieza | Dónde | Para qué sirve en Fase 2 |
|---|---|---|
| DynamoDB Streams (`NEW_AND_OLD_IMAGES`) | [dynamodb.tf](../../terraform/dynamodb.tf) | Disparar el resumen al crear/editar un artículo. ARN en el output `articles_table_stream_arn`. |
| GSI `publish_date-index` | [dynamodb.tf](../../terraform/dynamodb.tf) | Recuperar lo publicado un día concreto con una única Query. Nombre en el output `articles_publish_date_index`. |
| Campos `summary` y `summary_status` | [create_article.py](../../src/articles/create_article.py) | Todo artículo nace con `summary = null` y `summary_status = "PENDING"`. |
| Reinicio de `summary_status` | [update_article.py](../../src/articles/update_article.py) | Al cambiar `title` o `content` vuelve a `"PENDING"`: el resumen viejo se invalida solo. |
| Stubs y tests | [ai-summarizer/](../../ai-summarizer/) | Ficheros creados con el contrato documentado; lanzan `NotImplementedError`. |

Ninguna de las dos primeras se puede añadir después sin recrear la tabla y
perder los datos: de ahí que se provisionen ya en la Fase 1.

## Lo que la Fase 2 tendrá que añadir

Fuera del alcance de la Fase 1 y **sin implementar** todavía:

- `summarize_article`: Lambda consumidora del stream (event source mapping,
  filtro por `summary_status = PENDING`, DLQ y control de reintentos).
- `daily_digest`: Lambda programada por EventBridge que consulta el GSI.
- Elección del modelo y del servicio de inferencia, con sus permisos IAM.
- Ampliación de los roles: la tabla de permisos actual es estrictamente de
  CRUD (ver [iam.tf](../../terraform/iam.tf)).

## Prompt

_(Pendiente de redactar.)_
