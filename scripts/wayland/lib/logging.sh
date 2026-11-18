# shellcheck shell=bash
C_B=$'\033[1m'; C_D=$'\033[2m'; C_R=$'\033[31m'; C_G=$'\033[32m'
C_Y=$'\033[33m'; C_C=$'\033[36m'; C_N=$'\033[0m'
CI_LOG_DIR=/tmp/ci-logs
CI_STEPS=/tmp/ci-steps.tsv
mkdir -p "$CI_LOG_DIR"

fmt_dur() {
  local s="$1"
  if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}
step() {
  STEP_ID="$1"; STEP_TITLE="$2"; STEP_T0=$(date +%s)
  printf '\n%s[%s]%s  %s%s%s\n' "$C_C" "$1" "$C_N" "$C_B" "$2" "$C_N"
  printf 'S\t%s\t%s\t%s\n' "$1" "$2" "$STEP_T0" >> "$CI_STEPS"
}
step_done() {
  local dt=$(( $(date +%s) - STEP_T0 ))
  printf 'D\t%s\t%s\n' "$STEP_ID" "$dt" >> "$CI_STEPS"
  printf '  %s· selesai dalam %s%s\n' "$C_D" "$(fmt_dur "$dt")" "$C_N"
}
info() { printf '  %s·%s %s\n' "$C_D" "$C_N" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$C_G" "$C_N" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_N" "$*"; }
fail() { printf '  %s✘%s %s\n' "$C_R" "$C_N" "$*"; echo "::error::$*"; }
kv()   { printf '    %s%-11s%s %s\n' "$C_D" "$1" "$C_N" "$2"; }

run_quiet() {
  local label="$1"; shift
  local slug log t0 rc=0 dt
  slug="$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '-' | cut -c1-40)"
  log="$CI_LOG_DIR/$(date +%H%M%S)-$$-${slug}.log"
  t0=$(date +%s)
  {
    if [ -z "${RQ_NOCMD:-}" ]; then printf '$ %s\n' "$*"; fi
    "$@"
  } > "$log" 2>&1 || rc=$?
  dt=$(( $(date +%s) - t0 ))
  if [ "$rc" -eq 0 ]; then
    ok "$label ($(fmt_dur "$dt"))"
    return 0
  fi
  if [ -n "${RQ_SOFT:-}" ]; then
    warn "$label: gagal (exit $rc, $(fmt_dur "$dt"))"
  else
    fail "$label: gagal (exit $rc, $(fmt_dur "$dt"))"
  fi
  echo "::group::Log: $label (80 baris terakhir)"
  tail -n 80 "$log"
  echo "::endgroup::"
  return "$rc"
}
