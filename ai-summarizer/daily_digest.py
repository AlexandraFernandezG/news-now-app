"""FASE 2 - Resumen diario de la actualidad. NO IMPLEMENTADO EN LA FASE 1.

Modulo reservado. La pieza de infraestructura que necesita ya existe:

  - GSI `publish_date-index` sobre la tabla `articles`
    (hash key: publish_date en formato YYYY-MM-DD, range key: created_at).
    Recuperar todo lo publicado un dia concreto es una unica Query sobre una
    sola particion, sin recorrer la tabla.
    Nombre disponible en el output `articles_publish_date_index`.

Contrato previsto para la Fase 2:

    lambda_handler(event, context)
        Disparada por una regla programada de EventBridge.
        1. Query al GSI con publish_date = fecha objetivo
        2. componer el digest a partir de los `summary` ya generados
        3. persistir/publicar el resultado

Nada de esto se implementa aqui todavia.
"""

from __future__ import annotations

raise NotImplementedError(
    "La capa de IA corresponde a la Fase 2; consulta docs/ai-usage/02-fase2-prompt.md"
)
