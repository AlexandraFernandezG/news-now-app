"""FASE 2 - Resumen automatico por articulo. NO IMPLEMENTADO EN LA FASE 1.

Este modulo queda reservado a proposito. La Fase 1 solo deja preparada la
infraestructura que la Fase 2 necesitara y que no puede anadirse despues sin
recrear recursos:

  - DynamoDB Streams ya activo en la tabla `articles`
    (terraform/dynamodb.tf: stream_view_type = NEW_AND_OLD_IMAGES).
    El ARN del stream se expone en el output `articles_table_stream_arn`.

  - Los items de articulo ya se escriben con los campos `summary` (None) y
    `summary_status` ("PENDING"), y `update_article` vuelve a marcar
    summary_status = "PENDING" cuando cambian `title` o `content`.

Contrato previsto para la Fase 2:

    lambda_handler(event, context)
        event: evento de DynamoDB Streams (Records[].eventName / dynamodb).
        Por cada INSERT/MODIFY con summary_status == "PENDING":
          1. leer el contenido del articulo de NewImage
          2. generar el resumen con el modelo elegido
          3. UpdateItem: summary = <texto>, summary_status = "DONE"
             (condicionado para no pisar una edicion posterior)

Nada de esto se implementa aqui todavia.
"""

from __future__ import annotations

raise NotImplementedError(
    "La capa de IA corresponde a la Fase 2; consulta docs/ai-usage/02-fase2-prompt.md"
)
