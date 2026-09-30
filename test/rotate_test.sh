#!/bin/bash
# Tests for rotating to the next profile on a usage limit, and for switching
# profile from inside a session with /carousel:switch.
#
# Runs carousel against a throwaway $HOME with a stand-in for claude that plays
# out a usage limit the way Claude Code does: it runs the StopFailure hook it
# was handed through --settings, and waits for that hook to stop it.
#
#   ./test/rotate_test.sh

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
profiles() { cut -d'|' -f1 "$T/launches" | tr '\n' ' '; }
count()  { wc -l < "$T/launches" | tr -d ' '; }

# Logs "<profile>|<args>" for every launch. A "<profile>|<prompt>" line in
# $T/typed is typed into that profile's first launch: it goes through the
# UserPromptSubmit hook, whose output lands in $T/hookout. A profile listed in
# $T/limited then hits a limit; anything else exits with $FAKE_EXIT.
cat > "$T/claude" <<EOF
#!/bin/bash
prof=default
[ -n "\${CLAUDE_CONFIG_DIR:-}" ] && prof=\$(basename "\$CLAUDE_CONFIG_DIR")
printf '%s|%s\n' "\$prof" "\$*" >> "$T/launches"
settings="" plugin="" prev=""
for a in "\$@"; do
  [ "\$prev" = "--settings" ] && settings="\$a"
  [ "\$prev" = "--plugin-dir" ] && plugin="\$a"
  prev="\$a"
done
if line=\$(grep -m1 "^\$prof|" "$T/typed" 2>/dev/null); then
  grep -vxF "\$line" "$T/typed" > "$T/typed.new"; mv "$T/typed.new" "$T/typed"
  [ -f "\$plugin/commands/switch.md" ] || exit 98
  cmd=\$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])
' "\$settings") || exit 99
  # The hook stops this process when it switches, as it stops claude.
  printf '{"session_id":"$SID","transcript_path":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' \
    "\${FAKE_TRANSCRIPT:-$T/transcript.jsonl}" "\${line#*|}" | sh -c "\$cmd" >> "$T/hookout"
fi
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

reset() { : > "$T/launches"; : > "$T/typed"; : > "$T/hookout"; printf '%s\n' "$@" > "$T/limited"; }
type_in() { printf '%s\n' "$@" > "$T/typed"; }
echo '{}' > "$T/transcript.jsonl"

echo "a limit resumes the same conversation on the next profile"
"$CAROUSEL" order default a b >/dev/null
reset default a
out=$("$CAROUSEL" --model opus "fix the bug" 2>&1); code=$?
check "exits with the last profile's code"   "$code" "0"
check "ran default, then a, then b"          "$(profiles)" "default a b "
check "first launch gets the original args"  "$(has "$(launch 1)" "--model opus fix the bug")" "yes"
check "first launch registers the hook"      "$(has "$(launch 1)" "--settings")" "yes"
check "bypass is still on by default"        "$(has "$(launch 1)" "--dangerously-skip-permissions")" "yes"
check "next launch resumes the session"      "$(has "$(launch 2)" "--resume $SID $PROMPT_DEFAULT")" "yes"
check "...without repeating the first prompt" "$(has "$(launch 2)" "fix the bug")" "no"
check "the one after that resumes it too"    "$(has "$(launch 3)" "--resume $SID")" "yes"
check "says why it switched"                 "$(has "$out" "$LIMIT_MSG")" "yes"
check "says where it switched to"            "$(has "$out" "switching to a")" "yes"

echo "a named profile rotates from itself and wraps around"
reset a b
out=$("$CAROUSEL" a 2>&1); code=$?
check "exits cleanly"           "$code" "0"
check "ran a, then b, then default" "$(profiles)" "a b default "

echo "a profile left out of the order still runs first"
"$CAROUSEL" order default a >/dev/null
reset b
out=$("$CAROUSEL" b 2>&1); code=$?
check "ran b, then the order"   "$(profiles)" "b default "

echo "go still works, from the default profile"
"$CAROUSEL" order default a b >/dev/null
reset default
out=$("$CAROUSEL" go 2>&1); code=$?
check "ran default, then a"     "$(profiles)" "default a "

