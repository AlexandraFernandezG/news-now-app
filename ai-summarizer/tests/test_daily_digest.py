"""Tests de la Fase 2. Se implementaran junto con daily_digest.py."""

import pytest

pytestmark = pytest.mark.skip(reason="Fase 2: la capa de IA aun no esta implementada")


def test_consulta_el_gsi_por_publish_date():
    """El digest usa Query sobre publish_date-index, nunca Scan."""


def test_dia_sin_articulos_no_genera_digest():
    """Sin articulos publicados ese dia no se produce salida."""


def test_agrega_los_resumenes_existentes():
    """El digest se compone a partir del campo `summary` de cada articulo."""
