"""Tests de ai-summarizer/summarize_article.py (consumidor del stream)."""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import boto3
import pytest
from boto3.dynamodb.types import TypeSerializer
from moto import mock_aws

import summarize_article as handler

TABLE_NAME = "articles-test"
_serializer = TypeSerializer()


@pytest.fixture(autouse=True)
def _environment(monkeypatch):
    """Variables de entorno presentes en toda invocacion real (terraform/ai/)."""
    monkeypatch.setenv("ARTICLES_TABLE_NAME", TABLE_NAME)
    monkeypatch.setenv("HAIKU_MODEL_ID", "anthropic.claude-haiku-4-5-test-v1:0")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")


@pytest.fixture
def articles_table(monkeypatch):
    """Tabla `articles` simulada con moto; sustituye a handler.get_table()."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")
        table = dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        table.wait_until_exists()
        monkeypatch.setattr(handler, "get_table", lambda: table)
        yield table


@pytest.fixture
def bedrock(monkeypatch):
    """Cliente de Bedrock mockeado a mano: moto no simula bedrock-runtime."""
    client = MagicMock(name="bedrock-runtime")
    monkeypatch.setattr(handler, "get_bedrock_client", lambda: client)
    return client


def _bedrock_response(text: str) -> dict:
    body = MagicMock(name="StreamingBody")
    body.read.return_value = json.dumps({"content": [{"text": text}]}).encode("utf-8")
    return {"body": body}


def _stream_record(event_name: str, article: dict) -> dict:
    """Registro de DynamoDB Streams a partir de un item en formato Python."""
    image = {key: _serializer.serialize(value) for key, value in article.items()}
    return {"eventName": event_name, "dynamodb": {"NewImage": image}}


def _article(**overrides) -> dict:
    base = {
        "id": "art-1",
        "title": "Un titular",
        "content": "Cuerpo del articulo",
        "summary": None,
        "summary_status": "PENDING",
    }
    base.update(overrides)
    return base


def test_item_pendiente_se_procesa_y_termina_en_done(articles_table, bedrock):
    articles_table.put_item(Item=_article())
    bedrock.invoke_model.return_value = _bedrock_response("Resumen generado.")

    event = {"Records": [_stream_record("INSERT", _article())]}
    handler.lambda_handler(event, None)

    bedrock.invoke_model.assert_called_once()
    assert bedrock.invoke_model.call_args.kwargs["modelId"] == "anthropic.claude-haiku-4-5-test-v1:0"

    item = articles_table.get_item(Key={"id": "art-1"})["Item"]
    assert item["summary"] == "Resumen generado."
    assert item["summary_status"] == "DONE"


def test_item_ya_resumido_se_ignora(articles_table, bedrock):
    """Evita el bucle infinito: un MODIFY con summary_status=DONE no se reprocesa."""
    articles_table.put_item(Item=_article(summary="Ya tiene resumen", summary_status="DONE"))

    event = {
        "Records": [
            _stream_record("MODIFY", _article(summary="Ya tiene resumen", summary_status="DONE"))
        ]
    }
    handler.lambda_handler(event, None)

    bedrock.invoke_model.assert_not_called()
    item = articles_table.get_item(Key={"id": "art-1"})["Item"]
    assert item["summary_status"] == "DONE"
    assert item["summary"] == "Ya tiene resumen"


def test_fallo_de_bedrock_marca_error_y_relanza(articles_table, bedrock):
    articles_table.put_item(Item=_article())
    bedrock.invoke_model.side_effect = RuntimeError("throttling")

    event = {"Records": [_stream_record("INSERT", _article())]}
    with pytest.raises(RuntimeError):
        handler.lambda_handler(event, None)

    item = articles_table.get_item(Key={"id": "art-1"})["Item"]
    assert item["summary_status"] == "ERROR"
    assert item["summary"] is None  # no se pisa con un resumen a medias


def test_evento_remove_se_ignora(articles_table, bedrock):
    """Un articulo borrado no genera ninguna escritura ni llamada a Bedrock."""
    event = {"Records": [{"eventName": "REMOVE", "dynamodb": {"OldImage": {}}}]}

    handler.lambda_handler(event, None)

    bedrock.invoke_model.assert_not_called()
