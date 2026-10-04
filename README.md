# ha-glkvm-relay

Home Assistant add-on running GL.iNet's self-hosted GLKVM Cloud relay (`rttys`) and a TURN server (coturn) on the host network. Usage, ports and options: [glkvm_relay/DOCS.md](glkvm_relay/DOCS.md).

## Install as a local add-on

```bash
git archive HEAD glkvm_relay | ssh root@<ha-host> 'tar -x -C /local_apps && ha store reload'
```

Then install `local_glkvm_relay` from the add-on store.

## Licence

MIT for this repository's files. GLKVM Cloud is GL.iNet's work under the Business Source License 1.1; the image downloads its binary from GL.iNet's published image at build time.
