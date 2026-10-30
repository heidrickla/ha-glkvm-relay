#!/bin/bash
# Runs the TURN credential block of run.sh against a scratch /data and checks when the secret is replaced.
# Usage: tests/turn_rotation_test.sh   (needs bash, jq, openssl; run from the repository root)
set -euo pipefail

RUN=glkvm_relay/run.sh
DATA="$(mktemp -d)"
OPTS="$DATA/options.json"
trap 'rm -rf "$DATA"' EXIT

# shellcheck disable=SC2317  # called by the evaluated block
log() { echo "[glkvm-relay] $*"; }
# shellcheck disable=SC2317
opt() { jq -r --arg k "$1" --arg d "${2-}" 'if (.[$k] == null) or (.[$k] == "") then $d else (.[$k] | tostring) end' "$OPTS"; }
# shellcheck disable=SC2317
rand() { openssl rand -base64 96 | tr -dc 'A-Za-z0-9' | cut -c "1-$1"; }

block="$(sed -n '/^# Nobody types the TURN/,/^log "TURN credential generation/p' "$RUN")"
[ -n "$block" ] || { echo "FAIL: the TURN block is not in $RUN"; exit 1; }

# Runs the block with the given options and prints the fingerprint it logged.
start() {
  echo "$1" > "$OPTS"
  (eval "$block") | sed -n 's/.*fingerprint \([0-9a-f]\{8\}\)$/\1/p'
}

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $3, got $2)"; fail=1; fi
}
differs() {
  if [ "$2" != "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (the fingerprint did not change)"; fail=1; fi
}

fp1="$(start '{"turn_secret_generation":1}')"
check "a fresh install logs an 8 hex fingerprint" "${#fp1}" 8
check "a restart at the same generation keeps the secret" "$(start '{"turn_secret_generation":1}')" "$fp1"
fp2="$(start '{"turn_secret_generation":2}')"
differs "raising the generation replaces the secret" "$fp2" "$fp1"
check "a restart at the new generation keeps it" "$(start '{"turn_secret_generation":2}')" "$fp2"
check "the stored secret is 32 characters" "$(wc -c < "$DATA/turn.secret" | tr -d ' ')" 33

rm -f "$DATA/turn.generation"
check "a secret from before the option existed counts as generation 1" "$(start '{}')" "$fp2"
fp3="$(start '{"turn_secret_generation":3}')"
differs "raising the generation past a legacy secret replaces it" "$fp3" "$fp2"

exit "$fail"
