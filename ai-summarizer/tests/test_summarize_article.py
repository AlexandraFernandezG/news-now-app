"""Tests de la Fase 2. Se implementaran junto con summarize_article.py."""

import pytest

pytestmark = pytest.mark.skip(reason="Fase 2: la capa de IA aun no esta implementada")


def test_marca_el_articulo_como_resumido():
    """INSERT con summary_status PENDING -> summary escrito y estado DONE."""


def test_ignora_eventos_remove():
    """Un evento REMOVE del stream no debe generar ninguna escritura."""


def test_no_pisa_una_edicion_posterior():
    """Si el articulo cambio mientras se generaba el resumen, no se sobrescribe."""
