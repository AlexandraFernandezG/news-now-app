"""Fase 2 - Resumen diario de la actualidad.

Disparada por EventBridge Scheduler (terraform/ai/daily_digest.tf, cron
19:00 UTC). Consulta el GSI `publish_date-index` de la tabla `articles` para
traer lo publicado el dia en curso, se queda solo con los articulos que ya
tienen resumen (`summary_status == "DONE"`) y le pide a Bedrock (modelo
Claude Sonnet, ver SONNET_MODEL_ID / terraform/ai/variables.tf) que
sintetice un digest de 4 a 6 parrafos a partir de sus titulos y resumenes.
El resultado se guarda en la tabla `digests`, particionada por fecha.

Sin envio por email ni notificacion externa: el digest queda disponible en
DynamoDB para que, en el futuro, un endpoint de lectura lo exponga.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import date, datetime, timezone
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

DONE = "DONE"

# Clientes/recursos cacheados a nivel de modulo (reutilizados entre
# invocaciones sobre el mismo contenedor).
_articles_table = None
_digests_table = None
_bedrock = None


def get_articles_table():
    global _articles_table
    if _articles_table is None:
        _articles_table = boto3.resource("dynamodb").Table(os.environ["ARTICLES_TABLE_NAME"])
    return _articles_table


def get_digests_table():
    global _digests_table
    if _digests_table is None:
        _digests_table = boto3.resource("dynamodb").Table(os.environ["DIGESTS_TABLE_NAME"])
    return _digests_table


def get_bedrock_client():
    global _bedrock
    if _bedrock is None:
        _bedrock = boto3.client("bedrock-runtime")
    return _bedrock


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any] | None:
    target_date = date.today().isoformat()

    articles = _fetch_published_articles(target_date)
    summarized = [a for a in articles if a.get("summary_status") == DONE and a.get("summary")]

    if not summarized:
        logger.info("Sin articulos con resumen para %s: no se genera digest", target_date)
        return None

    digest_text = _build_digest(summarized)
    _save_digest(target_date, digest_text, len(summarized))

    logger.info("Digest generado para %s (%d articulos)", target_date, len(summarized))
    return {"date": target_date, "article_count": len(summarized)}


def _fetch_published_articles(target_date: str) -> list[dict[str, Any]]:
    """Query sobre publish_date-index: una sola particion, nunca un Scan."""
    index_name = os.environ.get("PUBLISH_DATE_INDEX", "publish_date-index")
    table = get_articles_table()

    items: list[dict[str, Any]] = []
    kwargs: dict[str, Any] = {
        "IndexName": index_name,
        "KeyConditionExpression": Key("publish_date").eq(target_date),
    }

    while True:
        response = table.query(**kwargs)
        items.extend(response.get("Items", []))

        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            return items
        kwargs["ExclusiveStartKey"] = last_key


def _build_digest(articles: list[dict[str, Any]]) -> str:
    bullets = "\n".join(f"- {a.get('title', '')}: {a.get('summary', '')}" for a in articles)

    prompt = (
        "Eres el editor de NewsNow. A partir de los siguientes titulares y "
        "resumenes publicados hoy, redacta un digest informativo de 4 a 6 "
        "parrafos en castellano, agrupando temas relacionados y sin inventar "
        "informacion que no aparezca en el material de partida.\n\n"
        f"{bullets}"
    )

    body = json.dumps(
        {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1500,
            "messages": [{"role": "user", "content": prompt}],
        }
    )

    response = get_bedrock_client().invoke_model(
        modelId=os.environ["SONNET_MODEL_ID"],
        body=body,
        contentType="application/json",
        accept="application/json",
    )

    payload = json.loads(response["body"].read())
    return payload["content"][0]["text"].strip()


def _save_digest(target_date: str, digest_text: str, article_count: int) -> None:
    get_digests_table().put_item(
        Item={
            "digest_date": target_date,
            "digest": digest_text,
            "article_count": article_count,
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
    )
