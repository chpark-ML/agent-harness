#!/bin/bash
# fixture-python.sh — build a small Python package for the LSP experiment.
#
# Type-clean on purpose: `pyright` reports zero errors on it as generated. The
# benchmark task then asks for an addition whose obvious implementation is NOT
# type-clean — load_config returns Optional[Config] and describe takes Config —
# so the only thing that moves the error count is whether the agent noticed.
#
# Usage: bash evals/fixture-python.sh <dir>
set -euo pipefail
D="$1"; mkdir -p "$D/app"

cat > "$D/app/__init__.py" <<'EOF'
EOF

cat > "$D/app/config.py" <<'EOF'
"""Configuration loading."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Config:
    endpoint: str
    timeout_s: float
    retries: int
    verify_tls: bool = True

    @property
    def timeout_ms(self) -> int:
        return int(self.timeout_s * 1000)


DEFAULT_PATH = os.environ.get("APP_CONFIG", "config.json")


def load_config(path: Optional[str] = None) -> Optional[Config]:
    """Read the config file.

    Returns None when the file does not exist. Raises ValueError when it
    exists but cannot be parsed.
    """
    target = path or DEFAULT_PATH
    if not os.path.exists(target):
        return None
    try:
        with open(target, encoding="utf-8") as fh:
            raw = json.load(fh)
    except json.JSONDecodeError as exc:
        raise ValueError(f"malformed config at {target}") from exc
    return Config(
        endpoint=raw["endpoint"],
        timeout_s=float(raw.get("timeout_s", 5.0)),
        retries=int(raw.get("retries", 3)),
        verify_tls=bool(raw.get("verify_tls", True)),
    )
EOF

cat > "$D/app/client.py" <<'EOF'
"""HTTP client built from configuration."""
from __future__ import annotations

from typing import Any, Optional

from .config import Config, load_config


class Client:
    def __init__(self, config: Config) -> None:
        self._config = config

    @property
    def timeout_ms(self) -> int:
        return self._config.timeout_ms

    def get(self, path: str) -> dict[str, Any]:
        return {"url": self._config.endpoint + path, "timeout": self.timeout_ms}


def build_client(path: Optional[str] = None) -> Optional[Client]:
    cfg = load_config(path)
    if cfg is None:
        return None
    return Client(cfg)
EOF

cat > "$D/app/scheduler.py" <<'EOF'
"""Retry scheduling."""
from __future__ import annotations

from .config import load_config


def backoff_schedule() -> list[float]:
    cfg = load_config()
    if cfg is None:
        return []
    return [cfg.timeout_s * (2 ** i) for i in range(cfg.retries)]
EOF

cat > "$D/app/report.py" <<'EOF'
"""Reporting helpers."""
from __future__ import annotations

from .config import Config


def describe(cfg: Config) -> str:
    return f"{cfg.endpoint} (timeout {cfg.timeout_ms}ms, {cfg.retries} retries)"


def describe_safe(cfg: Config | None) -> str:
    if cfg is None:
        return "no configuration"
    return describe(cfg)
EOF

cat > "$D/app/cli.py" <<'EOF'
"""Command line entry point."""
from __future__ import annotations

import sys

from .client import build_client
from .report import describe_safe
from .scheduler import backoff_schedule


def main(argv: list[str]) -> int:
    client = build_client(argv[1] if len(argv) > 1 else None)
    if client is None:
        print("no configuration")
        return 1
    print(describe_safe(client._config))
    print(backoff_schedule())
    print(client.get("/health"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
EOF

cat > "$D/pyproject.toml" <<'EOF'
[project]
name = "app"
version = "0.1.0"
requires-python = ">=3.10"
EOF