echo "a normal exit is passed through and does not rotate"
reset
out=$(FAKE_EXIT=7 "$CAROUSEL" 2>&1); code=$?
check "exit code passed through" "$code" "7"
check "launched once"            "$(count)" "1"

echo "every profile limited ends the run"
"$CAROUSEL" order default a >/dev/null
reset default a
out=$("$CAROUSEL" 2>&1); code=$?
check "exits non-zero"             "$code" "1"
check "tried each profile once"    "$(count)" "2"
check "says so"                    "$(has "$out" "every profile in rotation has hit a limit")" "yes"
check "says how to pick it up"     "$(has "$out" "carousel --resume $SID")" "yes"

echo "an empty CAROUSEL_RESUME_PROMPT resumes without sending anything"
reset default
out=$(CAROUSEL_RESUME_PROMPT= "$CAROUSEL" 2>&1); code=$?
check "exits cleanly"           "$code" "0"
check "resume is the last word" "$(launch 2 | sed 's/.*--resume //')" "$SID"

echo "-p runs go straight to claude"
reset
out=$(FAKE_EXIT=3 "$CAROUSEL" a -p "summarise" 2>&1); code=$?
check "exit code passed through" "$code" "3"
check "no hook registered"       "$(has "$(launch 1)" "--settings")" "no"

echo "CAROUSEL_ROTATE=0 pins the run, but go still rotates"
reset
out=$(CAROUSEL_ROTATE=0 "$CAROUSEL" a 2>&1); code=$?
check "no hook registered"       "$(has "$(launch 1)" "--settings")" "no"
check "ran as a"                 "$(profiles)" "a "
reset default
out=$(CAROUSEL_ROTATE=0 "$CAROUSEL" go 2>&1); code=$?
check "go rotated anyway"        "$(profiles)" "default a "

echo "/carousel:switch <name> resumes the conversation as that profile"
"$CAROUSEL" order default a b >/dev/null
reset
type_in "default|/carousel:switch b"
out=$("$CAROUSEL" --model opus "fix the bug" 2>&1); code=$?
check "exits cleanly"                        "$code" "0"
check "ran default, then b"                  "$(profiles)" "default b "
check "first launch loads the command"       "$(has "$(launch 1)" "--plugin-dir")" "yes"
check "b resumes the session"                "$(has "$(launch 2)" "--resume $SID")" "yes"
check "...and waits at the prompt"           "$(has "$(launch 2)" "$PROMPT_DEFAULT")" "no"
check "...without the first launch's args"   "$(has "$(launch 2)" "fix the bug")" "no"
check "says where it switched to"            "$(has "$out" "switching to b")" "yes"

echo "/carousel:switch alone moves to the next profile in order"
reset
type_in "a|/carousel:switch"
out=$("$CAROUSEL" a 2>&1); code=$?
check "ran a, then b"                        "$(profiles)" "a b "

echo "a limit after a switch rotates on from the new profile"
reset b
type_in "default|/carousel:switch b"
out=$("$CAROUSEL" 2>&1); code=$?
check "ran default, b, then default again"   "$(profiles)" "default b default "
check "the limit resume sends the prompt"    "$(has "$(launch 3)" "--resume $SID $PROMPT_DEFAULT")" "yes"

echo "a switch before the first message starts the new profile fresh"
reset
type_in "default|/carousel:switch a"
out=$(FAKE_TRANSCRIPT="$T/none.jsonl" "$CAROUSEL" 2>&1); code=$?
check "ran default, then a"                  "$(profiles)" "default a "
check "nothing to resume"                    "$(has "$(launch 2)" "--resume")" "no"

echo "a switch that can't happen is refused in the session"
reset
type_in "default|/carousel:switch nope"
out=$("$CAROUSEL" 2>&1); code=$?
check "unknown profile: stays put"           "$(profiles)" "default "
check "...and says which profiles exist"     "$(has "$(cat "$T/hookout")" "no profile named 'nope'. Profiles: default, a, b")" "yes"
reset
type_in "a|/carousel:switch a"
out=$("$CAROUSEL" a 2>&1); code=$?
check "same profile: stays put"              "$(profiles)" "a "
check "...and says so"                       "$(has "$(cat "$T/hookout")" "already running as a")" "yes"

