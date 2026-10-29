# Changelog

## 0.3.0

- The app runs under its own AppArmor profile.
- The store shows an icon, a logo and a short description, and the app's link opens its GitHub repository.

## 0.2.1

- `rttys` runs at log level warn, so its start-up print of its parsed config no longer reaches the log.
- The option `turn_secret_generation` replaces the TURN credential when raised and the add-on restarts; the log gives the hash prefix of the one in use.

## 0.2.0

- TURN relays to public addresses and the addresses in `turn_allowed_peers`; other private, shared, link-local and loopback addresses, the host's own included, are refused.

## 0.1.0

- GLKVM Cloud relay (`rttys` v2.8.0, image digest pinned) and coturn in one add-on on the host network.
- Admin password and device token generated into the options when empty; TURN credentials generated into `/data`.
- Certificate from `/ssl`, or a self-signed one for the access address.
