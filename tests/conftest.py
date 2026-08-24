"""Fixtures compartidas para las pruebas de src/articles.

Los handlers viven en `src/` como namespace packages (sin instalar), asi que
primero hay que ponerlos en sys.path. Las variables de entorno replican
exactamente las que Terraform inyecta en cada Lambda via
`local.lambda_environment` (ver terraform/main.tf).
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

SRC_DIR = Path(__file__).resolve().parent.parent / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))


@pytest.fixture(autouse=True)
def _lambda_environment(monkeypatch):
    """Variables de entorno presentes en toda invocacion real (main.tf)."""
    monkeypatch.setenv("ARTICLES_TABLE_NAME", "articles-test")
    monkeypatch.setenv("PUBLISH_DATE_INDEX", "publish_date-index")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")


@pytest.fixture
def mock_table(monkeypatch):
    """Sustituye common.db.get_table() por una tabla DynamoDB simulada.

    Los cuatro handlers hacen `from common import db` y llaman a
    `db.get_table()`; parchear el atributo en el modulo `common.db` (en vez de
    en cada handler) los afecta a los cuatro por igual y evita tocar el cache
    interno de `_table`.
    """
    from common import db

    table = MagicMock(name="dynamodb.Table")
    monkeypatch.setattr(db, "get_table", lambda: table)
    return table


@pytest.fixture
def lambda_context():
    """Objeto de contexto minimo. Ningun handler lo usa, pero forma parte de
    la firma `lambda_handler(event, context)`."""
    return MagicMock(name="lambda_context")


def _make_event(
    *,
    method: str = "GET",
    path: str = "/articles",
    query: dict | None = None,
    path_params: dict | None = None,
    body: str | None = None,
    is_base64: bool = False,
    claims: dict | None = None,
) -> dict:
    """Construye un evento minimo de API Gateway HTTP API (payload 2.0)."""
    event: dict = {
        "version": "2.0",
        "routeKey": f"{method} {path}",
        "rawPath": path,
        "queryStringParameters": query,
        "pathParameters": path_params,
        "isBase64Encoded": is_base64,
        "requestContext": {
            "http": {"method": method, "path": path},
        },
    }
    if body is not None:
        event["body"] = body
    if claims is not None:
        event["requestContext"]["authorizer"] = {"jwt": {"claims": claims}}
    return event


@pytest.fixture
def event_factory():
    """Factoria de eventos de API Gateway, para no repetir el boilerplate."""
    return _make_event
