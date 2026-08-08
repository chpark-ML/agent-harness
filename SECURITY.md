# Security

## Reporting

Open a [private security advisory](https://github.com/chpark-ML/agent-harness/security/advisories/new). Please do not open a public issue for anything exploitable.

## What this project is, in security terms

It installs guard hooks and permission tiers into a Claude Code configuration, and it can remove them again. It runs no server, opens no port, and stores no credentials. The blast radius is a developer machine or a repository's `.claude/` directory.

Two properties are verified rather than asserted:

- **Uninstall restores the original.** After `harnessctl uninstall`, `settings.json` is canonically identical to what it was before install (`jq -S`). The installer reverts only what its own receipt (`harness-manifest.json`) records, so a value you already had survives even when it is byte-identical to one we would have added.
- **The `hooks` block is never written.** Hooks are registered by the plugin system. A verifier asserts `settings.json`'s `.hooks` is byte-identical before and after install.

## What the default permissions allow

The `allow` tier means *no approval prompt*. It contains read-only inspection, safe git subcommands, and — deliberately — **five test runners**: `pytest`, `python3 -m pytest`, `npm test`, `cargo test`, `go test`.

**A test runner executes the repository's own code**, including `conftest.py` and any `pretest` script, without a prompt. That is a real widening and it is documented rather than hidden ([ADR-0012](docs/adr/0012-test-runners-in-allow.md)).

The reasoning: `make` was already in `allow`, and a Makefile runs anything. The line had been crossed; what existed was not "runners are dangerous" but "only repositories with a Makefile can be verified", which is an accident rather than a policy. `CLAUDE.md` §4 requires the agent to run its checks, and without a runner that requirement is unsatisfiable in a headless session.

**Bare `python3`, `sh`, `bash` and `node` are not in `allow`** — those open a shell rather than run a test. Neither is `npm run <script>`, whose script name is arbitrary.

**To narrow it**, put the entry in your own `settings.json` under `deny`. Deny beats allow.

## What the guards do and do not catch

Guards reduce the chance of a specific accident. They are not a security boundary, and the documented limits are real:

- `secret-scrubber` matches named patterns. A high-entropy value with no surrounding name is not detectable without treating every long string as a secret, and it is a known miss.
- `protected-paths` compares literal prefixes. Path traversal is not resolved, and a verifier asserts that gap so it cannot change silently.
- `ai-attribution-guard` matches attribution markers, and a contributor actually named Claude would trip it.

Each limit is stated in `docs/hooks/<name>.md` and pinned by a test case that asserts the current behaviour, so the documentation cannot drift away from the code.

Measured on an independently written corpus: 27 of 29 staged incidents stopped, 2 of 24 ordinary commands falsely blocked. **Read both numbers.** A guard that blocks everything scores perfectly and gets disabled the same day.

## Supply chain

- Dependencies are declared plugins: [`superpowers`](https://github.com/obra/superpowers) and the official LSP plugins. They are installed by `claude plugin install`, not vendored.
- `install.sh` runs `claude plugin marketplace add` against this repository. Pin it with `--ref <tag>` if a moving `main` is a concern; tags version the snapshot a consumer receives ([ADR-0013](docs/adr/0013-release-tags.md)).
- `--with-tools` runs `npm install -g` for language servers. It is opt-in for that reason.
- The installer requires `jq` and refuses to proceed without it. Shipping guards that silently self-disable is worse than an honest failure ([ADR-0002](docs/adr/0002-hook-contract.md)).

## Not adopted, on security grounds

- **Session-capture tooling** that records all tool input and output. In a repository that runs `secret-scrubber`, what such a tool swallows has to be established first.
- **Local model gateways** that route prompts and code through a third-party proxy. That is a security decision for the operator, not a harness default.
