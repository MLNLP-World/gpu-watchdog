#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

MYGPU="${MYGPU:-${SCRIPT_DIR}/mygpu.sh}"

CONFIG_DEFAULT="${ROOT_DIR}/config/gpu-watch.env"
CONFIG="${GPUWATCH_CONFIG:-$CONFIG_DEFAULT}"

CACHE_DEFAULT="${ROOT_DIR}/cache"
CACHE_DIR="${GPUWATCH_CACHE:-$CACHE_DEFAULT}"

FORCE_SEND=0
DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --test-mail) FORCE_SEND=1 ;;
  "" ) ;;
  * ) echo "Usage: $(basename "$0") [--dry-run|--test-mail]" >&2; exit 2 ;;
esac

if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG"

# Optional notification config
NOTIFY_CFG_DEFAULT="${ROOT_DIR}/config/notify.env"
NOTIFY_CFG="${GPUWATCH_NOTIFY_CONFIG:-$NOTIFY_CFG_DEFAULT}"
if [[ -f "$NOTIFY_CFG" ]]; then
  # shellcheck disable=SC1090
  source "$NOTIFY_CFG"
fi

else
  echo "ERROR: config not found: $CONFIG" >&2
  echo "Tip: set GPUWATCH_CONFIG=/path/to/gpu-watch.env" >&2
  exit 2
fi

TO_EMAIL="${TO_EMAIL:-}"
GPU_LIMIT="${GPU_LIMIT:-2}"
MAX_ETIME_MIN="${MAX_ETIME_MIN:-360}"
COOLDOWN_MIN="${COOLDOWN_MIN:-60}"

if [[ -z "$TO_EMAIL" ]]; then
  echo "ERROR: TO_EMAIL empty in config: $CONFIG" >&2
  exit 2
fi

HOST="$(hostname -s 2>/dev/null || hostname)"
NOW="$(date '+%F %T')"

mkdir -p "$CACHE_DIR"
LAST_FILE="$CACHE_DIR/last_sent.txt"
LAST_SIG_FILE="$CACHE_DIR/last_sig.txt"

