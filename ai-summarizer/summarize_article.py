"""Fase 2 - Resumen automatico por articulo.

Consumidor del stream de DynamoDB de la tabla `articles` (event source
mapping definido en terraform/ai/summarize_article.tf, filtrado a nivel de
stream por eventName INSERT/MODIFY). Por cada registro con
`summary_status == "PENDING"` genera el resumen con Bedrock (Claude Haiku
4.5) y lo persiste con `summary_status = "DONE"`.

El propio `summary_status` actua como maquina de estados para evitar el
bucle infinito tipico de "escribir en la tabla que disparo el evento": al
terminar pasa a "DONE", y el evento MODIFY que produce esa misma escritura
ya no cumple la condicion, asi que no se vuelve a procesar.

Si la llamada a Bedrock falla, el item se marca "ERROR" -para visibilidad
inmediata en la tabla, sin esperar a que se agoten los reintentos- y se
relanza la excepcion: el event source mapping reintenta y, si se agotan los
intentos (p.ej. throttling sostenido de Bedrock), el registro cae en la DLQ
sin perder el articulo que quedo sin resumir.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

import boto3
from boto3.dynamodb.types import TypeDeserializer

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

PENDING = "PENDING"
DONE = "DONE"
ERROR = "ERROR"

# Margen de contexto suficiente para un articulo de prensa sin disparar
# coste/latencia de la llamada a Haiku.
MAX_CONTENT_CHARS = 12_000

_deserializer = TypeDeserializer()

# Clientes cacheados a nivel de modulo: se crean una vez por contenedor y se
# reutilizan en las invocaciones siguientes (menos latencia en warm start).
_table = None
_bedrock = None


def get_table():
    """Devuelve el recurso Table de la tabla de articulos."""
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(os.environ["ARTICLES_TABLE_NAME"])
    return _table


def get_bedrock_client():
    """Devuelve el cliente de Bedrock Runtime (invocacion de modelos)."""
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client("bedrock-runtime")
    return _bedrock


def lambda_handler(event: dict[str, Any], context: Any) -> None:
    for record in event.get("Records", []):
        _process_record(record)


def _process_record(record: dict[str, Any]) -> None:
    # REMOVE no trae NewImage y no hay nada que resumir; el filtro del event
    # source mapping ya descarta este caso, pero se comprueba igualmente por
    # si el handler se invoca directamente (tests, replay manual).
    if record.get("eventName") not in ("INSERT", "MODIFY"):
        return

    new_image = record.get("dynamodb", {}).get("NewImage")
    if not new_image:
        return

    article = _from_stream_image(new_image)
    if article.get("summary_status") != PENDING:
        return  # ya resumido (DONE), en error (ERROR) o sin marcar todavia

    article_id = article["id"]

    try:
        summary = _summarize(article.get("title", ""), article.get("content", ""))
    except Exception:
        logger.exception("Fallo generando el resumen del articulo %s", article_id)
        _mark_error(article_id)
        raise  # agotados los reintentos del event source mapping, va a la DLQ

    _mark_done(article_id, summary)
    logger.info("Resumen generado para el articulo %s", article_id)


def _from_stream_image(image: dict[str, Any]) -> dict[str, Any]:
    """Convierte el NewImage (formato low-level de Streams) a tipos Python."""
    return {key: _deserializer.deserialize(value) for key, value in image.items()}


def _summarize(title: str, content: str) -> str:
    prompt = (
        "Resume el siguiente articulo de noticias en un unico parrafo de 3 a "
        "4 frases, en castellano, sin anadir informacion que no aparezca en "
        "el texto.\n\n"
        f"Titulo: {title}\n\n"
        f"Contenido: {content[:MAX_CONTENT_CHARS]}"
    )

    body = json.dumps(
        {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 500,
            "messages": [{"role": "user", "content": prompt}],
        }
    )

    response = get_bedrock_client().invoke_model(
        modelId=os.environ["HAIKU_MODEL_ID"],
        body=body,
        contentType="application/json",
        accept="application/json",
    )

    payload = json.loads(response["body"].read())
    return payload["content"][0]["text"].strip()


def _mark_done(article_id: str, summary: str) -> None:
    get_table().update_item(
        Key={"id": article_id},
        UpdateExpression="SET summary = :summary, summary_status = :status",
        ExpressionAttributeValues={":summary": summary, ":status": DONE},
    )


def _mark_error(article_id: str) -> None:
    get_table().update_item(
        Key={"id": article_id},
        UpdateExpression="SET summary_status = :status",
        ExpressionAttributeValues={":status": ERROR},
    )
