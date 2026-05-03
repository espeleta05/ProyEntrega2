"""
Punto de entrada sugerido para la CLI de Flask.

Arranque recomendado (desarrollo): ver INICIAR.bat
  set FLASK_APP=app_2daE:app
  flask init-db
  flask run

Este módulo reexpone `app` por si defines FLASK_APP=app:app.
"""

from app_2daE import app

__all__ = ["app"]
