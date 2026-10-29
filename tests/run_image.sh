#!/bin/bash
# Starts a built image as the Supervisor would (options in /data, no /ssl), probes it from inside its
# network namespace, and checks that the log holds none of the credentials.
# Usage: tests/run_image.sh <image tag>   (needs docker; run from the repository root)
set -euo pipefail

image="$1"
name="glkvm-relay-test-$$-${RANDOM}"
work="$(mktemp -d)"
trap 'docker logs "$name" 2>&1 | tail -n 40 || true; docker rm -f "$name" > /dev/null 2>&1 || true; rm -rf "$work"' EXIT

mkdir -p "$work/data"
cat > "$work/data/options.json" << 'JSON'
{"admin_name": "admin", "password": "test-password-1", "device_token": "test-token-1",
 "access_ip": "127.0.0.1", "web_port": 443, "proxy_port": 10443, "device_port": 5912,
 "turn_port": 3478, "turn_allowed_peers": [], "turn_secret_generation": 1,
 "certfile": "fullchain.pem", "keyfile": "privkey.pem"}
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
echo "ok   the relay answers and its log holds no credential"
