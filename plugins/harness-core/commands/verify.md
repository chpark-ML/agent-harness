---
description: Run the harness guard hooks against their test cases and report the pass/fail summary
---

The hooks ship inside the `harness-core` plugin, so they are not in this project's tree — they live in the plugin cache and the verifiers sit beside them.

Run the dispatcher from the plugin root:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/verify-hooks.sh"
```

If `$CLAUDE_PLUGIN_ROOT` is not set in your shell, find the plugin with `claude plugin list` and run `scripts/verify-hooks.sh` from its directory.

Report concisely:

- how many verifiers ran (they are auto-discovered from `scripts/verify-*.sh`)
- one line each: `✓ secret-scrubber 30/30` / `✗ protected-paths 38/40`
- for any failure, the failing case names from that verifier's output

If everything passes, say so in one line and stop.

If something fails, say what changed recently and stop there. These files belong to the plugin: editing the cached copy is pointless because the next `claude plugin update` replaces it, so the fix goes to the [agent-harness](https://github.com/chpark-ML/agent-harness) repo and reaches you through a version bump.

For a quicker check that the guards are loaded at all — rather than that they are correct — `harnessctl doctor` feeds a sample credential through `secret-scrubber` and reports whether it blocked.
