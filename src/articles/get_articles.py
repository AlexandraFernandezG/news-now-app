"""GET /articles - listado publico de articulos.

Ruta sin autenticacion y con diferencia la mas golpeada: es la que CloudFront
cachea (TTL configurable, 60s por defecto), asi que la mayoria de las
peticiones ni siquiera llegan hasta aqui.

Parametros de query soportados:
    publish_date  YYYY-MM-DD. Si se indica, consulta el GSI publish_date-index
                  en lugar de recorrer la tabla.
    limit         1..100 (20 por defecto).
    next          cursor de paginacion devuelto por la llamada anterior.
"""

from __future__ import annotations

import re
from typing import Any

from boto3.dynamodb.conditions import Key

from common import db
from common.responses import ApiError, from_exception, get_logger, ok

logger = get_logger(__name__)

DEFAULT_LIMIT = 20
MAX_LIMIT = 100
_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        params = event.get("queryStringParameters") or {}

        limit = _parse_limit(params.get("limit"))
        publish_date = _parse_publish_date(params.get("publish_date"))
        start_key = db.decode_cursor(params.get("next"))

        if publish_date:
            result = _query_by_publish_date(publish_date, limit, start_key)
        else:
            result = _scan_all(limit, start_key)

        items = [db.normalize_item(item) for item in result.get("Items", [])]
        next_cursor = db.encode_cursor(result.get("LastEvaluatedKey"))

        logger.info(
            "Listado de articulos devuelto",
            extra={"count": len(items), "publish_date": publish_date},
        )

        return ok(
            {
                "items": items,
                "count": len(items),
                "next": next_cursor,
            }
        )

    except Exception as exc:  # noqa: BLE001 - frontera del handler
        return from_exception(exc, logger)


def _query_by_publish_date(
    publish_date: str,
    limit: int,
    start_key: dict[str, Any] | None,
) -> dict[str, Any]:
    """Consulta el GSI: una sola particion, coste independiente del historico."""
    kwargs: dict[str, Any] = {
        "IndexName": db.publish_date_index(),
        "KeyConditionExpression": Key("publish_date").eq(publish_date),
        # created_at es la range key: mas recientes primero.
        "ScanIndexForward": False,
        "Limit": limit,
    }
    if start_key:
        kwargs["ExclusiveStartKey"] = start_key

    return db.get_table().query(**kwargs)


def _scan_all(limit: int, start_key: dict[str, Any] | None) -> dict[str, Any]:
    """Listado sin filtro.

    Es un Scan paginado: aceptable para el volumen de un MVP y amortiguado por
    la cache de CloudFront. Cuando el archivo crezca, la portada debera pedir
    un `publish_date` concreto y pasar por el GSI.
    """
    kwargs: dict[str, Any] = {"Limit": limit}
    if start_key:
        kwargs["ExclusiveStartKey"] = start_key

    return db.get_table().scan(**kwargs)


def _parse_limit(raw: str | None) -> int:
    if raw is None or raw == "":
        return DEFAULT_LIMIT

    try:
        limit = int(raw)
    except (TypeError, ValueError) as exc:
        raise ApiError(400, "El parametro 'limit' debe ser un entero") from exc

    if not 1 <= limit <= MAX_LIMIT:
        raise ApiError(400, f"El parametro 'limit' debe estar entre 1 y {MAX_LIMIT}")

    return limit


def _parse_publish_date(raw: str | None) -> str | None:
    if raw is None or raw == "":
        return None

    if not _DATE_PATTERN.match(raw):
        raise ApiError(400, "El parametro 'publish_date' debe tener formato YYYY-MM-DD")

    return raw
