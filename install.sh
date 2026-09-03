#!/usr/bin/env bash
# claude-carousel installer
#   curl -fsSL https://raw.githubusercontent.com/jungjoongi/claude-carousel/main/install.sh | bash
#
# Non-interactive / CI use:
#   CAROUSEL_ALIAS=cc CAROUSEL_NO_PROMPT=1 bash install.sh
set -eu

REPO_SLUG="jungjoongi/claude-carousel"
REPO_RAW="https://raw.githubusercontent.com/$REPO_SLUG/main"
BIN_DIR="${CAROUSEL_BIN_DIR:-$HOME/.local/bin}"
TARGET="$BIN_DIR/carousel"
NO_PROMPT="${CAROUSEL_NO_PROMPT:-0}"

# `curl … | bash` leaves stdin pointed at the pipe, so prompts have to come
# from the real terminal. If there isn't one, we skip every question.
have_tty() { { : < /dev/tty; } 2>/dev/null; }
ask() {
  local reply=""
  if have_tty; then read -r reply < /dev/tty || true; fi
  printf '%s\n' "$reply"
}

printf 'Installing claude-carousel to %s\n' "$TARGET"
mkdir -p "$BIN_DIR"

if [ -f "./bin/carousel" ]; then
  install -m 755 ./bin/carousel "$TARGET"          # running from a clone
else
  tmp="$(mktemp)"
  curl -fsSL "$REPO_RAW/bin/carousel" -o "$tmp"
  install -m 755 "$tmp" "$TARGET"
  rm -f "$tmp"
fi

printf '✓ installed\n\n'

# --- PATH ---------------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    printf '%s is not on your PATH yet. Add this to your shell rc:\n\n' "$BIN_DIR"
    printf '  export PATH="%s:$PATH"\n\n' "$BIN_DIR"
    ;;
esac

# --- optional short alias ------------------------------------------------------
alias_name="${CAROUSEL_ALIAS:-}"
DEFAULT_ALIAS="cc"

if [ -z "$alias_name" ] && [ "$NO_PROMPT" != "1" ] && have_tty; then
  printf 'Typing "carousel" gets old fast — register a short shell alias?\n'
  printf '  This only affects what you type interactively; scripts and Makefiles\n'
  printf '  are untouched, so shadowing a name like "cc" is safe.\n'
  printf '  alias name [%s], or "-" to skip: ' "$DEFAULT_ALIAS"
  alias_name="$(ask)"
  [ -z "$alias_name" ] && alias_name="$DEFAULT_ALIAS"
  [ "$alias_name" = "-" ] && alias_name=""
fi

if [ -n "$alias_name" ]; then
  # carousel handles name validation, conflicting alias lines, and shadowed
  # binaries; it prompts on conflicts unless we pass -y.
  "$TARGET" alias "$alias_name" || true
  printf '\n'
fi

# --- optional star (prompted, Enter accepts; never automatic) ------------------
if [ "$NO_PROMPT" != "1" ] && have_tty; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf 'Star %s on GitHub? It helps other people find it. [Y/n] ' "$REPO_SLUG"
    case "$(ask)" in
      ''|y|Y|yes|YES) "$TARGET" star || true ;;
      *) printf 'No problem — "carousel star" any time you change your mind.\n' ;;
    esac
    printf '\n'
  else
    printf 'If it turns out useful, a star helps: https://github.com/%s\n\n' "$REPO_SLUG"
  fi
fi

# --- next steps ----------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  printf 'Note: the "claude" CLI was not found on your PATH — install Claude Code first.\n'
fi

cmd_name="carousel"
[ -n "$alias_name" ] && cmd_name="$alias_name"

printf 'Next:  %s ls        # your current login is already the "default" profile\n' "$cmd_name"
printf '       %s add work  # then: %s login work\n' "$cmd_name" "$cmd_name"
