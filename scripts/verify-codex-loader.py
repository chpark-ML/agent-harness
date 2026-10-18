#!/usr/bin/env python3
"""Check the actual Codex skill loader against an owned installed consumer.

No model request, auth copying, or user configuration edit. The app-server
protocol comes from the installed CLI; CI pins the version exercised here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time

sys.stdout.reconfigure(errors="replace")
sys.stderr.reconfigure(errors="replace")


class Loader:
    def __init__(self, cwd: Path, stderr):
        self.proc = subprocess.Popen(
            ["codex", "app-server", "--stdio"], cwd=cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.proc.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.sequence = 0
        try:
            self.request("initialize", {
                "clientInfo": {"name": "agent-harness-verification", "version": "1"},
                "capabilities": {"experimentalApi": True},
            })
            self.send({"method": "initialized", "params": {}})
        except BaseException:
            self.close()
            raise

    def send(self, message):
        self.proc.stdin.write((json.dumps(message) + "\n").encode("utf-8"))
        self.proc.stdin.flush()

    def request(self, method, params):
        self.sequence += 1
        request_id = self.sequence
        self.send({"id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                if not line:
                    continue
                message = json.loads(line)
                if message.get("id") == request_id:
                    if "error" in message:
                        raise RuntimeError(message["error"])
                    return message["result"]
            if self.selector.select(timeout=1):
                chunk = os.read(self.proc.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("Codex app server closed before responding")
                self.buffer += chunk
        raise TimeoutError(method)

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.selector.close()


def metadata(value, root):
    found = {}
    if isinstance(value, dict):
        path = value.get("path")
        if isinstance(path, str) and path.endswith("SKILL.md"):
            real = Path(path).resolve()
            if root in real.parents or root.parent / "skills" in Path(path).absolute().parents:
                if value.get("isEnabled") is False:
                    raise RuntimeError(f"Codex configuration disabled {value.get('name')}")
                found[value["name"]] = {"name": value["name"], "path": path,
                                        "description": value.get("description"), "scope": value.get("scope")}
        for child in value.values():
            found.update(metadata(child, root))
    elif isinstance(value, list):
        for child in value:
            found.update(metadata(child, root))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bash", default="/bin/bash")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if not shutil.which("codex"):
        parser.error("Codex CLI is required for the real loader check")
    repo = Path(__file__).resolve().parent.parent
    cli = repo / "plugins/harness-core/bin/harness-codex"
    args.evidence.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(argv, cwd):
        result = subprocess.run([str(x) for x in argv], cwd=cwd, capture_output=True, text=True, timeout=120)
        row = {"command": [str(x) for x in argv], "exit": result.returncode,
               "stdout": result.stdout, "stderr": result.stderr}
        commands.append(row)
        if result.returncode:
            raise RuntimeError(row)
        return result.stdout

    version = run(["codex", "--version"], repo).strip()
    with tempfile.TemporaryDirectory(prefix="codex-loader-consumer-") as raw:
        room = Path(raw).resolve()
        run(["git", "init", "--quiet"], room)
        consumer = b"Consumer-owned instructions; preserve these bytes.\n"
        (room / "AGENTS.md").write_bytes(consumer)
        run([args.bash, cli, "init", "--source", repo, "--with", "dev,research,slides"], room)
        root = room / ".agents/agent-harness"
        receipt = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        expected = {f"{Path(target).parent.parent.name}:{name}" for name, target in receipt["links"].items()}
        engineering_name = "harness-dev:engineering"
        assert expected and engineering_name in expected and "harness-dev:project-verification" in expected
        app = None
        moved = root / "payload/plugins/harness-dev/skills/engineering/SKILL.moved"
        original = moved.with_name("SKILL.md")
        try:
            with (args.evidence / "app-server.stderr").open("w", encoding="utf-8") as err:
                app = Loader(room, err)

                def scan():
                    return metadata(app.request("skills/list", {"cwds": [str(room)], "forceReload": True}), root)

                before = scan()
                assert set(before) == expected, {"expected": sorted(expected), "loaded": before}
                original.rename(moved)
                broken = scan()
                assert engineering_name not in broken and set(broken) == expected - {engineering_name}, broken
                moved.rename(original)
                restored = scan()
                assert set(restored) == expected, restored
                run([args.bash, cli, "uninstall"], room)
                after = scan()
                assert not after, after
                assert (room / "AGENTS.md").read_bytes() == consumer
        finally:
            if moved.exists():
                moved.rename(original)
            if app:
                app.close()
        evidence = {"codex": version, "cli_sha256": hashlib.sha256(cli.read_bytes()).hexdigest(),
                    "loaded": before, "missing_skill_control": sorted(broken),
                    "restored": sorted(restored), "after_uninstall": after,
                    "consumer_instructions_preserved": True, "commands": commands,
                    "limits": ["metadata discovery, not a model-quality measurement", "project scope"]}
    evidence["owned_consumer_removed"] = not room.exists()
    (args.evidence / "result.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"Codex loader: {len(before)} shared skills discovered; missing-file control, reload and uninstall verified")
    print(f"Evidence: {args.evidence}")


if __name__ == "__main__":
    main()
