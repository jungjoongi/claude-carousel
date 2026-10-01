#!/bin/bash
# Tests for "carousel artifacts <profile>": the hook it registers, and the proxy
# that replays artifact calls as the owning profile.
#
# Runs carousel against a throwaway $HOME. The stand-in for claude has two jobs:
# launched by carousel it records the hook it was handed, and launched by the
# proxy (with -p) it plays the owner's replay and prints a tool result.
#
#   ./test/artifacts_test.sh

set -u

CAROUSEL="$(cd "$(dirname "$0")/.." && pwd)/bin/carousel"
T=$(mktemp -d "${TMPDIR:-/tmp}/carousel-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

export HOME="$T"
export TMPDIR="$T/tmp"
export CAROUSEL_NO_UPDATE=1
export CAROUSEL_CLAUDE_BIN="$T/claude"
mkdir -p "$TMPDIR"

SID="0a9c9877-4507-44c8-b064-ec25285de521"
PROXY="$T/.claude-carousel/artifacts/proxy.py"

pass=0
fail=0

ok()    { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no; }

# Launched by carousel: save the PreToolUse hook it was given as
# "<matcher><tab><command>" (or "none"). Launched with -p: log who it ran as and what it was asked, then
# print $FAKE_RESULT and exit with $FAKE_EXIT. One line per replay, so the
# prompt's newlines become spaces.
cat > "$T/claude" <<EOF
#!/bin/bash
if [ "\${1:-}" = "-p" ]; then
  all="\$*"
  printf '%s|%s|%s\n' "\${CLAUDE_CONFIG_DIR:-unset}" "\${CLAUDE_CODE_ARTIFACT:-}" "\${all//\$'\n'/ }" >> "$T/replays"
  printf '%s\n' "\${FAKE_RESULT-Published x.html at https://claude.ai/artifact/AAA111 (Version 1)}"
  exit "\${FAKE_EXIT:-0}"
fi
settings="" prev=""
for a in "\$@"; do [ "\$prev" = "--settings" ] && settings="\$a"; prev="\$a"; done
python3 -c '
import json, sys
try:
    h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]
    print(h["matcher"] + "\\t" + h["hooks"][0]["command"])
except Exception:
    print("none")
' "\$settings" > "$T/hook"
EOF
chmod +x "$T/claude"

"$CAROUSEL" add a >/dev/null 2>&1

# Feeds one tool call to the proxy as Claude Code would, running as profile $1.
call() {
  local prof="$1" tool="$2" input="$3" sid="${4:-$SID}" cmd
  cmd=$(cut -f2- "$T/hook")
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' \
    "$sid" "$T" "$tool" "$input" > "$T/input"
  if [ "$prof" = "default" ]; then
    env -u CLAUDE_CONFIG_DIR sh -c "$cmd" < "$T/input"
  else
    CLAUDE_CONFIG_DIR="$T/.claude-carousel/profiles/$prof" sh -c "$cmd" < "$T/input"
  fi
}
reason() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"])' 2>/dev/null; }
replays() { if [ -f "$T/replays" ]; then wc -l < "$T/replays" | tr -d ' '; else echo 0; fi; }

echo "off until a profile is chosen"
out=$("$CAROUSEL" artifacts 2>&1)
check "says it's off"                 "$(has "$out" "(off)")" "yes"
"$CAROUSEL" a >/dev/null 2>&1
check "no hook registered"            "$(cat "$T/hook")" "none"

echo "choosing an owner"
out=$("$CAROUSEL" artifacts nope 2>&1); code=$?
check "an unknown profile is refused" "$code" "1"
out=$("$CAROUSEL" artifacts default 2>&1)
check "says who owns them now"        "$(has "$out" "published as default")" "yes"
check "status shows it"               "$(has "$("$CAROUSEL" artifacts 2>&1)" "published as: default")" "yes"
check "doctor shows it"               "$(has "$("$CAROUSEL" doctor 2>&1)" "published as default")" "yes"

