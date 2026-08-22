"""Helpers de acceso y serializacion para la tabla DynamoDB `articles`.

Se usa el recurso de alto nivel de boto3 (`dynamodb.Table`), que ya convierte
entre tipos Python y el formato nativo de DynamoDB; aqui solo queda resolver
la reutilizacion del cliente entre invocaciones, los cursores de paginacion y
la normalizacion de los items antes de devolverlos al cliente HTTP.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Mapping

import boto3

from common.responses import ApiError

__all__ = [
    "get_table",
    "publish_date_index",
    "utc_now_iso",
    "today_iso",
    "normalize_item",
    "encode_cursor",
    "decode_cursor",
]

# Cliente cacheado a nivel de modulo: se crea una vez por contenedor y se
# reutiliza en las invocaciones siguientes (menos latencia en warm start).
_table = None


def get_table():
    """Devuelve el recurso Table de la tabla de articulos."""
    global _table

    if _table is None:
        table_name = os.environ.get("ARTICLES_TABLE_NAME")
        if not table_name:
            raise RuntimeError("Falta la variable de entorno ARTICLES_TABLE_NAME")
        _table = boto3.resource("dynamodb").Table(table_name)

    return _table


def publish_date_index() -> str:
    """Nombre del GSI por fecha de publicacion."""
    return os.environ.get("PUBLISH_DATE_INDEX", "publish_date-index")


def utc_now_iso() -> str:
    """Timestamp ISO-8601 en UTC, usado como range key del GSI."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def today_iso() -> str:
    """Fecha de hoy en UTC (YYYY-MM-DD), formato de la hash key del GSI."""
    return date.today().isoformat()


def normalize_item(item: Mapping[str, Any] | None) -> dict[str, Any] | None:
    """Convierte Decimal y sets a tipos JSON nativos, recursivamente."""
    if item is None:
        return None
    return _normalize(dict(item))


def _normalize(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, dict):
        return {key: _normalize(inner) for key, inner in value.items()}
    if isinstance(value, (list, tuple)):
        return [_normalize(inner) for inner in value]
    if isinstance(value, (set, frozenset)):
        return sorted(_normalize(inner) for inner in value)
    return value


def encode_cursor(last_evaluated_key: Mapping[str, Any] | None) -> str | None:
    """Serializa LastEvaluatedKey a un token opaco apto para query string."""
    if not last_evaluated_key:
        return None

    raw = json.dumps(_normalize(dict(last_evaluated_key)), separators=(",", ":"))
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("ascii")


def decode_cursor(cursor: str | None) -> dict[str, Any] | None:
    """Inverso de `encode_cursor`. Un token corrupto es un error del cliente."""
    if not cursor:
        return None

    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii"))
        decoded = json.loads(raw)
    except (ValueError, binascii.Error, UnicodeDecodeError) as exc:
        raise ApiError(400, "El parametro 'next' no es un cursor valido") from exc

    if not isinstance(decoded, dict):
        raise ApiError(400, "El parametro 'next' no es un cursor valido")

    return decoded
