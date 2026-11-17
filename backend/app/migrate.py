"""Apply SQL migrations in backend/migrations in order (idempotent).

    python -m app.migrate
"""
from __future__ import annotations

import sys
from pathlib import Path

from .config import load_settings

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


def main() -> int:
    import psycopg

    settings = load_settings()
    with psycopg.connect(settings.database_url, autocommit=True) as conn:
        conn.execute("""CREATE TABLE IF NOT EXISTS schema_migrations (
                            version TEXT PRIMARY KEY,
                            applied_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
        done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if path.name in done:
                continue
            print("applying", path.name)
            conn.execute(path.read_text(encoding="utf-8"))
            conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.name,))
    print("migrations up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
