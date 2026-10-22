#!/usr/bin/env bash
#
# Install codex-move-session into ~/.local/bin by default.
#
set -euo pipefail

REPO="doggy8088/codex-move-session"
BRANCH="main"
SCRIPT_NAME="codex-move-session"
DEFAULT_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
TMP_FILE=""

usage() {
  cat <<'EOF'
Usage:
  install.sh [options]

Options:
  --prefix DIR, --dir DIR  Install into DIR (default: ~/.local/bin)
  -h, --help               Show this help

Environment:
  INSTALL_DIR              Default install directory; --prefix overrides it

Examples:
  ./install.sh
  ./install.sh --prefix "$HOME/bin"
  curl -fsSL https://raw.githubusercontent.com/doggy8088/codex-move-session/main/install.sh | bash
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

expand_home() {
  local path=$1

  if [ "$path" = "~" ]; then
    printf '%s' "$HOME"
    return 0
  fi

  if [ "${path:0:1}" = "~" ] && [ "${path:1:1}" = "/" ]; then
    printf '%s' "$HOME/${path:2}"
    return 0
  fi

  printf '%s' "$path"
}

cleanup() {
  if [ -n "$TMP_FILE" ]; then
    rm -f -- "$TMP_FILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --prefix | --dir)
      [ $# -ge 2 ] || die "$1 requires a directory"
      [ -n "$2" ] || die "$1 requires a non-empty directory"
      INSTALL_DIR=$2
      shift 2
      ;;
    --prefix=* | --dir=*)
      INSTALL_DIR=${1#*=}
      [ -n "$INSTALL_DIR" ] || die "$1 requires a non-empty directory"
      shift
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

INSTALL_DIR=$(expand_home "$INSTALL_DIR")
[ -n "$INSTALL_DIR" ] || die "install directory is empty"

SOURCE_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

LOCAL_SOURCE=""
if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/$SCRIPT_NAME" ]; then
  LOCAL_SOURCE="$SOURCE_DIR/$SCRIPT_NAME"
fi

if [ -n "$LOCAL_SOURCE" ]; then
  SRC=$LOCAL_SOURCE
  printf 'Installing from local checkout: %s\n' "$SRC"
else
  command -v curl >/dev/null 2>&1 ||
    die "curl is required when installing outside a local checkout"
  SRC=$(mktemp "${TMPDIR:-/tmp}/codex-move-session.XXXXXX") ||
    die "cannot create a temporary file"
  TMP_FILE=$SRC
  URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${SCRIPT_NAME}"
  printf 'Downloading %s\n' "$URL"
  curl -fsSL "$URL" -o "$SRC" || die "download failed: $URL"
fi

bash -n "$SRC" || die "downloaded script failed the syntax check"
mkdir -p -- "$INSTALL_DIR" || die "cannot create install directory: $INSTALL_DIR"
[ -w "$INSTALL_DIR" ] || die "install directory is not writable: $INSTALL_DIR"

install -m 0755 -- "$SRC" "$INSTALL_DIR/$SCRIPT_NAME" ||
  die "failed to install $SCRIPT_NAME into $INSTALL_DIR"

if ! command -v jq >/dev/null 2>&1; then
  warn "jq is required at runtime; install it with: brew install jq"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    warn "$INSTALL_DIR is not in PATH"
    # shellcheck disable=SC2016 # $PATH is intentionally printed literally
    printf 'Add it with:\n  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
    ;;
esac

INSTALLED_VERSION=$("$INSTALL_DIR/$SCRIPT_NAME" --version)
printf 'Installed %s to %s\n' "$INSTALLED_VERSION" "$INSTALL_DIR/$SCRIPT_NAME"
printf 'Run "%s --help" for usage.\n' "$(basename "$SCRIPT_NAME")"
