#!/bin/bash
# verify-doc-refs.sh — a document must be able to reach what it points at.
#
# Two incidents, same shape, both recorded in .claude/harness-gaps.md:
#
#   1. pr-create/SKILL.md said `.claece/harness-gaps.md`. The step was written
#      as `[ -f ... ] && ...`, so a missing file means the step silently does
#      nothing — that section could never have run and nothing would have said so.
#   2. README.md linked `#2-make-bench----날것-…`. GitHub does not collapse the
#      spaces left behind by stripped punctuation, so the real slug has two
#      hyphens where that link had four. It renders fine and goes nowhere.
#
# Neither is an error. Both are *nothing happening*, which is the failure mode
# docs/agent-layer.md §4 keeps finding: some failures show up as an empty value,
# not an exception. Hooks have verify-*.sh and frontmatter has
# verify-frontmatter.sh; the bodies of those same files had nothing.
#
# Checks: markdown/HTML links resolve (local files exist, #anchors match a
# heading under GitHub's slug rules), and paths named in instruction files
# start with a directory that exists here.
#
# Run:  bash scripts/verify-doc-refs.sh
#       bash scripts/verify-doc-refs.sh --selftest   # the checker's own cases

set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  echo "verify-doc-refs: python3 is required" >&2; exit 1; }

python3 - "$REPO" "${1:-}" <<'PY'
import glob, os, re, sys

# A FAIL line here carries an em-dash, so on a console whose encoding cannot
# hold one this raised UnicodeEncodeError at the moment it had a problem to
# report — clean runs looked fine and only failing ones died. Asserted by
# verify-frontmatter.sh --selftest, which globs every verifier for this line.
sys.stdout.reconfigure(errors='replace')
sys.stderr.reconfigure(errors='replace')

repo, mode = sys.argv[1], sys.argv[2]

