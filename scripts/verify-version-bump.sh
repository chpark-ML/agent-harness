#!/bin/bash
# verify-version-bump.sh — a change inside a plugin must move that plugin's version.
#
# catches: a commit range that edits plugins/<name>/** without changing the
#          `version` value in plugins/<name>/.claude-plugin/plugin.json.
# scope:   the range only. It says nothing about whether the new version is
#          larger, or semver-shaped — `claude plugin validate --strict` owns
#          the manifest's shape and this owns the fact that it moved.
# bypass:  none. Bump the version; even a comment-only edit needs one, because
#          the plugin cache is keyed on the version string and an un-bumped
#          change reaches nobody.
#
# WHY THIS IS A SCRIPT AND NOT A WORKFLOW STEP
# CLAUDE.md §4: "a line that runs in only *one* of the environments the verifier
# runs in is an unverified line". verify-check-total was written on a machine
# with the Claude CLI and its no-CLI branch executed for the first time in CI,
# where it broke. A guard that lives in YAML can only ever run in CI, so the
# logic lives here, `--selftest` exercises it everywhere, and the workflow is a
# two-line caller.
#
# Requires bash 3.2, git and jq. jq rather than python3 on purpose: the version
# has to be read as a *value*, and jq is already a hard requirement of `verify`
# (every hook verifier needs it), so this adds no dependency and stays clear of
# verify-frontmatter's encoding rules for python-embedding verifiers.
#
# Run:  bash scripts/verify-version-bump.sh                  # main..HEAD
#       bash scripts/verify-version-bump.sh <base> <head>
#       bash scripts/verify-version-bump.sh --selftest        # 13 cases

set -u

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
BASH_BIN="${BASH:-bash}"

# ---- the check ---------------------------------------------------------------
# Reads the version as a value at each end of the range. Two upstream lessons
# are load-bearing here and each has a selftest case:
#
#   * merge-base, not the base tip. The tip moves after a PR is opened, and a
#     tip diff then reports files the branch never touched (case 12).
#   * the parsed value, not the diff line. Reformatting plugin.json moves the
#     version line without changing it, and a diff-line grep passes (case 11).

read_version() {  # <ref> <path> -> the version value, or empty
  git show "$1:$2" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true
}

check_range() {  # <base> <head> -> 0 clean, 1 a plugin moved without a bump
  base="$1"; head="$2"

  mb="$(git merge-base "$base" "$head" 2>/dev/null || true)"
  if [ -z "$mb" ]; then
    echo "  FAIL  no merge base between '$base' and '$head'"
    return 1
  fi

  # A path directly under plugins/ (plugins/README.md) has no second slash and
  # so names no plugin — the `[^/]*/` is what excludes it.
  touched="$(git diff --name-only "$mb" "$head" -- 'plugins' 2>/dev/null \
             | sed -n 's|^plugins/\([^/]*\)/.*|\1|p' | sort -u)"

  if [ -z "$touched" ]; then
    echo "  ok    no plugin content in ${mb}..${head}"
    return 0
  fi

  rc=0
  for p in $touched; do
    manifest="plugins/$p/.claude-plugin/plugin.json"
    was="$(read_version "$mb" "$manifest")"
    now="$(read_version "$head" "$manifest")"

    if [ "$was" != "$now" ]; then
      echo "  ok    $p  ${was:-(absent)} -> ${now:-(absent)}"
    else
      rc=1
      echo "  FAIL  $p  changed with version still '${now:-(unset)}'"
      echo "        The plugin cache is keyed on that string, so this change"
      echo "        reaches nobody. Bump \"version\" in $manifest."
    fi
  done
  return $rc
}

# ---- selftest ---------------------------------------------------------------
# Fixture repositories, not a mocked diff. Every bug this check can have lives
# in the git plumbing — which ref, which base, which file — so a selftest that
# stubs git out would verify the part that cannot break.
#
# How it fails decides what it owes (CLAUDE.md §4): a false positive blocks a
# correct PR, and a blocked contributor switches the gate off. Hence four
# no-op cases and five boundary cases against four blocking ones.

