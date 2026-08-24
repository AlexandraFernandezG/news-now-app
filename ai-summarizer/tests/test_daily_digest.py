"""Tests de ai-summarizer/daily_digest.py (disparado por EventBridge Scheduler)."""

from __future__ import annotations

import json
from datetime import date
from unittest.mock import MagicMock

import boto3
import pytest
from moto import mock_aws

import daily_digest as handler

ARTICLES_TABLE = "articles-test"
DIGESTS_TABLE = "digests-test"
INDEX_NAME = "publish_date-index"


@pytest.fixture(autouse=True)
def _environment(monkeypatch):
    """Variables de entorno presentes en toda invocacion real (terraform/ai/)."""
    monkeypatch.setenv("ARTICLES_TABLE_NAME", ARTICLES_TABLE)
    monkeypatch.setenv("DIGESTS_TABLE_NAME", DIGESTS_TABLE)
    monkeypatch.setenv("PUBLISH_DATE_INDEX", INDEX_NAME)
    monkeypatch.setenv("SONNET_MODEL_ID", "anthropic.claude-sonnet-5-test-v1:0")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")


@pytest.fixture
def tables(monkeypatch):
    """Tablas `articles` (con la GSI publish_date-index) y `digests` simuladas."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")

        articles = dynamodb.create_table(
            TableName=ARTICLES_TABLE,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "id", "AttributeType": "S"},
                {"AttributeName": "publish_date", "AttributeType": "S"},
                {"AttributeName": "created_at", "AttributeType": "S"},
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": INDEX_NAME,
                    "KeySchema": [
                        {"AttributeName": "publish_date", "KeyType": "HASH"},
                        {"AttributeName": "created_at", "KeyType": "RANGE"},
                    ],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        articles.wait_until_exists()

        digests = dynamodb.create_table(
            TableName=DIGESTS_TABLE,
            KeySchema=[{"AttributeName": "digest_date", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "digest_date", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        digests.wait_until_exists()

        monkeypatch.setattr(handler, "get_articles_table", lambda: articles)
        monkeypatch.setattr(handler, "get_digests_table", lambda: digests)

        yield {"articles": articles, "digests": digests}


@pytest.fixture
def bedrock(monkeypatch):
    client = MagicMock(name="bedrock-runtime")
    monkeypatch.setattr(handler, "get_bedrock_client", lambda: client)
    return client


def _bedrock_response(text: str) -> dict:
    body = MagicMock(name="StreamingBody")
    body.read.return_value = json.dumps({"content": [{"text": text}]}).encode("utf-8")
    return {"body": body}


def _article(article_id: str, *, index: int = 0, **overrides) -> dict:
    today = date.today().isoformat()
    base = {
        "id": article_id,
        "title": f"Titular {article_id}",
        "publish_date": today,
        "created_at": f"{today}T{index:02d}:00:00+00:00",
        "summary": "Resumen existente",
        "summary_status": "DONE",
    }
    base.update(overrides)
    return base


def test_filtra_articulos_sin_resumen(tables, bedrock):
    """Solo los articulos con summary_status=DONE entran en el digest."""
    tables["articles"].put_item(Item=_article("a1", index=1))
    tables["articles"].put_item(
        Item=_article("a2", index=2, summary=None, summary_status="PENDING")
    )
    bedrock.invoke_model.return_value = _bedrock_response("Digest del dia.")

    result = handler.lambda_handler({}, None)

    assert result["article_count"] == 1
    prompt_body = json.loads(bedrock.invoke_model.call_args.kwargs["body"])
    prompt_text = prompt_body["messages"][0]["content"]
    assert "Titular a1" in prompt_text
    assert "Titular a2" not in prompt_text


def test_query_usa_el_gsi_y_no_arrastra_otros_dias(tables, bedrock):
    """La query esta acotada a publish_date: un articulo de otro dia no cuenta."""
    tables["articles"].put_item(Item=_article("a1", index=1))
    tables["articles"].put_item(
        Item=_article(
            "a2",
            publish_date="2020-01-01",
            created_at="2020-01-01T00:00:00+00:00",
        )
    )
    bedrock.invoke_model.return_value = _bedrock_response("Digest del dia.")

    result = handler.lambda_handler({}, None)

    assert result["article_count"] == 1


def test_agrega_los_resumenes_y_guarda_el_digest(tables, bedrock):
    tables["articles"].put_item(Item=_article("a1", index=1))
    bedrock.invoke_model.return_value = _bedrock_response("Digest del dia.")

    handler.lambda_handler({}, None)

    digest = tables["digests"].get_item(Key={"digest_date": date.today().isoformat()})["Item"]
    assert digest["digest"] == "Digest del dia."
    assert digest["article_count"] == 1


def test_dia_sin_articulos_resumidos_no_genera_digest(tables, bedrock):
    tables["articles"].put_item(Item=_article("a1", index=1, summary=None, summary_status="PENDING"))

    result = handler.lambda_handler({}, None)

    assert result is None
    bedrock.invoke_model.assert_not_called()
    assert "Item" not in tables["digests"].get_item(Key={"digest_date": date.today().isoformat()})
