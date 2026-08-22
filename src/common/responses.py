"""Helpers de respuesta HTTP para las Lambdas del CRUD de articulos.

Las respuestas siguen el formato de payload 2.0 de API Gateway HTTP API.

No se anaden cabeceras CORS aqui a proposito: CORS lo resuelve el propio
HTTP API (`cors_configuration` en api_gateway.tf). Devolverlas tambien desde
la integracion produciria cabeceras duplicadas y el navegador rechazaria la
respuesta.
"""

from __future__ import annotations

import json
import logging
import os
from decimal import Decimal
from typing import Any, Mapping

__all__ = [
    "ApiError",
    "build",
    "ok",
    "created",
    "no_content",
    "bad_request",
    "unauthorized",
    "not_found",
    "server_error",
    "from_exception",
    "get_logger",
]

_JSON_CONTENT_TYPE = "application/json; charset=utf-8"


def get_logger(name: str) -> logging.Logger:
    """Logger con el nivel que fija la variable de entorno LOG_LEVEL."""
    logger = logging.getLogger(name)
    logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    return logger


class ApiError(Exception):
    """Error de negocio que se traduce directamente a una respuesta HTTP.

    Permite abortar desde cualquier punto del handler sin arrastrar el codigo
    de estado por toda la pila de llamadas.
    """

    def __init__(self, status_code: int, message: str, **details: Any) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.details = details

    def to_response(self) -> dict[str, Any]:
        body: dict[str, Any] = {"message": self.message}
        if self.details:
            body["details"] = self.details
        return build(self.status_code, body)


def _json_default(value: Any) -> Any:
    """DynamoDB devuelve numeros como Decimal, que json no sabe serializar."""
    if isinstance(value, Decimal):
        # Se preserva int cuando el valor no tiene parte decimal, para que el
        # frontend no reciba 3.0 donde espera 3.
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, (set, frozenset)):
        return sorted(value)
    raise TypeError(f"Objeto no serializable a JSON: {type(value).__name__}")


def build(
    status_code: int,
    body: Any = None,
    headers: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    """Construye la respuesta que espera API Gateway."""
    response: dict[str, Any] = {
        "statusCode": status_code,
        "headers": dict(headers or {}),
        "isBase64Encoded": False,
    }

    if body is None:
        response["body"] = ""
        return response

    response["headers"].setdefault("Content-Type", _JSON_CONTENT_TYPE)
    response["body"] = json.dumps(body, default=_json_default, ensure_ascii=False)
    return response


def ok(body: Any, headers: Mapping[str, str] | None = None) -> dict[str, Any]:
    return build(200, body, headers)


def created(body: Any, location: str | None = None) -> dict[str, Any]:
    headers = {"Location": location} if location else None
    return build(201, body, headers)


def no_content() -> dict[str, Any]:
    return build(204)


def bad_request(message: str, **details: Any) -> dict[str, Any]:
    return ApiError(400, message, **details).to_response()


def unauthorized(message: str = "No autenticado") -> dict[str, Any]:
    return ApiError(401, message).to_response()


def not_found(message: str = "Recurso no encontrado") -> dict[str, Any]:
    return ApiError(404, message).to_response()


def server_error(message: str = "Error interno") -> dict[str, Any]:
    return ApiError(500, message).to_response()


def from_exception(exc: Exception, logger: logging.Logger) -> dict[str, Any]:
    """Traduce una excepcion a respuesta HTTP sin filtrar detalles internos."""
    if isinstance(exc, ApiError):
        logger.warning("Error de negocio %s: %s", exc.status_code, exc.message)
        return exc.to_response()

    logger.exception("Error no controlado en el handler")
    return server_error()