selftest() {
  pass=0; fail=0
  echo "=== version-bump selftest ==="

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT INT TERM

  # Each case gets its own repository. Shared state between git fixtures is how
  # a case starts passing because of the case before it.
  fixture() {  # <name> -> echoes the repo path, cwd left inside it
    d="$tmp/$1"
    mkdir -p "$d"
    cd "$d" || exit 1
    git init -q .
    git config user.email h@example.com
    git config user.name harness
    git config commit.gpgsign false
    mkdir -p docs scripts plugins
    echo doc > docs/a.md
    echo script > scripts/a.sh
    echo root > plugins/README.md
    plugin harness-core 1.0.0
    plugin harness-dev 1.0.0
    git add -A && git commit -qm base
    git branch -M main
    echo "$d"
  }

  plugin() {  # <name> <version>
    mkdir -p "plugins/$1/.claude-plugin" "plugins/$1/skills/s" \
             "plugins/$1/hooks" "plugins/$1/bin"
    printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$1" "$2" \
      > "plugins/$1/.claude-plugin/plugin.json"
    echo body > "plugins/$1/skills/s/SKILL.md"
    echo hook > "plugins/$1/hooks/h.sh"
    echo bin  > "plugins/$1/bin/b"
  }

  bump() {  # <name> <version>
    printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$1" "$2" \
      > "plugins/$1/.claude-plugin/plugin.json"
  }

  # `case_is <label> <expected-rc>` runs the check in the current fixture on
  # main..work and compares the exit code. The message is asserted separately
  # only where the message is the point (case 8).
  case_is() {
    out="$("$BASH_BIN" "$SELF" main work 2>&1)"; got=$?
    if [ "$got" -eq "$2" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "  FAIL  $1 (expected rc=$2, got $got)"
      printf '%s\n' "$out" | sed 's/^/          /'
    fi
    LAST_OUT="$out"
  }

  section() { printf '\n--- %s\n' "$1"; }

  section "no-op — must stay quiet"

  # 1. An empty range. The commonest case on a freshly branched tree, and the
  #    one that decides whether this gate is silent by default.
  fixture noop-empty >/dev/null
  git checkout -qb work
  case_is "an empty range passes" 0

  # 2/3. Everything outside plugins/ is invisible to this check. Two separate
  #      cases because docs and scripts are the two trees that change most.
  fixture noop-docs >/dev/null
  git checkout -qb work
  echo more >> docs/a.md && git commit -qam docs
  case_is "a docs-only range passes" 0

  fixture noop-scripts >/dev/null
  git checkout -qb work
  echo more >> scripts/a.sh && git commit -qam scripts
  case_is "a scripts-only range passes" 0

  # 4. plugins/README.md is under plugins/ but inside no plugin, so it names no
  #    manifest to bump. The first draft's regex claimed it and demanded a bump
  #    for a plugin called "README.md".
  fixture noop-plugins-root >/dev/null
  git checkout -qb work
  echo more >> plugins/README.md && git commit -qam "plugins root"
  case_is "a file at the plugins root passes" 0

  section "block — the change reaches nobody without a bump"

  # 5/6/7. The three shipped component kinds. Separate cases because each is a
  #        different cache-invalidation story in CLAUDE.md §2/§2b/§2c, and a
  #        regex that covers skills but not bin/ would pass a single joint case.
  for kind in skills/s/SKILL.md hooks/h.sh bin/b; do
    fixture "block-$(echo "$kind" | tr /. --)" >/dev/null
    git checkout -qb work
    echo edited >> "plugins/harness-core/$kind" && git commit -qam "$kind"
    case_is "an unbumped $kind fails" 1
  done

  # 8. Two plugins, one bumped. The message has to name the one that is wrong;
  #    "a plugin needs a bump" sends the reader to check both.
  fixture block-partial >/dev/null
  git checkout -qb work
  echo edited >> plugins/harness-core/skills/s/SKILL.md
  echo edited >> plugins/harness-dev/skills/s/SKILL.md
  bump harness-core 1.0.1
  git commit -qam "two plugins, one bump"
  case_is "one bumped and one not fails" 1
  if printf '%s' "$LAST_OUT" | grep -q 'FAIL  harness-dev' \
     && printf '%s' "$LAST_OUT" | grep -q 'ok    harness-core'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL  the message must name harness-dev and clear harness-core"
    printf '%s\n' "$LAST_OUT" | sed 's/^/          /'
  fi

  section "boundary — resembles a block and must pass"

  # 9. The ordinary correct PR.
  fixture ok-bumped >/dev/null
  git checkout -qb work
  echo edited >> plugins/harness-core/skills/s/SKILL.md
  bump harness-core 1.0.1
  git commit -qam "skill + bump"
  case_is "a bumped change passes" 0

  # 10. A release commit that moves nothing but the version. Failing this would
  #     make the gate impossible to satisfy in one commit.
  fixture ok-bump-only >/dev/null
  git checkout -qb work
  bump harness-core 1.1.0
  git commit -qam "bump only"
  case_is "a version-only change passes" 0

  # 11. The diff-line trap. plugin.json is rewritten so the version line moves
  #     to a different position with the same value. A check that greps the diff
  #     for a changed line containing "version" passes this; reading the value
  #     does not. This is the case that fixes the implementation, not the spec.
  fixture boundary-reformat >/dev/null
  git checkout -qb work
  echo edited >> plugins/harness-core/skills/s/SKILL.md
  printf '{\n  "version": "1.0.0",\n  "name": "harness-core"\n}\n' \
    > plugins/harness-core/.claude-plugin/plugin.json
  git commit -qam "reformat, no bump"
  case_is "a moved-but-equal version line still fails" 1

  # 12. The base tip moves after the branch point. main gains a commit that
  #     edits a plugin *without* a bump — legal in a fixture, and exactly what
  #     makes this discriminating: a `git diff main work` reports harness-dev as
  #     changed (work lacks that commit) and demands a bump for work's author.
  #     merge-base sees only work's own commits.
  fixture boundary-moved-tip >/dev/null
  git checkout -qb work
  echo edited >> plugins/harness-core/skills/s/SKILL.md
  bump harness-core 1.0.1
  git commit -qam "work: skill + bump"
  git checkout -q main
  echo unrelated >> plugins/harness-dev/skills/s/SKILL.md
  git commit -qam "main moved on"
  git checkout -q work
  case_is "a base tip that moved after branching passes" 0

  # 13. A plugin that did not exist at the base has no old version to differ
  #     from. Absent-to-present is a move, and treating "no manifest at base"
  #     as "version unchanged" would block every new profile.
  fixture boundary-new-plugin >/dev/null
  git checkout -qb work
  plugin harness-newthing 0.1.0
  git add -A && git commit -qm "a new plugin"
  case_is "a brand-new plugin passes" 0

  echo
  echo "  $pass / $((pass + fail)) passed"
  [ "$fail" -eq 0 ] || return 1
  return 0
}

# ---- entry ------------------------------------------------------------------

if [ "${1:-}" = "--selftest" ]; then
  selftest
  exit $?
fi

echo "=== version bump ==="
check_range "${1:-main}" "${2:-HEAD}"
exit $?
