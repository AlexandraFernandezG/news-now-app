"""PUT /articles/{id} - edicion de un articulo. Requiere JWT valido de Cognito.

Actualizacion parcial: solo se tocan los campos presentes en el cuerpo. Se usa
UpdateItem con `attribute_exists(id)` en lugar de un GetItem previo, de forma
que la comprobacion de existencia es atomica y la Lambda no necesita permiso
de lectura sobre la tabla.
"""

from __future__ import annotations

import base64
import json
import re
from typing import Any

from botocore.exceptions import ClientError

from common import db
from common.responses import ApiError, from_exception, get_logger, ok

logger = get_logger(__name__)

# `id`, `created_at` y `author` no son editables: identidad y trazabilidad.
UPDATABLE_FIELDS = (
    "title",
    "content",
    "excerpt",
    "image_url",
    "tags",
    "status",
    "publish_date",
)

# Cambios que invalidan el resumen generado por la IA (Fase 2).
CONTENT_FIELDS = ("title", "content")

MAX_TITLE_LENGTH = 200
MAX_CONTENT_LENGTH = 100_000
VALID_STATUSES = ("draft", "published")

_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        article_id = _path_id(event)
        changes = _parse_body(event)

        response = db.get_table().update_item(
            Key={"id": article_id},
            ConditionExpression="attribute_exists(id)",
            ReturnValues="ALL_NEW",
            **_build_update_expression(changes),
        )

        logger.info("Articulo actualizado", extra={"article_id": article_id})

        return ok(db.normalize_item(response.get("Attributes")))

    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return from_exception(ApiError(404, "El articulo no existe"), logger)
        return from_exception(exc, logger)

    except Exception as exc:  # noqa: BLE001 - frontera del handler
        return from_exception(exc, logger)


def _build_update_expression(changes: dict[str, Any]) -> dict[str, Any]:
    """Traduce el diccionario de cambios a UpdateExpression.

    Los nombres se pasan siempre como placeholders porque varios campos
    (`status`, entre otros) son palabras reservadas de DynamoDB.
    """
    names: dict[str, str] = {}
    values: dict[str, Any] = {}
    assignments: list[str] = []

    for index, (field, value) in enumerate(sorted(changes.items())):
        name_key = f"#f{index}"
        value_key = f":v{index}"
        names[name_key] = field
        values[value_key] = value
        assignments.append(f"{name_key} = {value_key}")

    names["#updated_at"] = "updated_at"
    values[":updated_at"] = db.utc_now_iso()
    assignments.append("#updated_at = :updated_at")

    # Si cambia el texto del articulo, el resumen existente deja de ser valido:
    # se vuelve a marcar como pendiente para que la Fase 2 lo regenere.
    if any(field in changes for field in CONTENT_FIELDS):
        names["#summary_status"] = "summary_status"
        values[":summary_status"] = "PENDING"
        assignments.append("#summary_status = :summary_status")

    return {
        "UpdateExpression": "SET " + ", ".join(assignments),
        "ExpressionAttributeNames": names,
        "ExpressionAttributeValues": values,
    }


def _path_id(event: dict[str, Any]) -> str:
    article_id = (event.get("pathParameters") or {}).get("id")
    if not article_id:
        raise ApiError(400, "Falta el identificador del articulo en la ruta")
    return article_id


def _parse_body(event: dict[str, Any]) -> dict[str, Any]:
    raw = event.get("body")
    if not raw:
        raise ApiError(400, "El cuerpo de la peticion esta vacio")

    if event.get("isBase64Encoded"):
        try:
            raw = base64.b64decode(raw).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as exc:
            raise ApiError(400, "El cuerpo de la peticion no es texto valido") from exc

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ApiError(400, "El cuerpo de la peticion no es JSON valido") from exc

    if not isinstance(payload, dict):
        raise ApiError(400, "El cuerpo de la peticion debe ser un objeto JSON")

    return _validate(payload)


def _validate(payload: dict[str, Any]) -> dict[str, Any]:
    unknown = sorted(set(payload) - set(UPDATABLE_FIELDS))
    if unknown:
        raise ApiError(400, "Campos no editables", unknown=unknown)

    changes = {field: payload[field] for field in UPDATABLE_FIELDS if field in payload}
    if not changes:
        raise ApiError(400, "No se ha indicado ningun campo a modificar")

    if "title" in changes:
        title = str(changes["title"]).strip()
        if not title:
            raise ApiError(400, "'title' no puede estar vacio")
        if len(title) > MAX_TITLE_LENGTH:
            raise ApiError(400, f"'title' supera los {MAX_TITLE_LENGTH} caracteres")
        changes["title"] = title

    if "content" in changes:
        content = str(changes["content"])
        if not content.strip():
            raise ApiError(400, "'content' no puede estar vacio")
        if len(content) > MAX_CONTENT_LENGTH:
            raise ApiError(400, f"'content' supera los {MAX_CONTENT_LENGTH} caracteres")
        changes["content"] = content

    if "status" in changes and changes["status"] not in VALID_STATUSES:
        raise ApiError(400, f"'status' debe ser uno de: {', '.join(VALID_STATUSES)}")

    # publish_date es la hash key del GSI: no puede quedar vacia ni malformada.
    if "publish_date" in changes and not _DATE_PATTERN.match(str(changes["publish_date"])):
        raise ApiError(400, "'publish_date' debe tener formato YYYY-MM-DD")

    if "tags" in changes:
        tags = changes["tags"]
        if not isinstance(tags, list) or any(not isinstance(tag, str) for tag in tags):
            raise ApiError(400, "'tags' debe ser una lista de cadenas")

    return changes
