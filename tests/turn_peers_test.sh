#!/bin/bash
# Runs the learned TURN peer block of run.sh against a scratch relay database and checks which
# addresses reach coturn's peer table.
# Usage: tests/turn_peers_test.sh   (needs bash and sqlite3; run from the repository root, or with
# RUN=/run.sh inside the image: docker run -i --rm --entrypoint bash -e RUN=/run.sh <image> -s < this)
set -euo pipefail

RUN="${RUN:-glkvm_relay/run.sh}"
DATA="$(mktemp -d)"
trap 'rm -rf "$DATA"' EXIT

# shellcheck disable=SC2317  # called by the evaluated block
log() { echo "[glkvm-relay] $*"; }
# shellcheck disable=SC2034  # read by the evaluated block
access_ip=192.168.1.10

block="$(sed -n '/^# TURN peers learned from the KVMs/,/^# End of the learned TURN peers/p' "$RUN")"
[ -n "$block" ] || { echo "FAIL: the learned TURN peer block is not in $RUN"; exit 1; }
eval "$block"
# The block reads this host's addresses; the test names them.
# shellcheck disable=SC2034  # read by the evaluated block
host_addrs=" 192.168.1.10 172.30.32.1 "
TURN_DB="$DATA/turndb"

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected '$3', got '$2')"; fail=1; fi
}
coturn_peers() { sqlite3 "$TURN_DB" "SELECT ip_range FROM allowed_peer_ip ORDER BY ip_range;" | tr '\n' ' ' | sed 's/ $//'; }
device() {
  sqlite3 "$RTTYS_DB" "INSERT INTO devices (ddns, mac, ip, status) VALUES ('$1', '$1', '$2', '$3');"
}

check "no relay database yet: nothing is learned" "$(learned_peers)" ""
sync_peers_once > /dev/null
check "no relay database yet: coturn's table is made and empty" "$(coturn_peers)" ""

mkdir -p "$DATA/database"
sqlite3 "$RTTYS_DB" "CREATE TABLE devices (id INTEGER PRIMARY KEY AUTOINCREMENT, ddns TEXT NOT NULL UNIQUE,
  mac TEXT NOT NULL UNIQUE, ip TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'online');"
device kvm1 10.1.2.3 online
device kvm2 10.1.2.4 offline
device kvm3 10.1.2.5 disabled
device kvm4 10.1.2.3 online
device kvm5 192.168.1.10 online
device kvm6 172.30.32.1 online
device kvm7 "" online
device kvm8 fd00::1 online
device kvm9 999.1.2.3 online
device kvm10 010.1.2.3 online
device kvm11 "10.9.9.9-10.9.9.99" online

check "registered KVMs are learned once each; disabled ones, this host and non-addresses are not" \
  "$(learned_peers | tr '\n' ' ' | sed 's/ $//')" "10.1.2.3 10.1.2.4"
sync_peers_once > "$DATA/sync.log"
check "a change is logged" "$(cat "$DATA/sync.log")" "[glkvm-relay] TURN peers learned from registered KVMs: 10.1.2.3 10.1.2.4"
check "coturn's table holds the learned peers" "$(coturn_peers)" "10.1.2.3 10.1.2.4"
sync_peers_once > "$DATA/sync.log"
check "no change, no log" "$(cat "$DATA/sync.log")" ""

sqlite3 "$RTTYS_DB" "UPDATE devices SET status = 'disabled' WHERE ddns = 'kvm2';"
device kvm12 10.1.2.6 online
sync_peers_once > /dev/null
check "a disabled KVM leaves coturn's table and a new one joins" "$(coturn_peers)" "10.1.2.3 10.1.2.6"

exit "$fail"
