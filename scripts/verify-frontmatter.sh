#!/bin/bash
# verify-frontmatter.sh — every skill, agent and rule must have parseable YAML
# frontmatter, and skills must carry the fields that route them.
#
# This exists because of a silent failure: three skills shipped with a
# description containing `한국어 트리거: '...'`, and an unquoted YAML scalar
# cannot contain a colon-space. The frontmatter failed to parse, so at runtime
# those skills loaded with EMPTY metadata — no description, therefore no
# triggers and no negative routing. Nothing was broken visibly; the skills just
# silently stopped being findable. `claude plugin validate` catches it, but that
# needs the Claude CLI, so this runs the same check with nothing but python3.
#
# Run:  bash scripts/verify-frontmatter.sh

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "verify-frontmatter: python3 is required" >&2; exit 1; }

python3 - "$REPO" <<'PY'
import glob, os, re, sys

repo = sys.argv[1]
try:
    import yaml
except ImportError:
    print("verify-frontmatter: PyYAML not available — falling back to a colon-space scan")
    yaml = None

FM = re.compile(r'^---\n(.*?)\n---\n', re.S)
passed = failed = 0
problems = []


def check(path, kind, required):
    global passed, failed
    rel = os.path.relpath(path, repo)
    text = open(path, encoding='utf-8').read()
    m = FM.match(text)
    if not m:
        failed += 1; problems.append((rel, "no YAML frontmatter block")); return
    body = m.group(1)

    if yaml is None:
        # An unquoted scalar containing ": " is the failure we actually hit.
        for line in body.split('\n'):
            k, _, v = line.partition(': ')
            if k and not k.startswith((' ', '-')) and v and not v.startswith(('"', "'")) and ': ' in v:
                failed += 1
                problems.append((rel, "unquoted value contains a colon-space: %s" % k))
                return
        passed += 1
        return

    try:
        data = yaml.safe_load(body)
    except Exception as e:
        failed += 1
        problems.append((rel, "YAML parse error: %s" % str(e).split('\n')[0]))
        return
    if not isinstance(data, dict):
        failed += 1; problems.append((rel, "frontmatter is not a mapping")); return

    missing = [f for f in required if not data.get(f)]
    if missing:
        failed += 1
        problems.append((rel, "missing field(s): %s" % ", ".join(missing)))
        return

    if kind == 'skill':
        name = data['name']
        dirname = os.path.basename(os.path.dirname(path))
        if name != dirname:
            failed += 1
            problems.append((rel, "name '%s' does not match directory '%s'" % (name, dirname)))
            return
        # The description is what routes the model to the skill. Korean triggers
        # and the routing clause are checkable; English triggers are not, since
        # any English prose would satisfy a naive test — that part stays a human
        # review item, and harness-reviewer says so.
        desc = data['description']
        if '한국어' not in desc and 'Korean' not in desc:
            failed += 1
            problems.append((rel, "description has no Korean triggers"))
            return
        if '말고' not in desc and 'not this skill' not in desc.lower():
            failed += 1
            problems.append((rel, "description has no negative-routing clause"))
            return
    passed += 1


for p in sorted(glob.glob(os.path.join(repo, 'plugins/*/skills/*/SKILL.md'))):
    check(p, 'skill', ['name', 'description'])
for p in sorted(glob.glob(os.path.join(repo, '.claude/agents/*.md'))):
    check(p, 'agent', ['name', 'description'])
for p in sorted(glob.glob(os.path.join(repo, 'plugins/*/declarative/rules/*/*.md'))):
    check(p, 'rule', ['description', 'paths'])
for p in sorted(glob.glob(os.path.join(repo, 'plugins/*/commands/*.md'))
                + glob.glob(os.path.join(repo, '.claude/commands/*.md'))):
    check(p, 'command', ['description'])

total = passed + failed
print("=== frontmatter verification ===")
print("  %d / %d passed" % (passed, total))
for rel, why in problems:
    print("  FAIL  %s — %s" % (rel, why))
sys.exit(1 if failed else 0)
PY
