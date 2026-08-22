"""Tests de POST /articles (src/articles/create_article.py)."""

from __future__ import annotations

import base64
import json

import pytest
from botocore.exceptions import ClientError

import articles.create_article as handler


def _conditional_check_failed() -> ClientError:
    return ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "boom"}},
        "PutItem",
    )


def test_crea_articulo_con_campos_minimos(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "Un titular", "content": "Cuerpo del articulo"}),
        claims={"email": "redactor@newsnow.test"},
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 201
    body = json.loads(response["body"])
    assert body["title"] == "Un titular"
    assert body["author"] == "redactor@newsnow.test"
    assert body["status"] == "published"  # valor por defecto
    assert body["summary"] is None
    assert body["summary_status"] == "PENDING"  # reservado para la Fase 2
    assert response["headers"]["Location"] == f"/articles/{body['id']}"

    mock_table.put_item.assert_called_once()
    kwargs = mock_table.put_item.call_args.kwargs
    assert kwargs["ConditionExpression"] == "attribute_not_exists(id)"
    assert kwargs["Item"]["id"] == body["id"]


def test_publish_date_indicado_se_respeta(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps(
            {"title": "T", "content": "C", "publish_date": "2026-01-15"}
        ),
    )

    handler.lambda_handler(event, lambda_context)

    item = mock_table.put_item.call_args.kwargs["Item"]
    assert item["publish_date"] == "2026-01-15"


def test_publish_date_por_defecto_es_hoy(mock_table, lambda_context, event_factory, monkeypatch):
    from common import db

    monkeypatch.setattr(db, "today_iso", lambda: "2026-08-22")
    event = event_factory(method="POST", body=json.dumps({"title": "T", "content": "C"}))

    handler.lambda_handler(event, lambda_context)

    item = mock_table.put_item.call_args.kwargs["Item"]
    assert item["publish_date"] == "2026-08-22"


def test_body_vacio_devuelve_400(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(event_factory(method="POST", body=""), lambda_context)

    assert response["statusCode"] == 400
    mock_table.put_item.assert_not_called()


def test_body_no_json_devuelve_400(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(
        event_factory(method="POST", body="esto no es json"), lambda_context
    )

    assert response["statusCode"] == 400


def test_body_base64_se_decodifica_antes_de_parsear(mock_table, lambda_context, event_factory):
    payload = json.dumps({"title": "T", "content": "C"}).encode("utf-8")
    event = event_factory(
        method="POST",
        body=base64.b64encode(payload).decode("ascii"),
        is_base64=True,
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 201


@pytest.mark.parametrize("missing_field", ["title", "content"])
def test_campo_obligatorio_faltante_devuelve_400(
    missing_field, mock_table, lambda_context, event_factory
):
    payload = {"title": "T", "content": "C"}
    del payload[missing_field]

    response = handler.lambda_handler(
        event_factory(method="POST", body=json.dumps(payload)), lambda_context
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert missing_field in body["details"]["missing"]


def test_autor_no_se_acepta_desde_el_cuerpo(mock_table, lambda_context, event_factory):
    """La autoria sale solo del JWT: un 'author' en el body debe rechazarse."""
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "T", "content": "C", "author": "impostor@x.com"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert "author" in body["details"]["unknown"]
    mock_table.put_item.assert_not_called()


def test_status_invalido_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "T", "content": "C", "status": "publicado"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_publish_date_con_formato_invalido_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "T", "content": "C", "publish_date": "22/08/2026"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_tags_no_lista_de_strings_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "T", "content": "C", "tags": ["ok", 5]}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_titulo_demasiado_largo_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "x" * 201, "content": "C"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_content_demasiado_largo_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="POST",
        body=json.dumps({"title": "T", "content": "x" * 100_001}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_body_base64_corrupto_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="POST", body="no-es-base64-valido!!", is_base64=True)

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    mock_table.put_item.assert_not_called()


def test_body_json_que_no_es_objeto_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="POST", body=json.dumps(["no", "es", "un", "objeto"]))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_articulo_duplicado_devuelve_409(mock_table, lambda_context, event_factory):
    mock_table.put_item.side_effect = _conditional_check_failed()
    event = event_factory(method="POST", body=json.dumps({"title": "T", "content": "C"}))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 409


def test_autor_desconocido_si_no_hay_claims(mock_table, lambda_context, event_factory):
    event = event_factory(method="POST", body=json.dumps({"title": "T", "content": "C"}))

    handler.lambda_handler(event, lambda_context)

    item = mock_table.put_item.call_args.kwargs["Item"]
    assert item["author"] == "desconocido"


def test_error_generico_de_dynamodb_devuelve_500(mock_table, lambda_context, event_factory):
    mock_table.put_item.side_effect = RuntimeError("fallo de red")
    event = event_factory(method="POST", body=json.dumps({"title": "T", "content": "C"}))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500


def test_client_error_no_condicional_devuelve_500(mock_table, lambda_context, event_factory):
    """Un ClientError que no sea ConditionalCheckFailedException es un 500, no un 409."""
    mock_table.put_item.side_effect = ClientError(
        {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "boom"}},
        "PutItem",
    )
    event = event_factory(method="POST", body=json.dumps({"title": "T", "content": "C"}))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500
