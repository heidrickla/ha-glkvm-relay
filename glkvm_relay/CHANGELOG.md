# Changelog

## 0.2.0

- TURN relays to public addresses and the addresses in `turn_allowed_peers`; other private, shared, link-local and loopback addresses, the host's own included, are refused.

## 0.1.0

- GLKVM Cloud relay (`rttys` v2.8.0, image digest pinned) and coturn in one add-on on the host network.
- Admin password and device token generated into the options when empty; TURN credentials generated into `/data`.
- Certificate from `/ssl`, or a self-signed one for the access address.
