"""Fixtures compartidas para las pruebas de ai-summarizer/.

Los handlers viven sueltos en ai-summarizer/ (sin subpaquete "common"): cada
Lambda se empaqueta con un unico fichero (ver terraform/ai/summarize_article.tf
y terraform/ai/daily_digest.tf, `source_files`), asi que primero hay que
anadir el directorio a sys.path para poder importarlos como `import
summarize_article` / `import daily_digest`.
"""

from __future__ import annotations

import sys
from pathlib import Path

AI_DIR = Path(__file__).resolve().parent.parent
if str(AI_DIR) not in sys.path:
    sys.path.insert(0, str(AI_DIR))