echo "every kind of launch carries the hook"
"$CAROUSEL" a >/dev/null 2>&1
check "a rotating run registers it"   "$(cut -f1 "$T/hook")" "Artifact|ArtifactComments|ArtifactData"
check "...next to the rotation hooks" "$(has "$(cat "$T/hook")" "proxy.py")" "yes"
CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1
check "a run that doesn't rotate too" "$(cut -f1 "$T/hook")" "Artifact|ArtifactComments|ArtifactData"
check "the proxy is written out"      "$([ -f "$PROXY" ] && echo yes)" "yes"

echo "a call made as the owner goes through untouched"
: > "$T/replays"
out=$(call default Artifact '{"file_path":"x.html"}')
check "no answer from the hook"       "$out" ""
check "nothing replayed"              "$(replays)" "0"

echo "a publish made as another profile is replayed as the owner"
out=$(call a Artifact '{"file_path":"x.html","icon":"test"}' | reason)
check "the call is answered"          "$(has "$out" "ran as the 'default' profile")" "yes"
check "...with the replay's result"   "$(has "$out" "https://claude.ai/artifact/AAA111")" "yes"
check "replayed once"                 "$(replays)" "1"
line=$(sed -n 1p "$T/replays")
check "...as the default account"     "$(printf '%s' "$line" | cut -d'|' -f1)" "unset"
check "...with the Artifact tool on"  "$(printf '%s' "$line" | cut -d'|' -f2)" "1"
check "...passing the arguments"      "$(has "$line" '"icon": "test"')" "yes"
check "...without leaving a session"  "$(has "$line" "--no-session-persistence")" "yes"

echo "publishing the same file again updates that artifact"
: > "$T/replays"
call a Artifact '{"file_path":"x.html"}' >/dev/null
check "the url is carried over"       "$(has "$(cat "$T/replays")" '"url": "https://claude.ai/artifact/AAA111"')" "yes"
: > "$T/replays"
call a Artifact '{"file_path":"x.html"}' "11111111-2222-3333-4444-555555555555" >/dev/null
check "...but not into another conversation" "$(has "$(cat "$T/replays")" '"url"')" "no"

echo "comments and data are replayed too, but a watch stays put"
: > "$T/replays"
call a ArtifactComments '{"action":"read","url":"https://claude.ai/artifact/AAA111"}' >/dev/null
check "comments are replayed"         "$(has "$(cat "$T/replays")" "ArtifactComments tool")" "yes"
: > "$T/replays"
out=$(call a ArtifactComments '{"action":"watch","url":"https://claude.ai/artifact/AAA111"}')
check "a watch isn't answered"        "$out" ""
check "...or replayed"                "$(replays)" "0"

echo "a delete is answered with how to do it as the owner"
out=$(call a Artifact '{"action":"delete","url":"https://claude.ai/artifact/AAA111"}' | reason)
check "nothing is replayed"           "$(replays)" "0"
check "says nothing was deleted"      "$(has "$out" "nothing was deleted")" "yes"
check "says how to delete it"         "$(has "$out" "carousel default")" "yes"

echo "a replay that fails lets the call run where it was made"
out=$(FAKE_EXIT=1 call a Artifact '{"file_path":"y.html"}')
check "a failed replay isn't answered" "$out" ""
out=$(FAKE_RESULT= call a Artifact '{"file_path":"y.html"}')
check "...nor an empty one"           "$out" ""

echo "another profile can own them"
"$CAROUSEL" artifacts a >/dev/null
"$CAROUSEL" >/dev/null 2>&1
: > "$T/replays"
call default Artifact '{"file_path":"z.html"}' >/dev/null
check "replayed as a"                 "$(cut -d'|' -f1 "$T/replays")" "$T/.claude-carousel/profiles/a"
out=$(call a Artifact '{"file_path":"z.html"}')
check "a's own calls go through"      "$out" ""

echo "turning it off"
"$CAROUSEL" artifacts off >/dev/null
"$CAROUSEL" a >/dev/null 2>&1
check "no hook registered"            "$(cat "$T/hook")" "none"
check "nothing left in TMPDIR"        "$(ls -A "$TMPDIR" | wc -l | tr -d ' ')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
