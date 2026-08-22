"""POST /articles - alta de un articulo. Requiere JWT valido de Cognito.

El item se escribe ya con los campos que consumira la capa de IA de la Fase 2
(`summary`, `summary_status`), de modo que el stream de DynamoDB pueda
disparar el resumen sin cambiar el esquema de escritura.
"""

from __future__ import annotations

import base64
import json
import re
import uuid
from typing import Any

from botocore.exceptions import ClientError

from common import db
from common.responses import ApiError, created, from_exception, get_logger

logger = get_logger(__name__)

REQUIRED_FIELDS = ("title", "content")
OPTIONAL_FIELDS = ("publish_date", "tags", "status", "image_url", "excerpt")

MAX_TITLE_LENGTH = 200
MAX_CONTENT_LENGTH = 100_000
VALID_STATUSES = ("draft", "published")

_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        payload = _parse_body(event)
        author = _author_from_claims(event)

        now = db.utc_now_iso()
        article_id = str(uuid.uuid4())

        item: dict[str, Any] = {
            "id": article_id,
            "title": payload["title"],
            "content": payload["content"],
            "excerpt": payload.get("excerpt", ""),
            "image_url": payload.get("image_url", ""),
            "tags": payload.get("tags", []),
            "status": payload.get("status", "published"),
            "publish_date": payload.get("publish_date") or db.today_iso(),
            "author": author,
            "created_at": now,
            "updated_at": now,
            # --- Reservado para la Fase 2 (capa de IA) ---
            # El resumen aun no se genera; se marca como pendiente para que el
            # consumidor del stream sepa que tiene trabajo que hacer.
            "summary": None,
            "summary_status": "PENDING",
        }

        # Guarda contra colisiones de UUID y contra reintentos duplicados.
        db.get_table().put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(id)",
        )

        logger.info("Articulo creado", extra={"article_id": article_id})

        return created(db.normalize_item(item), location=f"/articles/{article_id}")

    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return from_exception(ApiError(409, "El articulo ya existe"), logger)
        return from_exception(exc, logger)

    except Exception as exc:  # noqa: BLE001 - frontera del handler
        return from_exception(exc, logger)


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
    missing = [field for field in REQUIRED_FIELDS if not str(payload.get(field) or "").strip()]
    if missing:
        raise ApiError(400, "Faltan campos obligatorios", missing=missing)

    unknown = sorted(set(payload) - set(REQUIRED_FIELDS) - set(OPTIONAL_FIELDS))
    if unknown:
        raise ApiError(400, "Campos no permitidos", unknown=unknown)

    title = str(payload["title"]).strip()
    if len(title) > MAX_TITLE_LENGTH:
        raise ApiError(400, f"'title' supera los {MAX_TITLE_LENGTH} caracteres")

    content = str(payload["content"])
    if len(content) > MAX_CONTENT_LENGTH:
        raise ApiError(400, f"'content' supera los {MAX_CONTENT_LENGTH} caracteres")

    status = payload.get("status", "published")
    if status not in VALID_STATUSES:
        raise ApiError(400, f"'status' debe ser uno de: {', '.join(VALID_STATUSES)}")

    publish_date = payload.get("publish_date")
    if publish_date is not None and not _DATE_PATTERN.match(str(publish_date)):
        raise ApiError(400, "'publish_date' debe tener formato YYYY-MM-DD")

    tags = payload.get("tags", [])
    if not isinstance(tags, list) or any(not isinstance(tag, str) for tag in tags):
        raise ApiError(400, "'tags' debe ser una lista de cadenas")

    normalized = dict(payload)
    normalized["title"] = title
    normalized["content"] = content
    normalized["status"] = status
    normalized["tags"] = tags

    return normalized


def _author_from_claims(event: dict[str, Any]) -> str:
    """Identidad del redactor, tomada del JWT ya validado por API Gateway.

    Nunca se acepta un `author` enviado en el cuerpo: la autoria sale del token.
    """
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )

    return claims.get("email") or claims.get("cognito:username") or claims.get("sub") or "desconocido"