etime_to_sec() {
  local s="${1:-}"
  s="${s// /}"
  [[ -z "$s" || "$s" == "NA" ]] && { echo 0; return; }

  local days=0 hh=0 mm=0 ss=0
  if [[ "$s" =~ ^([0-9]+)-([0-9]+):([0-9]{2}):([0-9]{2})$ ]]; then
    days="${BASH_REMATCH[1]}"; hh="${BASH_REMATCH[2]}"; mm="${BASH_REMATCH[3]}"; ss="${BASH_REMATCH[4]}"
  elif [[ "$s" =~ ^([0-9]+):([0-9]{2}):([0-9]{2})$ ]]; then
    hh="${BASH_REMATCH[1]}"; mm="${BASH_REMATCH[2]}"; ss="${BASH_REMATCH[3]}"
  elif [[ "$s" =~ ^([0-9]+):([0-9]{2})$ ]]; then
    mm="${BASH_REMATCH[1]}"; ss="${BASH_REMATCH[2]}"
  else
    echo 0; return
  fi
  echo $(( 10#${days:-0}*86400 + 10#${hh:-0}*3600 + 10#${mm:-0}*60 + 10#${ss:-0} ))
}

OUT="$("$MYGPU" 2>/dev/null || true)"

GPU_COUNT=0
MAX_SEC=0
MAX_LINE=""

if [[ -n "${OUT//[[:space:]]/}" ]]; then
  GPU_COUNT="$(grep -oE 'GPU=[0-9]+' <<<"$OUT" | cut -d= -f2 | sort -u | wc -l | xargs)"

  while IFS= read -r line; do
    [[ "$line" =~ ^GPU= ]] || continue
    etime="$(sed -n 's/.*ETIME=\([^ ]*\).*/\1/p' <<<"$line")"
    sec="$(etime_to_sec "$etime")"
    if (( sec > MAX_SEC )); then
      MAX_SEC="$sec"
      MAX_LINE="$line"
    fi
  done <<<"$OUT"
fi

MAX_LIMIT_SEC=$(( MAX_ETIME_MIN * 60 ))
REASONS=()
(( GPU_COUNT > GPU_LIMIT )) && REASONS+=("GPU_COUNT(${GPU_COUNT}) > GPU_LIMIT(${GPU_LIMIT})")
(( MAX_SEC > MAX_LIMIT_SEC )) && REASONS+=("MAX_ETIME(${MAX_SEC}s) > LIMIT(${MAX_LIMIT_SEC}s) :: ${MAX_LINE}")

if (( FORCE_SEND == 1 )) && (( ${#REASONS[@]} == 0 )); then
  REASONS=("TEST_MAIL: force send (no threshold triggered)")
fi

if (( ${#REASONS[@]} == 0 )); then
  exit 0
fi

now_epoch="$(date +%s)"
last_epoch=0
[[ -f "$LAST_FILE" ]] && last_epoch="$(cat "$LAST_FILE" 2>/dev/null || echo 0)"
cooldown_sec=$(( COOLDOWN_MIN * 60 ))

sig="$(printf "%s\n---\n%s\n" "${REASONS[*]}" "$OUT" | sha256sum | awk '{print $1}')"
last_sig=""
[[ -f "$LAST_SIG_FILE" ]] && last_sig="$(cat "$LAST_SIG_FILE" 2>/dev/null || true)"

# For --test-mail, skip de-dup/cooldown
if (( FORCE_SEND == 0 )); then
  if (( now_epoch - last_epoch < cooldown_sec )) && [[ "$sig" == "$last_sig" ]]; then
    exit 0
  fi
fi

SUBJECT="[GPU Watchdog] ${USER}@${HOST}  ${NOW}"
REASON_TEXT="$(printf "%s\n" "${REASONS[@]}" | sed 's/^/- /')"

BODY="$(cat <<EOT
Time: ${NOW}
Host: ${HOST}
User: ${USER}

Config: ${CONFIG}
Triggered:
${REASON_TEXT}

Raw output:
${OUT:-<no gpu processes detected>}
EOT
)"

export TO_EMAIL SUBJECT BODY

send_mail() {
  # Gmail API (HTTPS) first if NOTIFY_METHOD=gmail_api
  if [[ "${NOTIFY_METHOD:-}" == "gmail_api" ]]; then
    : "${GMAIL_API_CREDENTIALS:?missing GMAIL_API_CREDENTIALS}"
    : "${GMAIL_API_TOKEN:?missing GMAIL_API_TOKEN}"
    export GMAIL_API_CREDENTIALS GMAIL_API_TOKEN FROM_EMAIL
    if "${SCRIPT_DIR}/send_gmail_api.py"; then
      return 0
    else
      echo "ERROR: Gmail API send failed." >&2
      return 1
    fi
  fi

  # SMTP strict: if configured, MUST succeed; no fallback to local mail.
  SMTP_ENV_DEFAULT="${ROOT_DIR}/config/smtp.env"
  SMTP_ENV="${GPUWATCH_SMTP_CONFIG:-$SMTP_ENV_DEFAULT}"
  if [[ -f "$SMTP_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$SMTP_ENV"
    : "${SMTP_HOST:?missing SMTP_HOST}"
    : "${SMTP_USER:?missing SMTP_USER}"
    : "${SMTP_PASS:?missing SMTP_PASS}"
    SMTP_PORT="${SMTP_PORT:-587}"
    FROM_EMAIL="${FROM_EMAIL:-$SMTP_USER}"
    export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS FROM_EMAIL
    if "${SCRIPT_DIR}/send_smtp.py"; then
      return 0
    else
      echo "ERROR: SMTP configured but failed; not falling back to local mail." >&2
      return 1
    fi
  fi

  # No SMTP config: fallback local mail tools (may be unreliable for external delivery)
  if command -v mail >/dev/null 2>&1; then
    printf "%s\n" "$BODY" | mail -s "$SUBJECT" "$TO_EMAIL" && return 0
  elif command -v mailx >/dev/null 2>&1; then
    printf "%s\n" "$BODY" | mailx -s "$SUBJECT" "$TO_EMAIL" && return 0
  elif command -v sendmail >/dev/null 2>&1; then
    { echo "To: ${TO_EMAIL}"; echo "Subject: ${SUBJECT}"; echo; printf "%s\n" "$BODY"; } | sendmail -t && return 0
  fi
  return 1
}

if (( DRY_RUN == 1 )); then
  echo "=== DRY RUN (not sending) ==="
  echo "$SUBJECT"
  echo "-----------------------------"
  echo "$BODY"
  exit 0
fi

if send_mail; then
  if (( FORCE_SEND == 0 )); then
    echo "$now_epoch" > "$LAST_FILE"
    echo "$sig" > "$LAST_SIG_FILE"
  fi
  exit 0
else
  echo "ERROR: cannot send mail. No SMTP config and local mail tool failed/unreliable." >&2
  echo "  - SMTP: create ${ROOT_DIR}/config/smtp.env or set GPUWATCH_SMTP_CONFIG=/path/to/smtp.env" >&2
  exit 2
fi
