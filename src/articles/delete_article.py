"""DELETE /articles/{id} - baja de un articulo. Requiere JWT valido de Cognito.

Borrado condicionado a que el articulo exista, para poder distinguir un 404
de un borrado real sin necesitar permiso de lectura sobre la tabla.
"""

from __future__ import annotations

from typing import Any

from botocore.exceptions import ClientError

from common import db
from common.responses import ApiError, from_exception, get_logger, no_content

logger = get_logger(__name__)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        article_id = _path_id(event)

        db.get_table().delete_item(
            Key={"id": article_id},
            ConditionExpression="attribute_exists(id)",
        )

        logger.info("Articulo eliminado", extra={"article_id": article_id})

        return no_content()

    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return from_exception(ApiError(404, "El articulo no existe"), logger)
        return from_exception(exc, logger)

    except Exception as exc:  # noqa: BLE001 - frontera del handler
        return from_exception(exc, logger)


def _path_id(event: dict[str, Any]) -> str:
    article_id = (event.get("pathParameters") or {}).get("id")
    if not article_id:
        raise ApiError(400, "Falta el identificador del articulo en la ruta")
    return article_id
