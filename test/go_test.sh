#!/bin/bash
# Tests for `carousel go` rotation.
#
# Runs carousel against a throwaway $HOME with a stand-in for claude that plays
# out a usage limit the way Claude Code does: it runs the StopFailure hook it
# was handed through --settings, and waits for that hook to stop it.
#
#   ./test/go_test.sh

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
LIMIT_MSG="You've hit your session limit · resets 3pm"
PROMPT_DEFAULT="You were cut off by a usage limit. Continue where you left off."

pass=0
fail=0

ok()    { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s (got %s, want %s)\n' "$1" "$2" "$3"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()   { printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no; }
launch() { sed -n "${1}p" "$T/launches"; }

# Logs "<profile>|<args>" for every launch. A profile listed in $T/limited hits
# a limit; anything else exits with $FAKE_EXIT.
cat > "$T/claude" <<EOF
#!/bin/bash
prof=default
[ -n "\${CLAUDE_CONFIG_DIR:-}" ] && prof=\$(basename "\$CLAUDE_CONFIG_DIR")
printf '%s|%s\n' "\$prof" "\$*" >> "$T/launches"
settings="" prev=""
for a in "\$@"; do [ "\$prev" = "--settings" ] && settings="\$a"; prev="\$a"; done
if grep -qx "\$prof" "$T/limited" 2>/dev/null; then
  cmd=\$(python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["StopFailure"][0]
assert h["matcher"] == "rate_limit"
print(h["hooks"][0]["command"])
' "\$settings") || exit 99
  printf '{"session_id":"$SID","hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"%s"}' \
    "$LIMIT_MSG" | sh -c "\$cmd" &
  exec sleep 10   # the hook is what ends this, as it ends claude
fi
exit "\${FAKE_EXIT:-0}"
EOF
chmod +x "$T/claude"

"$CAROUSEL" add a >/dev/null 2>&1
"$CAROUSEL" add b >/dev/null 2>&1

reset() { : > "$T/launches"; printf '%s\n' "$@" > "$T/limited"; }

echo "a limit resumes the same conversation on the next profile"
"$CAROUSEL" order default a b >/dev/null
reset default a
out=$("$CAROUSEL" go --model opus "fix the bug" 2>&1); code=$?
check "exits with the last profile's code"   "$code" "0"
check "ran default, then a, then b"          "$(cut -d'|' -f1 "$T/launches" | tr '\n' ' ')" "default a b "
check "first launch gets the original args"  "$(has "$(launch 1)" "--model opus fix the bug")" "yes"
check "first launch registers the hook"      "$(has "$(launch 1)" "--settings")" "yes"
check "bypass is still on by default"        "$(has "$(launch 1)" "--dangerously-skip-permissions")" "yes"
check "next launch resumes the session"      "$(has "$(launch 2)" "--resume $SID $PROMPT_DEFAULT")" "yes"
check "...without repeating the first prompt" "$(has "$(launch 2)" "fix the bug")" "no"
check "the one after that resumes it too"    "$(has "$(launch 3)" "--resume $SID")" "yes"
check "says why it switched"                 "$(has "$out" "$LIMIT_MSG")" "yes"
check "says where it switched to"            "$(has "$out" "switching to a")" "yes"

echo "a normal exit is passed through and does not rotate"
reset
out=$(FAKE_EXIT=7 "$CAROUSEL" go 2>&1); code=$?
check "exit code passed through" "$code" "7"
check "launched once"            "$(wc -l < "$T/launches" | tr -d ' ')" "1"

echo "every profile limited ends the run"
"$CAROUSEL" order default a >/dev/null
reset default a
out=$("$CAROUSEL" go 2>&1); code=$?
check "exits non-zero"             "$code" "1"
check "tried each profile once"    "$(wc -l < "$T/launches" | tr -d ' ')" "2"
check "says so"                    "$(has "$out" "every profile in rotation has hit a limit")" "yes"
check "says how to pick it up"     "$(has "$out" "carousel --resume $SID")" "yes"

echo "an empty CAROUSEL_RESUME_PROMPT resumes without sending anything"
reset default
out=$(CAROUSEL_RESUME_PROMPT= "$CAROUSEL" go 2>&1); code=$?
check "exits cleanly"           "$code" "0"
check "resume is the last word" "$(launch 2 | sed 's/.*--resume //')" "$SID"

echo "temp state is cleaned up"
check "nothing left in TMPDIR" "$(ls -A "$TMPDIR" | wc -l | tr -d ' ')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
