"""Export the API contract as a static file (plan D-011): python -m app.export_openapi docs/openapi.json"""

import json
import sys
from pathlib import Path

from app.config import Settings
from app.main import create_app


def render() -> str:
    return json.dumps(create_app(Settings()).openapi(), indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> None:
    target = Path(argv[1] if len(argv) > 1 else "docs/openapi.json")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render(), encoding="utf-8")
    print(f"OpenAPI written to {target}")


if __name__ == "__main__":
    main(sys.argv)
