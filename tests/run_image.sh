#!/bin/bash
# Starts a built image as the Supervisor would on a fresh install (only the two shown options set, no
# /ssl), probes it from inside its network namespace, checks that the log holds none of the
# credentials, and checks that TURN relays to a private peer only once a KVM has registered from it.
# Usage: tests/run_image.sh <image tag>   (needs docker; run from the repository root)
set -euo pipefail

image="$1"
name="glkvm-relay-test-$$-${RANDOM}"
work="$(mktemp -d)"
trap 'docker logs "$name" 2>&1 | tail -n 40 || true; docker rm -f "$name" "$name-peer" > /dev/null 2>&1 || true; rm -rf "$work"' EXIT

echo "== learned TURN peer block, in the image"
docker run -i --rm --entrypoint bash -e RUN=/run.sh "$image" -s < tests/turn_peers_test.sh

mkdir -p "$work/data"
cat > "$work/data/options.json" << 'JSON'
{"password": "test-password-1", "device_token": "test-token-1"}
JSON

docker create --name "$name" "$image" > /dev/null
docker cp "$work/data/." "$name:/data"
docker start "$name" > /dev/null

ok=0
for _ in $(seq 1 30); do
  if docker run -i --rm --network "container:$name" python:3.14-alpine python - 127.0.0.1 < tests/relay_probe.py; then
    ok=1
    break
  fi
  sleep 2
done
[ "$ok" = 1 ] || { echo "FAIL: the relay did not answer the probe"; exit 1; }

secret="$(docker exec "$name" cat /data/turn.secret)"
if docker logs "$name" 2>&1 | grep -q -F -e test-password-1 -e test-token-1 -e "$secret"; then
  echo "FAIL: a credential reached the log"
  exit 1
fi
echo "ok   the relay answers with no option but the two credentials, and its log holds no credential"

# A UDP echo on the container network stands in for a KVM: its address is private, so TURN refuses it
# until a device row with that address appears in the relay's database, as a KVM's registration writes.
docker run -d --name "$name-peer" python:3.14-alpine python -c '
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 5000))
while True:
    d, a = s.recvfrom(65535)
    s.sendto(d, a)' > /dev/null
addr() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }
peer="$(addr "$name-peer")"
self="$(addr "$name")"
# The client reaches TURN on the container's own address: a relay bound to loopback cannot send out.
relay() {
  docker exec "$name" sh -c "turnutils_uclient -u glkvm -w \"\$(cat /data/turn.secret)\" -e $peer -r 5000 -n 5 -m 1 -c $self" 2>&1 |
    grep -a -c 'Total lost packets 0 ' || true
}

[ "$(relay)" = 0 ] || { echo "FAIL: TURN relayed to the private peer $peer before any KVM registered from it"; exit 1; }
echo "ok   TURN refuses the private peer $peer while no KVM has registered from it"

docker exec "$name" sqlite3 /data/database/glkvm-cloud.db \
  "INSERT INTO devices (ddns, mac, ip, status) VALUES ('testkvm', '000000000001', '${peer}', 'online');"
learned=0
for _ in $(seq 1 15); do
  if docker logs "$name" 2>&1 | grep -q -F "TURN peers learned from registered KVMs: ${peer}"; then
    learned=1
    break
  fi
  sleep 2
done
[ "$learned" = 1 ] || { echo "FAIL: the registered address $peer was not learned"; exit 1; }
# coturn rereads its peer table every five seconds.
relayed=0
for _ in $(seq 1 6); do
  if [ "$(relay)" = 1 ]; then
    relayed=1
    break
  fi
  sleep 2
done
[ "$relayed" = 1 ] || { echo "FAIL: TURN did not relay to $peer after it was learned"; exit 1; }
echo "ok   TURN relays to $peer once a KVM has registered from it, with no restart"