echo "other prompts pass the hook untouched"
reset
type_in "default|/carousel:switchy b"
out=$("$CAROUSEL" 2>&1); code=$?
check "launched once"                        "$(count)" "1"
check "hook said nothing"                    "$(wc -c < "$T/hookout" | tr -d ' ')" "0"

echo "a folder trusted in one profile is trusted in the one launched"
mkdir -p "$T/work/sub"
W=$(cd "$T/work/sub" && pwd -P)
trust() { python3 -c '
import json, sys
path, d = sys.argv[1], sys.argv[2]
print(bool(((json.load(open(path)).get("projects") or {}).get(d) or {}).get("hasTrustDialogAccepted")))
' "$1" "$W"; }
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$(dirname "$W")" > "$T/.claude.json"
printf '{"oauthAccount":{"emailAddress":"a@example.com"}}' > "$T/.claude-carousel/profiles/a/.claude.json"
reset
( cd "$W" && CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1 )
check "trusted via the default's parent folder" "$(trust "$T/.claude-carousel/profiles/a/.claude.json")" "True"
check "the rest of the file is kept"  "$(has "$(cat "$T/.claude-carousel/profiles/a/.claude.json")" "a@example.com")" "yes"
printf '{}' > "$T/.claude-carousel/profiles/b/.claude.json"
reset
type_in "a|/carousel:switch b"
( cd "$W" && "$CAROUSEL" a >/dev/null 2>&1 )
check "a switch carries it to the next profile" "$(trust "$T/.claude-carousel/profiles/b/.claude.json")" "True"
printf '{}' > "$T/.claude.json"
printf '{}' > "$T/.claude-carousel/profiles/a/.claude.json"
printf '{}' > "$T/.claude-carousel/profiles/b/.claude.json"
reset
( cd "$W" && CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1 )
check "a folder nobody trusts is left to ask" "$(cat "$T/.claude-carousel/profiles/a/.claude.json")" "{}"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$(dirname "$W")" > "$T/.claude.json"
rm -f "$T/.claude-carousel/profiles/a/.claude.json"
reset
( cd "$W" && CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1 )
check "a profile that never ran gets a config holding it" "$(trust "$T/.claude-carousel/profiles/a/.claude.json")" "True"
check "...readable only by you" "$(stat -f %Lp "$T/.claude-carousel/profiles/a/.claude.json" 2>/dev/null || stat -c %a "$T/.claude-carousel/profiles/a/.claude.json")" "600"
rm -f "$T/.claude-carousel/profiles/a/.claude.json"
reset
( cd "$W" && "$CAROUSEL" login a >/dev/null 2>&1 )
check "login carries it too" "$(trust "$T/.claude-carousel/profiles/a/.claude.json")" "True"
check "login runs in bypass mode" "$(launch 1)" "a|--dangerously-skip-permissions"
reset
( cd "$W" && CAROUSEL_BYPASS=0 "$CAROUSEL" login a >/dev/null 2>&1 )
check "login leaves bypass off when told to" "$(launch 1)" "a|"
mkdir -p "$W/.git"
printf '{}' > "$T/.claude-carousel/profiles/a/.claude.json"
reset
( cd "$W" && CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1 )
check "a trusted parent doesn't reach into a git repo" "$(cat "$T/.claude-carousel/profiles/a/.claude.json")" "{}"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$(dirname "$W")" > "$T/.claude-carousel/profiles/a/.claude.json"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}' "$W" > "$T/.claude.json"
reset
( cd "$W" && CAROUSEL_ROTATE=0 "$CAROUSEL" a >/dev/null 2>&1 )
check "...nor stops a trusted repo reaching a profile that trusts only its parent" "$(trust "$T/.claude-carousel/profiles/a/.claude.json")" "True"
rm -rf "$W/.git"

echo "temp state is cleaned up"
check "nothing left in TMPDIR" "$(ls -A "$TMPDIR" | wc -l | tr -d ' ')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
