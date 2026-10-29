# GLKVM Relay

Runs GL.iNet's self-hosted GLKVM Cloud relay (`rttys`, v2.8.0) with a TURN server (coturn) on the Home Assistant host, so GL.iNet KVMs can be reached through one web console.

## Ports

The add-on uses the host network.

| Port | Protocol | Use |
|---|---|---|
| 443 | TCP | web console (HTTPS) |
| 10443 | TCP | websocket and HTTP proxy |
| 5912 | TCP | KVM connections |
| 3478 | TCP, UDP | STUN and TURN |
| 49160-49260 | UDP | TURN relayed media |

Each port is an option; change one when it is taken on the host.

## First start

The admin password and the device token are generated when left empty and written back to the options, where this page shows them. The TURN credentials are generated into `/data`, are never shown here, and are handed to browsers by the relay.

## TURN peers

TURN relays to public addresses and to the addresses in `turn_allowed_peers` (IPv4 addresses or ranges `a.b.c.d-e.f.g.h`). Every other address in 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 198.18.0.0/15, `::1`, `fc00::/7` and `fe80::/10` is refused, the access address included. List each KVM's address; a browser's address is needed only when a KVM relays to it.

## Replacing the TURN credential

Raise `turn_secret_generation` and restart. The start-up log says `made a new TURN credential` and gives the first eight hex characters of the credential's SHA-256 hash, so a change can be seen without the credential. A KVM keeps the credential it was added with in its own `S01selfCloud` script: after a new generation, run the add-device script (see below) on each KVM again so its copy matches.

## Log

The relay runs at log level warn, so its part of the log holds warnings and errors only; the add-on's own lines carry the `[glkvm-relay]` tag, and coturn logs as it does by default. The relay's start-up print of its parsed config is an info line and does not appear.

## Certificate

With `fullchain.pem` and `privkey.pem` in `/ssl` (or the files the options name), the web console uses them. Without them it uses a self-signed certificate for the access address, kept in `/data/tls` and remade when the access address changes.

## Adding a KVM

In the web console, add a device and copy the script it shows, then run that script in the KVM's terminal. The script carries the relay's address and the device token.

## Data

The relay's SQLite database is `/data/database/glkvm-cloud.db` and is included in add-on backups.

## Licence

The add-on's own files are MIT. GLKVM Cloud is GL.iNet's work under the Business Source License 1.1, which permits non-production use, including personal use; the add-on downloads its binary from GL.iNet's published image at build time and includes none of its code. GL.iNet and GLKVM are GL.iNet's names; this app is not affiliated with GL.iNet.
