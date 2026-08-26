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
# Run:  make frontmatter          # selftest, then the check
#       bash scripts/verify-frontmatter.sh   # reads .claude/trigger-langs
#       bash scripts/verify-frontmatter.sh --selftest   # the reporting path

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "verify-frontmatter: python3 is required" >&2; exit 1; }

# ---- selftest ---------------------------------------------------------------
# Not about frontmatter: about this script's ability to *report*. Every line it
# prints carries an em-dash, and Python's stdout defaults to the locale encoding
# with errors='strict'. On a console that cannot hold one — cp949 on Korean
# Windows, or any locale reached through PYTHONIOENCODING — printing raised
# UnicodeEncodeError, so the checker died at the exact moment it had something
# to say. Observed as: 11 / 11 checks pass, then exit 1 with a traceback.
#
# PYTHONIOENCODING reproduces it on every platform, so this runs in CI too and
# is not a Windows-only case. The glob half is the other arm of CLAUDE.md §4:
# a third python-embedding verifier must not be able to reappear without this.
if [ "${1:-}" = "--selftest" ]; then
  pass=0; fail=0
  echo "=== frontmatter selftest ==="

  # "$BASH" re-runs under the same interpreter, so `make frontmatter
  # BASH=/bin/bash` measures the 3.2 floor here too rather than silently
  # falling back to whatever /usr/bin/env picks.
  out="$(PYTHONIOENCODING=ascii HARNESS_TRIGGER_LANGS='' "$BASH" "$0" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'UnicodeEncodeError'; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL  a clean run must stay clean when stdout cannot encode its output (rc=$rc)"
  fi

  for f in "$REPO"/scripts/verify-*.sh; do
    grep -q "python3 -" "$f" || continue

    # Anchored: the call sits at column 0 inside the heredoc. An unanchored
    # pattern matches this very line, which exempted this file from its own
    # check — the first thing this loop caught was itself lying.
    if grep -q '^sys\.stdout\.reconfigure' "$f"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "  FAIL  $(basename "$f") embeds python3 with a strict stdout"
    fi

    # The other direction, found the same afternoon: a bare read call without an
    # encoding takes the locale codec, so verify-benches could not decode the
    # Korean eval sets it exists to validate. Output and input are the same
    # assumption made twice.
    #
    # `[A-Za-z_]` after the paren, and comment lines dropped: the first draft
    # matched its own grep argument and the prose in this very comment, and a
    # checker that cries wolf gets switched off (ADR-0003). Real calls pass an
    # identifier; a quoted pattern and a prose `()` do not.
    if grep "open([A-Za-z_]" "$f" | grep -v '^[[:space:]]*#' | grep -qv 'encoding='; then
      fail=$((fail + 1))
      echo "  FAIL  $(basename "$f") opens a file without declaring its encoding"
    else
      pass=$((pass + 1))
    fi
  done

  echo "  $pass / $((pass + fail)) passed"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

python3 - "$REPO" <<'PY'
import glob, os, re, sys

# Report first, encode second. Every line below carries an em-dash and stdout
# defaults to the locale encoding with errors='strict', so on a console that
# cannot hold one this used to raise UnicodeEncodeError *while printing the
# result* — a fully passing run exited 1 with a traceback. 'replace' degrades
# the character; 'strict' degrades the whole verifier. See --selftest.
sys.stdout.reconfigure(errors='replace')
sys.stderr.reconfigure(errors='replace')

repo = sys.argv[1]
# Where the declaration comes from, and why it is not a Makefile variable.
#
# HARNESS_TRIGGER_LANGS *present* wins, even when empty — that is how the
# selftest asks for "no languages" and how a caller overrides for one run.
# Absent means read .claude/trigger-langs, which is the deployment's standing
# answer. The env var used to be the only route, set by `make frontmatter`, and
# Windows `make.exe` re-encodes recipe text through the ANSI codepage on its way
# into the child environment: `한국어` arrived as mojibake and five skills that
# carry the marker were reported as missing it. Reading the file here means the
# value never crosses a process boundary that can re-encode it.
LANGS_FILE = os.path.join(repo, '.claude', 'trigger-langs')
raw = os.environ.get('HARNESS_TRIGGER_LANGS')
if raw is None:
    raw = ''
    if os.path.exists(LANGS_FILE):
        with open(LANGS_FILE, encoding='utf-8') as fh:
            raw = ','.join(l.strip() for l in fh
                           if l.strip() and not l.lstrip().startswith('#'))
