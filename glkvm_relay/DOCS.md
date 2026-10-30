# GLKVM Relay

Runs GL.iNet's self-hosted GLKVM Cloud relay (`rttys`, v2.8.0) with a TURN server (coturn) on the Home Assistant host, so GL.iNet KVMs can be reached through one web console.

## Setup

1. Install the app and start it. Nothing needs to be typed first.
2. Open the Configuration tab: the admin password and the device token generated on the first start are there.
3. Select Open Web UI (or browse to `https://<home assistant host>/`) and sign in as `admin` with that password. With no certificate in `/ssl` the browser warns about a self-signed certificate once.
4. Add each KVM: in the web console, add a device, copy the script it shows, and run that script in the KVM's terminal. The KVM appears in the device list, and TURN may relay to it from then on.

The log names the console's address and says when it has learned a KVM's address for TURN.

## Options

Only the two credentials are shown by default; the others have working defaults and appear under the unused optional options.

| Option | Default | Use |
|---|---|---|
| `password` | generated | Admin password for the web console. |
| `device_token` | generated | Token a KVM presents to join the relay. |
| `admin_name` | `admin` | Administrator account name. |
| `access_ip` | the host's address on its default route | Address browsers and KVMs use to reach the relay; also the TURN server's address. |
| `web_port` | `443` | Web console (HTTPS). The Open Web UI button assumes 443. |
| `proxy_port` | `10443` | Websocket and HTTP proxy. |
| `device_port` | `5912` | KVM connections. |
| `turn_port` | `3478` | STUN and TURN, TCP and UDP. |
| `turn_learn_peers` | on | TURN may relay to the address each registered KVM connected from. |
| `turn_allowed_peers` | none | More private IPv4 addresses or ranges `a.b.c.d-e.f.g.h` TURN may relay to. |
| `turn_secret_generation` | `1` | Raise and restart to replace the TURN credential. |
| `certfile`, `keyfile` | `fullchain.pem`, `privkey.pem` | Certificate pair in `/ssl`. |

## Ports

The app uses the host network.

| Port | Protocol | Use |
|---|---|---|
| 443 | TCP | web console (HTTPS) |
| 10443 | TCP | websocket and HTTP proxy |
| 5912 | TCP | KVM connections |
| 3478 | TCP, UDP | STUN and TURN |
| 49160-49260 | UDP | TURN relayed media |

Each port is an option; change one when it is taken on the host.

## First start

The admin password and the device token are generated when left empty and written back to the options, where the Configuration tab shows them. The TURN credentials are generated into `/data`, are never shown there, and are handed to browsers by the relay.

## TURN peers

TURN relays to public addresses and to the KVMs. A KVM's address is learned when it registers with the relay: once the relay has accepted its device token, it records the address the KVM connected from, and TURN may relay to that address within about fifteen seconds, with no restart. A KVM disabled in the web console is dropped from the list. The host's own addresses are never learned.

Every other address in 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, `::1`, `fc00::/7` and `fe80::/10` is refused, the access address included. `turn_allowed_peers` adds addresses that are not learned, such as a browser a KVM relays to. With `turn_learn_peers` off, TURN relays only to public addresses and `turn_allowed_peers`.

## Replacing the TURN credential

Raise `turn_secret_generation` and restart. The start-up log says `made a new TURN credential` and gives the first eight hex characters of the credential's SHA-256 hash, so a change can be seen without the credential. A KVM keeps the credential it was added with in its own `S01selfCloud` script: after a new generation, run the add-device script on each KVM again so its copy matches.

## Log

The relay runs at log level warn, so its part of the log holds warnings and errors only; the app's own lines carry the `[glkvm-relay]` tag, and coturn logs as it does by default. The relay's start-up print of its parsed config is an info line and does not appear.

## Certificate

With `fullchain.pem` and `privkey.pem` in `/ssl` (or the files the options name), the web console uses them. Without them it uses a self-signed certificate for the access address, kept in `/data/tls` and remade when the access address changes.

## Data

The relay's SQLite database is `/data/database/glkvm-cloud.db` and is included in app backups.

## Licence

The app's own files are MIT. GLKVM Cloud is GL.iNet's work under the Business Source License 1.1, which permits non-production use, including personal use; the app builds it from GL.iNet's published source at build time and includes none of its code. GL.iNet and GLKVM are GL.iNet's names; this app is not affiliated with GL.iNet.