FENCE = re.compile(r'^\s*(```|~~~)', re.M)
ATX = re.compile(r'^(#{1,6})\s+(.+?)\s*$', re.M)
MD_LINK = re.compile(r'!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
HTML_HREF = re.compile(r'(?:href|src)="([^"]+)"')
EXTERNAL = re.compile(r'^(https?:|mailto:|tel:|data:|//)')

# A backticked token that looks like a repo-relative path: no spaces, no
# placeholder brackets, at least one slash. `<name>.json` and `origin/<x>..HEAD`
# are excluded by the bracket rule, `~/.claude/...` by the leading character.
PATH_TOKEN = re.compile(r'`(\.?[A-Za-z0-9_][-\w.]*(?:/[-\w.@]+)+)`')


INLINE_CODE = re.compile(r'`[^`]*`')


def strip_code(text):
    """Blank out fenced blocks, keeping line count so nothing shifts."""
    out, fence = [], None
    for line in text.split('\n'):
        m = FENCE.match(line)
        if fence is None and m:
            fence = m.group(1); out.append(''); continue
        if fence is not None:
            if line.strip().startswith(fence):
                fence = None
            out.append(''); continue
        out.append(line)
    return '\n'.join(out)


def linkable(text):
    """Text with code removed — what is left is where real links can be.

    Inline code goes too: `[x](#anchor)` inside backticks is a quotation, which
    is how the ledger records the broken link that motivated this checker. Note
    that slugs() deliberately does NOT use this — GitHub keeps the text of an
    inline-code heading when it builds the anchor, so stripping it there would
    compute the wrong slug for every `### \\`make bench\\`` style heading.
    """
    return INLINE_CODE.sub('', strip_code(text))


def slugs(text):
    """Heading anchors as GitHub generates them.

    Lowercase, drop everything that is not a word character, space or hyphen,
    then spaces become hyphens. Spaces are NOT collapsed — that is exactly the
    step the broken README link got wrong. Repeats get -1, -2, ... appended.
    """
    seen, out = {}, set()
    for _, heading in ATX.findall(strip_code(text)):
        s = re.sub(r'[^\w\s-]', '', heading.strip().lower(), flags=re.U).replace(' ', '-')
        n = seen.get(s, 0)
        seen[s] = n + 1
        out.add(s if n == 0 else '%s-%d' % (s, n))
    return out


def links_resolve_here(path):
    """False for payload written to be read from somewhere other than this tree.

    `declarative/` is installed into a consumer project, so its relative links
    are correct for `.claude/rules/harness/` and wrong for the source tree —
    `review.md`'s `../workflow.md` lands on the installed sibling. Checking those
    against this checkout reports the payload as broken when it is correct, and
    a checker that cries wolf gets switched off. Their anchors are still checked;
    only file existence is skipped. Nothing verifies the install-relative half:
    doing that means reproducing harnessctl's file plan, and no link in this
    payload has broken yet, so that stays unbuilt (docs/agent-layer.md §7).
    """
    # Compared on a slash-normalised copy. `glob` hands back the platform
    # separator, so on Windows this asked whether '/declarative/' appeared in
    # a path spelled with backslashes — never, so the payload below was checked
    # against the source tree after all and reported 4 correct links as broken.
    # An exemption that silently stops exempting is worse than none: it turns
    # the checker into the wolf-crier it was written to avoid.
    return '/declarative/' not in path.replace(os.sep, '/')


def check_doc(path, read):
    """Yield (line_number, target, reason) for every reference that goes nowhere."""
    text = read(path)
    body = linkable(text)
    here = slugs(text)
    check_files = links_resolve_here(path)
    problems = []
    for i, line in enumerate(body.split('\n'), 1):
        for target in MD_LINK.findall(line) + HTML_HREF.findall(line):
            if EXTERNAL.match(target):
                continue
            file_part, _, anchor = target.partition('#')
            if not file_part:                              # same-document anchor
                if anchor not in here:
                    problems.append((i, target, "no heading makes this anchor"))
                continue
            if not check_files:
                continue
            dest = os.path.normpath(os.path.join(os.path.dirname(path), file_part))
            if not os.path.exists(dest):
                problems.append((i, target, "file does not exist"))
            elif anchor and dest.endswith('.md'):
                if anchor not in slugs(read(dest)):
                    problems.append((i, target, "no heading in %s makes this anchor"
                                     % os.path.relpath(dest, repo)))
    return problems


def check_paths(path, read):
    """Yield problems for path tokens whose first segment exists nowhere.

    Only the first segment is checked, on purpose. Instruction files legitimately
    name paths that exist only after install (`.claude/rules/harness/workflow.md`
    has no counterpart in this tree), so a full-path check would flag correct
    references. The first segment is the part a typo destroys visibly — it is
    what turned `.claude/` into `.claece/` — and it is safe to verify.
    """
    problems = []
    for i, line in enumerate(read(path).split('\n'), 1):
        for token in PATH_TOKEN.findall(line):
            top = token.split('/')[0]
            if not os.path.exists(os.path.join(repo, top)):
                problems.append((i, token, "no '%s' in this repo" % top))
    return problems


# ---- the real run -----------------------------------------------------------
# '*.md' at the root, not a list: README.ko.md, CONTRIBUTING.md and SECURITY.md
# were added and none of them were checked, because a hardcoded list is exactly
# how a new document becomes invisible to its own checker.
DOCS = ['*.md', 'docs/**/*.md', 'plugins/**/*.md',
        '.claude/**/*.md', 'evals/*.md']
# Frozen copies of documents that used to live elsewhere, kept as bench-claims
# input and marked DO NOT EDIT. Their links were relative to the originals, so
# they are historical text, not references this tree is supposed to satisfy.
# `.claude/rules/` is what `harnessctl init` writes when this repository is
# installed onto itself. Same reasoning as the line above — output, not a
# document this tree wrote — but it matters for a different reason: the scan
# globs the filesystem rather than asking git, so an untracked install artefact
# is counted on a developer's machine and absent in CI. That made the published
# check total differ by three between the two, and it was rediscovered on all
# six republishes in one session before anyone traced it.
EXCLUDE = ['evals/prose-corpus.md', '.claude/rules/**/*.md']
# Instruction files: their bodies are executed, so a dead path there is a step
# that never runs.
INSTRUCTIONS = ['plugins/*/skills/*/SKILL.md', 'plugins/*/declarative/rules/*/*.md',
                'plugins/*/commands/*.md', '.claude/commands/*.md', '.claude/agents/*.md']


def expand(patterns, exclude=None):
    out = set()
    for pat in patterns:
        out.update(glob.glob(os.path.join(repo, pat), recursive=True))
    # normpath both sides before comparing. os.path.join(repo, 'evals/x.md')
    # keeps the forward slash the pattern was written with while glob returns
    # the platform separator, so on Windows the two spellings of the same file
    # never matched and EXCLUDE excluded nothing — 6 failures from the one file
    # this list exists to keep out.
    # EXCLUDE entries go through glob too, so a pattern works as well as a
    # literal path. Comparing them as literals only is how '.claude/rules/**'
    # was added and silently excluded nothing — the same shape as the Windows
    # bug the comment above describes, and found the same way: by the count
    # not moving.
    skip = set()
    for e in (EXCLUDE if exclude is None else exclude):
        skip.update(os.path.normpath(x) for x in glob.glob(os.path.join(repo, e), recursive=True))
    return sorted(p for p in out if os.path.isfile(p) and os.path.normpath(p) not in skip)


# ---- selftest ---------------------------------------------------------------
# Three kinds, as docs/agent-layer.md §4 requires: no-op (must stay quiet),
# block (must fire), boundary (resembles a failure and must stay quiet).
CASES = [
    # (label, kind, filename, content, expected problem count)
    ("resolving anchor is quiet", 'doc', 'a.md',
     "## Hello There\n[x](#hello-there)\n", 0),
    ("em-dash heading keeps both hyphens", 'doc', 'a.md',
     "## a — b\n[x](#a--b)\n", 0),
    ("the README bug: one hyphen too few", 'doc', 'a.md',
     "## a — b\n[x](#a-b)\n", 1),
    ("the README bug: hyphens too many", 'doc', 'a.md',
     "## a — b\n[x](#a----b)\n", 1),
    ("missing local file", 'doc', 'a.md',
     "[x](docs/nope.md)\n", 1),
    ("external link is not our problem", 'doc', 'a.md',
     "[x](https://example.com/nope)\n", 0),
    ("anchor inside a fenced block is not a heading", 'doc', 'a.md',
     "```\n## Fake\n```\n[x](#fake)\n", 1),
    ("a link inside a fenced block is not a link", 'doc', 'a.md',
     "```\n[x](#nowhere)\n```\n", 0),
    ("duplicate headings number from the second", 'doc', 'a.md',
     "## Dup\n## Dup\n[x](#dup)\n[y](#dup-1)\n", 0),
    ("a link quoted in inline code is not a link", 'doc', 'a.md',
     "I wrote `[x](#nowhere)` and it was wrong\n", 0),
    ("but a real link on the same line still counts", 'doc', 'a.md',
     "`[x](#nowhere)` and also [y](#nowhere)\n", 1),
    ("inline code in a heading stays in its slug", 'doc', 'a.md',
     "## 2. `make bench` — x\n[a](#2-make-bench--x)\n", 0),
    # Pinned limitation: install-relative links are not verified, so this stays
    # silent by design rather than by accident. If that ever gets built, this
    # case is the one that has to change.
    ("declarative payload: file existence is not checked", 'doc',
     'plugins/x/declarative/rules/dev/review.md', "[x](../workflow.md)\n", 0),
    ("declarative payload: its own anchors still are", 'doc',
     'plugins/x/declarative/rules/dev/review.md', "## A\n[x](#nope)\n", 1),
    ("the SKILL.md bug: .claece", 'paths', 'a.md',
     "run `.claece/harness-gaps.md` now\n", 1),
    ("post-install path is not a typo", 'paths', 'a.md',
     "run `.claude/rules/harness/workflow.md` now\n", 0),
    ("placeholder is not a path", 'paths', 'a.md',
     "see `evals/trigger/<name>.json` and `origin/<default>..HEAD`\n", 0),
    ("home-relative path is not ours to check", 'paths', 'a.md',
     "see `~/.local/bin/harnessctl`\n", 0),
    ("real repo path is quiet", 'paths', 'a.md',
     "see `plugins/harness-core/bin/harnessctl`\n", 0),
]

if mode == '--selftest':
    passed = failed = 0
    print("=== doc-refs selftest ===")
    for label, kind, name, content, expected in CASES:
        files = {os.path.join(repo, name): content}
        read = lambda p, _f=files: _f[p] if p in _f else open(p, encoding='utf-8').read()
        fn = check_doc if kind == 'doc' else check_paths
        got = fn(os.path.join(repo, name), read)
        if len(got) == expected:
            passed += 1
        else:
            failed += 1
            print("  FAIL  %s — expected %d, got %d %s"
                  % (label, expected, len(got), [g[2] for g in got]))
    # expand()'s exclusion is not reachable through CASES, and it failed
    # silently once: EXCLUDE entries were compared as literal paths, so a
    # pattern added to keep install output out of the scan matched nothing and
    # the count did not move. These run against files that exist in every
    # environment, so neither can pass by having nothing to find.
    probe = expand(['docs/adr/*.md'], exclude=[])
    if not probe:
        failed += 1; print("  FAIL  expand() found no docs/adr/*.md to test with")
    else:
        for label, exclude in (("a literal path", [os.path.relpath(probe[0], repo)]),
                               ("a glob pattern", ['docs/adr/*.md'])):
            left = expand(['docs/adr/*.md'], exclude=exclude)
            want = len(probe) - 1 if 'literal' in label else 0
            if len(left) == want:
                passed += 1
            else:
                failed += 1
                print("  FAIL  EXCLUDE accepts %s — expected %d left, got %d"
                      % (label, want, len(left)))

    print("  %d / %d passed" % (passed, passed + failed))
    sys.exit(1 if failed else 0)

cache = {}


def read(path):
    if path not in cache:
        cache[path] = open(path, encoding='utf-8').read()
    return cache[path]


passed = failed = 0
problems = []
for path in expand(DOCS):
    found = check_doc(path, read)
    if found:
        failed += 1
        problems += [(os.path.relpath(path, repo), i, t, w) for i, t, w in found]
    else:
        passed += 1
for path in expand(INSTRUCTIONS):
    found = check_paths(path, read)
    if found:
        failed += 1
        problems += [(os.path.relpath(path, repo), i, t, w) for i, t, w in found]
    else:
        passed += 1

print("=== doc-refs verification ===")
print("  %d / %d files clean" % (passed, passed + failed))
for rel, line, target, why in problems:
    print("  FAIL  %s:%d — %s: %s" % (rel, line, target, why))
sys.exit(1 if failed else 0)
PY