LANGS = [x.strip() for x in raw.split(',') if x.strip()]
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
        # Without PyYAML the kind-specific checks below cannot run, and for most
        # kinds that is an acceptable degradation — a skill missing its routing
        # clause is caught by review. An output style is the exception: omitting
        # keep-coding-instructions SUBTRACTS the built-in coding instructions,
        # and it does so silently. Presence is a substring test, so the degraded
        # path can still hold that one line.
        if kind == 'output-style' and 'keep-coding-instructions' not in body:
            failed += 1
            problems.append((rel, "no keep-coding-instructions — the default "
                                  "(false) drops the built-in coding instructions"))
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

    if kind == 'output-style':
        # `keep-coding-instructions` defaults to FALSE, and that default strips
        # Claude Code's built-in software-engineering instructions — how to
        # scope a change, when to comment, how to verify. A style that omits
        # the key therefore guts the harness without saying so anywhere.
        #
        # The key is required to be PRESENT, not to be true: a style that
        # genuinely replaces the coding instructions is a legitimate thing to
        # write, and a check that forbade it would be a false positive. What is
        # not legitimate is arriving at either behaviour by default. It cannot
        # go in `required` above, because that test is `not data.get(f)` and a
        # deliberate `false` would read as missing.
        if 'keep-coding-instructions' not in data:
            failed += 1
            problems.append((rel, "no keep-coding-instructions — the default "
                                  "(false) drops the built-in coding instructions"))
            return
        passed += 1
        return

    if kind == 'skill':
        name = data['name']
        dirname = os.path.basename(os.path.dirname(path))
        if name != dirname:
            failed += 1
            problems.append((rel, "name '%s' does not match directory '%s'" % (name, dirname)))
            return
        # The description is what routes the model to the skill. The routing
        # clause is checkable; English triggers are not, since any English prose
        # would satisfy a naive test — that part stays a human review item, and
        # harness-reviewer says so.
        #
        # Second-language triggers used to be required here, and the required
        # language was Korean. That made a contributor writing a skill for a
        # Japanese team unable to pass CI without adding a Korean marker, which
        # is a defect rather than a convention. A deployment now declares which
        # languages it serves and only those are checked; unset means the check
        # does not run, and the summary line says so rather than printing a
        # clean pass. Which languages a description should carry is a property
        # of the deployment, not of the harness.
        #
        # Each comma-separated entry must appear. `|` inside an entry accepts
        # any one of its labels, which is what the hardcoded check did: a
        # description could mark its Korean triggers as 한국어 or as Korean.
        desc = data['description']
        for entry in LANGS:
            if not any(alt in desc for alt in entry.split('|')):
                failed += 1
                problems.append((rel, "description has no %s triggers" % entry))
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
for p in sorted(glob.glob(os.path.join(repo, 'plugins/*/output-styles/*.md'))):
    check(p, 'output-style', ['name', 'description'])
for p in sorted(glob.glob(os.path.join(repo, 'plugins/*/commands/*.md'))
                + glob.glob(os.path.join(repo, '.claude/commands/*.md'))):
    check(p, 'command', ['description'])

total = passed + failed
print("=== frontmatter verification ===")
print("  %d / %d passed" % (passed, total))
print("  trigger languages: %s" % (" + ".join(LANGS) if LANGS
      else "none declared — .claude/trigger-langs is empty or absent and "
           "HARNESS_TRIGGER_LANGS was set empty, so that check did not run"))
for rel, why in problems:
    print("  FAIL  %s — %s" % (rel, why))
sys.exit(1 if failed else 0)
PY
