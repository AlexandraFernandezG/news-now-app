"""Tests de GET /articles (src/articles/get_articles.py).

La tabla DynamoDB esta mockeada (fixture `mock_table`): estos tests verifican
la logica del handler -- que parametros arma para query/scan, la validacion
de query params y la traduccion de errores -- no el comportamiento real de
DynamoDB.
"""

from __future__ import annotations

import base64
import json
from decimal import Decimal

import articles.get_articles as handler


def test_sin_filtro_hace_scan_y_normaliza_decimals(mock_table, lambda_context, event_factory):
    mock_table.scan.return_value = {
        "Items": [{"id": "a1", "title": "Titulo", "views": Decimal("3")}],
    }

    response = handler.lambda_handler(event_factory(), lambda_context)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["count"] == 1
    assert body["items"][0]["views"] == 3  # Decimal -> int, no "3.0"
    assert body["next"] is None
    mock_table.scan.assert_called_once()
    mock_table.query.assert_not_called()


def test_con_publish_date_consulta_el_gsi_en_vez_de_escanear(mock_table, lambda_context, event_factory):
    mock_table.query.return_value = {"Items": []}

    handler.lambda_handler(event_factory(query={"publish_date": "2026-08-22"}), lambda_context)

    mock_table.scan.assert_not_called()
    mock_table.query.assert_called_once()
    kwargs = mock_table.query.call_args.kwargs
    assert kwargs["IndexName"] == "publish_date-index"
    assert kwargs["ScanIndexForward"] is False  # mas recientes primero
    assert kwargs["Limit"] == 20

    expr = kwargs["KeyConditionExpression"].get_expression()
    key, value = expr["values"]
    assert key.name == "publish_date"
    assert value == "2026-08-22"


def test_limit_personalizado_se_reenvia_tal_cual(mock_table, lambda_context, event_factory):
    mock_table.scan.return_value = {"Items": []}

    handler.lambda_handler(event_factory(query={"limit": "5"}), lambda_context)

    assert mock_table.scan.call_args.kwargs["Limit"] == 5


def test_limit_no_numerico_devuelve_400_sin_tocar_dynamodb(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(event_factory(query={"limit": "abc"}), lambda_context)

    assert response["statusCode"] == 400
    mock_table.scan.assert_not_called()


def test_limit_fuera_de_rango_devuelve_400(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(event_factory(query={"limit": "0"}), lambda_context)

    assert response["statusCode"] == 400


def test_publish_date_con_formato_invalido_devuelve_400(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(
        event_factory(query={"publish_date": "22-08-2026"}), lambda_context
    )

    assert response["statusCode"] == 400
    mock_table.query.assert_not_called()
    mock_table.scan.assert_not_called()


def test_cursor_corrupto_devuelve_400(mock_table, lambda_context, event_factory):
    response = handler.lambda_handler(event_factory(query={"next": "no-es-base64!!"}), lambda_context)

    assert response["statusCode"] == 400


def test_last_evaluated_key_se_traduce_en_cursor_next(mock_table, lambda_context, event_factory):
    mock_table.scan.return_value = {
        "Items": [],
        "LastEvaluatedKey": {"id": "a1"},
    }

    response = handler.lambda_handler(event_factory(), lambda_context)

    body = json.loads(response["body"])
    assert body["next"] is not None
    decoded = json.loads(base64.urlsafe_b64decode(body["next"]))
    assert decoded == {"id": "a1"}


def test_cursor_valido_se_reenvia_como_exclusive_start_key_en_scan(
    mock_table, lambda_context, event_factory
):
    mock_table.scan.return_value = {"Items": []}
    cursor = handler.db.encode_cursor({"id": "a1"})

    handler.lambda_handler(event_factory(query={"next": cursor}), lambda_context)

    assert mock_table.scan.call_args.kwargs["ExclusiveStartKey"] == {"id": "a1"}


def test_cursor_valido_se_reenvia_como_exclusive_start_key_en_query(
    mock_table, lambda_context, event_factory
):
    mock_table.query.return_value = {"Items": []}
    cursor = handler.db.encode_cursor({"id": "a1", "publish_date": "2026-08-22"})

    handler.lambda_handler(
        event_factory(query={"publish_date": "2026-08-22", "next": cursor}), lambda_context
    )

    assert mock_table.query.call_args.kwargs["ExclusiveStartKey"] == {
        "id": "a1",
        "publish_date": "2026-08-22",
    }


def test_error_inesperado_de_dynamodb_devuelve_500_sin_filtrar_detalles(
    mock_table, lambda_context, event_factory
):
    mock_table.scan.side_effect = RuntimeError("fallo interno de red")

    response = handler.lambda_handler(event_factory(), lambda_context)

    assert response["statusCode"] == 500
    body = json.loads(response["body"])
    assert body["message"] == "Error interno"
    assert "fallo interno de red" not in response["body"]
