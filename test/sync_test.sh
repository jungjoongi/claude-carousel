#!/bin/bash
# Regression tests for shared-asset sync.
#
# Runs carousel against a throwaway $HOME, so nothing here touches the real
# ~/.claude. Every case below is one that used to lose an edit, or that broke
# while fixing the ones that did.
#
#   ./test/sync_test.sh

set -u

CAROUSEL="$(cd "$(dirname "$0")/.." && pwd)/bin/carousel"
T=$(mktemp -d "${TMPDIR:-/tmp}/carousel-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

export HOME="$T"
export CAROUSEL_NO_UPDATE=1
export CAROUSEL_CLAUDE_BIN=/usr/bin/true

M="$T/.claude"
P="$T/.claude-carousel/profiles"
pass=0
fail=0

ok()     { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad()    { printf '  \033[31mFAIL\033[0m %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail + 1)); }
check()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
islink() { [ -L "$1" ] && echo yes || echo no; }
isfile() { [ -f "$1" ] && [ ! -L "$1" ] && echo yes || echo no; }
exists() { [ -e "$1" ] && echo yes || echo no; }

mkdir -p "$M/plugins" "$M/skills" "$M/projects"
printf '{"enabledPlugins":{"superpowers":true,"github":true}}\n' > "$M/settings.json"
printf '{"enableAllProjectMcpServers":true}\n'                   > "$M/settings.local.json"
printf '{"a":1}\n'                                               > "$M/mcp.json"
printf '# master\n'                                              > "$M/CLAUDE.md"

echo "add: shared files are symlinked, per-profile files are real"
"$CAROUSEL" add tech >/dev/null 2>&1
for f in settings.json mcp.json CLAUDE.md; do
  check "$f is a symlink to the master" "$(readlink "$P/tech/$f")" "$M/$f"
done
check "plugins is still a symlink"              "$(islink "$P/tech/plugins")" "yes"
check "settings.local.json is seeded as a file" "$(isfile "$P/tech/settings.local.json")" "yes"

echo "edit through a profile reaches the master"
printf '{"enabledPlugins":{"github":true}}\n' > "$P/tech/settings.json"
check "master no longer lists superpowers" "$(grep -c superpowers "$M/settings.json")" "0"

echo "repeated sync does not resurrect a removed plugin"
for _ in 1 2 3; do "$CAROUSEL" sync tech >/dev/null 2>&1; done
check "still gone after 3 syncs" "$(grep -c superpowers "$P/tech/settings.json")" "0"
check "still a symlink"          "$(islink "$P/tech/settings.json")" "yes"

echo "a rename that breaks the link gets promoted, not discarded"
printf '{"enabledPlugins":{"github":true,"sentry":true}}\n' > "$T/tmpwrite"
mv "$T/tmpwrite" "$P/tech/settings.json"
check "link is broken to begin with" "$(islink "$P/tech/settings.json")" "no"
out=$("$CAROUSEL" sync tech 2>&1)
check "edit reached the master"  "$(grep -c sentry "$M/settings.json")" "1"
check "link was restored"        "$(islink "$P/tech/settings.json")" "yes"
check "promotion was announced"  "$(printf '%s' "$out" | grep -c promoted)" "1"

echo "a copy older than the master loses to it"
"$CAROUSEL" add legacy >/dev/null 2>&1
rm -f "$P/legacy/settings.json"
printf '{"enabledPlugins":{"STALE":true}}\n' > "$P/legacy/settings.json"
touch -t 200001010000 "$P/legacy/settings.json"
"$CAROUSEL" sync legacy >/dev/null 2>&1
check "master is untouched"      "$(grep -c STALE "$M/settings.json")" "0"
check "profile relinked"         "$(islink "$P/legacy/settings.json")" "yes"
check "discarded copy is backed up" \
  "$(ls "$T/.claude-carousel/backups/legacy/" 2>/dev/null | grep -c settings.json)" "1"

echo "a shared file the master lacks is promoted from the profile"
rm -f "$M/mcp.json" "$P/tech/mcp.json" "$P/legacy/mcp.json"
printf '{"servers":{"x":1}}\n' > "$P/tech/mcp.json"
"$CAROUSEL" sync tech >/dev/null 2>&1
check "master now has it"   "$(exists "$M/mcp.json")" "yes"
check "profile links to it" "$(islink "$P/tech/mcp.json")" "yes"

echo "profiles see each other's shared edits immediately"
printf '{"enabledPlugins":{"shared-edit":true}}\n' > "$P/legacy/settings.json"
check "visible from the other profile" "$(grep -c shared-edit "$P/tech/settings.json")" "1"

echo "settings.local.json stays per-profile"
printf '{"model":"fable"}\n' > "$P/legacy/settings.local.json"
"$CAROUSEL" sync legacy >/dev/null 2>&1
"$CAROUSEL" sync tech   >/dev/null 2>&1
check "the profile keeps its override" "$(grep -c fable "$P/legacy/settings.local.json")" "1"
check "it does not reach the sibling"  "$(grep -c fable "$P/tech/settings.local.json")" "0"
check "it does not reach the master"   "$(grep -c fable "$M/settings.local.json")" "0"
check "it is a real file"              "$(isfile "$P/legacy/settings.local.json")" "yes"

echo "a link left by an older carousel is turned back into a file"
rm -f "$P/tech/settings.local.json"
ln -s "$M/settings.local.json" "$P/tech/settings.local.json"
"$CAROUSEL" sync tech >/dev/null 2>&1
check "it is a real file again" "$(isfile "$P/tech/settings.local.json")" "yes"
check "seeded from the master"  "$(grep -c enableAllProjectMcpServers "$P/tech/settings.local.json")" "1"

echo "rm unlinks without following the links"
echo y | "$CAROUSEL" rm legacy >/dev/null 2>&1
check "profile is gone"          "$(exists "$P/legacy")" "no"
check "master settings survive"  "$(exists "$M/settings.json")" "yes"
check "master plugins survive"   "$(exists "$M/plugins")" "yes"
check "master content survives"  "$(grep -c shared-edit "$M/settings.json")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
