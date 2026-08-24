"""Tests de DELETE /articles/{id} (src/articles/delete_article.py)."""

from __future__ import annotations

from botocore.exceptions import ClientError

import articles.delete_article as handler


def _conditional_check_failed() -> ClientError:
    return ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "boom"}},
        "DeleteItem",
    )


def test_elimina_articulo_existente(mock_table, lambda_context, event_factory):
    event = event_factory(method="DELETE", path_params={"id": "a1"})

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 204
    assert response["body"] == ""
    mock_table.delete_item.assert_called_once_with(
        Key={"id": "a1"},
        ConditionExpression="attribute_exists(id)",
    )


def test_sin_id_en_la_ruta_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="DELETE", path_params=None)

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    mock_table.delete_item.assert_not_called()


def test_articulo_inexistente_devuelve_404(mock_table, lambda_context, event_factory):
    mock_table.delete_item.side_effect = _conditional_check_failed()
    event = event_factory(method="DELETE", path_params={"id": "no-existe"})

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 404


def test_error_generico_de_dynamodb_devuelve_500(mock_table, lambda_context, event_factory):
    mock_table.delete_item.side_effect = RuntimeError("fallo de red")
    event = event_factory(method="DELETE", path_params={"id": "a1"})

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500


def test_client_error_no_condicional_devuelve_500(mock_table, lambda_context, event_factory):
    mock_table.delete_item.side_effect = ClientError(
        {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "boom"}},
        "DeleteItem",
    )
    event = event_factory(method="DELETE", path_params={"id": "a1"})

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500
