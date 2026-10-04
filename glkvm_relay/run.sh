#!/usr/bin/env bash
# GLKVM Cloud relay (rttys) and its TURN server (coturn), configured from the add-on options.
set -euo pipefail

OPTS=/data/options.json
DATA=/data

log() { echo "[glkvm-relay] $*"; }
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTS"; }
# `cut` reads all of its input, so nothing in the pipe dies of SIGPIPE under pipefail.
rand() { openssl rand -base64 96 | tr -dc 'A-Za-z0-9' | cut -c "1-$1"; }
# Single-quoted YAML scalar: a quote inside is written twice.
yq() { local s=$1; printf "'%s'" "${s//\'/\'\'}"; }

admin_name="$(opt admin_name)"
web_port="$(opt web_port)"
proxy_port="$(opt proxy_port)"
device_port="$(opt device_port)"
turn_port="$(opt turn_port)"

# The admin password and the device token are needed by people (to sign in, to onboard a KVM), so
# they live in the options, where the add-on page shows them. Empty ones are generated once and
# saved back through the Supervisor; the request body goes on stdin to stay out of argv.
password="$(opt password)"
token="$(opt device_token)"
if [ -z "$password" ] || [ -z "$token" ]; then
  [ -n "$password" ] || password="$(rand 24)"
  [ -n "$token" ] || token="$(rand 32)"
  jq --arg p "$password" --arg t "$token" '{options: (. + {password: $p, device_token: $t})}' "$OPTS" |
    curl -fsS -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" \
      --data-binary @- http://supervisor/addons/self/options > /dev/null
  log "generated the empty admin password or device token and saved them to the add-on options"
fi

# TURN credentials are handed to browsers by rttys, so nobody types them: generated once, kept in /data.
umask 077
[ -s "$DATA/turn.secret" ] || rand 32 > "$DATA/turn.secret"
turn_user=glkvm
turn_pass="$(cat "$DATA/turn.secret")"

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
certfile="/ssl/$(opt certfile)"
keyfile="/ssl/$(opt keyfile)"
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

cat > "$DATA/rttys.conf" << EOF
token: $(yq "$token")
password: $(yq "$password")
admin-name: $(yq "$admin_name")
webrtc-ip: $(yq "$access_ip")
webrtc-port: ${turn_port}
webrtc-username: $(yq "$turn_user")
webrtc-password: $(yq "$turn_pass")
addr-dev: :${device_port}
addr-user: :${web_port}
addr-http-proxy: :${proxy_port}
ldap-enabled: false
oidc-enabled: false
EOF

cat > "$DATA/turnserver.conf" << EOF
listening-port=${turn_port}
lt-cred-mech
user=${turn_user}:${turn_pass}
realm=glkvm
no-multicast-peers
no-cli
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
rttys -c "$DATA/rttys.conf" &
rttys_pid=$!

stop() { kill -TERM "$rttys_pid" "$turn_pid" 2> /dev/null || true; }
trap stop TERM INT

# Either process ending ends the add-on, so the Supervisor's watchdog restarts both together.
code=0
wait -n "$rttys_pid" "$turn_pid" || code=$?
log "a process exited (code ${code}); stopping the other"
stop
wait || true
exit "$((code == 0 ? 1 : code))"
