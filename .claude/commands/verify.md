---
description: Run the full harness check suite (make verify) and report the pass/fail summary
---

Run `make verify` from the repo root. If it passes, also run `make verify BASH=/bin/bash` — the macOS bash 3.2 floor is the constraint that actually breaks, and CI enforces it, so finding out locally is cheaper.

Report concisely:

- syntax: how many scripts parsed
- hooks: one line per verifier, `✓ secret-scrubber 37/37` / `✗ protected-paths 49/51`
- installer: `✓ verify-install 90/90`, and for any failure the failing assertion names

If everything passes, say so in one line and stop. If something fails, name the failing cases and the most likely cause given the current diff — do not fix it unless asked.
