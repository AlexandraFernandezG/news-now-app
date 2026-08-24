"""Tests de PUT /articles/{id} (src/articles/update_article.py)."""

from __future__ import annotations

import json

from botocore.exceptions import ClientError

import articles.update_article as handler


def _conditional_check_failed() -> ClientError:
    return ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "boom"}},
        "UpdateItem",
    )


def _update_kwargs(mock_table):
    return mock_table.update_item.call_args.kwargs


def test_actualiza_campos_indicados(mock_table, lambda_context, event_factory):
    mock_table.update_item.return_value = {
        "Attributes": {"id": "a1", "title": "Nuevo titulo"}
    }
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"title": "Nuevo titulo"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["title"] == "Nuevo titulo"

    kwargs = _update_kwargs(mock_table)
    assert kwargs["Key"] == {"id": "a1"}
    assert kwargs["ConditionExpression"] == "attribute_exists(id)"
    # updated_at siempre se refresca, cambie lo que cambie.
    assert "#updated_at" in kwargs["ExpressionAttributeNames"]


def test_cambiar_title_marca_el_resumen_como_pendiente(mock_table, lambda_context, event_factory):
    mock_table.update_item.return_value = {"Attributes": {}}
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"title": "Titulo editado"}),
    )

    handler.lambda_handler(event, lambda_context)

    kwargs = _update_kwargs(mock_table)
    assert kwargs["ExpressionAttributeNames"]["#summary_status"] == "summary_status"
    assert kwargs["ExpressionAttributeValues"][":summary_status"] == "PENDING"


def test_cambiar_content_tambien_marca_el_resumen_como_pendiente(
    mock_table, lambda_context, event_factory
):
    mock_table.update_item.return_value = {"Attributes": {}}
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"content": "Contenido editado"}),
    )

    handler.lambda_handler(event, lambda_context)

    assert "#summary_status" in _update_kwargs(mock_table)["ExpressionAttributeNames"]


def test_cambiar_solo_tags_no_invalida_el_resumen(mock_table, lambda_context, event_factory):
    mock_table.update_item.return_value = {"Attributes": {}}
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"tags": ["politica"]}),
    )

    handler.lambda_handler(event, lambda_context)

    assert "#summary_status" not in _update_kwargs(mock_table)["ExpressionAttributeNames"]


def test_sin_id_en_la_ruta_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="PUT", path_params=None, body=json.dumps({"title": "T"}))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    mock_table.update_item.assert_not_called()


def test_body_vacio_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="PUT", path_params={"id": "a1"}, body="")

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_sin_ningun_campo_a_modificar_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(method="PUT", path_params={"id": "a1"}, body=json.dumps({}))

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_campo_no_editable_devuelve_400(mock_table, lambda_context, event_factory):
    """'author' y 'created_at' no son editables: la identidad no se toca aqui."""
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"author": "otro@x.com"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert "author" in body["details"]["unknown"]


def test_title_vacio_tras_strip_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"title": "   "})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_title_demasiado_largo_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"title": "x" * 201})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_content_vacio_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"content": "   "})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_content_demasiado_largo_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"content": "x" * 100_001}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_tags_no_lista_de_strings_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"tags": ["ok", 5]})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_body_base64_corrupto_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body="no-es-base64-valido!!",
        is_base64=True,
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400
    mock_table.update_item.assert_not_called()


def test_body_no_json_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body="esto no es json"
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_body_json_que_no_es_objeto_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps(["no", "es", "objeto"])
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_publish_date_con_formato_invalido_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT",
        path_params={"id": "a1"},
        body=json.dumps({"publish_date": "22-08-2026"}),
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_status_invalido_devuelve_400(mock_table, lambda_context, event_factory):
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"status": "borrador"})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 400


def test_articulo_inexistente_devuelve_404(mock_table, lambda_context, event_factory):
    mock_table.update_item.side_effect = _conditional_check_failed()
    event = event_factory(
        method="PUT", path_params={"id": "no-existe"}, body=json.dumps({"title": "T"})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 404


def test_error_generico_de_dynamodb_devuelve_500(mock_table, lambda_context, event_factory):
    mock_table.update_item.side_effect = RuntimeError("fallo de red")
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"title": "T"})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500


def test_client_error_no_condicional_devuelve_500(mock_table, lambda_context, event_factory):
    mock_table.update_item.side_effect = ClientError(
        {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "boom"}},
        "UpdateItem",
    )
    event = event_factory(
        method="PUT", path_params={"id": "a1"}, body=json.dumps({"title": "T"})
    )

    response = handler.lambda_handler(event, lambda_context)

    assert response["statusCode"] == 500
