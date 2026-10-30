#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# GLKVM Cloud relay (rttys) and its TURN server (coturn), configured from the add-on options.
# with-contenv: s6-overlay keeps the container environment, SUPERVISOR_TOKEN included, out of CMD otherwise.
set -euo pipefail

OPTS=/data/options.json
DATA=/data

log() { echo "[glkvm-relay] $*"; }
# An option's value, or the default given when it is unset or empty; false stays false.
opt() { jq -r --arg k "$1" --arg d "${2-}" 'if (.[$k] == null) or (.[$k] == "") then $d else (.[$k] | tostring) end' "$OPTS"; }
# `cut` reads all of its input, so nothing in the pipe dies of SIGPIPE under pipefail.
rand() { openssl rand -base64 96 | tr -dc 'A-Za-z0-9' | cut -c "1-$1"; }
# rttys parses its config with go-gypsy, which reads plain scalars; values are written unquoted, so
# each is held to characters that need no quoting.
safe() {
  if ! [[ $2 =~ ^[A-Za-z0-9._~@%+=-]+$ ]]; then
    log "$1 may only hold letters, digits and . _ ~ @ % + = -"
    exit 1
  fi
}

admin_name="$(opt admin_name admin)"
web_port="$(opt web_port 443)"
proxy_port="$(opt proxy_port 10443)"
device_port="$(opt device_port 5912)"
turn_port="$(opt turn_port 3478)"
learn_peers="$(opt turn_learn_peers true)"

# The admin password and the device token are needed by people (to sign in, to onboard a KVM), so
# they live in the options, where the add-on page shows them. Empty ones are generated once and
# saved back through the Supervisor; the request body goes on stdin to stay out of argv.
password="$(opt password)"
token="$(opt device_token)"
if [ -z "$password" ] || [ -z "$token" ]; then
  [ -n "$password" ] || password="$(rand 24)"
  [ -n "$token" ] || token="$(rand 32)"
  if ! jq --arg p "$password" --arg t "$token" '{options: (. + {password: $p, device_token: $t})}' "$OPTS" |
    curl -fsS -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN:-}" -H "Content-Type: application/json" \
      --data-binary @- http://supervisor/addons/self/options > /dev/null; then
    log "could not save a generated password and device token through the Supervisor; type both in the Configuration tab and restart"
    exit 1
  fi
  log "generated the empty admin password or device token; both are on the app's Configuration tab"
fi

# Nobody types the TURN credentials, so they live in /data, not in the options. turn_secret_generation
# names the secret wanted: when it differs from the number kept beside the secret, a new one is made,
# so a restart never replaces it twice. A secret from before the option existed is generation 1.
umask 077
turn_generation="$(opt turn_secret_generation)"
turn_generation="${turn_generation:-1}"
kept_generation=1
[ ! -s "$DATA/turn.generation" ] || kept_generation="$(cat "$DATA/turn.generation")"
if [ ! -s "$DATA/turn.secret" ] || [ "$kept_generation" != "$turn_generation" ]; then
  rand 32 > "$DATA/turn.secret.new"
  mv "$DATA/turn.secret.new" "$DATA/turn.secret"
  echo "$turn_generation" > "$DATA/turn.generation"
  log "made a new TURN credential for generation ${turn_generation}"
fi
turn_user=glkvm
turn_pass="$(cat "$DATA/turn.secret")"
# Eight hex characters of its hash say which secret is in use without revealing it.
log "TURN credential generation ${turn_generation}, fingerprint $(printf '%s' "$turn_pass" | sha256sum | cut -c1-8)"

access_ip="$(opt access_ip)"
if [ -z "$access_ip" ]; then
  # The source address of the default route; `ip route get` sends nothing.
  access_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
fi
if [ -z "$access_ip" ]; then
  log "could not find the host's address; set access_ip in the options"
  exit 1
fi

# rttys reads its certificate from fixed paths. HA's /ssl pair when present, else a self-signed one.
certfile="/ssl/$(opt certfile fullchain.pem)"
keyfile="/ssl/$(opt keyfile privkey.pem)"
if [ -f "$certfile" ] && [ -f "$keyfile" ]; then
  cert=$certfile
  key=$keyfile
  log "certificate: $certfile"
else
  mkdir -p "$DATA/tls"
  cert=$DATA/tls/selfsigned.crt
  key=$DATA/tls/selfsigned.key
  if [ ! -s "$cert" ] || ! openssl x509 -in "$cert" -noout -checkip "$access_ip" > /dev/null 2>&1; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
      -subj "/CN=glkvm-relay" -addext "subjectAltName=IP:${access_ip}" \
      -keyout "$key" -out "$cert" 2> /dev/null
  fi
  log "certificate: self-signed for ${access_ip} (no ${certfile} and ${keyfile})"
fi
mkdir -p /home/certificate
ln -sf "$cert" /home/certificate/glkvm_cer
ln -sf "$key" /home/certificate/glkvm_key

# rttys keeps its SQLite database and reads its schema in /home/database; the data lives in /data.
mkdir -p "$DATA/database"
cp /usr/share/glkvm/schema.sql "$DATA/database/schema.sql"
rm -rf /home/database
ln -s "$DATA/database" /home/database

safe password "$password"
safe device_token "$token"
safe access_ip "$access_ip"

