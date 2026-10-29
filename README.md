# GLKVM Relay for Home Assistant

A Home Assistant app that runs GL.iNet's self-hosted GLKVM Cloud relay (`rttys`) and a TURN server (coturn) on the Home Assistant host, so the GL.iNet KVMs on your network are reached through one web console with no separate server.

| App | What |
|---|---|
| [GLKVM Relay](glkvm_relay/) | GLKVM Cloud relay and its TURN server on the host network, with generated credentials, a TURN peer allow-list and a credential you replace by raising one option. |

## Installing

[![Open your Home Assistant instance and add this repository.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fheidrickla%2Fha-glkvm-relay)

Settings > Apps > App Store > ⋮ > Repositories, add `https://github.com/heidrickla/ha-glkvm-relay`, then install GLKVM Relay. The app is built for amd64. Usage, ports and options are in [glkvm_relay/DOCS.md](glkvm_relay/DOCS.md).

To run it as a local app instead:

```bash
git archive HEAD glkvm_relay | ssh root@<ha-host> 'tar -x -C /local_apps && ha store reload'
```

## Developing

```bash
python -m pip install ruff yamllint shellcheck-py
ruff check . && ruff format --check .
shellcheck glkvm_relay/run.sh tests/turn_rotation_test.sh
bash tests/turn_rotation_test.sh
python tests/relay_probe.py <relay host>
```

`tests/turn_rotation_test.sh` needs bash, jq and openssl. `tests/relay_probe.py` checks a running relay from the network: the web console, the device and proxy ports, and a STUN answer.

## Licence

MIT for this repository's files; see `LICENSE`. GLKVM Cloud is GL.iNet's work under the Business Source License 1.1, which permits non-production use, including personal use, and becomes GPLv3 on 2030-01-01. The image copies GL.iNet's `rttys` binary from their published image when it is built, and this repository includes none of their code. GL.iNet and GLKVM are GL.iNet's names; this project is not affiliated with GL.iNet.