# TURN relays to the addresses in turn_allowed_peers (the KVMs) and to public addresses; every other
# private, shared, link-local and loopback address is refused, this host and the add-on network
# included. An allowed address wins over a denied range.
peer_lines=""
while IFS= read -r peer; do
  [ -n "$peer" ] || continue
  if ! [[ $peer =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(-[0-9]{1,3}(\.[0-9]{1,3}){3})?$ ]]; then
    log "turn_allowed_peers entries are IPv4 addresses or ranges a.b.c.d-e.f.g.h"
    exit 1
  fi
  peer_lines+="allowed-peer-ip=${peer}"$'\n'
done < <(jq -r '(.turn_allowed_peers // [])[]' "$OPTS")

# TURN peers learned from the KVMs. rttys stores a KVM's source address in devices.ip only after it
# has accepted the device token. Those addresses go into coturn's allowed_peer_ip table, which coturn
# rereads every five seconds, so a KVM added later is reachable without a restart.
RTTYS_DB="$DATA/database/glkvm-cloud.db"
TURN_DB=/tmp/turndb
# This host's own addresses are never learned: TURN must not relay to the host.
host_addrs=" $(ip -o addr show 2> /dev/null | awk '{split($4, a, "/"); printf "%s ", a[1]}')${access_ip} "
peers_last="-"

is_ipv4() {
  local o='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
  [[ $1 =~ ^$o\.$o\.$o\.$o$ ]]
}

# Addresses of the registered KVMs that are not disabled, sorted, one per line.
learned_peers() {
  local ip
  [ -s "$RTTYS_DB" ] || return 0
  { sqlite3 -readonly -batch -noheader -cmd '.timeout 3000' "$RTTYS_DB" \
    "SELECT DISTINCT ip FROM devices WHERE status <> 'disabled';" 2> /dev/null || true; } |
    while IFS= read -r ip; do
      is_ipv4 "$ip" || continue
      [[ $host_addrs == *" $ip "* ]] && continue
      echo "$ip"
    done | sort -u
}

# Replaces coturn's learned peers with the space-separated addresses given, in one transaction.
write_peers() {
  local ip sql="BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS allowed_peer_ip (realm varchar(127) default '',"
  sql+=" ip_range varchar(256), primary key (realm,ip_range)); DELETE FROM allowed_peer_ip;"
  for ip in $1; do
    is_ipv4 "$ip" && sql+=" INSERT INTO allowed_peer_ip (realm, ip_range) VALUES ('', '${ip}');"
  done
  sqlite3 -batch -cmd '.timeout 3000' "$TURN_DB" "${sql} COMMIT;" > /dev/null
}

# Copies the learned peers to coturn when they have changed since the last copy, and logs the change.
sync_peers_once() {
  local peers
  peers="$(learned_peers | tr '\n' ' ')"
  peers="${peers% }"
  [ "$peers" != "$peers_last" ] || return 0
  if write_peers "$peers"; then
    log "TURN peers learned from registered KVMs: ${peers:-none yet}"
    peers_last=$peers
  else
    log "could not write the learned TURN peers to ${TURN_DB}; trying again"
  fi
}
# End of the learned TURN peers.

rm -f "$TURN_DB" "${TURN_DB}-journal"
write_peers ""

# rttys v2.8.0 takes its config file from RTTYS_CONF (or ./rttys.conf); it has no -c option. At its
# default info level it logs its parsed config, passwords and token included; log-level warn keeps
# that and every other info line out of the log.
export RTTYS_CONF="$DATA/rttys.conf"
cat > "$RTTYS_CONF" << EOF
log-level: warn
token: ${token}
password: ${password}
admin-name: ${admin_name}
webrtc-ip: ${access_ip}
webrtc-port: ${turn_port}
webrtc-username: ${turn_user}
webrtc-password: ${turn_pass}
addr-dev: :${device_port}
addr-user: :${web_port}
addr-http-proxy: :${proxy_port}
ldap-enabled: false
oidc-enabled: false
EOF

# coturn 4.10 keeps its admin CLI off by default; its old no-cli line only logs an error.
cat > "$DATA/turnserver.conf" << EOF
listening-port=${turn_port}
lt-cred-mech
user=${turn_user}:${turn_pass}
realm=glkvm
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=::1
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
${peer_lines}userdb=${TURN_DB}
external-ip=${access_ip}
min-port=49160
max-port=49260
pidfile=/tmp/turnserver.pid
log-file=stdout
EOF

log "relay for ${access_ip}: web ${web_port}, http proxy ${proxy_port}, devices ${device_port}, TURN ${turn_port}"
turnserver -c "$DATA/turnserver.conf" &
turn_pid=$!
cd /home
rttys &
rttys_pid=$!

sync_pid=""
if [ "$learn_peers" = true ]; then
  while :; do
    sync_peers_once
    sleep 10
  done &
  sync_pid=$!
else
  log "learning TURN peers from the KVMs is off; TURN relays only to turn_allowed_peers and public addresses"
fi
log "web console https://${access_ip}:${web_port}, user ${admin_name}; the password is on the app's Configuration tab"

stop() { kill -TERM "$rttys_pid" "$turn_pid" ${sync_pid:+"$sync_pid"} 2> /dev/null || true; }
trap stop TERM INT

# Either process ending ends the add-on, so the Supervisor's watchdog restarts both together.
code=0
wait -n "$rttys_pid" "$turn_pid" || code=$?
log "a process exited (code ${code}); stopping the other"
stop
wait || true
exit "$((code == 0 ? 1 : code))"
